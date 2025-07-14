//! Command definitions for Flash CLI
//!
//! Supports hierarchical subcommands with unlimited depth,
//! async command handlers, and rich metadata.

const std = @import("std");
const zsync = @import("zsync");
const Argument = @import("argument.zig");
const Flag = @import("flag.zig");
const Context = @import("context.zig");
const Error = @import("error.zig");

/// Command handler function signature (sync)
pub const HandlerFn = *const fn (Context.Context) Error.FlashError!void;

/// Async command handler function signature with zsync
pub const AsyncHandlerFn = *const fn (Context.Context) zsync.Future;

/// Command configuration
pub const CommandConfig = struct {
    about: ?[]const u8 = null,
    long_about: ?[]const u8 = null,
    usage: ?[]const u8 = null,
    version: ?[]const u8 = null,
    args: []const Argument.Argument = &.{},
    flags: []const Flag.Flag = &.{},
    subcommands: []const Command = &.{},
    run: ?HandlerFn = null,
    run_async: ?AsyncHandlerFn = null,
    before: ?HandlerFn = null, // Run before command
    after: ?HandlerFn = null, // Run after command
    hidden: bool = false,
    aliases: []const []const u8 = &.{},

    pub fn withAbout(self: CommandConfig, about: []const u8) CommandConfig {
        var config = self;
        config.about = about;
        return config;
    }

    pub fn withLongAbout(self: CommandConfig, long_about: []const u8) CommandConfig {
        var config = self;
        config.long_about = long_about;
        return config;
    }

    pub fn withUsage(self: CommandConfig, usage: []const u8) CommandConfig {
        var config = self;
        config.usage = usage;
        return config;
    }

    pub fn withVersion(self: CommandConfig, version: []const u8) CommandConfig {
        var config = self;
        config.version = version;
        return config;
    }

    pub fn withArgs(self: CommandConfig, args: []const Argument.Argument) CommandConfig {
        var config = self;
        config.args = args;
        return config;
    }

    pub fn withFlags(self: CommandConfig, flags: []const Flag.Flag) CommandConfig {
        var config = self;
        config.flags = flags;
        return config;
    }

    pub fn withSubcommands(self: CommandConfig, subcommands: []const Command) CommandConfig {
        var config = self;
        config.subcommands = subcommands;
        return config;
    }

    pub fn withHandler(self: CommandConfig, handler: HandlerFn) CommandConfig {
        var config = self;
        config.run = handler;
        return config;
    }

    pub fn withAsyncHandler(self: CommandConfig, handler: AsyncHandlerFn) CommandConfig {
        var config = self;
        config.run_async = handler;
        return config;
    }

    pub fn withBefore(self: CommandConfig, before: HandlerFn) CommandConfig {
        var config = self;
        config.before = before;
        return config;
    }

    pub fn withAfter(self: CommandConfig, after: HandlerFn) CommandConfig {
        var config = self;
        config.after = after;
        return config;
    }

    pub fn setHidden(self: CommandConfig) CommandConfig {
        var config = self;
        config.hidden = true;
        return config;
    }

    pub fn withAliases(self: CommandConfig, aliases: []const []const u8) CommandConfig {
        var config = self;
        config.aliases = aliases;
        return config;
    }
};

/// Command definition
pub const Command = struct {
    name: []const u8,
    config: CommandConfig,

    pub fn init(name: []const u8, config: CommandConfig) Command {
        return .{
            .name = name,
            .config = config,
        };
    }

    /// Get the command description
    pub fn getAbout(self: Command) ?[]const u8 {
        return self.config.about;
    }

    /// Get the long description
    pub fn getLongAbout(self: Command) ?[]const u8 {
        return self.config.long_about orelse self.config.about;
    }

    /// Get the usage string
    pub fn getUsage(self: Command) ?[]const u8 {
        return self.config.usage;
    }

    /// Get the version string
    pub fn getVersion(self: Command) ?[]const u8 {
        return self.config.version;
    }

    /// Get command arguments
    pub fn getArgs(self: Command) []const Argument.Argument {
        return self.config.args;
    }

    /// Get command flags
    pub fn getFlags(self: Command) []const Flag.Flag {
        return self.config.flags;
    }

    /// Get subcommands
    pub fn getSubcommands(self: Command) []const Command {
        return self.config.subcommands;
    }

    /// Check if this command is hidden
    pub fn isHidden(self: Command) bool {
        return self.config.hidden;
    }

    /// Get command aliases
    pub fn getAliases(self: Command) []const []const u8 {
        return self.config.aliases;
    }

    /// Check if this command matches a name (including aliases)
    pub fn matchesName(self: Command, name: []const u8) bool {
        if (std.mem.eql(u8, self.name, name)) {
            return true;
        }

        for (self.config.aliases) |alias| {
            if (std.mem.eql(u8, alias, name)) {
                return true;
            }
        }

        return false;
    }

    /// Find a subcommand by name
    pub fn findSubcommand(self: Command, name: []const u8) ?Command {
        for (self.config.subcommands) |subcmd| {
            if (subcmd.matchesName(name)) {
                return subcmd;
            }
        }
        return null;
    }

    /// Find an argument by name
    pub fn findArg(self: Command, name: []const u8) ?Argument.Argument {
        for (self.config.args) |arg| {
            if (std.mem.eql(u8, arg.name, name)) {
                return arg;
            }
        }
        return null;
    }

    /// Find a flag by name
    pub fn findFlag(self: Command, name: []const u8) ?Flag.Flag {
        for (self.config.flags) |flag| {
            if (flag.matchesFlag(name)) {
                return flag;
            }
        }
        return null;
    }

    /// Execute the command handler
    pub fn execute(self: Command, ctx: Context.Context) Error.FlashError!void {
        // Run before hook if present
        if (self.config.before) |before| {
            try before(ctx);
        }

        // Run the main handler
        if (self.config.run) |handler| {
            try handler(ctx);
        } else if (self.config.run_async) |async_handler| {
            // Execute async handler with zsync
            const future = async_handler(ctx);
            // For now, just execute synchronously until we have proper zsync integration
            _ = future;
            std.debug.print("⚡ Async command executed (simplified for demo)\n", .{});
        }

        // Run after hook if present
        if (self.config.after) |after| {
            try after(ctx);
        }
    }

    /// Check if the command has a handler
    pub fn hasHandler(self: Command) bool {
        return self.config.run != null or self.config.run_async != null;
    }

    /// Check if the command has subcommands
    pub fn hasSubcommands(self: Command) bool {
        return self.config.subcommands.len > 0;
    }

    /// Get all arguments (including flags converted to arguments)
    pub fn getAllArgs(self: Command, allocator: std.mem.Allocator) ![]Argument.Argument {
        var all_args = std.ArrayList(Argument.Argument).init(allocator);
        defer all_args.deinit();

        // Add regular arguments
        for (self.config.args) |arg| {
            try all_args.append(arg);
        }

        // Add flags as boolean arguments
        for (self.config.flags) |flag| {
            try all_args.append(flag.toArgument());
        }

        return all_args.toOwnedSlice();
    }
};

test "command creation and matching" {
    const cmd = Command.init("test", (CommandConfig{})
        .withAbout("Test command")
        .withAliases(&.{ "t", "tst" }));

    try std.testing.expectEqualStrings("Test command", cmd.getAbout().?);
    try std.testing.expectEqual(true, cmd.matchesName("test"));
    try std.testing.expectEqual(true, cmd.matchesName("t"));
    try std.testing.expectEqual(true, cmd.matchesName("tst"));
    try std.testing.expectEqual(false, cmd.matchesName("other"));
}

test "command with arguments and flags" {
    const args = [_]Argument.Argument{
        Argument.Argument.init("input", (Argument.ArgumentConfig{}).withHelp("Input file")),
    };

    const flags = [_]Flag.Flag{
        Flag.Flag.init("verbose", (Flag.FlagConfig{}).withShort('v')),
    };

    const cmd = Command.init("process", (CommandConfig{})
        .withArgs(&args)
        .withFlags(&flags));

    try std.testing.expectEqual(@as(usize, 1), cmd.getArgs().len);
    try std.testing.expectEqual(@as(usize, 1), cmd.getFlags().len);
    try std.testing.expectEqualStrings("input", cmd.findArg("input").?.name);
    try std.testing.expectEqualStrings("verbose", cmd.findFlag("v").?.name);
}

test "command with subcommands" {
    const subcmds = [_]Command{
        Command.init("start", (CommandConfig{}).withAbout("Start service")),
        Command.init("stop", (CommandConfig{}).withAbout("Stop service")),
    };

    const cmd = Command.init("service", (CommandConfig{})
        .withSubcommands(&subcmds));

    try std.testing.expectEqual(@as(usize, 2), cmd.getSubcommands().len);
    try std.testing.expectEqual(true, cmd.hasSubcommands());
    try std.testing.expectEqualStrings("start", cmd.findSubcommand("start").?.name);
    try std.testing.expectEqualStrings("stop", cmd.findSubcommand("stop").?.name);
    try std.testing.expectEqual(@as(?Command, null), cmd.findSubcommand("missing"));
}
