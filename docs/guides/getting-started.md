# Getting Started With Flash

This guide uses the current public Flash API in `v0.4.0`.

## Requirements

- Zig `0.17.0-dev`
- a normal Zig project with `build.zig` and `build.zig.zon`

## Add Flash To `build.zig.zon`

```zig
.{
    .name = "myapp",
    .version = "0.1.0",
    .minimum_zig_version = "0.17.0-dev",
    .dependencies = .{
        .flash = .{
            .url = "https://github.com/ghostkellz/flash/archive/main.tar.gz",
            .hash = "<hash from zig fetch>",
        },
    },
}
```

Get the hash with:

```bash
zig fetch https://github.com/ghostkellz/flash/archive/main.tar.gz
```

## Wire Flash In `build.zig`

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const flash_dep = b.dependency("flash", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "myapp",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("flash", flash_dep.module("flash"));
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run myapp");
    run_step.dependOn(&run_cmd.step);
}
```

## First CLI

Create `src/main.zig`:

```zig
const std = @import("std");
const flash = @import("flash");

const App = flash.CLI(.{
    .name = "myapp",
    .version = flash.version_string,
    .about = "A small Flash CLI",
});

fn greet(ctx: flash.Context) flash.Error!void {
    const name = ctx.getString("name") orelse return flash.Error.MissingRequiredArgument;
    const loud = ctx.getBool("loud") orelse false;

    if (loud) {
        std.debug.print("HELLO, {s}!\n", .{name});
    } else {
        std.debug.print("Hello, {s}.\n", .{name});
    }
}

pub fn main(init: std.process.Init) !void {
    const greet_cmd = flash.cmd("greet", (flash.CommandConfig{})
        .withAbout("Print a greeting")
        .withArgs(&.{flash.arg("name", (flash.ArgumentConfig{})
            .withHelp("Who to greet")
            .setRequired())})
        .withFlags(&.{flash.flag("loud", (flash.FlagConfig{})
            .withShort('l')
            .withLong("loud")
            .withHelp("Use uppercase output"))})
        .withHandler(greet));

    var cli = App.init(init.gpa, (flash.CommandConfig{})
        .withSubcommands(&.{greet_cmd}));

    try cli.runWithInit(init);
}
```

## Run It

```bash
zig build run -- --help
zig build run -- greet world
zig build run -- greet world --loud
```

## Add Completion Generation

Flash ships a built-in `completion` command.

```bash
zig build run -- completion bash > completions/myapp.bash
zig build run -- completion zsh > completions/_myapp
```

## Add Config Parsing

TOML via Flare is the recommended config path.

```zig
const Config = struct {
    port: u16 = 8080,
    host: []const u8 = "127.0.0.1",
};

const parser = flash.Config.ConfigParser.init(allocator);
const cfg = try parser.parseContent(Config,
    \\port = 9000
    \\host = "0.0.0.0"
, .toml);
```

## Test Your CLI

```zig
test "help output" {
    var harness = flash.Testing.TestHarness.init(std.testing.allocator);
    defer harness.deinit();

    const result = try harness.execute(App, &.{ "myapp", "--help" });
    defer result.deinit();

    try result.expectExitCode(0);
    try result.expectStdoutContains("A small Flash CLI");
}
```

## Next Steps

1. read [Macro-First CLI](../examples/macro-first.md)
2. read [Shell Completions](completions.md)
3. read [Flash + Flare](flash-flare.md)
4. read [API Overview](../api/README.md)
