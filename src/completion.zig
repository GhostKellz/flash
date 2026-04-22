//! ⚡ Flash Shell Completion Generation
//!
//! Generates dynamic shell completion scripts for Bash, Zsh, Fish, and PowerShell
//! Supports custom completers, flag completions, and dynamic value generation

const std = @import("std");
const Command = @import("command.zig");
const Argument = @import("argument.zig");
const Flag = @import("flag.zig");
const Context = @import("context.zig");
const flash_async = @import("async.zig");

fn writeStdout(bytes: []const u8) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(std.Io.Threaded.global_single_threaded.io(), &stdout_buffer);
    stdout_writer.interface.writeAll(bytes) catch return error.IOError;
}

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
pub const AsyncCompletionFn = *const fn (Context.Context, []const u8) flash_async.Future(anyerror![]const []const u8);

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

const CompletionState = struct {
    command_path: []const []const u8,
    current_command: Command.Command,
    current_prefix: []const u8,
    expecting_value_for: ?Argument.Argument = null,
};

const DynamicCompletionBehavior = struct {
    no_file_completion: bool = false,
    directory_only: bool = false,
    file_extensions: ?[]const []const u8 = null,
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

        _ = output_dir;
        try writeStdout(completion_script);
    }

    fn generateBash(self: CompletionGenerator, command: Command.Command, program_name: []const u8) ![]u8 {
        var aw: std.Io.Writer.Allocating = .init(self.allocator);
        const writer = &aw.writer;

        try writer.print("# ⚡ Flash completion script for Bash\n", .{});
        try writer.print("# Generated for {s}\n", .{program_name});
        try writer.print("# Support dynamic completions, flags, and file completion\n\n", .{});

        // Helper functions for dynamic completion
        if (self.enable_dynamic) {
            try writer.print("_{s}_dynamic_completion() {{\n", .{program_name});
            try writer.print("    local cmd=\"$1\"\n", .{});
            try writer.print("    local current=\"$2\"\n", .{});
            try writer.print("    shift 2\n", .{});
            try writer.print("    \"$cmd\" __complete bash \"$current\" \"$@\" 2>/dev/null || echo \"\"\n", .{});
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
            try writer.print("            local completion_output\n", .{});
            try writer.print("            local -a completions\n", .{});
            try writer.print("            local no_file_comp=0\n", .{});
            try writer.print("            local directory_only=0\n", .{});
            try writer.print("            local file_extensions=\"\"\n", .{});
            try writer.print("            completions=$(_{s}_dynamic_completion \"{s}\" \"$cur\" \"${{words[@]}}\")\n", .{ program_name, program_name });
            try writer.print("            while IFS= read -r line; do\n", .{});
            try writer.print("                [[ -z \"$line\" ]] && continue\n", .{});
            try writer.print("                case \"$line\" in\n", .{});
            try writer.print("                    __flash_directive__:no_file_comp) no_file_comp=1 ;;\n", .{});
            try writer.print("                    __flash_directive__:filter_dirs) directory_only=1 ;;\n", .{});
            try writer.print("                    __flash_directive__:filter_file_ext:*) file_extensions=\"${{line#__flash_directive__:filter_file_ext:}}\" ;;\n", .{});
            try writer.print("                    *) completions+=(\"$line\") ;;\n", .{});
            try writer.print("                esac\n", .{});
            try writer.print("            done <<< \"$completions\"\n", .{});
            try writer.print("            if [[ ${{#completions[@]}} -gt 0 ]]; then\n", .{});
            try writer.print("                COMPREPLY=($(compgen -W \"${{completions[*]}}\" -- \"$cur\"))\n", .{});
            try writer.print("            elif [[ $directory_only -eq 1 ]]; then\n", .{});
            try writer.print("                _filedir -d\n", .{});
            try writer.print("            elif [[ -n \"$file_extensions\" ]]; then\n", .{});
            try writer.print("                local ext_glob=\"@(${{file_extensions//,/|}})\"\n", .{});
            try writer.print("                _filedir \"$ext_glob\"\n", .{});
            try writer.print("            elif [[ $no_file_comp -eq 0 ]]; then\n", .{});
            try writer.print("                _filedir\n", .{});
            try writer.print("            fi\n", .{});
        } else {
            try writer.print("            _filedir\n", .{});
        }

        try writer.print("            ;;\n", .{});
        try writer.print("    esac\n", .{});
        try writer.print("}}\n\n", .{});

        try writer.print("complete -F _{s}_completions {s}\n", .{ program_name, program_name });

        return aw.toOwnedSlice();
    }

    fn writeBashFlags(self: CompletionGenerator, writer: anytype, command: Command.Command) !void {
        _ = self;
        // Write global flags
        try writer.print("-h --help -V --version ", .{});

        for (command.getArgs()) |arg| {
            if (arg.isHidden() or !arg.isOption()) continue;
            if (arg.config.short) |short| {
                try writer.print("-{c} ", .{short});
            }
            if (arg.config.long) |long| {
                try writer.print("--{s} ", .{long});
            }
            for (arg.config.aliases) |alias| {
                try writer.print("--{s} ", .{alias});
            }
        }

        // Write command-specific flags
        for (command.getFlags()) |flag| {
            if (flag.isHidden()) continue;
            if (flag.config.short) |short| {
                try writer.print("-{c} ", .{short});
            }
            if (flag.config.long) |long| {
                try writer.print("--{s} ", .{long});
            }
            for (flag.config.aliases) |alias| {
                try writer.print("--{s} ", .{alias});
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
        var aw: std.Io.Writer.Allocating = .init(self.allocator);
        const writer = &aw.writer;

        try writer.print("# ⚡ Flash completion script for Zsh\n", .{});
        try writer.print("# Generated for {s}\n", .{program_name});
        try writer.print("# Support dynamic completions, flags, and file completion\n\n", .{});

        try self.generateZshCommandRecursive(writer, program_name, command, &.{}, command);

        try writer.print("_commands() {{\n", .{});
        try writer.print("    local commands; commands=(\n", .{});

        // Add subcommands with descriptions
        for (command.getSubcommands()) |subcmd| {
            if (!subcmd.isHidden()) {
                const about = subcmd.getAbout() orelse "";
                try writer.print("        '{s}:{s}'\n", .{ subcmd.name, about });
                for (subcmd.getAliases()) |alias| {
                    try writer.print("        '{s}:{s}'\n", .{ alias, about });
                }
            }
        }
        // Add builtin commands
        try writer.print("        'help:Show help information'\n", .{});
        try writer.print("        'version:Show version information'\n", .{});
        try writer.print("        'completion:Generate shell completion scripts'\n", .{});
        try writer.print("    )\n", .{});
        try writer.print("    _describe 'commands' commands\n", .{});
        try writer.print("}}\n\n", .{});

        try writer.print("compdef _{s} {s}\n", .{ program_name, program_name });

        return aw.toOwnedSlice();
    }

    fn generatePowerShell(self: CompletionGenerator, command: Command.Command, program_name: []const u8) ![]u8 {
        var aw: std.Io.Writer.Allocating = .init(self.allocator);
        const writer = &aw.writer;

        try writer.print("# ⚡ Flash completion script for PowerShell\n", .{});
        try writer.print("# Generated for {s}\n\n", .{program_name});

        try writer.print("Register-ArgumentCompleter -Native -CommandName {s} -ScriptBlock {{\n", .{program_name});
        try writer.print("    param($commandName, $wordToComplete, $cursorPosition)\n\n", .{});
        try writer.print("    $tokens = $wordToComplete -split ' '\n", .{});
        try writer.print("    $current = if ($tokens.Length -gt 0) {{ $tokens[-1] }} else {{ '' }}\n", .{});
        try writer.print("    $path = if ($tokens.Length -gt 1) {{ $tokens[0..($tokens.Length - 2)] }} else {{ @() }}\n\n", .{});

        try self.generatePowerShellTree(writer, command, "        $commands = @(", "    )", 2);
        try writer.print("\n    $scope = $commands\n", .{});
        try writer.print("    foreach ($segment in $path) {{\n", .{});
        try writer.print("        $match = $scope | Where-Object {{ $_.Name -eq $segment }} | Select-Object -First 1\n", .{});
        try writer.print("        if ($null -ne $match -and $match.Children) {{ $scope = $match.Children }}\n", .{});
        try writer.print("    }}\n\n", .{});
        try writer.print("    $scope | Where-Object {{ $_.Name -like \"$current*\" }} | ForEach-Object {{\n", .{});
        try writer.print("        [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', $_.Description)\n", .{});
        try writer.print("    }}\n", .{});
        try writer.print("}}\n", .{});

        return aw.toOwnedSlice();
    }

    fn generateNuShell(self: CompletionGenerator, command: Command.Command, program_name: []const u8) ![]u8 {
        var aw: std.Io.Writer.Allocating = .init(self.allocator);
        const writer = &aw.writer;

        try writer.print("# ⚡ Flash completion script for Nu Shell\n", .{});
        try writer.print("# Generated for {s}\n\n", .{program_name});

        try writer.print("def \"nu-complete {s}\" [context?: list<string>] {{\n", .{program_name});
        try self.generateNuShellTree(writer, command, 1);
        try writer.print("    let path = if ($context | is-empty) {{ [] }} else {{ $context }}\n", .{});
        try writer.print("    mut scope = $commands\n", .{});
        try writer.print("    for segment in $path {{\n", .{});
        try writer.print("        let match = ($scope | where value == $segment | get 0? )\n", .{});
        try writer.print("        if $match != null and ($match | get children? | default [] | length) > 0 {{\n", .{});
        try writer.print("            $scope = ($match | get children)\n", .{});
        try writer.print("        }}\n", .{});
        try writer.print("    }}\n", .{});
        try writer.print("    $scope\n", .{});
        try writer.print("}}\n\n", .{});

        try writer.print("extern \"{s}\" [\n", .{program_name});
        try writer.print("    subcommand?: string@\"nu-complete {s}\"\n", .{program_name});
        try writer.print("    --help(-h)     # Show help information\n", .{});
        try writer.print("    --version(-V)  # Show version information\n", .{});
        try writer.print("]\n", .{});

        return aw.toOwnedSlice();
    }

    fn generateFish(self: CompletionGenerator, command: Command.Command, program_name: []const u8) ![]u8 {
        var aw: std.Io.Writer.Allocating = .init(self.allocator);
        const writer = &aw.writer;

        try writer.print("# ⚡ Flash completion script for Fish\n", .{});
        try writer.print("# Generated for {s}\n\n", .{program_name});

        try self.generateFishCommandRecursive(writer, program_name, command, &.{}, command);

        try writer.print("complete -c {s} -f -s h -l help -d 'Show help information'\n", .{program_name});
        try writer.print("complete -c {s} -f -s V -l version -d 'Show version information'\n", .{program_name});

        return aw.toOwnedSlice();
    }

    fn generateGShell(self: CompletionGenerator, command: Command.Command, program_name: []const u8) ![]u8 {
        var aw: std.Io.Writer.Allocating = .init(self.allocator);
        const writer = &aw.writer;

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
                    for (subcmd.getAliases()) |alias| {
                        try writer.print("        .{s} = .{{ .description = \"{s}\" }},\n", .{ alias, about });
                    }
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
                if (flag.isHidden()) continue;
                const help_text = flag.config.help orelse "";
                if (flag.config.long) |long| {
                    try writer.print("        .@\"{s}\" = \"{s}\",\n", .{ long, help_text });
                }
                for (flag.config.aliases) |alias| {
                    try writer.print("        .@\"{s}\" = \"{s}\",\n", .{ alias, help_text });
                }
            }
            for (command.getArgs()) |arg| {
                if (arg.isHidden() or !arg.isOption()) continue;
                const help_text = arg.getHelp() orelse arg.name;
                if (arg.config.long) |long| {
                    try writer.print("        .@\"{s}\" = \"{s}\",\n", .{ long, help_text });
                }
                for (arg.config.aliases) |alias| {
                    try writer.print("        .@\"{s}\" = \"{s}\",\n", .{ alias, help_text });
                }
            }
            try writer.print("        .help = \"Show help information\",\n", .{});
            try writer.print("        .version = \"Show version information\",\n", .{});
            try writer.print("    }},\n", .{});
        }

        try writer.print("}}\n", .{});

        return aw.toOwnedSlice();
    }

    /// Generate completion command to be embedded in CLI
    pub fn generateCompletionCommand(self: CompletionGenerator, program_name: []const u8) Command.Command {
        _ = self;
        _ = program_name;
        return Command.Command.init("completion", (Command.CommandConfig{})
            .withAbout("Generate shell completion scripts")
            .withArgs(&.{Argument.Argument.init("shell", (Argument.ArgumentConfig{})
            .withHelp("Shell to generate completions for")
            .withChoices(&.{ "bash", "zsh", "fish", "powershell", "nushell", "gsh" })
            .setRequired())}));
    }

    /// Handle completion command execution
    pub fn handleCompletionCommand(self: CompletionGenerator, ctx: Context.Context, root_command: Command.Command, program_name: []const u8) !void {
        const shell_str = ctx.getString("shell") orelse blk: {
            if (ctx.getPositional(0)) |value| break :blk value.asString();
            return error.MissingShell;
        };
        const shell = Shell.fromString(shell_str) orelse return error.InvalidShell;

        const completion_script = try self.generate(root_command, shell, program_name);
        defer self.allocator.free(completion_script);

        try writeStdout(completion_script);
    }

    pub fn handleDynamicCompletion(self: *CompletionGenerator, raw_args: []const []const u8, root_command: Command.Command) !void {
        if (raw_args.len < 4) return;

        const shell = Shell.fromString(raw_args[2]) orelse return error.InvalidShell;
        _ = shell;

        const state = try self.analyzeCompletionContext(raw_args, root_command);
        try self.writeDynamicCandidates(state, root_command);
    }

    fn analyzeCompletionContext(self: *CompletionGenerator, raw_args: []const []const u8, root_command: Command.Command) !CompletionState {
        var path = std.ArrayList([]const u8).empty;
        defer path.deinit(self.allocator);

        var current_prefix = raw_args[3];
        var current_command = root_command;
        var expecting_value_for: ?Argument.Argument = null;

        if (raw_args.len > 4) {
            for (raw_args[4 .. raw_args.len - 1]) |word| {
                if (expecting_value_for != null) {
                    expecting_value_for = null;
                    continue;
                }

                if (std.mem.startsWith(u8, word, "--")) {
                    if (std.mem.indexOfScalar(u8, word[2..], '=')) |eq| {
                        const name = word[2 .. 2 + eq];
                        if (current_command.findArg(name)) |arg| {
                            expecting_value_for = arg;
                            break;
                        }
                    } else if (current_command.findArg(word[2..])) |arg| {
                        expecting_value_for = arg;
                    }
                    continue;
                }

                if (std.mem.startsWith(u8, word, "-") and word.len > 1) {
                    if (word.len > 2) {
                        const short = word[1];
                        for (current_command.getArgs()) |arg| {
                            if (arg.config.short == short and arg.isOption()) {
                                if (word.len == 2) expecting_value_for = arg;
                                break;
                            }
                        }
                    }
                    continue;
                }

                if (current_command.findSubcommand(word)) |subcmd| {
                    try path.append(self.allocator, subcmd.name);
                    current_command = subcmd;
                    continue;
                }
            }
        }

        if (std.mem.startsWith(u8, current_prefix, "--")) {
            if (std.mem.indexOfScalar(u8, current_prefix[2..], '=')) |eq| {
                const name = current_prefix[2 .. 2 + eq];
                if (current_command.findArg(name)) |arg| {
                    expecting_value_for = arg;
                    current_prefix = current_prefix[2 + eq + 1 ..];
                }
            }
        }

        return .{
            .command_path = try path.toOwnedSlice(self.allocator),
            .current_command = current_command,
            .current_prefix = current_prefix,
            .expecting_value_for = expecting_value_for,
        };
    }

    fn writeDynamicCandidates(self: *CompletionGenerator, state: CompletionState, root_command: Command.Command) !void {
        defer self.allocator.free(state.command_path);

        var aw: std.Io.Writer.Allocating = .init(self.allocator);
        defer aw.deinit();
        const writer = &aw.writer;
        var behavior = DynamicCompletionBehavior{};

        if (state.expecting_value_for) |arg| {
            if (self.custom_completers.get(arg.name)) |config| {
                if (config.completion_fn) |completion_fn| {
                    var completion_ctx = Context.Context.init(self.allocator, &.{});
                    defer completion_ctx.deinit();
                    for (state.command_path) |segment| try completion_ctx.pushCommand(segment);

                    const values = try completion_fn(completion_ctx, state.current_prefix);
                    for (values) |value| {
                        if (state.current_prefix.len == 0 or std.mem.startsWith(u8, value, state.current_prefix)) {
                            try writer.print("{s}\n", .{value});
                        }
                    }
                }

                if (config.async_completion_fn) |async_completion_fn| {
                    var completion_ctx = Context.Context.init(self.allocator, &.{});
                    defer completion_ctx.deinit();
                    for (state.command_path) |segment| try completion_ctx.pushCommand(segment);

                    var future = async_completion_fn(completion_ctx, state.current_prefix);
                    const values = try future.resolve();
                    for (values) |value| {
                        if (state.current_prefix.len == 0 or std.mem.startsWith(u8, value, state.current_prefix)) {
                            try writer.print("{s}\n", .{value});
                        }
                    }
                }

                if (config.static_values) |values| {
                    for (values) |value| {
                        if (state.current_prefix.len == 0 or std.mem.startsWith(u8, value, state.current_prefix)) {
                            try writer.print("{s}\n", .{value});
                        }
                    }
                }

                behavior.no_file_completion = config.no_file_completion;
                behavior.directory_only = config.directory_only;
                behavior.file_extensions = config.file_extensions;
            }

            if (arg.getChoices()) |choices| {
                for (choices) |choice| {
                    if (state.current_prefix.len == 0 or std.mem.startsWith(u8, choice, state.current_prefix)) {
                        try writer.print("{s}\n", .{choice});
                    }
                }
            }
            try self.writeBehaviorDirectives(writer, behavior);
            try writeStdout(aw.written());
            return;
        }

        if (std.mem.startsWith(u8, state.current_prefix, "-")) {
            const flags = try Command.Command.collectScopedFlags(root_command, state.command_path, self.allocator);
            defer self.allocator.free(flags);

            for (flags) |flag| {
                if (flag.isHidden()) continue;
                if (flag.config.short) |short| {
                    const name = try std.fmt.allocPrint(self.allocator, "-{c}", .{short});
                    defer self.allocator.free(name);
                    if (std.mem.startsWith(u8, name, state.current_prefix)) try writer.print("{s}\n", .{name});
                }
                if (flag.config.long) |long| {
                    const name = try std.fmt.allocPrint(self.allocator, "--{s}", .{long});
                    defer self.allocator.free(name);
                    if (std.mem.startsWith(u8, name, state.current_prefix)) try writer.print("{s}\n", .{name});
                }
                for (flag.config.aliases) |alias| {
                    const name = try std.fmt.allocPrint(self.allocator, "--{s}", .{alias});
                    defer self.allocator.free(name);
                    if (std.mem.startsWith(u8, name, state.current_prefix)) try writer.print("{s}\n", .{name});
                }
            }

            for (state.current_command.getArgs()) |arg| {
                if (arg.isHidden() or !arg.isOption()) continue;
                if (arg.config.short) |short| {
                    const name = try std.fmt.allocPrint(self.allocator, "-{c}", .{short});
                    defer self.allocator.free(name);
                    if (std.mem.startsWith(u8, name, state.current_prefix)) try writer.print("{s}\n", .{name});
                }
                if (arg.config.long) |long| {
                    const name = try std.fmt.allocPrint(self.allocator, "--{s}", .{long});
                    defer self.allocator.free(name);
                    if (std.mem.startsWith(u8, name, state.current_prefix)) try writer.print("{s}\n", .{name});
                }
                for (arg.config.aliases) |alias| {
                    const name = try std.fmt.allocPrint(self.allocator, "--{s}", .{alias});
                    defer self.allocator.free(name);
                    if (std.mem.startsWith(u8, name, state.current_prefix)) try writer.print("{s}\n", .{name});
                }
            }

            try writeStdout(aw.written());
            return;
        }

        for (state.current_command.getSubcommands()) |subcmd| {
            if (subcmd.isHidden()) continue;
            if (state.current_prefix.len == 0 or std.mem.startsWith(u8, subcmd.name, state.current_prefix)) {
                try writer.print("{s}\n", .{subcmd.name});
            }
            for (subcmd.getAliases()) |alias| {
                if (state.current_prefix.len == 0 or std.mem.startsWith(u8, alias, state.current_prefix)) {
                    try writer.print("{s}\n", .{alias});
                }
            }
        }

        try self.writeBehaviorDirectives(writer, behavior);
        try writeStdout(aw.written());
    }

    fn writeBehaviorDirectives(self: *CompletionGenerator, writer: anytype, behavior: DynamicCompletionBehavior) !void {
        _ = self;
        if (behavior.no_file_completion) {
            try writer.print("__flash_directive__:no_file_comp\n", .{});
        }
        if (behavior.directory_only) {
            try writer.print("__flash_directive__:filter_dirs\n", .{});
        }
        if (behavior.file_extensions) |exts| {
            try writer.print("__flash_directive__:filter_file_ext:", .{});
            for (exts, 0..) |ext, i| {
                if (i > 0) try writer.print(",", .{});
                try writer.print("{s}", .{ext});
            }
            try writer.print("\n", .{});
        }
    }

    fn zshValueSpec(self: CompletionGenerator, arg: Argument.Argument) !?[]u8 {
        if (self.custom_completers.get(arg.name)) |config| {
            if (config.static_values) |values| {
                return try self.zshChoiceSpec(values, arg.getHelp());
            }
            if (config.directory_only) {
                return try self.allocator.dupe(u8, "_files -/");
            }
            if (config.file_extensions) |exts| {
                var aw: std.Io.Writer.Allocating = .init(self.allocator);
                defer aw.deinit();
                try aw.writer.print("_files -g '*.(", .{});
                for (exts, 0..) |ext, i| {
                    if (i > 0) try aw.writer.print("|", .{});
                    try aw.writer.print("{s}", .{ext});
                }
                try aw.writer.print(")'", .{});
                return try aw.toOwnedSlice();
            }
        }

        if (arg.getChoices()) |choices| {
            return try self.zshChoiceSpec(choices, arg.getHelp());
        }

        return null;
    }

    fn zshChoiceSpec(self: CompletionGenerator, values: []const []const u8, description: ?[]const u8) ![]u8 {
        var aw: std.Io.Writer.Allocating = .init(self.allocator);
        defer aw.deinit();
        try aw.writer.print("(", .{});
        for (values, 0..) |value, i| {
            if (i > 0) try aw.writer.print(" ", .{});
            if (description) |desc| {
                try aw.writer.print("\"{s}:{s}\"", .{ value, desc });
            } else {
                try aw.writer.print("{s}", .{value});
            }
        }
        try aw.writer.print(")", .{});
        return try aw.toOwnedSlice();
    }

    fn writeScopedZshArguments(self: CompletionGenerator, writer: anytype, root: Command.Command, path: []const []const u8) !void {
        const current = Command.Command.findCommandByPath(root, path) orelse root;
        const flags = try Command.Command.collectScopedFlags(root, path, self.allocator);
        defer self.allocator.free(flags);

        for (flags) |flag| {
            if (flag.isHidden()) continue;
            const help_text = flag.config.help orelse "";
            if (flag.config.short) |short| {
                try writer.print("        '-{c}[{s}]' \\\n", .{ short, help_text });
            }
            if (flag.config.long) |long| {
                try writer.print("        '--{s}[{s}]' \\\n", .{ long, help_text });
            }
            for (flag.config.aliases) |alias| {
                try writer.print("        '--{s}[{s}]' \\\n", .{ alias, help_text });
            }
        }

        for (current.getArgs()) |arg| {
            if (arg.isHidden() or !arg.isOption()) continue;
            const help_text = arg.getHelp() orelse "";
            const value_spec = try self.zshValueSpec(arg);
            defer if (value_spec) |spec| self.allocator.free(spec);
            const action = value_spec orelse "_files";
            if (arg.config.short) |short| {
                try writer.print("        '-{c}[{s}]:{s}:{s}' \\\n", .{ short, help_text, arg.name, action });
            }
            if (arg.config.long) |long| {
                try writer.print("        '--{s}[{s}]:{s}:{s}' \\\n", .{ long, help_text, arg.name, action });
            }
            for (arg.config.aliases) |alias| {
                try writer.print("        '--{s}[{s}]:{s}:{s}' \\\n", .{ alias, help_text, arg.name, action });
            }
        }
    }

    fn fishValueCandidates(self: CompletionGenerator, arg: Argument.Argument) !?[]u8 {
        if (self.custom_completers.get(arg.name)) |config| {
            if (config.static_values) |values| {
                var aw: std.Io.Writer.Allocating = .init(self.allocator);
                defer aw.deinit();
                for (values, 0..) |value, i| {
                    if (i > 0) try aw.writer.print(" ", .{});
                    try aw.writer.print("{s}", .{value});
                }
                return try aw.toOwnedSlice();
            }
        }

        if (arg.getChoices()) |choices| {
            var aw: std.Io.Writer.Allocating = .init(self.allocator);
            defer aw.deinit();
            for (choices, 0..) |choice, i| {
                if (i > 0) try aw.writer.print(" ", .{});
                try aw.writer.print("{s}", .{choice});
            }
            return try aw.toOwnedSlice();
        }

        return null;
    }

    fn generatePowerShellTree(self: CompletionGenerator, writer: anytype, command: Command.Command, prefix: []const u8, suffix: []const u8, indent_level: usize) !void {
        const indent = "    ";
        for (0..indent_level) |_| try writer.print("{s}", .{indent});
        try writer.print("{s}\n", .{prefix});

        for (command.getSubcommands()) |subcmd| {
            if (subcmd.isHidden()) continue;
            const about = subcmd.getAbout() orelse "";
            for (0..indent_level + 1) |_| try writer.print("{s}", .{indent});
            try writer.print("@{{ Name = '{s}'; Description = '{s}'; Children = @(\n", .{ subcmd.name, about });
            try self.generatePowerShellTree(writer, subcmd, "", "", indent_level + 2);
            for (0..indent_level + 1) |_| try writer.print("{s}", .{indent});
            try writer.print(") }}\n", .{});
            for (subcmd.getAliases()) |alias| {
                for (0..indent_level + 1) |_| try writer.print("{s}", .{indent});
                try writer.print("@{{ Name = '{s}'; Description = '{s}'; Children = @() }}\n", .{ alias, about });
            }
        }

        if (indent_level == 2) {
            for (0..indent_level + 1) |_| try writer.print("{s}", .{indent});
            try writer.print("@{{ Name = 'help'; Description = 'Show help information'; Children = @() }}\n", .{});
            for (0..indent_level + 1) |_| try writer.print("{s}", .{indent});
            try writer.print("@{{ Name = 'version'; Description = 'Show version information'; Children = @() }}\n", .{});
            for (0..indent_level + 1) |_| try writer.print("{s}", .{indent});
            try writer.print("@{{ Name = 'completion'; Description = 'Generate shell completion scripts'; Children = @() }}\n", .{});
        }

        if (suffix.len > 0) {
            for (0..indent_level) |_| try writer.print("{s}", .{indent});
            try writer.print("{s}\n", .{suffix});
        }
    }

    fn generateNuShellTree(self: CompletionGenerator, writer: anytype, command: Command.Command, indent_level: usize) !void {
        _ = self;
        const indent = "    ";
        for (0..indent_level) |_| try writer.print("{s}", .{indent});
        try writer.print("let commands = [\n", .{});

        for (command.getSubcommands()) |subcmd| {
            if (subcmd.isHidden()) continue;
            const about = subcmd.getAbout() orelse "";
            for (0..indent_level + 1) |_| try writer.print("{s}", .{indent});
            try writer.print("{{ value: \"{s}\", description: \"{s}\", children: [\n", .{ subcmd.name, about });
            for (subcmd.getSubcommands()) |child| {
                if (child.isHidden()) continue;
                const child_about = child.getAbout() orelse "";
                for (0..indent_level + 2) |_| try writer.print("{s}", .{indent});
                try writer.print("{{ value: \"{s}\", description: \"{s}\", children: [] }},\n", .{ child.name, child_about });
            }
            for (0..indent_level + 1) |_| try writer.print("{s}", .{indent});
            try writer.print("] }},\n", .{});
            for (subcmd.getAliases()) |alias| {
                for (0..indent_level + 1) |_| try writer.print("{s}", .{indent});
                try writer.print("{{ value: \"{s}\", description: \"{s}\", children: [] }},\n", .{ alias, about });
            }
        }

        if (indent_level == 1) {
            for (0..indent_level + 1) |_| try writer.print("{s}", .{indent});
            try writer.print("{{ value: \"help\", description: \"Show help information\", children: [] }},\n", .{});
            for (0..indent_level + 1) |_| try writer.print("{s}", .{indent});
            try writer.print("{{ value: \"version\", description: \"Show version information\", children: [] }},\n", .{});
            for (0..indent_level + 1) |_| try writer.print("{s}", .{indent});
            try writer.print("{{ value: \"completion\", description: \"Generate shell completion scripts\", children: [] }},\n", .{});
        }

        for (0..indent_level) |_| try writer.print("{s}", .{indent});
        try writer.print("]\n", .{});
    }

    fn writeFishScopedOptions(self: CompletionGenerator, writer: anytype, program_name: []const u8, root: Command.Command, path: []const []const u8, command: Command.Command) !void {
        const flags = try Command.Command.collectScopedFlags(root, path, self.allocator);
        defer self.allocator.free(flags);

        const condition = if (path.len == 0)
            try self.allocator.dupe(u8, "not __fish_seen_subcommand_from *")
        else blk: {
            const joined = try std.mem.join(self.allocator, " ", path);
            defer self.allocator.free(joined);
            break :blk try std.fmt.allocPrint(self.allocator, "__fish_seen_subcommand_from {s}", .{joined});
        };
        defer self.allocator.free(condition);

        for (flags) |flag| {
            if (flag.isHidden()) continue;
            const help_text = flag.config.help orelse "";
            if (flag.config.short) |short| {
                try writer.print("complete -c {s} -f -n \"{s}\" -s {c} -d '{s}'\n", .{ program_name, condition, short, help_text });
            }
            if (flag.config.long) |long| {
                try writer.print("complete -c {s} -f -n \"{s}\" -l {s} -d '{s}'\n", .{ program_name, condition, long, help_text });
            }
            for (flag.config.aliases) |alias| {
                try writer.print("complete -c {s} -f -n \"{s}\" -l {s} -d '{s}'\n", .{ program_name, condition, alias, help_text });
            }
        }

        for (command.getArgs()) |arg| {
            if (arg.isHidden() or !arg.isOption()) continue;
            const help_text = arg.getHelp() orelse arg.name;
            const candidates = try self.fishValueCandidates(arg);
            defer if (candidates) |values| self.allocator.free(values);

            if (arg.config.short) |short| {
                if (candidates) |values| {
                    try writer.print("complete -c {s} -f -n \"{s}\" -s {c} -a \"{s}\" -d '{s}'\n", .{ program_name, condition, short, values, help_text });
                } else {
                    try writer.print("complete -c {s} -f -n \"{s}\" -s {c} -d '{s}'\n", .{ program_name, condition, short, help_text });
                }
            }
            if (arg.config.long) |long| {
                if (candidates) |values| {
                    try writer.print("complete -c {s} -f -n \"{s}\" -l {s} -a \"{s}\" -d '{s}'\n", .{ program_name, condition, long, values, help_text });
                } else {
                    try writer.print("complete -c {s} -f -n \"{s}\" -l {s} -d '{s}'\n", .{ program_name, condition, long, help_text });
                }
            }
            for (arg.config.aliases) |alias| {
                if (candidates) |values| {
                    try writer.print("complete -c {s} -f -n \"{s}\" -l {s} -a \"{s}\" -d '{s}'\n", .{ program_name, condition, alias, values, help_text });
                } else {
                    try writer.print("complete -c {s} -f -n \"{s}\" -l {s} -d '{s}'\n", .{ program_name, condition, alias, help_text });
                }
            }
        }
    }

    fn generateFishCommandRecursive(self: CompletionGenerator, writer: anytype, program_name: []const u8, root: Command.Command, path: []const []const u8, command: Command.Command) !void {
        try self.writeFishScopedOptions(writer, program_name, root, path, command);

        const condition = if (path.len == 0)
            try self.allocator.dupe(u8, "__fish_use_subcommand")
        else blk: {
            const joined = try std.mem.join(self.allocator, " ", path);
            defer self.allocator.free(joined);
            break :blk try std.fmt.allocPrint(self.allocator, "__fish_seen_subcommand_from {s}", .{joined});
        };
        defer self.allocator.free(condition);

        for (command.getSubcommands()) |subcmd| {
            if (subcmd.isHidden()) continue;
            const about = subcmd.getAbout() orelse "";
            try writer.print("complete -c {s} -f -n \"{s}\" -a {s} -d '{s}'\n", .{ program_name, condition, subcmd.name, about });
            for (subcmd.getAliases()) |alias| {
                try writer.print("complete -c {s} -f -n \"{s}\" -a {s} -d '{s}'\n", .{ program_name, condition, alias, about });
            }

            const child_path = try self.extendPath(path, subcmd.name);
            defer self.freePath(child_path);
            try self.generateFishCommandRecursive(writer, program_name, root, child_path, subcmd);
        }

        if (path.len == 0) {
            try writer.print("complete -c {s} -f -n \"__fish_use_subcommand\" -a help -d 'Show help information'\n", .{program_name});
            try writer.print("complete -c {s} -f -n \"__fish_use_subcommand\" -a version -d 'Show version information'\n", .{program_name});
            try writer.print("complete -c {s} -f -n \"__fish_use_subcommand\" -a completion -d 'Generate shell completion scripts'\n", .{program_name});
        }
    }

    fn generateZshCommandRecursive(self: CompletionGenerator, writer: anytype, program_name: []const u8, root: Command.Command, path: []const []const u8, command: Command.Command) !void {
        const func_name = if (path.len == 0)
            try std.fmt.allocPrint(self.allocator, "_{s}", .{program_name})
        else blk: {
            var aw: std.Io.Writer.Allocating = .init(self.allocator);
            defer aw.deinit();
            try aw.writer.print("_{s}", .{program_name});
            for (path) |segment| try aw.writer.print("_{s}", .{segment});
            break :blk try aw.toOwnedSlice();
        };
        defer self.allocator.free(func_name);

        try writer.print("{s}() {{\n", .{func_name});
        try writer.print("    local line\n", .{});
        try writer.print("    _arguments -C \\\n", .{});

        try writer.print("        '-h[Show help information]' \\\n", .{});
        try writer.print("        '--help[Show help information]' \\\n", .{});
        try writer.print("        '-V[Show version information]' \\\n", .{});
        try writer.print("        '--version[Show version information]' \\\n", .{});
        try self.writeScopedZshArguments(writer, root, path);

        if (command.hasSubcommands()) {
            try writer.print("        '1: :_commands' \\\n", .{});
        }
        try writer.print("        '*: :_files'\n\n", .{});

        if (command.hasSubcommands()) {
            try writer.print("    case $line[1] in\n", .{});
            for (command.getSubcommands()) |subcmd| {
                if (subcmd.isHidden()) continue;
                const child_name = try std.fmt.allocPrint(self.allocator, "_{s}_{s}", .{ func_name[1..], subcmd.name });
                defer self.allocator.free(child_name);
                try writer.print("        {s})\n", .{subcmd.name});
                try writer.print("            {s}\n", .{child_name});
                try writer.print("            ;;\n", .{});
            }
            try writer.print("    esac\n", .{});
        }

        try writer.print("}}\n\n", .{});

        for (command.getSubcommands()) |subcmd| {
            if (subcmd.isHidden()) continue;
            const child_path = try self.extendPath(path, subcmd.name);
            defer self.freePath(child_path);
            try self.generateZshCommandRecursive(writer, program_name, root, child_path, subcmd);
        }
    }

    fn extendPath(self: *const CompletionGenerator, path: []const []const u8, segment: []const u8) ![]const []const u8 {
        var next = try self.allocator.alloc([]const u8, path.len + 1);
        @memcpy(next[0..path.len], path);
        next[path.len] = segment;
        return next;
    }

    fn freePath(self: *const CompletionGenerator, path: []const []const u8) void {
        self.allocator.free(path);
    }
};

// Built-in completion command for dynamic completions
pub fn createBuiltinCompletionCommand() Command.Command {
    return Command.Command.init("completion", (Command.CommandConfig{})
        .withAbout("Generate shell completion scripts")
        .withArgs(&.{Argument.Argument.init("shell", (Argument.ArgumentConfig{})
        .withHelp("Shell to generate completions for")
        .withChoices(&.{ "bash", "zsh", "fish", "powershell", "nushell", "gsh" })
        .setRequired())}));
}

pub fn createBuiltinDynamicCompletionCommand() Command.Command {
    return Command.Command.init("__complete", (Command.CommandConfig{})
        .withAbout("Internal completion command")
        .setHidden()
        .withArgs(&.{
        Argument.Argument.init("shell", (Argument.ArgumentConfig{}).setRequired()),
        Argument.Argument.init("current", (Argument.ArgumentConfig{})),
        Argument.Argument.init("words", (Argument.ArgumentConfig{}).setMultiple()),
    }));
}

test "bash completion includes option args and aliases" {
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    defer generator.deinit();

    const cmd = Command.Command.init("serve", (Command.CommandConfig{})
        .withArgs(&.{Argument.Argument.init("output", (Argument.ArgumentConfig{})
            .withHelp("Output file")
            .withLong("output")
            .withAliases(&.{"out"}))})
        .withFlags(&.{Flag.Flag.init("verbose", (Flag.FlagConfig{})
        .withLong("verbose")
        .withAliases(&.{"chatty"}))}));

    const completion = try generator.generate(cmd, .bash, "serve");
    defer allocator.free(completion);

    try std.testing.expect(std.mem.indexOf(u8, completion, "--output") != null);
    try std.testing.expect(std.mem.indexOf(u8, completion, "--out") != null);
    try std.testing.expect(std.mem.indexOf(u8, completion, "--chatty") != null);
}

test "fish completion hides hidden entries and includes aliases" {
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    defer generator.deinit();

    const cmd = Command.Command.init("tool", (Command.CommandConfig{})
        .withSubcommands(&.{Command.Command.init("serve", (Command.CommandConfig{})
            .withAbout("Serve files")
            .withAliases(&.{"srv"}))})
        .withFlags(&.{
        Flag.Flag.init("visible", (Flag.FlagConfig{}).withLong("visible").withAliases(&.{"shown"})),
        Flag.Flag.init("hidden", (Flag.FlagConfig{}).withLong("hidden").setHidden()),
    }));

    const completion = try generator.generate(cmd, .fish, "tool");
    defer allocator.free(completion);

    try std.testing.expect(std.mem.indexOf(u8, completion, "-a serve") != null);
    try std.testing.expect(std.mem.indexOf(u8, completion, "-a srv") != null);
    try std.testing.expect(std.mem.indexOf(u8, completion, "-l visible") != null);
    try std.testing.expect(std.mem.indexOf(u8, completion, "-l shown") != null);
    try std.testing.expect(std.mem.indexOf(u8, completion, "-l hidden") == null);
}

test "fish completion includes inherited global flags for subcommands" {
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    defer generator.deinit();

    const cmd = Command.Command.init("tool", (Command.CommandConfig{})
        .withFlags(&.{Flag.Flag.init("verbose", (Flag.FlagConfig{})
            .withLong("verbose")
            .setGlobal())})
        .withSubcommands(&.{Command.Command.init("serve", (Command.CommandConfig{})
        .withAbout("Serve files"))}));

    const completion = try generator.generate(cmd, .fish, "tool");
    defer allocator.free(completion);

    try std.testing.expect(std.mem.indexOf(u8, completion, "__fish_seen_subcommand_from serve") != null);
    try std.testing.expect(std.mem.indexOf(u8, completion, "-l verbose") != null);
}

test "zsh completion includes inherited global flags for subcommands" {
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    defer generator.deinit();

    const cmd = Command.Command.init("tool", (Command.CommandConfig{})
        .withFlags(&.{Flag.Flag.init("verbose", (Flag.FlagConfig{})
            .withLong("verbose")
            .setGlobal())})
        .withSubcommands(&.{Command.Command.init("serve", (Command.CommandConfig{})
        .withAbout("Serve files"))}));

    const completion = try generator.generate(cmd, .zsh, "tool");
    defer allocator.free(completion);

    try std.testing.expect(std.mem.indexOf(u8, completion, "_tool_serve") != null);
    try std.testing.expect(std.mem.indexOf(u8, completion, "--verbose[") != null);
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

test "bash dynamic completion passes full word context" {
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    defer generator.deinit();

    const cmd = Command.Command.init("flash", Command.CommandConfig{});

    const completion = try generator.generate(cmd, .bash, "flash");
    defer allocator.free(completion);

    try std.testing.expect(std.mem.indexOf(u8, completion, "\"${words[@]}\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, completion, "__complete bash \"$current\" \"$@\"") != null);
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

test "dynamic completion uses custom completer static values for option args" {
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    defer generator.deinit();

    try generator.addCustomCompleter("format", .{ .static_values = &.{ "json", "yaml", "toml" } });

    const root = Command.Command.init("flash", (Command.CommandConfig{})
        .withArgs(&.{Argument.Argument.init("format", (Argument.ArgumentConfig{})
        .withLong("format")
        .withChoices(&.{ "json", "yaml", "toml" }))}));

    const state = try generator.analyzeCompletionContext(&.{ "flash", "__complete", "bash", "y", "flash", "--format", "y" }, root);
    defer allocator.free(state.command_path);

    try std.testing.expect(state.expecting_value_for != null);
    try std.testing.expectEqualStrings("format", state.expecting_value_for.?.name);
}

test "dynamic completion supports synchronous completion_fn" {
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    defer generator.deinit();

    const Completer = struct {
        fn complete(ctx: Context.Context, prefix: []const u8) anyerror![]const []const u8 {
            _ = ctx;
            _ = prefix;
            return &.{ "staging", "production" };
        }
    };

    try generator.addCustomCompleter("env", .{ .completion_fn = Completer.complete });

    const root = Command.Command.init("flash", (Command.CommandConfig{})
        .withArgs(&.{Argument.Argument.init("env", (Argument.ArgumentConfig{}).withLong("env"))}));

    const state = try generator.analyzeCompletionContext(&.{ "flash", "__complete", "bash", "st", "flash", "--env", "st" }, root);
    defer allocator.free(state.command_path);

    try std.testing.expect(state.expecting_value_for != null);
    try std.testing.expectEqualStrings("env", state.expecting_value_for.?.name);
}

test "analyzeCompletionContext handles --option=value partials" {
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    defer generator.deinit();

    const root = Command.Command.init("flash", (Command.CommandConfig{})
        .withArgs(&.{Argument.Argument.init("format", (Argument.ArgumentConfig{}).withLong("format"))}));

    const state = try generator.analyzeCompletionContext(&.{ "flash", "__complete", "bash", "--format=ya", "flash", "--format=ya" }, root);
    defer allocator.free(state.command_path);

    try std.testing.expect(state.expecting_value_for != null);
    try std.testing.expectEqualStrings("format", state.expecting_value_for.?.name);
    try std.testing.expectEqualStrings("ya", state.current_prefix);
}

test "zsh value spec uses custom static completer values" {
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    defer generator.deinit();

    try generator.addCustomCompleter("format", .{ .static_values = &.{ "json", "yaml" } });

    const arg = Argument.Argument.init("format", (Argument.ArgumentConfig{})
        .withLong("format")
        .withHelp("Output format"));

    const spec = try generator.zshValueSpec(arg);
    defer if (spec) |value| allocator.free(value);

    try std.testing.expect(spec != null);
    try std.testing.expect(std.mem.indexOf(u8, spec.?, "json:Output format") != null);
    try std.testing.expect(std.mem.indexOf(u8, spec.?, "yaml:Output format") != null);
    try std.testing.expect(std.mem.indexOf(u8, spec.?, "\"json:Output format\"") != null);
}

test "dynamic completion emits file directives from completer config" {
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    defer generator.deinit();

    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();

    try generator.writeBehaviorDirectives(&aw.writer, .{
        .no_file_completion = true,
        .directory_only = true,
        .file_extensions = &.{ "zig", "zon" },
    });

    const output = aw.written();
    try std.testing.expect(std.mem.indexOf(u8, output, "__flash_directive__:no_file_comp") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "__flash_directive__:filter_dirs") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "__flash_directive__:filter_file_ext:zig,zon") != null);
}

test "zsh completion recurses into nested subcommands" {
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    defer generator.deinit();

    const cmd = Command.Command.init("flash", (Command.CommandConfig{})
        .withSubcommands(&.{Command.Command.init("serve", (Command.CommandConfig{})
        .withSubcommands(&.{Command.Command.init("http", (Command.CommandConfig{})
        .withAbout("Serve over HTTP"))}))}));

    const completion = try generator.generate(cmd, .zsh, "flash");
    defer allocator.free(completion);

    try std.testing.expect(std.mem.indexOf(u8, completion, "_flash_serve") != null);
    try std.testing.expect(std.mem.indexOf(u8, completion, "_flash_serve_http") != null);
    try std.testing.expect(std.mem.indexOf(u8, completion, "http)") != null);
}

test "fish completion recurses into nested subcommands" {
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    defer generator.deinit();

    const cmd = Command.Command.init("flash", (Command.CommandConfig{})
        .withSubcommands(&.{Command.Command.init("serve", (Command.CommandConfig{})
        .withSubcommands(&.{Command.Command.init("http", (Command.CommandConfig{})
        .withAbout("Serve over HTTP"))}))}));

    const completion = try generator.generate(cmd, .fish, "flash");
    defer allocator.free(completion);

    try std.testing.expect(std.mem.indexOf(u8, completion, "__fish_seen_subcommand_from serve") != null);
    try std.testing.expect(std.mem.indexOf(u8, completion, "-a http") != null);
}

test "fish value candidates use custom static completer values" {
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    defer generator.deinit();

    try generator.addCustomCompleter("format", .{ .static_values = &.{ "json", "yaml" } });

    const arg = Argument.Argument.init("format", (Argument.ArgumentConfig{})
        .withLong("format")
        .withHelp("Output format"));

    const values = try generator.fishValueCandidates(arg);
    defer if (values) |v| allocator.free(v);

    try std.testing.expect(values != null);
    try std.testing.expect(std.mem.indexOf(u8, values.?, "json yaml") != null);
}

test "powershell completion recurses into nested subcommands" {
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    defer generator.deinit();

    const cmd = Command.Command.init("flash", (Command.CommandConfig{})
        .withSubcommands(&.{Command.Command.init("serve", (Command.CommandConfig{})
        .withSubcommands(&.{Command.Command.init("http", (Command.CommandConfig{})
        .withAbout("Serve over HTTP"))}))}));

    const completion = try generator.generate(cmd, .powershell, "flash");
    defer allocator.free(completion);

    try std.testing.expect(std.mem.indexOf(u8, completion, "Children = @(") != null);
    try std.testing.expect(std.mem.indexOf(u8, completion, "Name = 'serve'") != null);
    try std.testing.expect(std.mem.indexOf(u8, completion, "Name = 'http'") != null);
}

test "nushell completion recurses into nested subcommands" {
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    defer generator.deinit();

    const cmd = Command.Command.init("flash", (Command.CommandConfig{})
        .withSubcommands(&.{Command.Command.init("serve", (Command.CommandConfig{})
        .withSubcommands(&.{Command.Command.init("http", (Command.CommandConfig{})
        .withAbout("Serve over HTTP"))}))}));

    const completion = try generator.generate(cmd, .nushell, "flash");
    defer allocator.free(completion);

    try std.testing.expect(std.mem.indexOf(u8, completion, "children") != null);
    try std.testing.expect(std.mem.indexOf(u8, completion, "serve") != null);
    try std.testing.expect(std.mem.indexOf(u8, completion, "http") != null);
}

test "fish async completer does not fabricate generation-time values" {
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    defer generator.deinit();

    const AsyncStub = struct {
        fn complete(_: Context.Context, _: []const u8) flash_async.Future(anyerror![]const []const u8) {
            return flash_async.Future(anyerror![]const []const u8).ready(std.testing.allocator, &.{ "staging", "prod" });
        }
    };

    try generator.addCustomCompleter("env", .{ .async_completion_fn = AsyncStub.complete });

    const arg = Argument.Argument.init("env", (Argument.ArgumentConfig{}).withLong("env"));
    const values = try generator.fishValueCandidates(arg);
    defer if (values) |v| allocator.free(v);

    try std.testing.expect(values == null);
}

test "dynamic completion supports async completion function" {
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    defer generator.deinit();

    const AsyncCompleter = struct {
        fn complete(_: Context.Context, _: []const u8) flash_async.Future(anyerror![]const []const u8) {
            return flash_async.Future(anyerror![]const []const u8).ready(std.testing.allocator, &.{ "staging", "production" });
        }
    };

    try generator.addCustomCompleter("env", .{ .async_completion_fn = AsyncCompleter.complete });

    const root = Command.Command.init("flash", (Command.CommandConfig{})
        .withArgs(&.{Argument.Argument.init("env", (Argument.ArgumentConfig{}).withLong("env"))}));

    const state = try generator.analyzeCompletionContext(&.{ "flash", "__complete", "bash", "st", "flash", "--env", "st" }, root);
    defer allocator.free(state.command_path);
    try std.testing.expect(state.expecting_value_for != null);

    var test_ctx = Context.Context.init(allocator, &.{});
    defer test_ctx.deinit();
    var future = AsyncCompleter.complete(test_ctx, "st");
    const values = try future.resolve();
    try std.testing.expectEqual(@as(usize, 2), values.len);
    try std.testing.expectEqualStrings("staging", values[0]);
    try std.testing.expectEqualStrings("flash", root.name);
}

test "handleCompletionCommand requires shell argument" {
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    defer generator.deinit();

    var ctx = Context.Context.init(allocator, &.{});
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

    var ctx = Context.Context.init(allocator, &.{});
    defer ctx.deinit();
    try ctx.setValue("shell", Argument.ArgValue{ .string = "notashell" });

    const test_cmd = Command.Command.init("testcli", Command.CommandConfig{});

    const result = generator.handleCompletionCommand(ctx, test_cmd, "testcli");
    try std.testing.expectError(error.InvalidShell, result);
}

test "analyzeCompletionContext resolves nested subcommand scope" {
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    defer generator.deinit();

    const root = Command.Command.init("flash", (Command.CommandConfig{})
        .withSubcommands(&.{Command.Command.init("serve", (Command.CommandConfig{})
        .withSubcommands(&.{Command.Command.init("http", Command.CommandConfig{})}))}));

    const raw_args = [_][]const u8{ "flash", "__complete", "bash", "", "flash", "serve", "http", "" };
    const state = try generator.analyzeCompletionContext(&raw_args, root);
    defer allocator.free(state.command_path);

    try std.testing.expectEqualStrings("http", state.current_command.name);
    try std.testing.expectEqual(@as(usize, 2), state.command_path.len);
}

test "analyzeCompletionContext detects option value expectation" {
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    defer generator.deinit();

    const root = Command.Command.init("flash", (Command.CommandConfig{})
        .withArgs(&.{Argument.Argument.init("format", (Argument.ArgumentConfig{})
        .withLong("format")
        .withChoices(&.{ "json", "yaml" }))}));

    const raw_args = [_][]const u8{ "flash", "__complete", "bash", "j", "flash", "--format", "j" };
    const state = try generator.analyzeCompletionContext(&raw_args, root);
    defer allocator.free(state.command_path);

    try std.testing.expect(state.expecting_value_for != null);
    try std.testing.expectEqualStrings("format", state.expecting_value_for.?.name);
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
    // Note: File I/O requires Io instance in Zig 0.17 - testing generate() instead
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    defer generator.deinit();

    const test_cmd = Command.Command.init("filetest", (Command.CommandConfig{})
        .withAbout("Test file generation"));

    const completion = try generator.generate(test_cmd, .bash, "filetest");
    defer allocator.free(completion);

    try std.testing.expect(std.mem.indexOf(u8, completion, "Flash completion script for Bash") != null);
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
            .withLong("format")
            .withChoices(choices)),
    }));

    const completion = try generator.generate(test_cmd, .fish, "formatter");
    defer allocator.free(completion);

    try std.testing.expect(std.mem.indexOf(u8, completion, "-l format -a \"json yaml toml\"") != null);
}
