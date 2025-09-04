//! Flash error types and handling

const std = @import("std");

pub const FlashError = error{
    // Parse errors
    InvalidArgument,
    MissingRequiredArgument,
    UnknownFlag,
    InvalidFlagValue,
    TooManyArguments,
    TooFewArguments,

    // Type conversion errors
    InvalidBoolValue,
    InvalidIntValue,
    InvalidFloatValue,
    InvalidEnumValue,

    // Command errors
    UnknownCommand,
    MissingSubcommand,
    AmbiguousCommand,

    // Runtime errors
    AllocationError,
    IOError,
    ConfigError,
    ValidationError,

    // Async errors
    AsyncExecutionFailed,
    OperationCancelled,
    InvalidInput,

    // Help/usage
    HelpRequested,
    VersionRequested,
} || std.mem.Allocator.Error || std.fmt.ParseIntError || std.fmt.ParseFloatError;

pub const ErrorContext = struct {
    message: []const u8,
    arg_name: ?[]const u8 = null,
    flag_name: ?[]const u8 = null,
    command_name: ?[]const u8 = null,
    help_text: ?[]const u8 = null,

    pub fn init(message: []const u8) ErrorContext {
        return .{ .message = message };
    }

    pub fn withArg(self: ErrorContext, arg_name: []const u8) ErrorContext {
        var ctx = self;
        ctx.arg_name = arg_name;
        return ctx;
    }

    pub fn withFlag(self: ErrorContext, flag_name: []const u8) ErrorContext {
        var ctx = self;
        ctx.flag_name = flag_name;
        return ctx;
    }

    pub fn withCommand(self: ErrorContext, command_name: []const u8) ErrorContext {
        var ctx = self;
        ctx.command_name = command_name;
        return ctx;
    }

    pub fn withHelp(self: ErrorContext, help_text: []const u8) ErrorContext {
        var ctx = self;
        ctx.help_text = help_text;
        return ctx;
    }
};

pub fn printError(err: FlashError, context: ?ErrorContext) void {
    std.debug.print("⚡ Flash Error: ", .{});

    switch (err) {
        FlashError.HelpRequested, FlashError.VersionRequested => return,
        FlashError.InvalidArgument => std.debug.print("Invalid argument", .{}),
        FlashError.MissingRequiredArgument => std.debug.print("Missing required argument", .{}),
        FlashError.UnknownFlag => std.debug.print("Unknown flag", .{}),
        FlashError.InvalidFlagValue => std.debug.print("Invalid flag value", .{}),
        FlashError.TooManyArguments => std.debug.print("Too many arguments provided", .{}),
        FlashError.TooFewArguments => std.debug.print("Too few arguments provided", .{}),
        FlashError.UnknownCommand => std.debug.print("Unknown command", .{}),
        FlashError.MissingSubcommand => std.debug.print("Missing subcommand", .{}),
        FlashError.AmbiguousCommand => std.debug.print("Ambiguous command", .{}),
        else => std.debug.print("{}", .{err}),
    }

    if (context) |ctx| {
        if (ctx.arg_name) |name| {
            std.debug.print(" '{s}'", .{name});
        }
        if (ctx.flag_name) |name| {
            std.debug.print(" '--{s}'", .{name});
        }
        if (ctx.command_name) |name| {
            std.debug.print(" '{s}'", .{name});
        }
        if (ctx.message.len > 0) {
            std.debug.print(": {s}", .{ctx.message});
        }
        std.debug.print("\n", .{});

        if (ctx.help_text) |help| {
            std.debug.print("\n{s}\n", .{help});
        }
    } else {
        std.debug.print("\n", .{});
    }
}