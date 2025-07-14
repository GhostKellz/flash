//! ⚡ Flash Help - Lightning-fast CLI help generation
//!
//! Generates beautiful help text with Zig-style command patterns

const std = @import("std");
const Command = @import("command.zig");
const Argument = @import("argument.zig");
const Flag = @import("flag.zig");

pub const Help = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Help {
        return .{ .allocator = allocator };
    }

    pub fn printHelp(self: Help, command: Command.Command, program_name: ?[]const u8) void {
        const name = program_name orelse command.name;

        // Flash header with lightning emoji
        std.debug.print("⚡ {s}", .{name});
        if (command.getVersion()) |version| {
            std.debug.print(" {s}", .{version});
        }
        if (command.getAbout()) |about| {
            std.debug.print(" - {s}", .{about});
        }
        std.debug.print("\n\n", .{});

        std.debug.print("USAGE:\n", .{});
        printUsage(self, command, name);
        std.debug.print("\n", .{});

        if (command.getArgs().len > 0) {
            std.debug.print("ARGUMENTS:\n", .{});
            for (command.getArgs()) |arg| {
                printArgument(self, arg);
            }
            std.debug.print("\n", .{});
        }

        if (command.getFlags().len > 0) {
            std.debug.print("OPTIONS:\n", .{});
            for (command.getFlags()) |flag| {
                printFlag(self, flag);
            }
            printBuiltinFlags(self);
            std.debug.print("\n", .{});
        }

        if (command.hasSubcommands()) {
            std.debug.print("COMMANDS:\n", .{});
            for (command.getSubcommands()) |subcmd| {
                if (!subcmd.isHidden()) {
                    printSubcommand(self, subcmd);
                }
            }
            // Add builtin Zig-style commands
            std.debug.print("    help\n        Show help information\n", .{});
            std.debug.print("    version\n        Show version information\n", .{});
            std.debug.print("\n", .{});
        }
    }

    fn printUsage(self: Help, command: Command.Command, program_name: []const u8) void {
        _ = self;
        std.debug.print("    {s}", .{program_name});

        if (command.getFlags().len > 0) {
            std.debug.print(" [OPTIONS]", .{});
        }

        for (command.getArgs()) |arg| {
            if (arg.isRequired()) {
                std.debug.print(" <{s}>", .{arg.name});
            } else {
                std.debug.print(" [{s}]", .{arg.name});
            }
        }

        if (command.hasSubcommands()) {
            std.debug.print(" <COMMAND>", .{});
        }

        std.debug.print("\n", .{});
    }

    fn printArgument(self: Help, arg: Argument.Argument) void {
        _ = self;
        std.debug.print("    {s}", .{arg.name});
        if (arg.isRequired()) {
            std.debug.print(" (required)", .{});
        }
        if (arg.getHelp()) |help| {
            std.debug.print("\n        {s}", .{help});
        }
        std.debug.print("\n", .{});
    }

    fn printFlag(self: Help, flag: Flag.Flag) void {
        _ = self;
        std.debug.print("    ", .{});
        
        var first = true;
        if (flag.config.short) |short| {
            std.debug.print("-{c}", .{short});
            first = false;
        }
        
        if (flag.config.long) |long| {
            if (!first) std.debug.print(", ", .{});
            std.debug.print("--{s}", .{long});
        }
        
        if (flag.getHelp()) |help| {
            std.debug.print("\n        {s}", .{help});
        }
        std.debug.print("\n", .{});
    }

    fn printBuiltinFlags(self: Help) void {
        _ = self;
        std.debug.print("    -h, --help\n        Print help information\n", .{});
        std.debug.print("    -V, --version\n        Print version information\n", .{});
    }

    fn printSubcommand(self: Help, command: Command.Command) void {
        _ = self;
        std.debug.print("    {s}", .{command.name});
        if (command.getAbout()) |about| {
            std.debug.print("\n        {s}", .{about});
        }
        std.debug.print("\n", .{});
    }

    pub fn printVersion(self: Help, command: Command.Command, program_name: ?[]const u8) void {
        _ = self;
        const name = program_name orelse command.name;
        
        std.debug.print("⚡ {s}", .{name});
        if (command.getVersion()) |version| {
            std.debug.print(" {s}", .{version});
        } else {
            const flash_version = @import("root.zig").version;
            std.debug.print(" {any}", .{flash_version});
        }
        std.debug.print(" - ⚡ Flash\n", .{});
    }

    pub fn generateCompletion(self: Help, command: Command.Command, shell: []const u8) void {
        _ = self;
        _ = command;
        std.debug.print("# Shell completion for {s}\n", .{shell});
        std.debug.print("# TODO: Implement completion generation\n", .{});
    }
};