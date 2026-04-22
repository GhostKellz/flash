# Shell Completions Guide

Flash provides shell completion support for Bash, Zsh, Fish, PowerShell, NuShell, and GShell (`gsh`).

Current backend maturity:

- Bash: strongest backend today, including dynamic `__complete` support, inherited global flags, custom value completers, and file/directory directives.
- Zsh: strongest generated-script backend, including recursive command trees, inherited global flags, and metadata-aware option-value specs.
- Fish: recursive/shared-scope generation with option-value suggestions from choices and static completers.
- PowerShell/NuShell: recursive command-tree generation, but less feature-rich than Bash/Zsh today.
- GShell: generated experimental target only.

## Supported Shells

- **Bash** - Traditional Unix shell
- **Zsh** - Enhanced Z shell
- **Fish** - Friendly Interactive Shell
- **PowerShell** - Microsoft PowerShell
- **NuShell** - Modern structured shell
- **GShell (gsh)** - Experimental Zig-native shell target

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

## Practical Guidance

- Prefer Bash or Zsh if you want Flash's most complete completion experience today.
- Fish is strong and recursive, but Bash/Zsh still get the deepest completion-specific polish.
- PowerShell and NuShell now generate recursive command trees, but their completion surface is still simpler than Bash/Zsh.

## Custom Completions

Flash supports custom completion configuration for dynamic values:

```zig
const config = flash.Completion.CompletionConfig{
    .static_values = &.{ "dev", "staging", "prod" },
};

try generator.addCustomCompleter("environment", config);
```

Supported today:

- `static_values` are used by generated Bash/Zsh/Fish completion flows.
- `completion_fn` is used by the dynamic Bash `__complete` path.
- `async_completion_fn` is executed by the dynamic Bash `__complete` path.
- `file_extensions`, `directory_only`, and `no_file_completion` influence Bash dynamic behavior and generated Zsh/Fish value specs.

Example custom completer configuration:

```zig
try generator.addCustomCompleter("format", .{
    .static_values = &.{ "json", "yaml", "toml" },
});

try generator.addCustomCompleter("env", .{
    .completion_fn = completeEnvironment,
    .no_file_completion = true,
});
```

## GShell Notes

GShell output is still experimental. Treat it as generated text that may change shape rather than a stable integration contract.

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

This is the current generated shape when you run `myapp completion gsh`.

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

Backend feature summary:

- ✅ Recursive command trees: Bash, Zsh, Fish, PowerShell, NuShell
- ✅ Inherited global flags: Bash, Zsh, Fish, PowerShell, NuShell
- ✅ Dynamic `__complete`: Bash
- ✅ Choice/static value suggestions: Bash, Zsh, Fish
- ✅ File/directory directive shaping: Bash dynamic, generated Zsh/Fish value specs
- ⚠️ Async completers: API only, not executed yet

⚡ Built with Zig
