# ⚡ Flash CLI Templates

Project templates for quickly scaffolding Flash-based CLI applications.

## 🎯 Available Templates

### 📝 **basic** - Simple CLI Application
Perfect for straightforward command-line tools with basic functionality.

**Features:**
- Single command with arguments and flags
- Input validation
- Help generation
- Shell completions
- Basic testing

**Use Cases:**
- File utilities
- Text processors
- Simple calculators
- Development tools

```bash
flash-init myapp --template basic
```

### 🛠️ **devops** - DevOps/Operations Tool
For system administration, deployment, and infrastructure management.

**Features:**
- Multi-environment support
- Configuration management
- Async operations
- Progress reporting
- Error recovery
- Metrics collection

**Use Cases:**
- Deployment tools
- System monitoring
- Infrastructure automation
- CI/CD utilities

```bash
flash-init deploy-tool --template devops
```

### ⚡ **async-files** - File Processing Tool
High-performance file operations with async I/O.

**Features:**
- Parallel file processing
- Progress bars
- Memory-efficient streaming
- Error handling
- Batch operations

**Use Cases:**
- Log analyzers
- File converters
- Backup tools
- Data processors

```bash
flash-init file-processor --template async-files
```

### 🌐 **network** - Network/API Client
For building HTTP clients, API tools, and network utilities.

**Features:**
- HTTP client operations
- JSON/YAML handling
- Authentication
- Rate limiting
- Retry logic
- Response formatting

**Use Cases:**
- API clients
- Web scrapers
- Service health checkers
- Data synchronization

```bash
flash-init api-client --template network
```

### 🌳 **git-like** - Complex Subcommand Hierarchy
For applications with complex command structures like git, docker, kubectl.

**Features:**
- Nested subcommands
- Global flags
- Context sharing
- Plugin architecture
- Advanced help system

**Use Cases:**
- Version control systems
- Container management
- Cloud CLIs
- Package managers

```bash
flash-init container-tool --template git-like
```

## 🏗️ Template Structure

Each template follows this standard structure:

```
template-name/
├── template.yaml          # Template metadata
├── files/                 # Files to copy/generate
│   ├── build.zig.tmpl     # Build configuration
│   ├── src/
│   │   ├── main.zig.tmpl  # Main application
│   │   └── commands/      # Command modules
│   ├── tests/
│   │   └── integration.zig.tmpl
│   ├── completions/       # Shell completion setup
│   ├── docs/             # Documentation
│   └── README.md.tmpl    # Project README
├── prompts.yaml          # Interactive prompts
└── hooks/                # Template hooks
    ├── pre-generate.zig   # Pre-generation hooks
    └── post-generate.zig  # Post-generation hooks
```

## 🎨 Template Variables

Templates support variables for customization:

```yaml
# Common variables available in all templates
project:
  name: "{{project_name}}"
  description: "{{project_description}}"
  version: "{{project_version}}"
  author: "{{author_name}}"
  license: "{{license}}"

# Template-specific variables
devops:
  cloud_provider: "{{cloud_provider}}"
  environments: "{{environments}}"

network:
  base_url: "{{api_base_url}}"
  auth_type: "{{auth_type}}"
```

## 🚀 Usage

### Basic Usage
```bash
# Create new project with default settings
flash-init myapp --template basic

# Interactive mode with prompts
flash-init myapp --template devops --interactive

# Specify variables directly
flash-init api-tool --template network \
  --var api_base_url=https://api.example.com \
  --var auth_type=bearer
```

### Advanced Usage
```bash
# Use custom template directory
flash-init myapp --template-dir ./custom-templates --template basic

# Generate without Git initialization
flash-init myapp --template basic --no-git

# Specify output directory
flash-init myapp --template basic --output ./projects/
```

## 🛠️ Creating Custom Templates

### 1. Template Metadata (`template.yaml`)

```yaml
name: "custom-tool"
description: "Custom CLI tool template"
version: "1.0.0"
author: "Your Name"

# Template configuration
config:
  min_flash_version: "1.0.0"
  zig_version: "0.16.0"

# Required variables
variables:
  - name: project_name
    type: string
    required: true
    description: "Name of the project"

  - name: use_database
    type: boolean
    default: false
    description: "Include database support"

# Dependencies
dependencies:
  - name: "flash"
    version: "^1.0.0"
  - name: "zsync"
    version: "^0.5.0"
    condition: "{{async_support}}"

# Template features
features:
  - async_operations
  - shell_completions
  - testing
  - documentation
```

### 2. Template Files

Files use Zig's built-in templating with variables:

```zig
// src/main.zig.tmpl
const std = @import("std");
const flash = @import("flash");

const {{pascal_case project_name}}CLI = flash.CLI(.{
    .name = "{{project_name}}",
    .version = "{{project_version}}",
    .about = "{{project_description}}",
    .author = "{{author_name}}",

    .commands = &.{
        {{#if use_database}}
        flash.cmd("migrate", .{
            .about = "Run database migrations",
            .run = migrateCommand,
        }),
        {{/if}}

        flash.cmd("{{default_command}}", .{
            .about = "{{default_command_description}}",
            .run = defaultCommand,
        }),
    },
});
```

### 3. Interactive Prompts (`prompts.yaml`)

```yaml
prompts:
  - name: project_name
    message: "Project name"
    type: input
    validate: "^[a-z][a-z0-9-]*$"

  - name: project_description
    message: "Project description"
    type: input
    default: "A CLI application built with Flash"

  - name: use_database
    message: "Include database support?"
    type: confirm
    default: false

  - name: cloud_provider
    message: "Select cloud provider"
    type: select
    choices:
      - aws
      - gcp
      - azure
      - none
    condition: "template == 'devops'"
```

### 4. Generation Hooks

```zig
// hooks/post-generate.zig
const std = @import("std");

pub fn run(allocator: std.mem.Allocator, context: TemplateContext) !void {
    // Initialize Git repository
    if (context.getVar("git_init") == "true") {
        try std.ChildProcess.exec(.{
            .allocator = allocator,
            .argv = &.{ "git", "init" },
            .cwd = context.output_dir,
        });
    }

    // Generate shell completions
    try std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = &.{ "zig", "build", "completions" },
        .cwd = context.output_dir,
    });

    std.debug.print("✅ Project {} created successfully!\n", .{context.project_name});
    std.debug.print("📁 Location: {s}\n", .{context.output_dir});
    std.debug.print("🚀 Run: cd {} && zig build run -- --help\n", .{context.project_name});
}
```

## 🔗 Related

- [flash-init CLI Tool](../flash-init/README.md)
- [Template Development Guide](../docs/guides/template-development.md)
- [Contributing Templates](../CONTRIBUTING.md#templates)