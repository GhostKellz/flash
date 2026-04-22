# Basic CLI Example

This example shows a small public-API-safe Flash CLI with:

- one command
- one positional argument
- one boolean flag
- built-in completion generation
- a matching test harness pattern

## `src/main.zig`

```zig
const std = @import("std");
const flash = @import("flash");

const HelloCLI = flash.CLI(.{
    .name = "hello",
    .version = flash.version_string,
    .about = "A simple greeting CLI",
});

fn greet(ctx: flash.Context) flash.Error!void {
    const name = ctx.getString("name") orelse "World";
    const loud = ctx.getBool("loud") orelse false;

    if (loud) {
        std.debug.print("HELLO, {s}!\n", .{name});
    } else {
        std.debug.print("Hello, {s}.\n", .{name});
    }
}

pub fn main(init: std.process.Init) !void {
    const greet_cmd = flash.cmd("greet", (flash.CommandConfig{})
        .withAbout("Greet someone")
        .withArgs(&.{flash.arg("name", (flash.ArgumentConfig{})
            .withHelp("Name to greet")
            .withDefault(flash.ArgValue{ .string = "World" }))})
        .withFlags(&.{flash.flag("loud", (flash.FlagConfig{})
            .withShort('l')
            .withLong("loud")
            .withHelp("Use uppercase output"))})
        .withHandler(greet));

    var cli = HelloCLI.init(init.gpa, (flash.CommandConfig{})
        .withSubcommands(&.{greet_cmd}));

    try cli.runWithInit(init);
}
```

## Usage

```bash
zig build run -- greet
zig build run -- greet Alice
zig build run -- greet Alice --loud
zig build run -- completion bash > completions/hello.bash
```

## Test Pattern

```zig
test "help renders" {
    var harness = flash.Testing.TestHarness.init(std.testing.allocator);
    defer harness.deinit();

    const result = try harness.execute(HelloCLI, &.{ "hello", "--help" });
    defer result.deinit();

    try result.expectExitCode(0);
    try result.expectStdoutContains("A simple greeting CLI");
}
```

For a larger example, continue with [Macro-First CLI](macro-first.md).
