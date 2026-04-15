//! ⚡ Flash Shell Completion Generation
//!
//! Generates dynamic shell completion scripts for Bash, Zsh, Fish, and PowerShell
//! Supports custom completers, flag completions, and dynamic value generation

const std = @import("std");
const zsync = @import("zsync");
const Command = @import("command.zig");
const Argument = @import("argument.zig");
const Flag = @import("flag.zig");
const Context = @import("context.zig");

pub const Shell = enum {
    bash,
    zsh,
    fish,
    powershell,
    nushell,
    gsh, // gshell - modern Zig shell

    pub fn fromString(s: []const u8) ?Shell {
        if (std.mem.eql(u8, s, "bash")) return .bash;
        if (std.mem.eql(u8, s, "zsh")) return .zsh;
        if (std.mem.eql(u8, s, "fish")) return .fish;
        if (std.mem.eql(u8, s, "powershell") or std.mem.eql(u8, s, "pwsh")) return .powershell;
        if (std.mem.eql(u8, s, "nushell") or std.mem.eql(u8, s, "nu")) return .nushell;
        if (std.mem.eql(u8, s, "gshell") or std.mem.eql(u8, s, "gsh")) return .gsh;
        return null;
    }

    pub fn fileExtension(self: Shell) []const u8 {
        return switch (self) {
            .bash => ".bash",
            .zsh => ".zsh",
            .fish => ".fish",
            .powershell => ".ps1",
            .nushell => ".nu",
            .gsh => ".gsh",
        };
    }
};

/// Completion directive for shell behavior
pub const CompletionDirective = enum {
    default,
    no_space,
    no_file_comp,
    filter_file_ext,
    filter_dirs,
    keep_order,
    completion_error,
};

/// Custom completion function signature
pub const CompletionFn = *const fn (Context.Context, []const u8) anyerror![]const []const u8;

/// Async completion function signature
pub const AsyncCompletionFn = *const fn (Context.Context, []const u8) zsync.Future;

/// Completion candidate with metadata
pub const CompletionCandidate = struct {
    value: []const u8,
    description: ?[]const u8 = null,
    directive: CompletionDirective = .default,

    pub fn simple(value: []const u8) CompletionCandidate {
        return .{ .value = value };
    }

    pub fn withDescription(value: []const u8, description: []const u8) CompletionCandidate {
        return .{ .value = value, .description = description };
    }
};

/// Completion configuration for arguments and flags
pub const CompletionConfig = struct {
    static_values: ?[]const []const u8 = null,
    completion_fn: ?CompletionFn = null,
    async_completion_fn: ?AsyncCompletionFn = null,
    file_extensions: ?[]const []const u8 = null,
    directory_only: bool = false,
    no_file_completion: bool = false,
};

pub const CompletionGenerator = struct {
    allocator: std.mem.Allocator,
    enable_dynamic: bool = true,
    custom_completers: std.StringHashMap(CompletionConfig) = undefined,

    pub fn init(allocator: std.mem.Allocator) CompletionGenerator {
        return .{
            .allocator = allocator,
            .custom_completers = std.StringHashMap(CompletionConfig).init(allocator),
        };
    }

    pub fn deinit(self: *CompletionGenerator) void {
        self.custom_completers.deinit();
    }

    pub fn addCustomCompleter(self: *CompletionGenerator, name: []const u8, config: CompletionConfig) !void {
        try self.custom_completers.put(name, config);
    }

    pub fn generate(self: CompletionGenerator, command: Command.Command, shell: Shell, program_name: []const u8) ![]u8 {
        return switch (shell) {
            .bash => self.generateBash(command, program_name),
            .zsh => self.generateZsh(command, program_name),
            .fish => self.generateFish(command, program_name),
            .powershell => self.generatePowerShell(command, program_name),
            .nushell => self.generateNuShell(command, program_name),
            .gsh => self.generateGShell(command, program_name),
        };
    }

    pub fn generateToFile(self: CompletionGenerator, command: Command.Command, shell: Shell, program_name: []const u8, output_dir: []const u8) !void {
        const completion_script = try self.generate(command, shell, program_name);
        defer self.allocator.free(completion_script);

        const filename = try std.fmt.allocPrint(self.allocator, "{s}/{s}{s}", .{ output_dir, program_name, shell.fileExtension() });
        defer self.allocator.free(filename);

        try std.fs.cwd().writeFile(.{ .sub_path = filename, .data = completion_script });
    }

    fn generateBash(self: CompletionGenerator, command: Command.Command, program_name: []const u8) ![]u8 {
        var buf = std.ArrayList(u8).init(self.allocator);
        const writer = buf.writer();

        try writer.print("# ⚡ Flash completion script for Bash\n", .{});
        try writer.print("# Generated for {s}\n", .{program_name});
        try writer.print("# Support dynamic completions, flags, and file completion\n\n", .{});

        // Helper functions for dynamic completion
        if (self.enable_dynamic) {
            try writer.print("_{s}_dynamic_completion() {{\n", .{program_name});
            try writer.print("    local cmd=\"$1\"\n", .{});
            try writer.print("    local current=\"$2\"\n", .{});
            try writer.print("    \"$cmd\" __complete bash \"$current\" 2>/dev/null || echo \"\"\n", .{});
            try writer.print("}}\n\n", .{});
        }

        try writer.print("_{s}_completions() {{\n", .{program_name});
        try writer.print("    local cur prev words cword\n", .{});
        try writer.print("    _init_completion || return\n\n", .{});

        // Handle flags completion
        try writer.print("    if [[ \"$cur\" == -* ]]; then\n", .{});
        try writer.print("        local flags=\"", .{});
        try self.writeBashFlags(writer, command);
        try writer.print("\"\n", .{});
        try writer.print("        COMPREPLY=($(compgen -W \"$flags\" -- \"$cur\"))\n", .{});
        try writer.print("        return\n", .{});
        try writer.print("    fi\n\n", .{});

        // Handle subcommands and dynamic completion
        try writer.print("    case ${{cword}} in\n", .{});
        try writer.print("        1)\n", .{});
        try writer.print("            local commands=\"", .{});

        // Add subcommands
        for (command.getSubcommands()) |subcmd| {
            if (!subcmd.isHidden()) {
                try writer.print("{s} ", .{subcmd.name});
            }
        }
        // Add builtin commands
        try writer.print("help version completion\"\n", .{});
        try writer.print("            COMPREPLY=($(compgen -W \"$commands\" -- \"$cur\"))\n", .{});
        try writer.print("            ;;\n", .{});
        try writer.print("        *)\n", .{});

        // Check for argument choices first
        var has_choices = false;
        for (command.getArgs()) |arg| {
            if (arg.getChoices() != null) {
                has_choices = true;
                break;
            }
        }

        if (has_choices) {
            try writer.print("            local arg_choices=\"", .{});
            try self.writeBashArgumentChoices(writer, command);
            try writer.print("\"\n", .{});
            try writer.print("            COMPREPLY=($(compgen -W \"$arg_choices\" -- \"$cur\"))\n", .{});
        } else if (self.enable_dynamic) {
            try writer.print("            local completions\n", .{});
            try writer.print("            completions=$(_{s}_dynamic_completion \"{s}\" \"$cur\")\n", .{ program_name, program_name });
            try writer.print("            if [[ -n \"$completions\" ]]; then\n", .{});
            try writer.print("                COMPREPLY=($(compgen -W \"$completions\" -- \"$cur\"))\n", .{});
            try writer.print("            else\n", .{});
            try writer.print("                _filedir\n", .{});
            try writer.print("            fi\n", .{});
        } else {
            try writer.print("            _filedir\n", .{});
        }

        try writer.print("            ;;\n", .{});
        try writer.print("    esac\n", .{});
        try writer.print("}}\n\n", .{});

        try writer.print("complete -F _{s}_completions {s}\n", .{ program_name, program_name });

        return buf.toOwnedSlice();
    }

    fn writeBashFlags(self: CompletionGenerator, writer: anytype, command: Command.Command) !void {
        _ = self;
        // Write global flags
        try writer.print("-h --help -V --version ", .{});

        // Write command-specific flags
        for (command.getFlags()) |flag| {
            if (flag.config.short) |short| {
                try writer.print("-{c} ", .{short});
            }
            if (flag.config.long) |long| {
                try writer.print("--{s} ", .{long});
            }
        }
    }

    /// Write argument choices for bash completion
    fn writeBashArgumentChoices(self: CompletionGenerator, writer: anytype, command: Command.Command) !void {
        _ = self;
        for (command.getArgs()) |arg| {
            if (arg.getChoices()) |choices| {
                for (choices) |choice| {
                    try writer.print("{s} ", .{choice});
                }
            }
        }
    }

    fn generateZsh(self: CompletionGenerator, command: Command.Command, program_name: []const u8) ![]u8 {
        var buf = std.ArrayList(u8).init(self.allocator);
        const writer = buf.writer();

        try writer.print("# ⚡ Flash completion script for Zsh\n", .{});
        try writer.print("# Generated for {s}\n", .{program_name});
        try writer.print("# Support dynamic completions, flags, and file completion\n\n", .{});

        try writer.print("#{s}() {{\n", .{program_name});
        try writer.print("    local line\n", .{});

        // Generate argument specifications
        try writer.print("    _arguments -C \\\n", .{});

        // Add global flags
        try writer.print("        '-h[Show help information]' \\\n", .{});
        try writer.print("        '--help[Show help information]' \\\n", .{});
        try writer.print("        '-V[Show version information]' \\\n", .{});
        try writer.print("        '--version[Show version information]' \\\n", .{});

        // Add command-specific flags
        for (command.getFlags()) |flag| {
            const help_text = flag.config.help orelse "";
            if (flag.config.short) |short| {
                try writer.print("        '-{c}[{s}]' \\\n", .{ short, help_text });
            }
            if (flag.config.long) |long| {
                try writer.print("        '--{s}[{s}]' \\\n", .{ long, help_text });
            }
        }

        try writer.print("        '1: :_commands' \\\n", .{});

        // Add argument completions with choices
        var arg_index: usize = 2;
        for (command.getArgs()) |arg| {
            if (arg.getChoices()) |choices| {
                try writer.print("        '{d}: :(", .{arg_index});
                for (choices, 0..) |choice, i| {
                    if (i > 0) try writer.print(" ", .{});
                    try writer.print("{s}", .{choice});
                }
                try writer.print(")' \\\n", .{});
            }
            arg_index += 1;
        }

        try writer.print("        '*: :_files'\n\n", .{});

        try writer.print("    case $line[1] in\n", .{});

        // Add subcommand completions
        for (command.getSubcommands()) |subcmd| {
            if (!subcmd.isHidden()) {
                try writer.print("        {s})\n", .{subcmd.name});
                try writer.print("            _{s}_{s}\n", .{ program_name, subcmd.name });
                try writer.print("            ;;\n", .{});
            }
        }

        try writer.print("    esac\n", .{});
        try writer.print("}}\n\n", .{});

        try writer.print("_commands() {{\n", .{});
        try writer.print("    local commands; commands=(\n", .{});

        // Add subcommands with descriptions
        for (command.getSubcommands()) |subcmd| {
            if (!subcmd.isHidden()) {
                const about = subcmd.getAbout() orelse "";
                try writer.print("        '{s}:{s}'\n", .{ subcmd.name, about });
            }
        }
        // Add builtin commands
        try writer.print("        'help:Show help information'\n", .{});
        try writer.print("        'version:Show version information'\n", .{});
        try writer.print("        'completion:Generate shell completion scripts'\n", .{});
        try writer.print("    )\n", .{});
        try writer.print("    _describe 'commands' commands\n", .{});
        try writer.print("}}\n\n", .{});

        // Generate subcommand completion functions
        for (command.getSubcommands()) |subcmd| {
            if (!subcmd.isHidden()) {
                try self.generateZshSubcommand(writer, program_name, subcmd);
            }
        }

        try writer.print("compdef _{s} {s}\n", .{ program_name, program_name });

        return buf.toOwnedSlice();
    }

    fn generateZshSubcommand(self: CompletionGenerator, writer: anytype, program_name: []const u8, subcmd: Command.Command) !void {
        _ = self;
        try writer.print("_{s}_{s}() {{\n", .{ program_name, subcmd.name });
        try writer.print("    _arguments \\\n", .{});

        // Add subcommand-specific flags
        for (subcmd.getFlags()) |flag| {
            const help_text = flag.config.help orelse "";
            if (flag.config.short) |short| {
                try writer.print("        '-{c}[{s}]' \\\n", .{ short, help_text });
            }
            if (flag.config.long) |long| {
                try writer.print("        '--{s}[{s}]' \\\n", .{ long, help_text });
            }
        }

        try writer.print("        '*: :_files'\n", .{});
        try writer.print("}}\n\n", .{});
    }

    fn generatePowerShell(self: CompletionGenerator, command: Command.Command, program_name: []const u8) ![]u8 {
        var buf = std.ArrayList(u8).init(self.allocator);
        const writer = buf.writer();

        try writer.print("# ⚡ Flash completion script for PowerShell\n", .{});
        try writer.print("# Generated for {s}\n\n", .{program_name});

        try writer.print("Register-ArgumentCompleter -Native -CommandName {s} -ScriptBlock {{\n", .{program_name});
        try writer.print("    param($commandName, $wordToComplete, $cursorPosition)\n\n", .{});

        try writer.print("    $commands = @(\n", .{});

        // Add subcommands
        for (command.getSubcommands()) |subcmd| {
            if (!subcmd.isHidden()) {
                const about = subcmd.getAbout() orelse "";
                try writer.print("        @{{ Name = '{s}'; Description = '{s}' }}\n", .{ subcmd.name, about });
            }
        }

        // Add builtin commands
        try writer.print("        @{{ Name = 'help'; Description = 'Show help information' }}\n", .{});
        try writer.print("        @{{ Name = 'version'; Description = 'Show version information' }}\n", .{});
        try writer.print("        @{{ Name = 'completion'; Description = 'Generate shell completion scripts' }}\n", .{});
        try writer.print("    )\n\n", .{});

        try writer.print("    $commands | Where-Object {{ $_.Name -like \"$wordToComplete*\" }} | ForEach-Object {{\n", .{});
        try writer.print("        [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', $_.Description)\n", .{});
        try writer.print("    }}\n", .{});
        try writer.print("}}\n", .{});

        return buf.toOwnedSlice();
    }

    fn generateNuShell(self: CompletionGenerator, command: Command.Command, program_name: []const u8) ![]u8 {
        var buf = std.ArrayList(u8).init(self.allocator);
        const writer = buf.writer();

        try writer.print("# ⚡ Flash completion script for Nu Shell\n", .{});
        try writer.print("# Generated for {s}\n\n", .{program_name});

        try writer.print("def \"nu-complete {s}\" [] {{\n", .{program_name});
        try writer.print("    [\n", .{});

        // Add subcommands
        for (command.getSubcommands()) |subcmd| {
            if (!subcmd.isHidden()) {
                const about = subcmd.getAbout() orelse "";
                try writer.print("        {{ value: \"{s}\", description: \"{s}\" }},\n", .{ subcmd.name, about });
            }
        }

        // Add builtin commands
        try writer.print("        {{ value: \"help\", description: \"Show help information\" }},\n", .{});
        try writer.print("        {{ value: \"version\", description: \"Show version information\" }},\n", .{});
        try writer.print("        {{ value: \"completion\", description: \"Generate shell completion scripts\" }},\n", .{});
        try writer.print("    ]\n", .{});
        try writer.print("}}\n\n", .{});

        try writer.print("extern \"{s}\" [\n", .{program_name});
        try writer.print("    subcommand?: string@\"nu-complete {s}\"\n", .{program_name});
        try writer.print("    --help(-h)     # Show help information\n", .{});
        try writer.print("    --version(-V)  # Show version information\n", .{});
        try writer.print("]\n", .{});

        return buf.toOwnedSlice();
    }

    fn generateFish(self: CompletionGenerator, command: Command.Command, program_name: []const u8) ![]u8 {
        var buf = std.ArrayList(u8).init(self.allocator);
        const writer = buf.writer();

        try writer.print("# ⚡ Flash completion script for Fish\n", .{});
        try writer.print("# Generated for {s}\n\n", .{program_name});

        // Add subcommands
        for (command.getSubcommands()) |subcmd| {
            if (!subcmd.isHidden()) {
                const about = subcmd.getAbout() orelse "";
                try writer.print("complete -c {s} -f -n \"__fish_use_subcommand\" -a {s} -d '{s}'\n", .{ program_name, subcmd.name, about });

                // Add flags for this subcommand
                for (subcmd.getFlags()) |flag| {
                    const help_text = flag.config.help orelse "";
                    const condition = try std.fmt.allocPrint(self.allocator, "__fish_seen_subcommand_from {s}", .{subcmd.name});
                    defer self.allocator.free(condition);

                    if (flag.config.short) |short| {
                        try writer.print("complete -c {s} -f -n \"{s}\" -s {c} -d '{s}'\n", .{ program_name, condition, short, help_text });
                    }
                    if (flag.config.long) |long| {
                        try writer.print("complete -c {s} -f -n \"{s}\" -l {s} -d '{s}'\n", .{ program_name, condition, long, help_text });
                    }
                }
            }
        }

        // Add builtin commands
        try writer.print("complete -c {s} -f -n \"__fish_use_subcommand\" -a help -d 'Show help information'\n", .{program_name});
        try writer.print("complete -c {s} -f -n \"__fish_use_subcommand\" -a version -d 'Show version information'\n", .{program_name});
        try writer.print("complete -c {s} -f -n \"__fish_use_subcommand\" -a completion -d 'Generate shell completion scripts'\n", .{program_name});

        // Global flags
        try writer.print("complete -c {s} -f -s h -l help -d 'Show help information'\n", .{program_name});
        try writer.print("complete -c {s} -f -s V -l version -d 'Show version information'\n", .{program_name});

        // Add command-specific flags
        for (command.getFlags()) |flag| {
            const help_text = flag.config.help orelse "";
            if (flag.config.short) |short| {
                try writer.print("complete -c {s} -f -s {c} -d '{s}'\n", .{ program_name, short, help_text });
            }
            if (flag.config.long) |long| {
                try writer.print("complete -c {s} -f -l {s} -d '{s}'\n", .{ program_name, long, help_text });
            }
        }

        // Add argument choices
        for (command.getArgs()) |arg| {
            if (arg.getChoices()) |choices| {
                const help_text = arg.getHelp() orelse arg.name;
                for (choices) |choice| {
                    try writer.print("complete -c {s} -f -a {s} -d '{s}'\n", .{ program_name, choice, help_text });
                }
            }
        }

        return buf.toOwnedSlice();
    }

    fn generateGShell(self: CompletionGenerator, command: Command.Command, program_name: []const u8) ![]u8 {
        var buf = std.ArrayList(u8).init(self.allocator);
        const writer = buf.writer();

        try writer.print("# ⚡ Flash completion script for GShell (gsh)\n", .{});
        try writer.print("# Generated for {s}\n", .{program_name});
        try writer.print("# Zig-native shell completion powered by flare config\n\n", .{});

        // GShell uses a declarative Zig-like syntax for completions
        try writer.print("completion {s} {{\n", .{program_name});
        try writer.print("    description = \"Flash CLI application\"\n\n", .{});

        // Add subcommands
        if (command.getSubcommands().len > 0) {
            try writer.print("    subcommands = .{{\n", .{});
            for (command.getSubcommands()) |subcmd| {
                if (!subcmd.isHidden()) {
                    const about = subcmd.getAbout() orelse "";
                    try writer.print("        .{s} = .{{\n", .{subcmd.name});
                    try writer.print("            .description = \"{s}\",\n", .{about});

                    // Add subcommand flags
                    if (subcmd.getFlags().len > 0) {
                        try writer.print("            .flags = .{{\n", .{});
                        for (subcmd.getFlags()) |flag| {
                            const help_text = flag.config.help orelse "";
                            if (flag.config.long) |long| {
                                try writer.print("                .@\"{s}\" = \"{s}\",\n", .{ long, help_text });
                            }
                        }
                        try writer.print("            }},\n", .{});
                    }

                    try writer.print("        }},\n", .{});
                }
            }
            // Add builtin commands
            try writer.print("        .help = .{{ .description = \"Show help information\" }},\n", .{});
            try writer.print("        .version = .{{ .description = \"Show version information\" }},\n", .{});
            try writer.print("        .completion = .{{ .description = \"Generate shell completion scripts\" }},\n", .{});
            try writer.print("    }},\n\n", .{});
        }

        // Add global flags
        if (command.getFlags().len > 0) {
            try writer.print("    flags = .{{\n", .{});
            for (command.getFlags()) |flag| {
                const help_text = flag.config.help orelse "";
                if (flag.config.long) |long| {
                    try writer.print("        .@\"{s}\" = \"{s}\",\n", .{ long, help_text });
                }
            }
            try writer.print("        .help = \"Show help information\",\n", .{});
            try writer.print("        .version = \"Show version information\",\n", .{});
            try writer.print("    }},\n", .{});
        }

        try writer.print("}}\n", .{});

        return buf.toOwnedSlice();
    }

    /// Generate completion command to be embedded in CLI
    pub fn generateCompletionCommand(self: CompletionGenerator, program_name: []const u8) Command.Command {
        _ = self;
        _ = program_name;
        // Simplified version - will be enhanced when Command API is stable
        return Command.Command.init("completion", (Command.CommandConfig{})
            .withAbout("Generate shell completion scripts")
        );
    }

    /// Handle completion command execution
    pub fn handleCompletionCommand(self: CompletionGenerator, ctx: Context.Context, root_command: Command.Command, program_name: []const u8) !void {
        const shell_str = ctx.getString("shell") orelse return error.MissingShell;
        const shell = Shell.fromString(shell_str) orelse return error.InvalidShell;

        const completion_script = try self.generate(root_command, shell, program_name);
        defer self.allocator.free(completion_script);

        if (ctx.getString("output")) |output_file| {
            try std.fs.cwd().writeFile(.{ .sub_path = output_file, .data = completion_script });
        } else {
            try std.io.getStdOut().writeAll(completion_script);
        }
    }
};

// Built-in completion command for dynamic completions
pub fn createBuiltinCompletionCommand() Command.Command {
    return Command.Command.init("__complete", (Command.CommandConfig{})
        .withAbout("Internal completion command")
        .withHidden(true)
        .withArgs(&.{
            Argument.Argument.init("shell", (Argument.ArgumentConfig{}).withRequired(true)),
            Argument.Argument.init("current", (Argument.ArgumentConfig{}).withRequired(false)),
        })
    );
}

test "bash completion generation" {
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    defer generator.deinit();

    const test_cmd = Command.Command.init("testcli", (Command.CommandConfig{})
        .withSubcommands(&.{
            Command.Command.init("deploy", (Command.CommandConfig{}).withAbout("Deploy application")),
            Command.Command.init("status", (Command.CommandConfig{}).withAbout("Show status")),
        }));

    const completion = try generator.generate(test_cmd, .bash, "testcli");
    defer allocator.free(completion);

    try std.testing.expect(std.mem.indexOf(u8, completion, "deploy") != null);
    try std.testing.expect(std.mem.indexOf(u8, completion, "status") != null);
    try std.testing.expect(std.mem.indexOf(u8, completion, "help") != null);
    try std.testing.expect(std.mem.indexOf(u8, completion, "completion") != null);
}

test "zsh completion generation" {
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    defer generator.deinit();

    const test_cmd = Command.Command.init("testcli", (Command.CommandConfig{})
        .withSubcommands(&.{
            Command.Command.init("build", (Command.CommandConfig{}).withAbout("Build the project")),
        }));

    const completion = try generator.generate(test_cmd, .zsh, "testcli");
    defer allocator.free(completion);

    try std.testing.expect(std.mem.indexOf(u8, completion, "build") != null);
    try std.testing.expect(std.mem.indexOf(u8, completion, "compdef") != null);
}

test "custom completer registration" {
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    defer generator.deinit();

    const config = CompletionConfig{
        .static_values = &.{ "json", "yaml", "toml" },
    };

    try generator.addCustomCompleter("format", config);
    try std.testing.expect(generator.custom_completers.contains("format"));
}

test "handleCompletionCommand requires shell argument" {
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    defer generator.deinit();

    var ctx = try Context.Context.init(allocator, &.{});
    defer ctx.deinit();
    // No shell argument set

    const test_cmd = Command.Command.init("testcli", Command.CommandConfig{});

    const result = generator.handleCompletionCommand(ctx, test_cmd, "testcli");
    try std.testing.expectError(error.MissingShell, result);
}

test "handleCompletionCommand rejects invalid shell" {
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    defer generator.deinit();

    var ctx = try Context.Context.init(allocator, &.{});
    defer ctx.deinit();
    try ctx.setValue("shell", Argument.ArgValue{ .string = "notashell" });

    const test_cmd = Command.Command.init("testcli", Command.CommandConfig{});

    const result = generator.handleCompletionCommand(ctx, test_cmd, "testcli");
    try std.testing.expectError(error.InvalidShell, result);
}

test "fish completion generation" {
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    defer generator.deinit();

    const test_cmd = Command.Command.init("myapp", (Command.CommandConfig{})
        .withSubcommands(&.{
            Command.Command.init("run", (Command.CommandConfig{}).withAbout("Run the app")),
        }));

    const completion = try generator.generate(test_cmd, .fish, "myapp");
    defer allocator.free(completion);

    try std.testing.expect(std.mem.indexOf(u8, completion, "# ⚡ Flash completion script for Fish") != null);
    try std.testing.expect(std.mem.indexOf(u8, completion, "complete -c myapp") != null);
    try std.testing.expect(std.mem.indexOf(u8, completion, "run") != null);
}

test "powershell completion generation" {
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    defer generator.deinit();

    const test_cmd = Command.Command.init("tool", (Command.CommandConfig{})
        .withSubcommands(&.{
            Command.Command.init("init", (Command.CommandConfig{}).withAbout("Initialize")),
        }));

    const completion = try generator.generate(test_cmd, .powershell, "tool");
    defer allocator.free(completion);

    try std.testing.expect(std.mem.indexOf(u8, completion, "# ⚡ Flash completion script for PowerShell") != null);
    try std.testing.expect(std.mem.indexOf(u8, completion, "Register-ArgumentCompleter") != null);
    try std.testing.expect(std.mem.indexOf(u8, completion, "init") != null);
}

test "generateToFile creates completion file" {
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    defer generator.deinit();

    const test_cmd = Command.Command.init("filetest", (Command.CommandConfig{})
        .withAbout("Test file generation"));

    // Use /tmp for test output
    const tmp_dir = "/tmp/flash_completion_test";
    std.fs.cwd().makePath(tmp_dir) catch {};
    defer std.fs.cwd().deleteTree(tmp_dir) catch {};

    try generator.generateToFile(test_cmd, .bash, "filetest", tmp_dir);

    // Verify file was created
    const expected_path = tmp_dir ++ "/filetest.bash";
    const file = try std.fs.cwd().openFile(expected_path, .{});
    defer file.close();

    var buf: [1024]u8 = undefined;
    const bytes_read = try file.readAll(&buf);
    try std.testing.expect(bytes_read > 0);
    try std.testing.expect(std.mem.indexOf(u8, buf[0..bytes_read], "Flash completion script for Bash") != null);
}

test "bash completion with argument choices" {
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    defer generator.deinit();

    const choices = &[_][]const u8{ "debug", "info", "warn", "error" };
    const test_cmd = Command.Command.init("logapp", (Command.CommandConfig{})
        .withArgs(&.{
            Argument.Argument.init("level", (Argument.ArgumentConfig{})
                .withHelp("Log level")
                .withChoices(choices)),
        }));

    const completion = try generator.generate(test_cmd, .bash, "logapp");
    defer allocator.free(completion);

    // Verify choices are in the completion script
    try std.testing.expect(std.mem.indexOf(u8, completion, "debug") != null);
    try std.testing.expect(std.mem.indexOf(u8, completion, "info") != null);
    try std.testing.expect(std.mem.indexOf(u8, completion, "warn") != null);
    try std.testing.expect(std.mem.indexOf(u8, completion, "error") != null);
}

test "fish completion with argument choices" {
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    defer generator.deinit();

    const choices = &[_][]const u8{ "json", "yaml", "toml" };
    const test_cmd = Command.Command.init("formatter", (Command.CommandConfig{})
        .withArgs(&.{
            Argument.Argument.init("format", (Argument.ArgumentConfig{})
                .withHelp("Output format")
                .withChoices(choices)),
        }));

    const completion = try generator.generate(test_cmd, .fish, "formatter");
    defer allocator.free(completion);

    // Verify choices are in the completion script
    try std.testing.expect(std.mem.indexOf(u8, completion, "json") != null);
    try std.testing.expect(std.mem.indexOf(u8, completion, "yaml") != null);
    try std.testing.expect(std.mem.indexOf(u8, completion, "toml") != null);
}