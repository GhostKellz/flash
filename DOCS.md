# ⚡ Flash v0.1.0 Documentation

**The Lightning-Fast CLI Framework for Zig**

Flash is the definitive CLI framework for Zig — inspired by Clap, Cobra, and structopt, but rebuilt for next-generation async, idiomatic Zig.

## Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Core Concepts](#core-concepts)
- [API Reference](#api-reference)
- [Async Integration](#async-integration)
- [Advanced Features](#advanced-features)
- [Examples](#examples)

## Features

✨ **Blazing Fast**: Lightning startup and zero-alloc CLI paths  
⚡ **Async-First**: All parsing and dispatch is async (zsync-powered)  
🔧 **Batteries Included**: Auto-generated help, subcommands, flags, shell completions  
📝 **Declarative**: Use Zig's struct/enum power for arguments and commands  
🛡️ **Error-Proof**: Predictable, type-safe, memory-safe; no panics, no segfaults  
🎨 **Beautiful Output**: Colored terminal output with progress indicators  
🔍 **Validation**: Custom validators with detailed error context  
💬 **Interactive**: Prompts for missing arguments and confirmations  

## Quick Start

### Basic CLI Application

```zig
const std = @import("std");
const flash = @import("flash");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli = flash.CLI.init(allocator, "myapp", "My awesome CLI application");
    defer cli.deinit();

    // Add a simple command
    try cli.addCommand(
        flash.cmd("greet", flash.CommandConfig{
            .description = "Greet someone",
            .handler = greetHandler,
        })
        .withArg(flash.arg("name", flash.ArgumentConfig{
            .description = "Name to greet",
            .required = true,
        }))
        .withFlag(flash.flag("loud", flash.FlagConfig{
            .description = "Greet loudly",
            .short = 'l',
        }))
    );

    try cli.run();
}

fn greetHandler(ctx: flash.Context) flash.Error!void {
    const name = ctx.getString("name") orelse "World";
    const loud = ctx.getBool("loud") orelse false;
    
    if (loud) {
        std.debug.print("HELLO, {s}! ⚡\n", .{name});
    } else {
        std.debug.print("Hello, {s} ⚡\n", .{name});
    }
}
```

### Running the CLI

```bash
# Basic usage
$ myapp greet Alice
Hello, Alice ⚡

# With flags
$ myapp greet --loud Bob
HELLO, BOB! ⚡

# Help system (Zig-style)
$ myapp help
$ myapp greet help
```

## Core Concepts

### CLI Structure

Flash follows a hierarchical command structure:

```
CLI Application
├── Command 1
│   ├── Arguments
│   ├── Flags
│   └── Subcommands
├── Command 2
└── Global Flags
```

### Context System

The `Context` object provides access to parsed arguments, flags, and configuration:

```zig
fn myHandler(ctx: flash.Context) flash.Error!void {
    // Access arguments
    const name = ctx.getString("name") orelse "default";
    const count = ctx.getInt("count") orelse 1;
    const enabled = ctx.getBool("enabled") orelse false;
    
    // Access environment variables
    const home = ctx.getEnv("HOME");
    
    // Get subcommand info
    if (ctx.getSubcommand()) |subcmd| {
        std.debug.print("Running subcommand: {s}\n", .{subcmd});
    }
}
```

## API Reference

### CLI

```zig
const CLI = struct {
    // Initialize CLI application
    pub fn init(allocator: Allocator, name: []const u8, description: []const u8) CLI
    
    // Add commands and global configuration
    pub fn addCommand(self: *CLI, command: Command) !void
    pub fn withGlobalFlag(self: *CLI, flag: Flag) *CLI
    pub fn withVersion(self: *CLI, version: std.SemanticVersion) *CLI
    
    // Run the CLI with provided arguments
    pub fn run(self: *CLI) !void
    pub fn runWithArgs(self: *CLI, args: []const []const u8) !void
    
    // Clean up resources
    pub fn deinit(self: *CLI) void
};
```

### Command

```zig
const Command = struct {
    // Create a command
    pub fn init(name: []const u8, config: CommandConfig) Command
    
    // Builder pattern for configuration
    pub fn withArg(self: Command, arg: Argument) Command
    pub fn withFlag(self: Command, flag: Flag) Command
    pub fn withSubcommand(self: Command, subcmd: Command) Command
    pub fn withAliases(self: Command, aliases: []const []const u8) Command
    pub fn withHandler(self: Command, handler: HandlerFn) Command
    pub fn withAsyncHandler(self: Command, handler: AsyncHandlerFn) Command
};

const CommandConfig = struct {
    description: []const u8,
    handler: ?HandlerFn = null,
    async_handler: ?AsyncHandlerFn = null,
    hidden: bool = false,
};
```

### Arguments and Flags

```zig
const Argument = struct {
    pub fn init(name: []const u8, config: ArgumentConfig) Argument
};

const ArgumentConfig = struct {
    description: []const u8,
    required: bool = false,
    default_value: ?ArgValue = null,
    arg_type: ArgType = .string,
    validator: ?ValidatorFn = null,
};

const Flag = struct {
    pub fn init(name: []const u8, config: FlagConfig) Flag
};

const FlagConfig = struct {
    description: []const u8,
    short: ?u8 = null,
    default_value: ?ArgValue = null,
    flag_type: FlagType = .bool,
};
```

## Async Integration

Flash is built with async-first design using zsync, supporting multiple execution models.

### Basic Async Handler

```zig
fn asyncHandler(io: flash.Async.zsync.Io, ctx: flash.Context) flash.Error!void {
    // Use zsync for async operations
    std.debug.print("⚡ Starting async operation...\n", .{});
    
    // Simulate async work
    std.time.sleep(100 * 1000 * 1000); // 100ms
    
    std.debug.print("✅ Async operation completed!\n", .{});
}

// Register async command
try cli.addCommand(
    flash.cmd("fetch", flash.CommandConfig{
        .description = "Fetch data asynchronously",
        .async_handler = asyncHandler,
    })
);
```

### Execution Models

Flash supports zsync's colorblind async where the same code works across all execution models:

```zig
const runtime = flash.Async.AsyncRuntime.init(allocator, .blocking);
const runtime = flash.Async.AsyncRuntime.init(allocator, .thread_pool);
const runtime = flash.Async.AsyncRuntime.init(allocator, .green_threads);
const runtime = flash.Async.AsyncRuntime.init(allocator, .stackless);
```

### Concurrent Operations

```zig
const operations = [_]flash.Async.ConcurrentOp{
    .{ .name = "Fetch API", .func = fetchAPI, .ctx = ctx },
    .{ .name = "Process Files", .func = processFiles, .ctx = ctx },
    .{ .name = "Update Database", .func = updateDB, .ctx = ctx },
};

try runtime.spawnConcurrent(&operations);
```

## Advanced Features

### Validation

Flash provides comprehensive validation with detailed error messages:

```zig
const flash = @import("flash");

// Built-in validators
const emailValidator = flash.Validation.Validators.email();
const lengthValidator = flash.Validation.Validators.stringLength(3, 50);
const rangeValidator = flash.Validation.Validators.numberRange(1, 100);
const fileValidator = flash.Validation.Validators.fileExists();
const choiceValidator = flash.Validation.Validators.oneOf(&.{"dev", "staging", "prod"});

// Use with arguments
try cli.addCommand(
    flash.cmd("deploy", flash.CommandConfig{
        .description = "Deploy application",
        .handler = deployHandler,
    })
    .withArg(flash.arg("environment", flash.ArgumentConfig{
        .description = "Deployment environment",
        .required = true,
        .validator = choiceValidator,
    }))
    .withArg(flash.arg("config", flash.ArgumentConfig{
        .description = "Config file path",
        .required = true,
        .validator = fileValidator,
    }))
);
```

### Interactive Prompts

```zig
fn setupHandler(ctx: flash.Context) flash.Error!void {
    const prompter = flash.Prompts.Prompter.init(allocator);
    
    // Text input
    const name = try prompter.text("Enter your name:", null);
    defer allocator.free(name);
    
    // Password input
    const password = try prompter.password("Enter password:");
    defer allocator.free(password);
    
    // Confirmation
    const confirmed = try prompter.confirm("Continue with setup?", true);
    
    // Selection
    const choices = [_][]const u8{"Option A", "Option B", "Option C"};
    const selected = try prompter.select("Choose an option:", &choices, 0);
    
    std.debug.print("Setup complete!\n", .{});
}
```

### Progress Indicators

```zig
fn processHandler(ctx: flash.Context) flash.Error!void {
    // Progress bar
    var progress = flash.Progress.ProgressBar.init(
        flash.Progress.ProgressConfig.withTotal(100)
            .withPrefix("⚡ Processing")
            .showRate()
    );
    
    var i: u64 = 0;
    while (i <= 100) : (i += 1) {
        progress.update(i);
        std.time.sleep(50 * 1000 * 1000); // 50ms
    }
    progress.finish();
    
    // Spinner
    var spinner = flash.Progress.Spinner.init(
        flash.Progress.SpinnerConfig.withStyle(.lightning)
            .withMessage("Loading data")
            .showTime()
    );
    
    // Simulate work with spinner
    var count: u8 = 0;
    while (count < 20) : (count += 1) {
        spinner.spin();
        std.time.sleep(100 * 1000 * 1000); // 100ms
    }
    spinner.finish("Data loaded successfully!");
}
```

### Colored Output

```zig
fn colorHandler(ctx: flash.Context) flash.Error!void {
    // Quick color functions
    const success_msg = flash.Colors.c.success("Operation succeeded!");
    defer allocator.free(success_msg);
    
    const error_msg = flash.Colors.c.err("Something went wrong!");
    defer allocator.free(error_msg);
    
    const lightning_msg = flash.Colors.c.lightning("⚡ Flash CLI ⚡");
    defer allocator.free(lightning_msg);
    
    std.debug.print("{s}\n{s}\n{s}\n", .{success_msg, error_msg, lightning_msg});
    
    // Advanced coloring
    const colorizer = flash.Colors.Colorizer.init(flash.Colors.ColorConfig.init());
    const custom_msg = colorizer.styled("Bold Red Text", .red, .bold);
    defer allocator.free(custom_msg);
    
    std.debug.print("{s}\n", .{custom_msg});
}
```

### Environment Variables

```zig
// Automatic environment variable integration
try cli.addCommand(
    flash.cmd("config", flash.CommandConfig{
        .description = "Configure application",
        .handler = configHandler,
    })
    .withArg(flash.arg("database_url", flash.ArgumentConfig{
        .description = "Database connection URL",
        .required = false,
        .env_var = "DATABASE_URL", // Automatically uses env var if arg not provided
    }))
);

fn configHandler(ctx: flash.Context) flash.Error!void {
    // Environment variables are automatically available in context
    const db_url = ctx.getString("database_url") orelse "sqlite://default.db";
    const debug = ctx.getEnv("DEBUG") != null;
    
    std.debug.print("Database URL: {s}\n", .{db_url});
    std.debug.print("Debug mode: {}\n", .{debug});
}
```

### Shell Completions

```zig
// Generate completions for various shells
fn generateCompletions(shell: flash.Completion.Shell) !void {
    const completion_script = try flash.Completion.generate(allocator, cli, shell);
    defer allocator.free(completion_script);
    
    std.debug.print("{s}\n", .{completion_script});
}

// Built-in completion command
try cli.addCommand(
    flash.cmd("completion", flash.CommandConfig{
        .description = "Generate shell completion scripts",
        .handler = completionHandler,
    })
    .withArg(flash.arg("shell", flash.ArgumentConfig{
        .description = "Shell type",
        .required = true,
        .validator = flash.Validation.Validators.oneOf(&.{"bash", "zsh", "fish", "powershell"}),
    }))
);
```

## Examples

### Complex CLI Application

```zig
const std = @import("std");
const flash = @import("flash");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli = flash.CLI.init(allocator, "devtool", "Development toolkit")
        .withVersion(std.SemanticVersion{.major = 1, .minor = 0, .patch = 0})
        .withGlobalFlag(flash.flag("verbose", flash.FlagConfig{
            .description = "Enable verbose output",
            .short = 'v',
        }))
        .withGlobalFlag(flash.flag("config", flash.FlagConfig{
            .description = "Config file path",
            .short = 'c',
            .flag_type = .string,
            .default_value = flash.ArgValue{.string = "config.json"},
        }));
    defer cli.deinit();

    // Build command with subcommands
    try cli.addCommand(
        flash.cmd("build", flash.CommandConfig{
            .description = "Build the project",
            .handler = buildHandler,
        })
        .withFlag(flash.flag("release", flash.FlagConfig{
            .description = "Build in release mode",
            .short = 'r',
        }))
        .withFlag(flash.flag("target", flash.FlagConfig{
            .description = "Build target",
            .short = 't',
            .flag_type = .string,
            .default_value = flash.ArgValue{.string = "native"},
        }))
    );

    // Deploy command with validation
    try cli.addCommand(
        flash.cmd("deploy", flash.CommandConfig{
            .description = "Deploy application",
            .async_handler = deployAsyncHandler,
        })
        .withArg(flash.arg("environment", flash.ArgumentConfig{
            .description = "Deployment environment",
            .required = true,
            .validator = flash.Validation.Validators.oneOf(&.{"dev", "staging", "prod"}),
        }))
        .withArg(flash.arg("version", flash.ArgumentConfig{
            .description = "Version to deploy",
            .required = false,
            .default_value = flash.ArgValue{.string = "latest"},
        }))
        .withFlag(flash.flag("dry-run", flash.FlagConfig{
            .description = "Perform a dry run",
            .short = 'd',
        }))
    );

    // Database commands with subcommands
    try cli.addCommand(
        flash.cmd("db", flash.CommandConfig{
            .description = "Database operations",
        })
        .withSubcommand(flash.cmd("migrate", flash.CommandConfig{
            .description = "Run database migrations",
            .handler = migrateHandler,
        }))
        .withSubcommand(flash.cmd("seed", flash.CommandConfig{
            .description = "Seed database with test data",
            .handler = seedHandler,
        }))
        .withSubcommand(flash.cmd("reset", flash.CommandConfig{
            .description = "Reset database",
            .handler = resetHandler,
        }))
    );

    try cli.run();
}

fn buildHandler(ctx: flash.Context) flash.Error!void {
    const release = ctx.getBool("release") orelse false;
    const target = ctx.getString("target") orelse "native";
    const verbose = ctx.getBool("verbose") orelse false;
    
    if (verbose) {
        std.debug.print("⚡ Building project...\n", .{});
        std.debug.print("Release mode: {}\n", .{release});
        std.debug.print("Target: {s}\n", .{target});
    }
    
    // Progress bar for build
    var progress = flash.Progress.ProgressBar.init(
        flash.Progress.ProgressConfig.withTotal(100)
            .withPrefix("⚡ Building")
    );
    
    var i: u64 = 0;
    while (i <= 100) : (i += 5) {
        progress.update(i);
        std.time.sleep(100 * 1000 * 1000); // 100ms
    }
    progress.finish();
    
    const success_msg = flash.Colors.c.success("✅ Build completed successfully!");
    defer std.heap.page_allocator.free(success_msg);
    std.debug.print("{s}\n", .{success_msg});
}

fn deployAsyncHandler(io: flash.Async.zsync.Io, ctx: flash.Context) flash.Error!void {
    const env = ctx.getString("environment") orelse "dev";
    const version = ctx.getString("version") orelse "latest";
    const dry_run = ctx.getBool("dry-run") orelse false;
    
    if (dry_run) {
        std.debug.print("🔍 Dry run: Would deploy {s} to {s}\n", .{version, env});
        return;
    }
    
    std.debug.print("🚀 Deploying {s} to {s} environment...\n", .{version, env});
    
    // Simulate async deployment steps
    const steps = [_][]const u8{
        "Validating deployment configuration",
        "Building deployment package",
        "Uploading to deployment server",
        "Running health checks",
        "Updating load balancer",
    };
    
    for (steps, 0..) |step, i| {
        std.debug.print("⚡ [{d}/{d}] {s}...\n", .{i + 1, steps.len, step});
        std.time.sleep(500 * 1000 * 1000); // 500ms
        std.debug.print("✅ Completed!\n", .{});
    }
    
    const success_msg = flash.Colors.c.success("🎉 Deployment completed successfully!");
    defer std.heap.page_allocator.free(success_msg);
    std.debug.print("{s}\n", .{success_msg});
    
    _ = io; // Use io for actual async operations
}

fn migrateHandler(ctx: flash.Context) flash.Error!void {
    std.debug.print("📊 Running database migrations...\n", .{});
    
    var spinner = flash.Progress.Spinner.init(
        flash.Progress.SpinnerConfig.withStyle(.lightning)
            .withMessage("Applying migrations")
            .showTime()
    );
    
    var count: u8 = 0;
    while (count < 30) : (count += 1) {
        spinner.spin();
        std.time.sleep(100 * 1000 * 1000); // 100ms
    }
    spinner.finish("Migrations applied successfully!");
    
    _ = ctx;
}

fn seedHandler(ctx: flash.Context) flash.Error!void {
    const prompter = flash.Prompts.Prompter.init(std.heap.page_allocator);
    
    const confirmed = try prompter.confirm("This will reset all data. Continue?", false);
    if (!confirmed) {
        std.debug.print("❌ Cancelled by user\n", .{});
        return;
    }
    
    std.debug.print("🌱 Seeding database with test data...\n", .{});
    flash.Progress.Progress.dots("Seeding", 2000);
    
    _ = ctx;
}

fn resetHandler(ctx: flash.Context) flash.Error!void {
    const prompter = flash.Prompts.Prompter.init(std.heap.page_allocator);
    
    const confirmation = try prompter.text("Type 'RESET' to confirm database reset:", null);
    defer std.heap.page_allocator.free(confirmation);
    
    if (!std.mem.eql(u8, confirmation, "RESET")) {
        const error_msg = flash.Colors.c.err("❌ Invalid confirmation. Database reset cancelled.");
        defer std.heap.page_allocator.free(error_msg);
        std.debug.print("{s}\n", .{error_msg});
        return;
    }
    
    std.debug.print("💥 Resetting database...\n", .{});
    std.time.sleep(1000 * 1000 * 1000); // 1s
    
    const success_msg = flash.Colors.c.success("✅ Database reset completed!");
    defer std.heap.page_allocator.free(success_msg);
    std.debug.print("{s}\n", .{success_msg});
    
    _ = ctx;
}
```

## Contributing

Flash is designed to be the definitive CLI framework for Zig. Contributions are welcome!

### Development Setup

```bash
git clone https://github.com/your-username/flash.git
cd flash
zig build
zig build test
```

### Architecture

Flash follows these design principles:

1. **Async-First**: All operations support zsync's colorblind async
2. **Type Safety**: Leverage Zig's compile-time features
3. **Zero-Cost Abstractions**: Pay only for what you use
4. **Memory Safety**: No hidden allocations or memory leaks
5. **Beautiful UX**: Rich terminal output with colors and progress indicators

---

⚡ **Flash v0.1.0** - The Lightning-Fast CLI Framework for Zig  
Built with ❤️ and ⚡ for the Zig community