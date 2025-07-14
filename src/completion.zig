//! ⚡ Flash Shell Completion Generation
//!
//! Generates shell completion scripts for Bash, Zsh, Fish, and PowerShell

const std = @import("std");
const Command = @import("command.zig");

pub const Shell = enum {
    bash,
    zsh,
    fish,
    powershell,

    pub fn fromString(s: []const u8) ?Shell {
        if (std.mem.eql(u8, s, "bash")) return .bash;
        if (std.mem.eql(u8, s, "zsh")) return .zsh;
        if (std.mem.eql(u8, s, "fish")) return .fish;
        if (std.mem.eql(u8, s, "powershell") or std.mem.eql(u8, s, "pwsh")) return .powershell;
        return null;
    }
};

pub const CompletionGenerator = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CompletionGenerator {
        return .{ .allocator = allocator };
    }

    pub fn generate(self: CompletionGenerator, command: Command.Command, shell: Shell, program_name: []const u8) ![]u8 {
        return switch (shell) {
            .bash => self.generateBash(command, program_name),
            .zsh => self.generateZsh(command, program_name),
            .fish => self.generateFish(command, program_name),
            .powershell => self.generatePowerShell(command, program_name),
        };
    }

    fn generateBash(self: CompletionGenerator, command: Command.Command, program_name: []const u8) ![]u8 {
        var buf = std.ArrayList(u8).init(self.allocator);
        const writer = buf.writer();

        try writer.print("# ⚡ Flash completion script for Bash\n", .{});
        try writer.print("# Generated for {s}\n\n", .{program_name});
        
        try writer.print("_{s}_completions() {{\n", .{program_name});
        try writer.print("    local cur prev words cword\n", .{});
        try writer.print("    _init_completion || return\n\n", .{});
        
        try writer.print("    case ${{cword}} in\n", .{});
        try writer.print("        1)\n", .{});
        try writer.print("            COMPREPLY=($(compgen -W \"", .{});
        
        // Add subcommands
        for (command.getSubcommands()) |subcmd| {
            if (!subcmd.isHidden()) {
                try writer.print("{s} ", .{subcmd.name});
            }
        }
        // Add builtin commands
        try writer.print("help version\" -- \"$cur\"))\n", .{});
        try writer.print("            ;;\n", .{});
        try writer.print("        *)\n", .{});
        try writer.print("            COMPREPLY=()\n", .{});
        try writer.print("            ;;\n", .{});
        try writer.print("    esac\n", .{});
        try writer.print("}}\n\n", .{});
        
        try writer.print("complete -F _{s}_completions {s}\n", .{ program_name, program_name });

        return buf.toOwnedSlice();
    }

    fn generateZsh(self: CompletionGenerator, command: Command.Command, program_name: []const u8) ![]u8 {
        var buf = std.ArrayList(u8).init(self.allocator);
        const writer = buf.writer();

        try writer.print("# ⚡ Flash completion script for Zsh\n", .{});
        try writer.print("# Generated for {s}\n\n", .{program_name});
        
        try writer.print("_{s}() {{\n", .{program_name});
        try writer.print("    local context state line\n", .{});
        try writer.print("    _arguments -C \\\n", .{});
        try writer.print("        '1: :->commands' \\\n", .{});
        try writer.print("        '*::arg:->args'\n\n", .{});
        
        try writer.print("    case $state in\n", .{});
        try writer.print("        commands)\n", .{});
        try writer.print("            _values 'commands' \\\n", .{});
        
        // Add subcommands
        for (command.getSubcommands()) |subcmd| {
            if (!subcmd.isHidden()) {
                const about = subcmd.getAbout() orelse "";
                try writer.print("                '{s}[{s}]' \\\n", .{ subcmd.name, about });
            }
        }
        // Add builtin commands
        try writer.print("                'help[Show help information]' \\\n", .{});
        try writer.print("                'version[Show version information]'\n", .{});
        try writer.print("            ;;\n", .{});
        try writer.print("    esac\n", .{});
        try writer.print("}}\n\n", .{});
        
        try writer.print("compdef _{s} {s}\n", .{ program_name, program_name });

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
                try writer.print("complete -c {s} -n '__fish_use_subcommand' -a {s} -d '{s}'\n", .{ program_name, subcmd.name, about });
            }
        }
        
        // Add builtin commands
        try writer.print("complete -c {s} -n '__fish_use_subcommand' -a help -d 'Show help information'\n", .{program_name});
        try writer.print("complete -c {s} -n '__fish_use_subcommand' -a version -d 'Show version information'\n", .{program_name});

        return buf.toOwnedSlice();
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
        try writer.print("    )\n\n", .{});
        
        try writer.print("    $commands | Where-Object {{ $_.Name -like \"$wordToComplete*\" }} | ForEach-Object {{\n", .{});
        try writer.print("        [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', $_.Description)\n", .{});
        try writer.print("    }}\n", .{});
        try writer.print("}}\n", .{});

        return buf.toOwnedSlice();
    }
};

test "bash completion generation" {
    const allocator = std.testing.allocator;
    var generator = CompletionGenerator.init(allocator);
    
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
}