//! Declarative command definition system for Flash CLI
//!
//! This module provides a way to define CLI commands using Zig structs
//! with compile-time validation and automatic parsing.

const std = @import("std");
const Command = @import("command.zig");
const Argument = @import("argument.zig");
const Flag = @import("flag.zig");
const Context = @import("context.zig");
const Error = @import("error.zig");

/// Metadata for field configuration
pub const FieldConfig = struct {
    help: ?[]const u8 = null,
    long: ?[]const u8 = null,
    short: ?u8 = null,
    required: bool = false,
    default: ?[]const u8 = null,
    env: ?[]const u8 = null,
    hidden: bool = false,
    multiple: bool = false,
    validator: ?FieldValidator = null,
    
    pub const FieldValidator = struct {
        validate_fn: *const fn ([]const u8) bool,
        error_message: []const u8,
    };
};

/// Alias configuration for field names
pub const Alias = struct {
    field: []const u8,
    short: ?u8 = null,
    long: ?[]const u8 = null,
};

/// Derive configuration for automatic implementation
pub const DeriveConfig = struct {
    help: bool = true,
    version: ?[]const u8 = null,
    author: ?[]const u8 = null,
    about: ?[]const u8 = null,
    long_about: ?[]const u8 = null,
};

/// Parse a struct type into a Flash command
pub fn parse(comptime T: type, allocator: std.mem.Allocator) !T {
    const parsed_args = try parseWithConfig(T, allocator, .{});
    return parsed_args;
}

/// Parse a struct type with configuration
pub fn parseWithConfig(comptime T: type, allocator: std.mem.Allocator, config: anytype) !T {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    return parseWithArgs(T, allocator, args, config);
}

/// Parse a struct type with specific arguments
pub fn parseWithArgs(comptime T: type, allocator: std.mem.Allocator, args: []const []const u8, config: anytype) !T {
    const command = try generateCommand(T, allocator, config);
    const parser = @import("parser.zig").Parser.init(allocator);
    
    var context = try parser.parse(command, args);
    defer context.deinit();
    
    return try parseFromContext(T, allocator, context);
}

/// Generate a Flash command from a struct type
pub fn generateCommand(comptime T: type, allocator: std.mem.Allocator, config: anytype) !Command.Command {
    const type_info = @typeInfo(T);
    
    if (type_info != .Struct) {
        @compileError("parseCommand can only be used with struct types");
    }
    
    var command_config = Command.CommandConfig{};
    
    // Set basic command info from config
    if (@hasField(@TypeOf(config), "about")) {
        command_config.about = config.about;
    }
    if (@hasField(@TypeOf(config), "long_about")) {
        command_config.long_about = config.long_about;
    }
    if (@hasField(@TypeOf(config), "version")) {
        command_config.version = config.version;
    }
    
    // Generate arguments and flags from struct fields
    var args_list = std.ArrayList(Argument.Argument).init(allocator);
    var flags_list = std.ArrayList(Flag.Flag).init(allocator);
    
    inline for (type_info.Struct.fields) |field| {
        const field_config = getFieldConfig(T, field.name);
        
        switch (field.type) {
            bool => {
                // Boolean fields become flags
                var flag_config = Flag.FlagConfig{
                    .help = field_config.help,
                    .hidden = field_config.hidden,
                };
                
                if (field_config.short) |short| {
                    flag_config.short = short;
                }
                
                if (field_config.long) |long| {
                    flag_config.long = long;
                } else {
                    flag_config.long = field.name;
                }
                
                try flags_list.append(Flag.Flag.init(field.name, flag_config));
            },
            else => {
                // Non-boolean fields become arguments
                var arg_config = Argument.ArgumentConfig{
                    .help = field_config.help,
                    .required = field_config.required,
                    .hidden = field_config.hidden,
                    .multiple = field_config.multiple,
                };
                
                if (field_config.long) |long| {
                    arg_config.long = long;
                } else {
                    arg_config.long = field.name;
                }
                
                if (field_config.short) |short| {
                    arg_config.short = short;
                }
                
                if (field_config.default) |default| {
                    arg_config.default = parseDefaultValue(field.type, default);
                }
                
                if (field_config.env) |env| {
                    arg_config.env = env;
                }
                
                try args_list.append(Argument.Argument.init(field.name, arg_config));
            },
        }
    }
    
    command_config.args = try args_list.toOwnedSlice();
    command_config.flags = try flags_list.toOwnedSlice();
    
    const command_name = if (@hasField(@TypeOf(config), "name")) 
        config.name 
    else 
        @typeName(T);
    
    return Command.Command.init(command_name, command_config);
}

/// Parse values from context into struct instance
fn parseFromContext(comptime T: type, allocator: std.mem.Allocator, context: Context.Context) !T {
    var result: T = undefined;
    const type_info = @typeInfo(T);
    
    inline for (type_info.Struct.fields) |field| {
        const field_value = switch (field.type) {
            bool => context.getFlag(field.name),
            []const u8 => context.getString(field.name),
            ?[]const u8 => context.getString(field.name),
            i32 => context.getInt(field.name),
            ?i32 => context.getInt(field.name),
            f64 => context.getFloat(field.name),
            ?f64 => context.getFloat(field.name),
            else => blk: {
                // Handle optional types
                if (field.type == @TypeOf(null)) {
                    break :blk null;
                }
                
                // Handle arrays/slices
                if (comptime std.meta.trait.isSlice(field.type)) {
                    const slice_info = @typeInfo(field.type);
                    if (slice_info.Pointer.child == []const u8) {
                        // Array of strings
                        break :blk try context.getStringArray(field.name, allocator);
                    }
                }
                
                @compileError("Unsupported field type: " ++ @typeName(field.type));
            },
        };
        
        if (field_value) |value| {
            @field(result, field.name) = value;
        } else {
            // Use default value if available
            if (field.default_value) |default_ptr| {
                const default_value = @as(*const field.type, @ptrCast(@alignCast(default_ptr))).*;
                @field(result, field.name) = default_value;
            } else {
                // Check if field is required
                const field_config = getFieldConfig(T, field.name);
                if (field_config.required) {
                    return Error.FlashError.MissingRequiredArgument;
                }
                
                // Use zero value for non-optional types
                @field(result, field.name) = std.mem.zeroes(field.type);
            }
        }
    }
    
    return result;
}

/// Get field configuration (placeholder for now)
fn getFieldConfig(comptime T: type, comptime field_name: []const u8) FieldConfig {
    _ = T;
    _ = field_name;
    return FieldConfig{};
}

/// Parse default value from string
fn parseDefaultValue(comptime T: type, value: []const u8) Argument.ArgValue {
    return switch (T) {
        []const u8, ?[]const u8 => Argument.ArgValue{ .string = value },
        i32, ?i32 => Argument.ArgValue{ .int = std.fmt.parseInt(i32, value, 10) catch 0 },
        f64, ?f64 => Argument.ArgValue{ .float = std.fmt.parseFloat(f64, value) catch 0.0 },
        bool => Argument.ArgValue{ .bool = std.mem.eql(u8, value, "true") },
        else => Argument.ArgValue{ .string = value },
    };
}

/// Generate help text from struct
pub fn generateHelp(comptime T: type, allocator: std.mem.Allocator, config: anytype) ![]const u8 {
    const command = try generateCommand(T, allocator, config);
    const help = @import("help.zig").Help.init(allocator);
    
    var buffer = std.ArrayList(u8).init(allocator);
    const writer = buffer.writer();
    
    try help.printCommandHelp(writer, command, @typeName(T));
    return buffer.toOwnedSlice();
}

/// Derive macro for automatic implementation
pub fn derive(comptime config: DeriveConfig) type {
    return struct {
        pub const derive_config = config;
        
        pub fn generateHelp(comptime T: type, allocator: std.mem.Allocator) ![]const u8 {
            return @import("declarative.zig").generateHelp(T, allocator, config);
        }
        
        pub fn parse(comptime T: type, allocator: std.mem.Allocator) !T {
            return @import("declarative.zig").parseWithConfig(T, allocator, config);
        }
    };
}

test "declarative struct parsing" {
    const allocator = std.testing.allocator;
    
    const TestArgs = struct {
        name: []const u8,
        count: i32 = 1,
        verbose: bool = false,
    };
    
    const args = [_][]const u8{ "test", "--name", "Alice", "--count", "5", "--verbose" };
    
    const parsed = try parseWithArgs(TestArgs, allocator, &args, .{
        .about = "Test command",
        .name = "test",
    });
    
    try std.testing.expectEqualStrings("Alice", parsed.name);
    try std.testing.expectEqual(@as(i32, 5), parsed.count);
    try std.testing.expectEqual(true, parsed.verbose);
}

test "declarative optional fields" {
    const allocator = std.testing.allocator;
    
    const TestArgs = struct {
        required_arg: []const u8,
        optional_arg: ?[]const u8 = null,
        flag: bool = false,
    };
    
    const args = [_][]const u8{ "test", "--required-arg", "value" };
    
    const parsed = try parseWithArgs(TestArgs, allocator, &args, .{
        .name = "test",
    });
    
    try std.testing.expectEqualStrings("value", parsed.required_arg);
    try std.testing.expectEqual(@as(?[]const u8, null), parsed.optional_arg);
    try std.testing.expectEqual(false, parsed.flag);
}