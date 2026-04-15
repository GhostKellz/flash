# Flash CLI Templates

Reference templates for building Flash-based CLI applications.

## Overview

These templates demonstrate patterns and structures for various CLI application types.
They are provided as **reference implementations only** - there is no scaffolding tool
to generate projects from them automatically.

To use a template, copy the relevant patterns into your own project.

## Available Templates

### basic - Simple CLI Application

For straightforward command-line tools with basic functionality.

**Patterns demonstrated:**
- Single command with arguments and flags
- Input validation
- Help generation
- Shell completions
- Basic testing

**Use cases:** File utilities, text processors, simple calculators, development tools

### devops - DevOps/Operations Tool

For system administration, deployment, and infrastructure management.

**Patterns demonstrated:**
- Multi-environment support
- Configuration management
- Progress reporting
- Error recovery

**Use cases:** Deployment tools, system monitoring, infrastructure automation

### network - Network/API Client

For building HTTP clients, API tools, and network utilities.

**Patterns demonstrated:**
- HTTP client operations
- JSON handling
- Authentication patterns
- Rate limiting
- Retry logic

**Use cases:** API clients, service health checkers, data synchronization

### git-like - Complex Subcommand Hierarchy

For applications with complex command structures like git, docker, kubectl.

**Patterns demonstrated:**
- Nested subcommands
- Global flags
- Context sharing
- Advanced help system

**Use cases:** Version control systems, container management, cloud CLIs, package managers

## Template Structure

Each template follows this standard structure:

```
template-name/
├── template.yaml          # Template metadata
├── files/                 # Example files
│   ├── build.zig.tmpl     # Build configuration
│   ├── src/
│   │   ├── main.zig.tmpl  # Main application
│   │   └── commands/      # Command modules
│   ├── tests/
│   └── README.md.tmpl     # Project README
└── prompts.yaml           # Configuration options
```

## Using Templates

Since there is no scaffolding tool, use these templates as follows:

1. Browse the template that matches your use case
2. Copy the patterns and structure into your project
3. Adapt the code to your specific requirements

### Example: Creating a Basic CLI

```zig
const std = @import("std");
const flash = @import("flash");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    const MyCLI = flash.CLI(.{
        .name = "mytool",
        .version = "1.0.0",
        .about = "My CLI application",
    });

    const cmd = flash.cmd("run", (flash.CommandConfig{})
        .withAbout("Run the main command")
        .withArgs(&.{
            flash.arg("input", (flash.ArgumentConfig{})
                .withHelp("Input file")
                .setRequired()),
        })
        .withHandler(runHandler));

    var cli = MyCLI.init(allocator, (flash.CommandConfig{})
        .withSubcommands(&.{cmd}));

    try cli.runWithInit(init);
}

fn runHandler(ctx: flash.Context) flash.Error!void {
    if (ctx.getString("input")) |input| {
        std.debug.print("Processing: {s}\n", .{input});
    }
}
```

## Status

These templates are reference implementations only. The `flash-init` scaffolding tool
was removed in v0.3.5 and may be reintroduced in a future version with updated API support.

## Related

- [Flash Documentation](../README.md)
- [Contributing](../CONTRIBUTING.md)
