//! Main CLI framework entry point
//!
//! The CLI struct ties together all Flash components and provides
//! the main interface for building and running CLI applications.

const std = @import("std");
const Argument = @import("argument.zig");
const Command = @import("command.zig");
const Completion = @import("completion.zig");
const Flag = @import("flag.zig");
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
                        const help_command = self.resolveHelpCommand(args);
                        const help_name = self.resolveHelpCommandName(args) catch self.allocator.dupe(u8, config.name) catch return err;
                        defer self.allocator.free(help_name);
                        self.printScopedHelp(help_command, self.commandPathFor(help_command), help_name);
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

        /// Run the CLI with process Init (Zig 0.17.0-dev style)
        pub fn runWithInit(self: *Self, process_init: std.process.Init) !void {
            // Collect args from iterator into a slice
            var args_list: std.ArrayList([]const u8) = .empty;
            defer args_list.deinit(self.allocator);

            var iter = std.process.Args.Iterator.init(process_init.minimal.args);
            while (iter.next()) |arg| {
                try args_list.append(self.allocator, arg);
            }

            try self.runWithArgs(args_list.items);
        }

        /// Parse arguments and execute the appropriate command
        fn parseAndExecute(self: *Self, args: []const []const u8) Error.FlashError!void {
            var context = try self.parser.parse(self.root_command, args);
            defer context.deinit();

            // Find the command to execute using full command path
            const command_path = context.getCommandPath();
            var current_command = self.findCommandByPath(self.root_command, command_path) orelse {
                return Error.FlashError.UnknownCommand;
            };

            // Check if we need a subcommand but don't have one
            if (config.subcommand_required and !current_command.hasHandler() and command_path.len == 0) {
                return Error.FlashError.MissingSubcommand;
            }

            // Execute the command
            if (command_path.len == 1 and std.mem.eql(u8, command_path[0], "completion")) {
                var generator = Completion.CompletionGenerator.init(self.allocator);
                defer generator.deinit();
                generator.handleCompletionCommand(context, self.root_command, config.name) catch |err| switch (err) {
                    error.MissingShell => return Error.FlashError.MissingRequiredArgument,
                    error.InvalidShell => return Error.FlashError.InvalidInput,
                    else => return Error.FlashError.IOError,
                };
            } else if (command_path.len == 1 and std.mem.eql(u8, command_path[0], "__complete")) {
                var generator = Completion.CompletionGenerator.init(self.allocator);
                defer generator.deinit();
                generator.handleDynamicCompletion(args, self.root_command) catch |err| switch (err) {
                    error.InvalidShell => return Error.FlashError.InvalidInput,
                    else => return Error.FlashError.IOError,
                };
            } else if (current_command.hasHandler()) {
                try current_command.execute(context);
            } else if (current_command.hasSubcommands()) {
                // No handler but has subcommands - show help
                const command_name = self.commandDisplayName(command_path, current_command) catch self.allocator.dupe(u8, config.name) catch return Error.FlashError.OutOfMemory;
                defer self.allocator.free(command_name);
                self.printScopedHelp(current_command, command_path, command_name);
            } else {
                // No handler and no subcommands - this shouldn't happen
                return Error.FlashError.MissingSubcommand;
            }
        }

        /// Find a command by walking the full command path (supports nested subcommands)
        fn findCommandByPath(self: *Self, root: Command.Command, path: []const []const u8) ?Command.Command {
            _ = self;
            return Command.Command.findCommandByPath(root, path);
        }

        /// Find a command by single name (backwards compatible)
        fn findCommand(self: *Self, root: Command.Command, name: []const u8) ?Command.Command {
            _ = self;
            return root.findSubcommand(name);
        }

        fn resolveHelpCommand(self: *Self, args: []const []const u8) Command.Command {
            var current = self.root_command;
            if (args.len <= 1) return current;

            var help_mode = false;
            for (args[1..]) |arg| {
                if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
                    break;
                }
                if (std.mem.eql(u8, arg, "help")) {
                    help_mode = true;
                    continue;
                }
                if (std.mem.startsWith(u8, arg, "-")) {
                    if (!help_mode) break;
                    continue;
                }
                if (current.findSubcommand(arg)) |subcmd| {
                    current = subcmd;
                    continue;
                }
                if (!help_mode) break;
            }

            return current;
        }

        fn resolveHelpCommandName(self: *Self, args: []const []const u8) ![]u8 {
            var current = self.root_command;
            if (args.len <= 1) return self.allocator.dupe(u8, current.name);

            var help_mode = false;
            var last_index: usize = 0;
            for (args[1..], 1..) |arg, index| {
                if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
                    break;
                }
                if (std.mem.eql(u8, arg, "help")) {
                    help_mode = true;
                    continue;
                }
                if (std.mem.startsWith(u8, arg, "-")) {
                    if (!help_mode) break;
                    continue;
                }
                if (current.findSubcommand(arg)) |subcmd| {
                    current = subcmd;
                    last_index = index;
                    continue;
                }
                if (!help_mode) break;
            }

            if (last_index == 0) return self.allocator.dupe(u8, self.root_command.name);
            return std.mem.join(self.allocator, " ", args[0 .. last_index + 1]);
        }

        fn commandDisplayName(self: *Self, command_path: []const []const u8, current_command: Command.Command) ![]u8 {
            _ = current_command;
            if (command_path.len == 0) return self.allocator.dupe(u8, config.name);

            var joined = std.ArrayList([]const u8).empty;
            defer joined.deinit(self.allocator);

            try joined.append(self.allocator, config.name);
            for (command_path) |segment| {
                try joined.append(self.allocator, segment);
            }

            return std.mem.join(self.allocator, " ", joined.items);
        }

        fn commandPathFor(self: *Self, command: Command.Command) []const []const u8 {
            if (std.mem.eql(u8, command.name, self.root_command.name)) return &.{};
            return self.findPathToCommand(self.root_command, command) orelse &.{command.name};
        }

        fn findPathToCommand(self: *Self, current: Command.Command, target: Command.Command) ?[]const []const u8 {
            for (current.getSubcommands()) |subcmd| {
                if (std.mem.eql(u8, subcmd.name, target.name)) {
                    return &.{subcmd.name};
                }
                if (self.findPathToCommand(subcmd, target)) |tail| {
                    if (tail.len == 0) return &.{subcmd.name};

                    var joined = std.ArrayList([]const u8).empty;
                    joined.append(self.allocator, subcmd.name) catch return null;
                    for (tail) |segment| joined.append(self.allocator, segment) catch return null;
                    return joined.toOwnedSlice(self.allocator) catch null;
                }
            }
            return null;
        }

        fn printScopedHelp(self: *Self, command: Command.Command, command_path: []const []const u8, display_name: []const u8) void {
            const merged = Command.Command.collectScopedFlags(self.root_command, command_path, self.allocator) catch {
                self.help.printHelp(command, display_name);
                return;
            };
            defer self.allocator.free(merged);

            var scoped_config = command.config;
            scoped_config.flags = merged;
            const scoped_command = Command.Command.init(command.name, scoped_config);
            self.help.printHelp(scoped_command, display_name);
        }

        /// Get the root command (for testing/inspection)
        pub fn getRootCommand(self: Self) Command.Command {
            return self.root_command;
        }

        /// Generate shell completion
        pub fn generateCompletion(self: *Self, writer: anytype, shell: []const u8) !void {
            try self.help.generateCompletionToWriter(writer, self.root_command, shell);
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

test "CLI resolves subcommand help target" {
    const allocator = std.testing.allocator;

    const TestCLI = CLI(.{
        .name = "service",
        .version = "1.0.0",
    });

    var cli = TestCLI.init(allocator, (Command.CommandConfig{})
        .withSubcommands(&.{Command.Command.init("start", (Command.CommandConfig{})
        .withAbout("Start the service")
        .withArgs(&.{Argument.Argument.init("config", (Argument.ArgumentConfig{})
        .withHelp("Config file")
        .withLong("config"))}))}));

    const args = [_][]const u8{ "service", "start", "--help" };

    const result = cli.parser.parse(cli.root_command, &args);
    try std.testing.expectError(Error.FlashError.HelpRequested, result);

    const current_command = cli.resolveHelpCommand(&args);

    try std.testing.expectEqualStrings("start", current_command.name);
    try std.testing.expectEqualStrings("Start the service", current_command.getAbout().?);
}

test "CLI parser recognizes builtin completion command" {
    const allocator = std.testing.allocator;

    const TestCLI = CLI(.{
        .name = "flash",
        .version = "1.0.0",
    });

    var cli = TestCLI.init(allocator, Command.CommandConfig{});

    const args = [_][]const u8{ "flash", "completion", "bash" };
    var context = try cli.parser.parse(cli.root_command, &args);
    defer context.deinit();

    try std.testing.expectEqualStrings("completion", context.getSubcommand().?);
    try std.testing.expectEqualStrings("bash", context.getPositional(0).?.asString());
}

test "CLI command display name includes nested path" {
    const allocator = std.testing.allocator;

    const TestCLI = CLI(.{
        .name = "flash",
        .version = "1.0.0",
    });

    var cli = TestCLI.init(allocator, (Command.CommandConfig{})
        .withSubcommands(&.{Command.Command.init("serve", (Command.CommandConfig{})
        .withSubcommands(&.{Command.Command.init("http", Command.CommandConfig{})}))}));

    const display = try cli.commandDisplayName(&.{ "serve", "http" }, cli.root_command);
    defer allocator.free(display);
    try std.testing.expect(std.mem.startsWith(u8, display, "flash serve http"));
}

test "CLI scoped help includes inherited global flags" {
    const allocator = std.testing.allocator;

    const TestCLI = CLI(.{
        .name = "flash",
        .version = "1.0.0",
    });

    var cli = TestCLI.init(allocator, (Command.CommandConfig{})
        .withFlags(&.{Flag.Flag.init("verbose", (Flag.FlagConfig{})
            .withLong("verbose")
            .withHelp("Verbose output")
            .setGlobal())})
        .withSubcommands(&.{Command.Command.init("serve", (Command.CommandConfig{})
        .withAbout("Serve files"))}));

    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();

    const command_name = try cli.commandDisplayName(&.{"serve"}, cli.root_command);
    defer allocator.free(command_name);

    const merged = try Command.Command.collectScopedFlags(cli.root_command, &.{"serve"}, allocator);
    defer allocator.free(merged);

    var scoped_config = cli.root_command.findSubcommand("serve").?.config;
    scoped_config.flags = merged;
    const scoped_command = Command.Command.init("serve", scoped_config);

    try cli.help.printCommandHelp(&aw.writer, scoped_command, command_name);

    const output = aw.written();
    try std.testing.expect(std.mem.indexOf(u8, output, "flash serve") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "--verbose") != null);
}
