//! Argument parser for Flash CLI
//!
//! Handles parsing command line arguments into typed values,
//! with support for flags, options, positional arguments, and subcommands.

const std = @import("std");
const Argument = @import("argument.zig");
const Flag = @import("flag.zig");
const Command = @import("command.zig");
const Context = @import("context.zig");
const Error = @import("error.zig");

/// Parser state for argument parsing
const ParseState = struct {
    args: []const []const u8,
    index: usize = 0,
    current_command: Command.Command,
    context: *Context.Context,

    fn hasMore(self: ParseState) bool {
        return self.index < self.args.len;
    }

    fn current(self: ParseState) ?[]const u8 {
        if (self.hasMore()) {
            return self.args[self.index];
        }
        return null;
    }

    fn advance(self: *ParseState) void {
        self.index += 1;
    }

    fn peek(self: ParseState, offset: usize) ?[]const u8 {
        const next_index = self.index + offset;
        if (next_index < self.args.len) {
            return self.args[next_index];
        }
        return null;
    }
};

/// Main argument parser
pub const Parser = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Parser {
        return .{ .allocator = allocator };
    }

    /// Parse command line arguments into a context
    pub fn parse(self: Parser, command: Command.Command, args: []const []const u8) Error.FlashError!Context.Context {
        var context = try Context.Context.init(self.allocator, args);
        errdefer context.deinit();

        var state = ParseState{
            .args = args,
            .current_command = command,
            .context = &context,
        };

        // Skip program name (first argument)
        if (state.hasMore()) {
            state.advance();
        }

        try self.parseCommand(&state);
        try self.validateRequired(&state);
        try self.setDefaults(&state);

        return context;
    }

    /// Parse a command and its arguments
    fn parseCommand(self: Parser, state: *ParseState) Error.FlashError!void {
        while (state.hasMore()) {
            const arg = state.current().?;

            if (std.mem.startsWith(u8, arg, "--")) {
                // Long flag: --flag or --flag=value
                try self.parseLongFlag(state);
            } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
                // Short flag(s): -f or -abc
                try self.parseShortFlags(state);
            } else {
                // Check for builtin commands first (Zig-style)
                if (std.mem.eql(u8, arg, "help")) {
                    // Set help context for current command
                    state.context.setSubcommand("help");
                    return Error.FlashError.HelpRequested;
                } else if (std.mem.eql(u8, arg, "version")) {
                    return Error.FlashError.VersionRequested;
                }
                
                // Check if it's a subcommand
                if (state.current_command.findSubcommand(arg)) |subcmd| {
                    state.context.setSubcommand(arg);
                    state.current_command = subcmd;
                    state.advance();
                    continue;
                }

                // Otherwise, it's a positional argument
                try self.parsePositional(state);
            }
        }
    }

    /// Parse a long flag (--flag or --flag=value)
    fn parseLongFlag(self: Parser, state: *ParseState) Error.FlashError!void {
        const arg = state.current().?;
        state.advance();

        const flag_part = arg[2..]; // Remove --
        var flag_name: []const u8 = undefined;
        var flag_value: ?[]const u8 = null;

        // Check for --flag=value format
        if (std.mem.indexOf(u8, flag_part, "=")) |eq_index| {
            flag_name = flag_part[0..eq_index];
            flag_value = flag_part[eq_index + 1 ..];
        } else {
            flag_name = flag_part;
        }

        // Handle special built-in flags
        if (std.mem.eql(u8, flag_name, "help") or std.mem.eql(u8, flag_name, "h")) {
            return Error.FlashError.HelpRequested;
        }

        if (std.mem.eql(u8, flag_name, "version") or std.mem.eql(u8, flag_name, "V")) {
            return Error.FlashError.VersionRequested;
        }

        // Find the flag in the current command
        if (state.current_command.findFlag(flag_name)) |flag| {
            if (flag_value) |value| {
                // Flag with value: --flag=value
                const parsed_value = try flag.toArgument().parseValue(self.allocator, value);
                try state.context.setValue(flag.name, parsed_value);
            } else {
                // Boolean flag: --flag
                try state.context.setFlag(flag.name, true);
            }
        } else {
            // Check if it's an argument that accepts a value
            if (state.current_command.findArg(flag_name)) |found_arg| {
                var value: []const u8 = undefined;
                if (flag_value) |fv| {
                    value = fv;
                } else if (state.hasMore()) {
                    value = state.current().?;
                    state.advance();
                } else {
                    return Error.FlashError.MissingRequiredArgument;
                }

                const parsed_value = try found_arg.parseValue(self.allocator, value);
                try state.context.setValue(found_arg.name, parsed_value);
            } else {
                return Error.FlashError.UnknownFlag;
            }
        }
    }

    /// Parse short flags (-f or -abc)
    fn parseShortFlags(self: Parser, state: *ParseState) Error.FlashError!void {
        const arg = state.current().?;
        state.advance();

        const flags = arg[1..]; // Remove -

        for (flags, 0..) |char, i| {
            const flag_name = [_]u8{char};

            // Handle special built-in flags
            if (char == 'h') {
                return Error.FlashError.HelpRequested;
            }

            if (char == 'V') {
                return Error.FlashError.VersionRequested;
            }

            // Find the flag in the current command
            if (state.current_command.findFlag(&flag_name)) |flag| {
                try state.context.setFlag(flag.name, true);
            } else {
                // Check if it's an argument that needs a value
                if (state.current_command.findArg(&flag_name)) |found_arg| {
                    var value: []const u8 = undefined;

                    // If this is the last character and there are more args, use the next arg
                    if (i == flags.len - 1 and state.hasMore()) {
                        value = state.current().?;
                        state.advance();
                    } else {
                        return Error.FlashError.MissingRequiredArgument;
                    }

                    const parsed_value = try found_arg.parseValue(self.allocator, value);
                    try state.context.setValue(found_arg.name, parsed_value);
                } else {
                    return Error.FlashError.UnknownFlag;
                }
            }
        }
    }

    /// Parse a positional argument
    fn parsePositional(self: Parser, state: *ParseState) Error.FlashError!void {
        _ = self;

        const arg = state.current().?;
        state.advance();

        // Try to match against expected positional arguments
        const expected_args = state.current_command.getArgs();
        const positional_count = state.context.getPositionalCount();
        
        if (positional_count < expected_args.len) {
            const expected_arg = expected_args[positional_count];
            const parsed_value = try expected_arg.parseValue(state.context.allocator, arg);
            try state.context.setValue(expected_arg.name, parsed_value);
        } else {
            // Store as additional positional argument
            const value = Argument.ArgValue{ .string = arg };
            try state.context.addPositional(value);
        }
    }

    /// Validate that all required arguments are present
    fn validateRequired(self: Parser, state: *ParseState) Error.FlashError!void {
        _ = self;

        for (state.current_command.getArgs()) |arg| {
            if (arg.isRequired() and !state.context.hasArg(arg.name)) {
                return Error.FlashError.MissingRequiredArgument;
            }
        }
    }

    /// Set default values for arguments that weren't provided
    fn setDefaults(self: Parser, state: *ParseState) Error.FlashError!void {
        _ = self;

        for (state.current_command.getArgs()) |arg| {
            if (!state.context.hasArg(arg.name)) {
                if (arg.getDefault()) |default| {
                    try state.context.setValue(arg.name, default);
                }
            }
        }

        for (state.current_command.getFlags()) |flag| {
            if (!state.context.hasFlag(flag.name)) {
                try state.context.setFlag(flag.name, flag.getDefault());
            }
        }
    }
};

test "parser basic functionality" {
    const allocator = std.testing.allocator;
    const parser = Parser.init(allocator);

    const cmd = Command.Command.init("test", (Command.CommandConfig{})
        .withFlags(&.{
            Flag.Flag.init("verbose", (Flag.FlagConfig{}).withShort('v')),
        })
        .withArgs(&.{
        Argument.Argument.init("input", (Argument.ArgumentConfig{}).withLong("input")),
    }));

    const args = [_][]const u8{ "test", "--verbose", "--input", "file.txt", "pos1" };

    var context = try parser.parse(cmd, &args);
    defer context.deinit();

    try std.testing.expectEqual(true, context.getFlag("verbose"));
    try std.testing.expectEqualStrings("file.txt", context.getString("input").?);
    try std.testing.expectEqual(@as(usize, 1), context.getPositionalCount());
    try std.testing.expectEqualStrings("pos1", context.getPositional(0).?.asString());
}

test "parser short flags" {
    const allocator = std.testing.allocator;
    const parser = Parser.init(allocator);

    const cmd = Command.Command.init("test", (Command.CommandConfig{})
        .withFlags(&.{
        Flag.Flag.init("verbose", (Flag.FlagConfig{}).withShort('v')),
        Flag.Flag.init("debug", (Flag.FlagConfig{}).withShort('d')),
    }));

    const args = [_][]const u8{ "test", "-vd" };

    var context = try parser.parse(cmd, &args);
    defer context.deinit();

    try std.testing.expectEqual(true, context.getFlag("verbose"));
    try std.testing.expectEqual(true, context.getFlag("debug"));
}

test "parser subcommands" {
    const allocator = std.testing.allocator;
    const parser = Parser.init(allocator);

    const subcmd = Command.Command.init("start", (Command.CommandConfig{})
        .withFlags(&.{
        Flag.Flag.init("force", (Flag.FlagConfig{}).withShort('f')),
    }));

    const cmd = Command.Command.init("service", (Command.CommandConfig{})
        .withSubcommands(&.{subcmd}));

    const args = [_][]const u8{ "service", "start", "--force" };

    var context = try parser.parse(cmd, &args);
    defer context.deinit();

    try std.testing.expectEqualStrings("start", context.getSubcommand().?);
    try std.testing.expectEqual(true, context.getFlag("force"));
}
