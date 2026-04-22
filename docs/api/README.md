# Flash API Overview

This document describes the public API Flash intends consumers to build against in `v0.4.0`.

## Stable Public Surface

These exports are the primary supported surface for application authors:

```zig
flash.CLI
flash.Command
flash.CommandConfig
flash.Argument
flash.ArgumentConfig
flash.ArgValue
flash.Flag
flash.FlagConfig
flash.Context
flash.Error
flash.Env
flash.Completion
flash.Validation
flash.Validators
flash.Testing
flash.Config
```

Core convenience helpers:

```zig
flash.cmd
flash.arg
flash.flag
```

## Experimental Public Surface

These modules are exported, but the API may still change more quickly than the core CLI surface:

```zig
flash.Declarative
flash.Macros
flash.Prompts
flash.Progress
flash.Colors
```

Use them when they fit your project, but expect more iteration than the core command/argument/flag/runtime path.

## Internal-Only Surface

These modules exist in the repository but are not part of the supported public API for consumers:

- Flash-owned async internals
- security internals
- benchmark internals
- advanced validation internals
- internal async CLI helpers

Flash uses some of these internally for completion, validation, and testing support, but they are intentionally not exported from `src/root.zig`.

## Stability Rules

For `v0.4.0`, consumers should assume:

- core CLI construction is the most stable path
- Bash and Zsh completion are first-class
- TOML via Flare is the preferred config story
- JSON config is supported as a secondary path
- YAML is unsupported
- internal modules are not stability promises

## Supported Consumer Workflows

### Build a CLI

```zig
const std = @import("std");
const flash = @import("flash");

const App = flash.CLI(.{
    .name = "myapp",
    .version = flash.version_string,
    .about = "Example Flash application",
});

fn greet(ctx: flash.Context) flash.Error!void {
    const name = ctx.getString("name") orelse return flash.Error.MissingRequiredArgument;
    std.debug.print("hello, {s}\n", .{name});
}

pub fn main(init: std.process.Init) !void {
    var cli = App.init(init.gpa, (flash.CommandConfig{})
        .withSubcommands(&.{flash.cmd("greet", (flash.CommandConfig{})
            .withAbout("Print a greeting")
            .withArgs(&.{flash.arg("name", (flash.ArgumentConfig{})
                .withHelp("Who to greet")
                .setRequired())})
            .withHandler(greet))}));
    try cli.runWithInit(init);
}
```

### Test a CLI

```zig
test "help output" {
    var harness = flash.Testing.TestHarness.init(std.testing.allocator);
    defer harness.deinit();

    const result = try harness.execute(App, &.{ "myapp", "--help" });
    defer result.deinit();

    try result.expectExitCode(0);
    try result.expectStdoutContains("Example Flash application");
}
```

### Generate Completions

```zig
var cli = App.init(allocator, root_config);
try cli.generateCompletion(std.io.getStdOut().writer(), "bash");
```

### Parse Config Files

```zig
const parser = flash.Config.ConfigParser.init(allocator, .toml);
const cfg = try parser.parse(MyConfig, toml_source);
```

## Public API Pointers

- [CLI Module](cli.md)
- [Getting Started](../guides/getting-started.md)
- [Completions Guide](../guides/completions.md)
- [Flash + Flare Guide](../guides/flash-flare.md)
- [Examples](../examples/)
