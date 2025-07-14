//! Main CLI framework entry point
//!
//! The CLI struct ties together all Flash components and provides
//! the main interface for building and running CLI applications.

const std = @import("std");
const Command = @import("command.zig");
const Parser = @import("parser.zig");
const Context = @import("context.zig");
const Help = @import("help.zig");
const Error = @import("error.zig");

/// Main CLI configuration
pub const CLIConfig = struct {
    name: []const u8,
    version: ?[]const u8 = null,
    about: ?[]const u8 = null,
    long_about: ?[]const u8 = null,
    author: ?[]const u8 = null,
    color: ?bool = null, // null = auto-detect

    // Global behavior
    global_help: bool = true,
    global_version: bool = true,
    propagate_version: bool = true,
    subcommand_required: bool = false,
    allow_external_subcommands: bool = false,

    pub fn withVersion(self: CLIConfig, version: []const u8) CLIConfig {
        var config = self;
        config.version = version;
        return config;
    }

    pub fn withAbout(self: CLIConfig, about: []const u8) CLIConfig {
        var config = self;
        config.about = about;
        return config;
    }

    pub fn withLongAbout(self: CLIConfig, long_about: []const u8) CLIConfig {
        var config = self;
        config.long_about = long_about;
        return config;
    }

    pub fn withAuthor(self: CLIConfig, author: []const u8) CLIConfig {
        var config = self;
        config.author = author;
        return config;
    }

    pub fn withColor(self: CLIConfig, use_color: bool) CLIConfig {
        var config = self;
        config.color = use_color;
        return config;
    }

    pub fn requireSubcommand(self: CLIConfig) CLIConfig {
        var config = self;
        config.subcommand_required = true;
        return config;
    }

    pub fn allowExternalSubcommands(self: CLIConfig) CLIConfig {
        var config = self;
        config.allow_external_subcommands = true;
        return config;
    }
};

/// Main CLI application
pub fn CLI(comptime config: CLIConfig) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        root_command: Command.Command,
        parser: Parser.Parser,
        help: Help.Help,

        pub fn init(allocator: std.mem.Allocator, root_config: Command.CommandConfig) Self {
            // Create root command with CLI config
            var cmd_config = root_config;
            if (config.about) |about| {
                if (cmd_config.about == null) {
                    cmd_config.about = about;
                }
            }
            if (config.version) |version| {
                if (cmd_config.version == null) {
                    cmd_config.version = version;
                }
            }

            const root_command = Command.Command.init(config.name, cmd_config);

            return .{
                .allocator = allocator,
                .root_command = root_command,
                .parser = Parser.Parser.init(allocator),
                .help = Help.Help.init(allocator),
            };
        }
        
        /// Run the CLI with the given arguments
        pub fn runWithArgs(self: *Self, args: []const []const u8) !void {
            self.parseAndExecute(args) catch |err| {
                // Use debug print for errors
                const use_stderr = true;
                _ = use_stderr;
                
                switch (err) {
                    Error.FlashError.HelpRequested => {
                        self.help.printHelp(self.root_command, config.name);
                        return;
                    },
                    Error.FlashError.VersionRequested => {
                        self.help.printVersion(self.root_command, config.name);
                        return;
                    },
                    else => {
                        Error.printError(err, null);
                        std.process.exit(1);
                    },
                }
            };
        }

        /// Run the CLI with process arguments
        pub fn run(self: *Self) !void {
            const args = try std.process.argsAlloc(self.allocator);
            defer std.process.argsFree(self.allocator, args);

            try self.runWithArgs(args);
        }

        /// Parse arguments and execute the appropriate command
        fn parseAndExecute(self: *Self, args: []const []const u8) Error.FlashError!void {
            var context = try self.parser.parse(self.root_command, args);
            defer context.deinit();

            // Find the command to execute
            var current_command = self.root_command;
            if (context.getSubcommand()) |subcmd_name| {
                if (self.findCommand(self.root_command, subcmd_name)) |found_cmd| {
                    current_command = found_cmd;
                } else {
                    return Error.FlashError.UnknownCommand;
                }
            }

            // Check if we need a subcommand but don't have one
            if (config.subcommand_required and !current_command.hasHandler() and context.getSubcommand() == null) {
                return Error.FlashError.MissingSubcommand;
            }

            // Execute the command
            if (current_command.hasHandler()) {
                try current_command.execute(context);
            } else if (current_command.hasSubcommands()) {
                // No handler but has subcommands - show help
                self.help.printHelp(current_command, config.name);
            } else {
                // No handler and no subcommands - this shouldn't happen
                return Error.FlashError.MissingSubcommand;
            }
        }

        /// Find a command by walking the command tree
        fn findCommand(self: *Self, root: Command.Command, path: []const u8) ?Command.Command {
            _ = self;

            // For now, just look for direct subcommands
            // TODO: Support nested subcommand paths like "service start"
            return root.findSubcommand(path);
        }

        /// Get the root command (for testing/inspection)
        pub fn getRootCommand(self: Self) Command.Command {
            return self.root_command;
        }

        /// Generate shell completion
        pub fn generateCompletion(self: *Self, writer: anytype, shell: []const u8) !void {
            try self.help.generateCompletion(writer, self.root_command, shell);
        }
    };
}

/// Convenience function to create a CLI app with minimal configuration
pub fn simpleCLI(comptime name: []const u8, comptime about: []const u8, comptime version: []const u8) type {
    const config = CLIConfig{
        .name = name,
        .about = about,
        .version = version,
    };

    return CLI(config);
}

test "CLI creation and basic functionality" {
    const allocator = std.testing.allocator;

    const TestCLI = CLI(.{
        .name = "test",
        .version = "1.0.0",
        .about = "Test CLI application",
    });

    const TestState = struct {
        var executed: bool = false;

        fn handler(ctx: Context.Context) Error.FlashError!void {
            _ = ctx;
            executed = true;
        }
    };

    TestState.executed = false;

    var cli = TestCLI.init(allocator, (Command.CommandConfig{})
        .withHandler(TestState.handler));

    const args = [_][]const u8{"test"};
    try cli.runWithArgs(&args);

    try std.testing.expectEqual(true, TestState.executed);
}

test "CLI with subcommands" {
    const allocator = std.testing.allocator;

    const TestCLI = CLI(.{
        .name = "service",
        .version = "1.0.0",
    });

    const TestState = struct {
        var start_executed: bool = false;

        fn handler(ctx: Context.Context) Error.FlashError!void {
            _ = ctx;
            start_executed = true;
        }
    };

    TestState.start_executed = false;

    const subcmds = [_]Command.Command{
        Command.Command.init("start", (Command.CommandConfig{})
            .withAbout("Start the service")
            .withHandler(TestState.handler)),
    };

    var cli = TestCLI.init(allocator, (Command.CommandConfig{})
        .withSubcommands(&subcmds));

    const args = [_][]const u8{ "service", "start" };
    try cli.runWithArgs(&args);

    try std.testing.expectEqual(true, TestState.start_executed);
}
