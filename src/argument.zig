//! Argument definitions for Flash CLI
//!
//! Supports typed arguments (bool, int, string, enum, etc) with
//! required/optional/default value logic and validation.

const std = @import("std");
const Error = @import("error.zig");

/// Supported argument types
pub const ArgType = enum {
    string,
    int,
    float,
    bool,
    @"enum",
    array,

    pub fn fromType(comptime T: type) ArgType {
        return switch (@typeInfo(T)) {
            .int => .int,
            .float => .float,
            .bool => .bool,
            .@"enum" => .@"enum",
            .optional => |opt| fromType(opt.child),
            .pointer => |ptr| {
                if (ptr.child == u8) return .string;
                if (ptr.size == .Slice) return .array;
                @compileError("Unsupported pointer type");
            },
            .array => .array,
            else => @compileError("Unsupported argument type: " ++ @typeName(T)),
        };
    }
};

/// Argument value storage
pub const ArgValue = union(ArgType) {
    string: []const u8,
    int: i64,
    float: f64,
    bool: bool,
    @"enum": []const u8, // Store as string, convert when needed
    array: []ArgValue, // Array of values

    pub fn format(self: ArgValue, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        switch (self) {
            .string => |s| try writer.print("'{s}'", .{s}),
            .int => |i| try writer.print("{d}", .{i}),
            .float => |f| try writer.print("{d}", .{f}),
            .bool => |b| try writer.print("{}", .{b}),
            .@"enum" => |e| try writer.print("'{s}'", .{e}),
            .array => |a| {
                try writer.print("[", .{});
                for (a, 0..) |item, i| {
                    if (i > 0) try writer.print(", ", .{});
                    try item.format(fmt, options, writer);
                }
                try writer.print("]", .{});
            },
        }
    }

    pub fn asString(self: ArgValue) []const u8 {
        return switch (self) {
            .string => |s| s,
            .@"enum" => |e| e,
            else => @panic("Value is not a string"),
        };
    }

    pub fn asInt(self: ArgValue) i64 {
        return switch (self) {
            .int => |i| i,
            else => @panic("Value is not an integer"),
        };
    }

    pub fn asFloat(self: ArgValue) f64 {
        return switch (self) {
            .float => |f| f,
            else => @panic("Value is not a float"),
        };
    }

    pub fn asBool(self: ArgValue) bool {
        return switch (self) {
            .bool => |b| b,
            else => @panic("Value is not a boolean"),
        };
    }
    
    pub fn asArray(self: ArgValue) []ArgValue {
        return switch (self) {
            .array => |a| a,
            else => @panic("Value is not an array"),
        };
    }
};

/// Argument configuration
pub const ArgumentConfig = struct {
    help: ?[]const u8 = null,
    required: bool = false,
    default: ?ArgValue = null,
    short: ?u8 = null, // Single character short flag
    long: ?[]const u8 = null, // Long flag name
    multiple: bool = false, // Can be specified multiple times
    hidden: bool = false, // Hidden from help
    validator: ?*const fn (ArgValue) Error.FlashError!void = null,

    pub fn withHelp(self: ArgumentConfig, help: []const u8) ArgumentConfig {
        var config = self;
        config.help = help;
        return config;
    }

    pub fn withDefault(self: ArgumentConfig, default: ArgValue) ArgumentConfig {
        var config = self;
        config.default = default;
        return config;
    }

    pub fn setRequired(self: ArgumentConfig) ArgumentConfig {
        var config = self;
        config.required = true;
        return config;
    }

    pub fn withShort(self: ArgumentConfig, short: u8) ArgumentConfig {
        var config = self;
        config.short = short;
        return config;
    }

    pub fn withLong(self: ArgumentConfig, long: []const u8) ArgumentConfig {
        var config = self;
        config.long = long;
        return config;
    }

    pub fn setMultiple(self: ArgumentConfig) ArgumentConfig {
        var config = self;
        config.multiple = true;
        return config;
    }

    pub fn setHidden(self: ArgumentConfig) ArgumentConfig {
        var config = self;
        config.hidden = true;
        return config;
    }
};

/// Argument definition
pub const Argument = struct {
    name: []const u8,
    arg_type: ArgType,
    config: ArgumentConfig,

    pub fn init(name: []const u8, config: ArgumentConfig) Argument {
        return .{
            .name = name,
            .arg_type = .string, // Default to string, can be overridden
            .config = config,
        };
    }

    pub fn typed(comptime T: type, name: []const u8, config: ArgumentConfig) Argument {
        return .{
            .name = name,
            .arg_type = ArgType.fromType(T),
            .config = config,
        };
    }

    /// Parse a string value into the correct type for this argument
    pub fn parseValue(self: Argument, allocator: std.mem.Allocator, input: []const u8) Error.FlashError!ArgValue {
        const value = switch (self.arg_type) {
            .string => ArgValue{ .string = input },
            .int => ArgValue{ .int = std.fmt.parseInt(i64, input, 10) catch |err| switch (err) {
                error.InvalidCharacter, error.Overflow => return Error.FlashError.InvalidIntValue,
            } },
            .float => ArgValue{ .float = std.fmt.parseFloat(f64, input) catch return Error.FlashError.InvalidFloatValue },
            .bool => blk: {
                if (std.mem.eql(u8, input, "true") or std.mem.eql(u8, input, "1") or std.mem.eql(u8, input, "yes")) {
                    break :blk ArgValue{ .bool = true };
                } else if (std.mem.eql(u8, input, "false") or std.mem.eql(u8, input, "0") or std.mem.eql(u8, input, "no")) {
                    break :blk ArgValue{ .bool = false };
                } else {
                    return Error.FlashError.InvalidBoolValue;
                }
            },
            .@"enum" => ArgValue{ .@"enum" = input },
            .array => blk: {
                // Parse comma-separated values
                var result = std.ArrayList(ArgValue).initCapacity(allocator, 0) catch return Error.FlashError.InvalidInput;
                var it = std.mem.splitScalar(u8, input, ',');
                while (it.next()) |item| {
                    const trimmed = std.mem.trim(u8, item, " \t");
                    if (trimmed.len > 0) {
                        // Parse each item as a string by default
                        try result.append(allocator, ArgValue{ .string = trimmed });
                    }
                }
                break :blk ArgValue{ .array = try result.toOwnedSlice(allocator) };
            },
        };

        // Run validator if present
        if (self.config.validator) |validator| {
            try validator(value);
        }

        return value;
    }

    /// Get the default value for this argument
    pub fn getDefault(self: Argument) ?ArgValue {
        return self.config.default;
    }

    /// Check if this argument is required
    pub fn isRequired(self: Argument) bool {
        return self.config.required;
    }

    /// Get help text for this argument
    pub fn getHelp(self: Argument) ?[]const u8 {
        return self.config.help;
    }

    /// Check if this argument matches a flag name
    pub fn matchesFlag(self: Argument, flag: []const u8) bool {
        if (flag.len == 1) {
            return self.config.short != null and self.config.short.? == flag[0];
        } else {
            return self.config.long != null and std.mem.eql(u8, self.config.long.?, flag);
        }
    }
};

test "argument type detection" {
    try std.testing.expect(ArgType.fromType([]const u8) == .string);
    try std.testing.expect(ArgType.fromType(i32) == .int);
    try std.testing.expect(ArgType.fromType(f64) == .float);
    try std.testing.expect(ArgType.fromType(bool) == .bool);
}

test "argument value parsing" {
    const allocator = std.testing.allocator;

    const string_arg = Argument.typed([]const u8, "test", .{});
    const int_arg = Argument.typed(i32, "num", .{});
    const bool_arg = Argument.typed(bool, "flag", .{});

    const string_val = try string_arg.parseValue(allocator, "hello");
    try std.testing.expectEqualStrings("hello", string_val.asString());

    const int_val = try int_arg.parseValue(allocator, "42");
    try std.testing.expectEqual(@as(i64, 42), int_val.asInt());

    const bool_val = try bool_arg.parseValue(allocator, "true");
    try std.testing.expectEqual(true, bool_val.asBool());
}

test "argument configuration" {
    const arg = Argument.init("test", (ArgumentConfig{})
        .withHelp("Test argument")
        .withDefault(ArgValue{ .string = "default" })
        .setRequired()
        .withShort('t')
        .withLong("test"));

    try std.testing.expectEqualStrings("Test argument", arg.getHelp().?);
    try std.testing.expectEqual(true, arg.isRequired());
    try std.testing.expectEqualStrings("default", arg.getDefault().?.asString());
    try std.testing.expectEqual(true, arg.matchesFlag("t"));
    try std.testing.expectEqual(true, arg.matchesFlag("test"));
    try std.testing.expectEqual(false, arg.matchesFlag("other"));
}
