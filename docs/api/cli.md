# 📖 CLI Module API Reference

The CLI module provides the main interface for creating and running Flash CLI applications.

## Overview

```zig
const flash = @import("flash");

const cli = flash.CLI(.{
    .name = "myapp",
    .version = "1.0.0",
    .about = "My awesome CLI application",
    .commands = &.{
        // Command definitions
    },
});
```

## Types

### `CLIConfig`

Configuration structure for defining CLI applications.

```zig
pub const CLIConfig = struct {
    name: []const u8,
    version: ?[]const u8 = null,
    about: ?[]const u8 = null,
    long_about: ?[]const u8 = null,
    author: ?[]const u8 = null,
    color: ?bool = null,

    // Global behavior
    global_help: bool = true,
    global_version: bool = true,
    propagate_version: bool = true,
    subcommand_required: bool = false,
    allow_external_subcommands: bool = false,
};
```

#### Fields

- **`name`** - Application name (required)
- **`version`** - Version string displayed with `--version`
- **`about`** - Short description for help text
- **`long_about`** - Detailed description for help text
- **`author`** - Author information
- **`color`** - Enable/disable colored output (null = auto-detect)
- **`global_help`** - Add global `--help` flag
- **`global_version`** - Add global `--version` flag
- **`propagate_version`** - Show version in subcommands
- **`subcommand_required`** - Require a subcommand to be specified
- **`allow_external_subcommands`** - Allow unknown subcommands

#### Builder Methods

```zig
pub fn withVersion(self: CLIConfig, version: []const u8) CLIConfig
pub fn withAbout(self: CLIConfig, about: []const u8) CLIConfig
pub fn withLongAbout(self: CLIConfig, long_about: []const u8) CLIConfig
pub fn withAuthor(self: CLIConfig, author: []const u8) CLIConfig
pub fn withColor(self: CLIConfig, use_color: bool) CLIConfig
pub fn requireSubcommand(self: CLIConfig) CLIConfig
pub fn allowExternalSubcommands(self: CLIConfig) CLIConfig
```

**Example:**

```zig
const config = CLIConfig{
    .name = "deploy-tool",
}
.withVersion("2.1.0")
.withAbout("Deployment automation tool")
.withAuthor("DevOps Team <devops@company.com>")
.requireSubcommand();
```

## Functions

### `CLI(comptime config: CLIConfig)`

Creates a CLI application type with the given configuration.

**Parameters:**
- `config` - CLI configuration

**Returns:** A CLI type with methods for running the application

**Example:**

```zig
const MyCLI = flash.CLI(.{
    .name = "git-tool",
    .version = "1.0.0",
    .commands = &.{
        flash.cmd("clone", .{
            .about = "Clone a repository",
            .args = &.{
                flash.arg("url", .{ .help = "Repository URL" }),
            },
            .run = cloneRepo,
        }),
    },
});
```

## CLI Type Methods

### `init(allocator: std.mem.Allocator) Self`

Initialize a CLI instance.

**Parameters:**
- `allocator` - Memory allocator to use

**Returns:** Initialized CLI instance

### `deinit(self: *Self) void`

Clean up CLI resources.

### `run(self: Self) !void`

Run the CLI with command line arguments from `std.process.args()`.

**Errors:** Various parsing and execution errors

**Example:**

```zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const cli = MyCLI.init(gpa.allocator());
    defer cli.deinit();

    try cli.run();
}
```

### `runWithArgs(self: Self, args: []const []const u8) !void`

Run the CLI with provided arguments.

**Parameters:**
- `args` - Command line arguments

**Example:**

```zig
const args = &.{ "myapp", "deploy", "--env", "production" };
try cli.runWithArgs(args);
```

### `runAsync(self: Self) !void`

Run the CLI asynchronously using zsync.

**Example:**

```zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const cli = MyCLI.init(gpa.allocator());
    defer cli.deinit();

    try cli.runAsync();
}
```

### `generateHelp(self: Self, writer: anytype) !void`

Generate help text for the CLI.

**Parameters:**
- `writer` - Output writer

### `generateCompletion(self: Self, shell: Shell, writer: anytype) !void`

Generate shell completion script.

**Parameters:**
- `shell` - Target shell (`.bash`, `.zsh`, `.fish`, `.powershell`)
- `writer` - Output writer

## Configuration Examples

### Basic CLI

```zig
const BasicCLI = flash.CLI(.{
    .name = "hello",
    .version = "1.0.0",
    .about = "A simple greeting tool",
    .commands = &.{
        flash.cmd("greet", .{
            .about = "Greet someone",
            .args = &.{
                flash.arg("name", .{
                    .help = "Name to greet",
                    .required = true,
                }),
            },
            .flags = &.{
                flash.flag("loud", .{
                    .short = 'l',
                    .help = "Use loud greeting",
                }),
            },
            .run = greetCommand,
        }),
    },
});

fn greetCommand(ctx: flash.Context) !void {
    const name = ctx.get("name").?;
    const loud = ctx.getBool("loud");

    if (loud) {
        std.debug.print("HELLO, {}!\n", .{name});
    } else {
        std.debug.print("Hello, {}.\n", .{name});
    }
}
```

### Complex CLI with Subcommands

```zig
const ComplexCLI = flash.CLI(.{
    .name = "docker-like",
    .version = "1.0.0",
    .about = "Container management tool",
    .subcommand_required = true,
    .commands = &.{
        flash.cmd("container", .{
            .about = "Manage containers",
            .commands = &.{
                flash.cmd("run", .{
                    .about = "Run a container",
                    .args = &.{
                        flash.arg("image", .{ .help = "Container image" }),
                    },
                    .flags = &.{
                        flash.flag("detach", .{
                            .short = 'd',
                            .help = "Run in background",
                        }),
                        flash.flag("port", .{
                            .short = 'p',
                            .help = "Port mapping",
                            .value_name = "HOST:CONTAINER",
                            .multiple = true,
                        }),
                    },
                    .run_async = runContainer,
                }),
                flash.cmd("list", .{
                    .about = "List containers",
                    .flags = &.{
                        flash.flag("all", .{
                            .short = 'a',
                            .help = "Show all containers",
                        }),
                    },
                    .run = listContainers,
                }),
            },
        }),
        flash.cmd("image", .{
            .about = "Manage images",
            .commands = &.{
                flash.cmd("pull", .{
                    .about = "Pull an image",
                    .args = &.{
                        flash.arg("image", .{ .help = "Image to pull" }),
                    },
                    .run_async = pullImage,
                }),
            },
        }),
    },
});
```

### CLI with Global Flags

```zig
const GlobalFlagsCLI = flash.CLI(.{
    .name = "kubectl-like",
    .global_flags = &.{
        flash.flag("namespace", .{
            .short = 'n',
            .help = "Kubernetes namespace",
            .value_name = "NAME",
            .env = "KUBECTL_NAMESPACE",
        }),
        flash.flag("context", .{
            .help = "Kubernetes context",
            .value_name = "NAME",
            .env = "KUBECTL_CONTEXT",
        }),
        flash.flag("verbose", .{
            .short = 'v',
            .help = "Verbose output",
            .count = true,
        }),
    },
    .commands = &.{
        // Commands inherit global flags
    },
});
```

## Error Handling

```zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const cli = MyCLI.init(gpa.allocator());
    defer cli.deinit();

    cli.run() catch |err| switch (err) {
        error.InvalidArgument => {
            std.debug.print("Invalid argument provided\n");
            std.process.exit(1);
        },
        error.MissingRequired => {
            std.debug.print("Missing required argument\n");
            std.process.exit(1);
        },
        error.CommandFailed => {
            std.debug.print("Command execution failed\n");
            std.process.exit(1);
        },
        else => return err,
    };
}
```

## Testing

```zig
test "CLI help generation" {
    const TestCLI = flash.CLI(.{
        .name = "test-app",
        .about = "Test application",
    });

    var cli = TestCLI.init(std.testing.allocator);
    defer cli.deinit();

    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();

    try cli.generateHelp(buf.writer());

    try std.testing.expect(std.mem.indexOf(u8, buf.items, "test-app") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "Test application") != null);
}

test "CLI with arguments" {
    var harness = flash.testing.TestHarness.init(std.testing.allocator);
    defer harness.deinit();

    const result = try harness.execute(MyCLI, &.{"greet", "World"});
    defer result.deinit();

    try result.expectExitCode(0);
    try result.expectStdoutContains("Hello, World");
}
```

## Related

- [Commands API](commands.md)
- [Arguments & Flags API](args-flags.md)
- [Context API](context.md)
- [Getting Started Guide](../guides/getting-started.md)