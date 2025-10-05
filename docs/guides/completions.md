# Shell Completions Guide

Flash provides comprehensive shell completion support for multiple shells including Bash, Zsh, Fish, PowerShell, NuShell, and GShell (gsh).

## Supported Shells

- **Bash** - Traditional Unix shell
- **Zsh** - Enhanced Z shell
- **Fish** - Friendly Interactive Shell
- **PowerShell** - Microsoft PowerShell
- **NuShell** - Modern structured shell
- **GShell (gsh)** - Zig-native shell with flare config integration

## Generating Completions

Flash can generate completion scripts for all supported shells:

```bash
# Generate for your shell
myapp completion bash > myapp-completion.bash
myapp completion zsh > myapp-completion.zsh
myapp completion fish > myapp-completion.fish
myapp completion gsh > myapp-completion.gsh

# Or write directly to shell config
myapp completion bash >> ~/.bashrc
myapp completion zsh >> ~/.zshrc
myapp completion fish > ~/.config/fish/completions/myapp.fish
myapp completion gsh > ~/.config/gsh/completions/myapp.gsh
```

## Installation by Shell

### Bash

```bash
# Generate and source
myapp completion bash > ~/.bash_completion.d/myapp
echo "source ~/.bash_completion.d/myapp" >> ~/.bashrc
```

### Zsh

```bash
# Add to fpath
myapp completion zsh > ~/.zsh/completions/_myapp
echo 'fpath=(~/.zsh/completions $fpath)' >> ~/.zshrc
echo 'autoload -Uz compinit && compinit' >> ~/.zshrc
```

### Fish

```bash
# Fish auto-loads from this directory
myapp completion fish > ~/.config/fish/completions/myapp.fish
```

### GShell (gsh)

```bash
# GShell uses declarative Zig-style completions
myapp completion gsh > ~/.config/gsh/completions/myapp.gsh
```

## Programmatic Generation

You can also generate completions from your Zig code:

```zig
const flash = @import("flash");

pub fn generateCompletions(allocator: std.mem.Allocator) !void {
    var generator = flash.Completion.CompletionGenerator.init(allocator);
    defer generator.deinit();

    const root_cmd = // your root command

    // Generate for all shells
    const shells = [_]flash.Completion.Shell{
        .bash,
        .zsh,
        .fish,
        .powershell,
        .nushell,
        .gsh,
    };

    for (shells) |shell| {
        try generator.generateToFile(root_cmd, shell, "myapp", "./completions");
    }
}
```

## Custom Completions

Flash supports custom completion functions for dynamic values:

```zig
const config = flash.Completion.CompletionConfig{
    .static_values = &.{ "dev", "staging", "prod" },
};

try generator.addCustomCompleter("environment", config);
```

## GShell Integration

GShell completions use a declarative Zig-style syntax that integrates with flare configuration:

```zig
completion myapp {
    description = "Flash CLI application"

    subcommands = .{
        .deploy = .{
            .description = "Deploy application",
            .flags = .{
                .@"dry-run" = "Perform a dry run",
                .verbose = "Enable verbose output",
            },
        },
    },

    flags = .{
        .help = "Show help information",
        .version = "Show version information",
    },
}
```

This format is automatically generated when you run `myapp completion gsh`.

## Testing Completions

After installing completions, test them:

```bash
# Bash/Zsh - press TAB
myapp <TAB>
myapp deploy <TAB>

# Fish - type and press TAB  
myapp <TAB>

# GShell - same as Fish
myapp <TAB>
```

## Features

All Flash completion scripts support:

- ✅ Subcommand completion
- ✅ Flag completion (short and long forms)
- ✅ Flag descriptions
- ✅ Dynamic completion (via `__complete` command)
- ✅ File path completion
- ✅ Custom value completion

⚡ Built with Zig
