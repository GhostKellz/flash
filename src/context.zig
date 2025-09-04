//! Context for storing parsed CLI arguments and flags
//!
//! The context is passed to command handlers and provides access
//! to all parsed values, subcommands, and utility methods.

const std = @import("std");
const Argument = @import("argument.zig");
const Error = @import("error.zig");

/// Context passed to command handlers
pub const Context = struct {
    allocator: std.mem.Allocator,
    values: std.StringHashMap(Argument.ArgValue),
    flags: std.StringHashMap(bool),
    positional: std.ArrayList(Argument.ArgValue),
    subcommand: ?[]const u8 = null,
    raw_args: []const []const u8,

    pub fn init(allocator: std.mem.Allocator, raw_args: []const []const u8) !Context {
        return .{
            .allocator = allocator,
            .values = std.StringHashMap(Argument.ArgValue).init(allocator),
            .flags = std.StringHashMap(bool).init(allocator),
            .positional = try std.ArrayList(Argument.ArgValue).initCapacity(allocator, 0),
            .raw_args = raw_args,
        };
    }

    pub fn deinit(self: *Context) void {
        self.values.deinit();
        self.flags.deinit();
        self.positional.deinit(self.allocator);
    }

    /// Set a named argument value
    pub fn setValue(self: *Context, name: []const u8, value: Argument.ArgValue) !void {
        try self.values.put(name, value);
    }

    /// Set a flag value
    pub fn setFlag(self: *Context, name: []const u8, value: bool) !void {
        try self.flags.put(name, value);
    }

    /// Add a positional argument
    pub fn addPositional(self: *Context, value: Argument.ArgValue) !void {
        try self.positional.append(self.allocator, value);
    }

    /// Set the subcommand name
    pub fn setSubcommand(self: *Context, subcommand: []const u8) void {
        self.subcommand = subcommand;
    }

    /// Get a named argument value
    pub fn get(self: Context, name: []const u8) ?Argument.ArgValue {
        return self.values.get(name);
    }

    /// Get a string argument value
    pub fn getString(self: Context, name: []const u8) ?[]const u8 {
        if (self.get(name)) |value| {
            return value.asString();
        }
        return null;
    }

    /// Get an integer argument value
    pub fn getInt(self: Context, name: []const u8) ?i64 {
        if (self.get(name)) |value| {
            return value.asInt();
        }
        return null;
    }

    /// Get a float argument value
    pub fn getFloat(self: Context, name: []const u8) ?f64 {
        if (self.get(name)) |value| {
            return value.asFloat();
        }
        return null;
    }

    /// Get a boolean argument value
    pub fn getBool(self: Context, name: []const u8) ?bool {
        if (self.get(name)) |value| {
            return value.asBool();
        }
        return null;
    }

    /// Get a flag value
    pub fn getFlag(self: Context, name: []const u8) bool {
        return self.flags.get(name) orelse false;
    }

    /// Get a positional argument by index
    pub fn getPositional(self: Context, index: usize) ?Argument.ArgValue {
        if (index < self.positional.items.len) {
            return self.positional.items[index];
        }
        return null;
    }

    /// Get the number of positional arguments
    pub fn getPositionalCount(self: Context) usize {
        return self.positional.items.len;
    }

    /// Get all positional arguments
    pub fn getPositionalArgs(self: Context) []const Argument.ArgValue {
        return self.positional.items;
    }

    /// Get the subcommand name
    pub fn getSubcommand(self: Context) ?[]const u8 {
        return self.subcommand;
    }

    /// Get the raw arguments passed to the CLI
    pub fn getRawArgs(self: Context) []const []const u8 {
        return self.raw_args;
    }

    /// Check if a named argument was provided
    pub fn hasArg(self: Context, name: []const u8) bool {
        return self.values.contains(name);
    }

    /// Check if a flag was provided
    pub fn hasFlag(self: Context, name: []const u8) bool {
        return self.flags.contains(name);
    }

    /// Get a string array argument value
    pub fn getStringArray(self: Context, name: []const u8, allocator: std.mem.Allocator) !?[][]const u8 {
        // Check if we have multiple values stored for this name
        if (self.values.get(name)) |value| {
            switch (value) {
                .string => |s| {
                    // Single string value - return as array of one element
                    const result = try allocator.alloc([]const u8, 1);
                    result[0] = s;
                    return result;
                },
                .array => |array| {
                    // Multiple string values
                    const result = try allocator.alloc([]const u8, array.len);
                    for (array, 0..) |item, i| {
                        result[i] = item.asString();
                    }
                    return result;
                },
                else => return null,
            }
        }
        
        // Check if we have it as a string that needs to be split
        if (self.get(name)) |value| {
            const str = value.asString();
            // Split by comma for basic array support
            var result = std.ArrayList([]const u8).init(allocator);
            var it = std.mem.splitScalar(u8, str, ',');
            while (it.next()) |item| {
                const trimmed = std.mem.trim(u8, item, " \t");
                if (trimmed.len > 0) {
                    try result.append(trimmed);
                }
            }
            return result.toOwnedSlice();
        }
        
        return null;
    }
    
    /// Add a value to an array argument
    pub fn addArrayValue(self: *Context, name: []const u8, value: Argument.ArgValue) !void {
        if (self.values.get(name)) |existing| {
            switch (existing) {
                .array => |array| {
                    // Add to existing array
                    var new_array = try self.allocator.alloc(Argument.ArgValue, array.len + 1);
                    std.mem.copy(Argument.ArgValue, new_array[0..array.len], array);
                    new_array[array.len] = value;
                    try self.values.put(name, Argument.ArgValue{ .array = new_array });
                },
                else => {
                    // Convert single value to array
                    const array = try self.allocator.alloc(Argument.ArgValue, 2);
                    array[0] = existing;
                    array[1] = value;
                    try self.values.put(name, Argument.ArgValue{ .array = array });
                },
            }
        } else {
            // Create new array with single value
            const array = try self.allocator.alloc(Argument.ArgValue, 1);
            array[0] = value;
            try self.values.put(name, Argument.ArgValue{ .array = array });
        }
    }

    /// Get a typed value with a default
    pub fn getWithDefault(self: Context, comptime T: type, name: []const u8, default: T) T {
        const arg_type = Argument.ArgType.fromType(T);
        if (self.get(name)) |value| {
            return switch (arg_type) {
                .string => value.asString(),
                .int => @intCast(value.asInt()),
                .float => @floatCast(value.asFloat()),
                .bool => value.asBool(),
                .@"enum" => value.asString(),
                .array => value.asArray(),
            };
        }
        return default;
    }

    /// Print debug information about the context
    pub fn debug(self: Context, writer: anytype) !void {
        try writer.print("Context Debug:\n");
        try writer.print("  Subcommand: {?s}\n", .{self.subcommand});
        try writer.print("  Arguments:\n");

        var value_iter = self.values.iterator();
        while (value_iter.next()) |entry| {
            try writer.print("    {s}: {}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }

        try writer.print("  Flags:\n");
        var flag_iter = self.flags.iterator();
        while (flag_iter.next()) |entry| {
            try writer.print("    {s}: {}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }

        try writer.print("  Positional ({d}):\n", .{self.positional.items.len});
        for (self.positional.items, 0..) |item, i| {
            try writer.print("    [{d}]: {}\n", .{ i, item });
        }
    }
};

test "context operations" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{ "test", "arg1", "arg2" };

    var ctx = Context.init(allocator, &args);
    defer ctx.deinit();

    // Test setting and getting values
    try ctx.setValue("name", Argument.ArgValue{ .string = "test" });
    try ctx.setFlag("verbose", true);
    try ctx.addPositional(Argument.ArgValue{ .string = "pos1" });
    ctx.setSubcommand("subcmd");

    try std.testing.expectEqualStrings("test", ctx.getString("name").?);
    try std.testing.expectEqual(true, ctx.getFlag("verbose"));
    try std.testing.expectEqualStrings("pos1", ctx.getPositional(0).?.asString());
    try std.testing.expectEqualStrings("subcmd", ctx.getSubcommand().?);
    try std.testing.expectEqual(@as(usize, 1), ctx.getPositionalCount());

    // Test defaults
    try std.testing.expectEqualStrings("default", ctx.getWithDefault([]const u8, "missing", "default"));
    try std.testing.expectEqual(@as(i32, 42), ctx.getWithDefault(i32, "missing", 42));
    try std.testing.expectEqual(false, ctx.getFlag("missing"));

    // Test existence checks
    try std.testing.expectEqual(true, ctx.hasArg("name"));
    try std.testing.expectEqual(false, ctx.hasArg("missing"));
    try std.testing.expectEqual(true, ctx.hasFlag("verbose"));
    try std.testing.expectEqual(false, ctx.hasFlag("missing"));
}
