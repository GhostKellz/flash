# Macro-First CLI Example

This is the recommended example for evaluating Flash's macro-first product direction.

It shows a high-signal path Flash currently offers:

- macro-first command construction
- aliases and repeated values
- command-spec parsing
- aliases and option defaults
- a clean path to built-in shell completion generation

If you want to see whether Flash feels closer to Clap/Cobra than a low-level argument parser, start here.

```zig
const std = @import("std");
const flash = @import("flash");

fn serve(ctx: flash.Context) flash.Error!void {
    _ = ctx;
}

const run_cmd = flash.Macros.command(
    "serve|srv:Serve files --port <port|8080|9090=8080> --tag [value...] <dir> -- Serve content",
    serve,
);

const root_cmd = flash.cmd("flashctl", (flash.CommandConfig{})
    .withAbout("Macro-first Flash CLI")
    .withFlags(&.{flash.flag("verbose", (flash.FlagConfig{})
        .withShort('v')
        .withLong("verbose")
        .withHelp("Verbose output")
        .setGlobal())})
    .withSubcommands(&.{run_cmd}));
```

Supported macro ergonomics in this style include:

- command aliases like `serve|srv`
- subcommand help on path segments like `run:Run a VM`
- inline flags like `--verbose`
- value-taking options like `--port <port|8080|9090=8080>`
- repeated values like `--tag [value...]`

This example intentionally keeps the root command on the core public `CommandConfig` path and uses macro parsing where it is already strongest today.

Completion generation for this CLI uses Flash's built-in command surface:

```bash
flashctl completion bash > completions/flashctl.bash
flashctl completion zsh > completions/_flashctl
flashctl completion fish > completions/flashctl.fish
```
