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
        if (arg.getChoices()) |choices| {
            std.debug.print("\n        Choices: ", .{});
            for (choices, 0..) |choice, i| {
                if (i > 0) std.debug.print(", ", .{});
                std.debug.print("{s}", .{choice});
            }
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

    /// Generate shell completion script and print to debug output
    pub fn generateCompletion(self: Help, command: Command.Command, shell: []const u8) void {
        const Completion = @import("completion.zig");
        const shell_type = Completion.Shell.fromString(shell) orelse {
            std.debug.print("# Error: Unknown shell '{s}'\n", .{shell});
            std.debug.print("# Supported shells: bash, zsh, fish, powershell, nushell, gsh\n", .{});
            return;
        };

        var generator = Completion.CompletionGenerator.init(self.allocator);
        defer generator.deinit();

        const script = generator.generate(command, shell_type, command.name) catch |err| {
            std.debug.print("# Error generating completion: {}\n", .{err});
            return;
        };
        defer self.allocator.free(script);

        std.debug.print("{s}", .{script});
    }

    /// Generate shell completion script and write to a writer
    pub fn generateCompletionToWriter(self: Help, writer: anytype, command: Command.Command, shell: []const u8) !void {
        const Completion = @import("completion.zig");
        const shell_type = Completion.Shell.fromString(shell) orelse return error.InvalidShell;

        var generator = Completion.CompletionGenerator.init(self.allocator);
        defer generator.deinit();

        const script = try generator.generate(command, shell_type, command.name);
        defer self.allocator.free(script);

        try writer.writeAll(script);
    }

    pub fn printCommandHelp(self: Help, writer: anytype, command: Command.Command, program_name: []const u8) !void {
        // Flash header with lightning emoji
        try writer.print("⚡ {s}", .{program_name});
        if (command.getVersion()) |version| {
            try writer.print(" {s}", .{version});
        }
        if (command.getAbout()) |about| {
            try writer.print(" - {s}", .{about});
        }
        try writer.print("\n\n", .{});

        try writer.print("USAGE:\n", .{});
        try self.printUsageToWriter(writer, command, program_name);
        try writer.print("\n", .{});

        if (command.getArgs().len > 0) {
            try writer.print("ARGUMENTS:\n", .{});
            for (command.getArgs()) |arg| {
                try self.printArgumentToWriter(writer, arg);
            }
            try writer.print("\n", .{});
        }

        if (command.getFlags().len > 0) {
            try writer.print("OPTIONS:\n", .{});
            for (command.getFlags()) |flag| {
                try self.printFlagToWriter(writer, flag);
            }
            try self.printBuiltinFlagsToWriter(writer);
            try writer.print("\n", .{});
        }

        if (command.hasSubcommands()) {
            try writer.print("COMMANDS:\n", .{});
            for (command.getSubcommands()) |subcmd| {
                if (!subcmd.isHidden()) {
                    try self.printSubcommandToWriter(writer, subcmd);
                }
            }
            // Add builtin Zig-style commands
            try writer.print("    help\n        Show help information\n", .{});
            try writer.print("    version\n        Show version information\n", .{});
            try writer.print("\n", .{});
        }
    }

    fn printUsageToWriter(self: Help, writer: anytype, command: Command.Command, program_name: []const u8) !void {
        _ = self;
        try writer.print("    {s}", .{program_name});

        if (command.getFlags().len > 0) {
            try writer.print(" [OPTIONS]", .{});
        }

        for (command.getArgs()) |arg| {
            if (arg.isRequired()) {
                try writer.print(" <{s}>", .{arg.name});
            } else {
                try writer.print(" [{s}]", .{arg.name});
            }
        }

        if (command.hasSubcommands()) {
            try writer.print(" <COMMAND>", .{});
        }

        try writer.print("\n", .{});
    }

    fn printArgumentToWriter(self: Help, writer: anytype, arg: Argument.Argument) !void {
        _ = self;
        try writer.print("    {s}", .{arg.name});
        if (arg.isRequired()) {
            try writer.print(" (required)", .{});
        }
        if (arg.getHelp()) |help| {
            try writer.print("\n        {s}", .{help});
        }
        if (arg.getChoices()) |choices| {
            try writer.print("\n        Choices: ", .{});
            for (choices, 0..) |choice, i| {
                if (i > 0) try writer.print(", ", .{});
                try writer.print("{s}", .{choice});
            }
        }
        try writer.print("\n", .{});
    }

    fn printFlagToWriter(self: Help, writer: anytype, flag: Flag.Flag) !void {
        _ = self;
        try writer.print("    ", .{});
        
        var first = true;
        if (flag.config.short) |short| {
            try writer.print("-{c}", .{short});
            first = false;
        }
        
        if (flag.config.long) |long| {
            if (!first) try writer.print(", ", .{});
            try writer.print("--{s}", .{long});
        }
        
        if (flag.getHelp()) |help| {
            try writer.print("\n        {s}", .{help});
        }
        try writer.print("\n", .{});
    }

    fn printBuiltinFlagsToWriter(self: Help, writer: anytype) !void {
        _ = self;
        try writer.print("    -h, --help\n        Print help information\n", .{});
        try writer.print("    -V, --version\n        Print version information\n", .{});
    }

    fn printSubcommandToWriter(self: Help, writer: anytype, command: Command.Command) !void {
        _ = self;
        try writer.print("    {s}", .{command.name});
        if (command.getAbout()) |about| {
            try writer.print("\n        {s}", .{about});
        }
        try writer.print("\n", .{});
    }
};

test "generateCompletionToWriter produces bash script" {
    const allocator = std.testing.allocator;
    const help = Help.init(allocator);

    const test_cmd = Command.Command.init("testapp", (Command.CommandConfig{})
        .withAbout("Test application")
        .withSubcommands(&.{
            Command.Command.init("deploy", (Command.CommandConfig{}).withAbout("Deploy the app")),
            Command.Command.init("status", (Command.CommandConfig{}).withAbout("Show status")),
        }));

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try help.generateCompletionToWriter(buffer.writer(), test_cmd, "bash");

    const output = buffer.items;
    // Verify it's a bash completion script
    try std.testing.expect(std.mem.indexOf(u8, output, "# ⚡ Flash completion script for Bash") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "testapp") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "deploy") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "status") != null);
}

test "generateCompletionToWriter produces zsh script" {
    const allocator = std.testing.allocator;
    const help = Help.init(allocator);

    const test_cmd = Command.Command.init("mycli", (Command.CommandConfig{})
        .withSubcommands(&.{
            Command.Command.init("build", (Command.CommandConfig{}).withAbout("Build project")),
        }));

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try help.generateCompletionToWriter(buffer.writer(), test_cmd, "zsh");

    const output = buffer.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "# ⚡ Flash completion script for Zsh") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "compdef") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "build") != null);
}

test "generateCompletionToWriter rejects invalid shell" {
    const allocator = std.testing.allocator;
    const help = Help.init(allocator);

    const test_cmd = Command.Command.init("app", Command.CommandConfig{});

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    const result = help.generateCompletionToWriter(buffer.writer(), test_cmd, "invalidshell");
    try std.testing.expectError(error.InvalidShell, result);
}