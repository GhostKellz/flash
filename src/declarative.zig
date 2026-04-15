//! Declarative command definition system for Flash CLI (Experimental)
//!
//! This module provides a way to define CLI commands using Zig structs
//! with compile-time validation and automatic parsing.
//!
//! USAGE:
//! Define `fieldname_config` declarations in your struct to configure fields:
//! ```zig
//! const MyArgs = struct {
//!     format: []const u8,
//!     pub const format_config = FieldConfig{
//!         .help = "Output format",
//!         .choices = &.{ "json", "yaml" },
//!         .validator = myValidator,
//!     };
//! };
//! ```
//!
//! LIMITATIONS:
//! - Default value handling uses struct field defaults, not FieldConfig.default
//! - For environment variable support, use env.zig directly with your parsed struct

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
    hidden: bool = false,
    multiple: bool = false,
    /// Validation function compatible with ArgumentConfig.validator
    validator: ?*const fn (Argument.ArgValue) Error.FlashError!void = null,
    /// Constrained choices for enum-like arguments
    choices: ?[]const []const u8 = null,
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
                    .validator = field_config.validator,
                    .choices = field_config.choices,
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

/// Get field configuration from struct declarations.
/// NOTE: This currently returns empty config. Field metadata (aliases, env bindings,
/// validators, hidden, defaults) defined in FieldConfig are not yet wired to struct
/// field analysis. Use explicit ArgumentConfig/FlagConfig for now.
fn getFieldConfig(comptime T: type, comptime field_name: []const u8) FieldConfig {
    // Check for field-specific config declarations like `pub const fieldname_config = FieldConfig{...}`
    const config_name = field_name ++ "_config";
    if (@hasDecl(T, config_name)) {
        return @field(T, config_name);
    }
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

test "getFieldConfig reads struct declarations" {
    const ConfiguredArgs = struct {
        name: []const u8,
        pub const name_config = FieldConfig{
            .help = "Your name",
            .required = true,
        };
    };

    const config = getFieldConfig(ConfiguredArgs, "name");
    try std.testing.expectEqualStrings("Your name", config.help.?);
    try std.testing.expectEqual(true, config.required);
}

test "getFieldConfig returns empty for unconfigured fields" {
    const UnconfiguredArgs = struct {
        value: i32,
    };

    const config = getFieldConfig(UnconfiguredArgs, "value");
    try std.testing.expectEqual(@as(?[]const u8, null), config.help);
    try std.testing.expectEqual(false, config.required);
}

fn testPositiveValidator(value: Argument.ArgValue) Error.FlashError!void {
    if (value.asInt() <= 0) {
        return Error.FlashError.ValidationError;
    }
}

test "declarative validator wiring" {
    const allocator = std.testing.allocator;

    const ValidatedArgs = struct {
        count: i32,
        pub const count_config = FieldConfig{
            .help = "A positive number",
            .validator = testPositiveValidator,
        };
    };

    const command = try generateCommand(ValidatedArgs, allocator, .{ .name = "validated" });
    const args = command.getArgs();
    try std.testing.expect(args.len == 1);
    try std.testing.expect(args[0].config.validator != null);
}

test "declarative choices wiring" {
    const allocator = std.testing.allocator;

    const ChoiceArgs = struct {
        format: []const u8,
        pub const format_config = FieldConfig{
            .help = "Output format",
            .choices = &[_][]const u8{ "json", "yaml", "toml" },
        };
    };

    const command = try generateCommand(ChoiceArgs, allocator, .{ .name = "choiced" });
    const args = command.getArgs();
    try std.testing.expect(args.len == 1);
    try std.testing.expect(args[0].config.choices != null);
    try std.testing.expectEqual(@as(usize, 3), args[0].config.choices.?.len);
}

test "declarative hidden field wiring" {
    const allocator = std.testing.allocator;

    const HiddenArgs = struct {
        visible_arg: []const u8,
        hidden_arg: []const u8,
        pub const hidden_arg_config = FieldConfig{
            .hidden = true,
        };
    };

    const command = try generateCommand(HiddenArgs, allocator, .{ .name = "hidden" });
    const args = command.getArgs();
    try std.testing.expectEqual(@as(usize, 2), args.len);

    // Find hidden arg and verify it's marked hidden
    for (args) |arg| {
        if (std.mem.eql(u8, arg.name, "hidden_arg")) {
            try std.testing.expectEqual(true, arg.config.hidden);
        }
    }
}

test "declarative multiple field wiring" {
    const allocator = std.testing.allocator;

    const MultiArgs = struct {
        files: []const u8,
        pub const files_config = FieldConfig{
            .multiple = true,
            .help = "Input files",
        };
    };

    const command = try generateCommand(MultiArgs, allocator, .{ .name = "multi" });
    const args = command.getArgs();
    try std.testing.expectEqual(@as(usize, 1), args.len);
    try std.testing.expectEqual(true, args[0].config.multiple);
}

test "declarative short and long flags" {
    const allocator = std.testing.allocator;

    const FlagArgs = struct {
        output: []const u8,
        pub const output_config = FieldConfig{
            .short = 'o',
            .long = "output",
            .help = "Output file",
        };
    };

    const command = try generateCommand(FlagArgs, allocator, .{ .name = "flagged" });
    const args = command.getArgs();
    try std.testing.expectEqual(@as(usize, 1), args.len);
    try std.testing.expectEqual(@as(u8, 'o'), args[0].config.short.?);
    try std.testing.expectEqualStrings("output", args[0].config.long.?);
}

test "derive config generation" {
    const TestDerive = derive(.{
        .help = true,
        .version = "1.0.0",
        .about = "Test app",
    });

    try std.testing.expectEqualStrings("1.0.0", TestDerive.derive_config.version.?);
    try std.testing.expectEqualStrings("Test app", TestDerive.derive_config.about.?);
}

test "generateCommand with full config" {
    const allocator = std.testing.allocator;

    const FullArgs = struct {
        input: []const u8,
        output: []const u8,
        verbose: bool = false,
        format: []const u8,

        pub const input_config = FieldConfig{
            .help = "Input file",
            .required = true,
            .short = 'i',
        };
        pub const output_config = FieldConfig{
            .help = "Output file",
            .short = 'o',
            .long = "output",
        };
        pub const format_config = FieldConfig{
            .choices = &[_][]const u8{ "json", "csv" },
        };
    };

    const command = try generateCommand(FullArgs, allocator, .{
        .name = "converter",
        .about = "File converter",
        .version = "2.0.0",
    });

    try std.testing.expectEqualStrings("converter", command.name);
    try std.testing.expectEqualStrings("File converter", command.getAbout().?);

    // Should have 3 args (input, output, format) and 1 flag (verbose)
    try std.testing.expectEqual(@as(usize, 3), command.getArgs().len);
    try std.testing.expectEqual(@as(usize, 1), command.getFlags().len);
}