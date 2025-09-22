# 🚀 Getting Started with Flash

Welcome to Flash, the lightning-fast CLI framework for Zig! This guide will get you up and running with your first Flash CLI application in minutes.

## 📋 Prerequisites

- **Zig 0.16.0+** - [Download from ziglang.org](https://ziglang.org/download/)
- **Basic Zig knowledge** - Familiarity with Zig syntax and concepts
- **Command line experience** - Comfortable with terminal usage

## 📦 Installation

### Option 1: Using `zig fetch` (Recommended)

```bash
# Add Flash to your project
zig fetch https://github.com/ghostkellz/flash/archive/main.tar.gz
```

### Option 2: Git Submodule

```bash
# Clone as submodule
git submodule add https://github.com/ghostkellz/flash.git deps/flash
```

### Option 3: Manual Download

Download the latest release from [GitHub Releases](https://github.com/ghostkellz/flash/releases) and extract to your project directory.

## 🔧 Project Setup

### 1. Create `build.zig`

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add Flash dependency
    const flash_dep = b.dependency("flash", .{
        .target = target,
        .optimize = optimize,
    });
    const flash_module = flash_dep.module("flash");

    // Create executable
    const exe = b.addExecutable(.{
        .name = "myapp",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Add Flash module
    exe.root_module.addImport("flash", flash_module);

    // Install executable
    b.installArtifact(exe);

    // Add run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
```

### 2. Create Project Structure

```
myapp/
├── build.zig
├── src/
│   └── main.zig
└── build.zig.zon
```

### 3. Add `build.zig.zon`

```zig
.{
    .name = "myapp",
    .version = "0.1.0",
    .minimum_zig_version = "0.16.0",
    .dependencies = .{
        .flash = .{
            .url = "https://github.com/ghostkellz/flash/archive/main.tar.gz",
            .hash = "1234567890abcdef...", // Hash from zig fetch
        },
    },
}
```

## ✨ Your First CLI

### 1. Simple "Hello World"

Create `src/main.zig`:

```zig
const std = @import("std");
const flash = @import("flash");

const MyCLI = flash.CLI(.{
    .name = "hello",
    .version = "1.0.0",
    .about = "A simple greeting CLI",
    .commands = &.{
        flash.cmd("greet", .{
            .about = "Greet someone",
            .args = &.{
                flash.arg("name", .{
                    .help = "Name of person to greet",
                    .required = true,
                }),
            },
            .flags = &.{
                flash.flag("loud", .{
                    .short = 'l',
                    .long = "loud",
                    .help = "Use loud greeting",
                }),
                flash.flag("count", .{
                    .short = 'c',
                    .long = "count",
                    .help = "Number of greetings",
                    .value_name = "NUM",
                    .default_value = "1",
                }),
            },
            .run = greetCommand,
        }),
    },
});

fn greetCommand(ctx: flash.Context) !void {
    const name = ctx.get("name").?;
    const loud = ctx.getBool("loud");
    const count = ctx.getInt("count") orelse 1;

    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (loud) {
            std.debug.print("HELLO, {s}!\n", .{name});
        } else {
            std.debug.print("Hello, {s}.\n", .{name});
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var cli = MyCLI.init(gpa.allocator());
    defer cli.deinit();

    try cli.run();
}
```

### 2. Build and Run

```bash
# Build the application
zig build

# Run with help
zig build run -- --help

# Run the greet command
zig build run -- greet "World"

# Run with flags
zig build run -- greet "World" --loud --count 3
```

### 3. Expected Output

```bash
$ zig build run -- greet "World" --loud --count 3
HELLO, World!
HELLO, World!
HELLO, World!
```

## 🌟 Adding More Features

### Subcommands

```zig
const MyCLI = flash.CLI(.{
    .name = "myapp",
    .version = "1.0.0",
    .about = "My awesome application",
    .commands = &.{
        flash.cmd("user", .{
            .about = "User management",
            .commands = &.{
                flash.cmd("create", .{
                    .about = "Create a new user",
                    .args = &.{
                        flash.arg("username", .{
                            .help = "Username for new user",
                            .required = true,
                        }),
                        flash.arg("email", .{
                            .help = "Email address",
                            .required = true,
                            .validator = flash.validation.emailValidator(),
                        }),
                    },
                    .run = createUser,
                }),
                flash.cmd("delete", .{
                    .about = "Delete a user",
                    .args = &.{
                        flash.arg("username", .{
                            .help = "Username to delete",
                            .required = true,
                        }),
                    },
                    .flags = &.{
                        flash.flag("force", .{
                            .short = 'f',
                            .help = "Force deletion without confirmation",
                        }),
                    },
                    .run = deleteUser,
                }),
            },
        }),
    },
});
```

### Async Commands

```zig
const AsyncCLI = flash.CLI(.{
    .name = "async-app",
    .commands = &.{
        flash.cmd("download", .{
            .about = "Download files concurrently",
            .args = &.{
                flash.arg("urls", .{
                    .help = "URLs to download",
                    .multiple = true,
                    .required = true,
                }),
            },
            .flags = &.{
                flash.flag("output", .{
                    .short = 'o',
                    .help = "Output directory",
                    .value_name = "DIR",
                    .default_value = "downloads",
                }),
                flash.flag("parallel", .{
                    .short = 'p',
                    .help = "Number of parallel downloads",
                    .value_name = "NUM",
                    .default_value = "4",
                }),
            },
            .run_async = downloadFiles,
        }),
    },
});

async fn downloadFiles(ctx: flash.Context) !void {
    const urls = ctx.getMany("urls").?;
    const output_dir = ctx.get("output").?;
    const parallel = ctx.getInt("parallel") orelse 4;

    // Create output directory
    try std.fs.cwd().makePath(output_dir);

    // Set up async context
    var async_ctx = flash.async_cli.AsyncContext.init(ctx.allocator);
    defer async_ctx.deinit();

    async_ctx.setMaxConcurrency(parallel);

    // Build download commands
    var commands = std.ArrayList(flash.AsyncCommand).init(ctx.allocator);
    defer commands.deinit();

    for (urls) |url| {
        const cmd = flash.AsyncCommand.init("curl", &.{
            "-o", try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ output_dir, std.fs.path.basename(url) }),
            url,
        });
        try commands.append(cmd);
    }

    std.debug.print("🌐 Downloading {} files with {} parallel connections...\n", .{ urls.len, parallel });

    // Execute downloads in parallel
    const results = try async_ctx.executeParallel(commands.items);
    defer ctx.allocator.free(results);

    var success_count: usize = 0;
    for (results) |result| {
        switch (result) {
            .success => |data| {
                success_count += 1;
                std.debug.print("✅ Downloaded ({}ms)\n", .{data.execution_time_ms});
            },
            .error => |err| {
                std.debug.print("❌ Download failed: {s}\n", .{err.message});
            },
            .timeout => std.debug.print("⏰ Download timed out\n", .{}),
            .cancelled => std.debug.print("🚫 Download cancelled\n", .{}),
        }
    }

    std.debug.print("📊 Results: {}/{} downloads successful\n", .{ success_count, urls.len });
}
```

### Validation

```zig
const ValidatedCLI = flash.CLI(.{
    .name = "server",
    .commands = &.{
        flash.cmd("start", .{
            .about = "Start the server",
            .args = &.{
                flash.arg("port", .{
                    .help = "Port to listen on",
                    .required = true,
                    .validator = flash.validation.portInRange(1024, 65535),
                }),
                flash.arg("config", .{
                    .help = "Configuration file",
                    .required = true,
                    .validator = flash.validation.fileValidator(true, &.{".json", ".yaml", ".toml"}),
                }),
            },
            .run = startServer,
        }),
    },
});

fn startServer(ctx: flash.Context) !void {
    const port = ctx.getInt("port").?;
    const config_file = ctx.get("config").?;

    std.debug.print("🚀 Starting server on port {}...\n", .{port});
    std.debug.print("📋 Using config: {s}\n", .{config_file});

    // Server implementation here
}
```

## 🛠️ Development Workflow

### 1. Add Shell Completions

```bash
# Generate completion scripts
zig build run -- completion bash > completions/myapp.bash
zig build run -- completion zsh > completions/_myapp
zig build run -- completion fish > completions/myapp.fish

# Install bash completion (example)
sudo cp completions/myapp.bash /etc/bash_completion.d/
```

### 2. Testing Your CLI

Create `src/test.zig`:

```zig
const std = @import("std");
const flash = @import("flash");
const MyCLI = @import("main.zig").MyCLI;

test "greet command" {
    var harness = flash.testing.TestHarness.init(std.testing.allocator);
    defer harness.deinit();

    const result = try harness.execute(MyCLI, &.{ "greet", "Test" });
    defer result.deinit();

    try result.expectExitCode(0);
    try result.expectStdoutContains("Hello, Test");
}

test "help generation" {
    var harness = flash.testing.TestHarness.init(std.testing.allocator);
    defer harness.deinit();

    const result = try harness.execute(MyCLI, &.{"--help"});
    defer result.deinit();

    try result.expectExitCode(0);
    try result.expectStdoutContains("A simple greeting CLI");
}
```

Run tests:

```bash
zig test src/test.zig
```

### 3. Performance Testing

```zig
test "performance benchmark" {
    var benchmark = flash.benchmark.BenchmarkRunner.init(std.testing.allocator, .{
        .iterations = 1000,
    });
    defer benchmark.deinit();

    _ = try benchmark.benchmark("greet_command", benchmarkGreet, .{});
}

fn benchmarkGreet() void {
    // Benchmark implementation
}
```

## 📚 Next Steps

### Essential Reading
- **[CLI Architecture](../architecture/cli-structure.md)** - Understand Flash's design
- **[Async CLI Guide](async-cli.md)** - Build async applications
- **[API Documentation](../api/)** - Complete API reference

### Example Projects
- **[Git-like Tool](../examples/git-like.md)** - Complex subcommand structure
- **[File Processor](../examples/file-processor.md)** - Async file operations
- **[API Client](../examples/api-client.md)** - Network operations

### Advanced Topics
- **[Custom Validation](validation.md)** - Build custom validators
- **[Performance Optimization](performance.md)** - Make your CLI blazing fast
- **[Testing Strategies](testing.md)** - Comprehensive testing

## 🤝 Getting Help

- **[GitHub Issues](https://github.com/ghostkellz/flash/issues)** - Bug reports and feature requests
- **[Discussions](https://github.com/ghostkellz/flash/discussions)** - Questions and community
- **[Discord](https://discord.gg/flash-cli)** - Real-time chat and support

## 🎉 Congratulations!

You've successfully created your first Flash CLI application! Flash's async-first design and powerful features will help you build fast, reliable command-line tools.

---

*Ready to build lightning-fast CLI applications with Flash! ⚡*