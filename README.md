<div align="center">
  <img src="assets/icons/flash-cli.png" alt="Flash CLI Framework" width="200"/>
</div>

# ⚡️ Flash — The Lightning-Fast CLI Framework for Zig

<p align="center">
  <img src="https://img.shields.io/badge/Zig-0.16--dev-F7A41D?style=for-the-badge&logo=zig&logoColor=white" alt="Zig">
  <img src="https://img.shields.io/badge/CLI-Framework-0078D4?style=for-the-badge&logo=gnometerminal&logoColor=white" alt="CLI Framework">
  <img src="https://img.shields.io/badge/Pure-Zig-2ECC71?style=for-the-badge&logo=checkmarx&logoColor=white" alt="Pure Zig">
  <img src="https://img.shields.io/badge/Cross--Platform-Build-8A2BE2?style=for-the-badge&logo=linux&logoColor=white" alt="Cross Platform">
</p>

---

### ⚡️**Flash** is a CLI framework for Zig, inspired by Clap, Cobra, and structopt but rebuilt for idiomatic Zig.

* **Blazing Fast:** Lightning startup, zero alloc CLI paths
* **Batteries Included:** Auto generated help, subcommands, flags, positional arguments
* **Declarative:** Use Zig's struct/enum power for arguments and commands
* **Error Proof:** Predictable, type safe, memory safe; no panics, no segfaults
* **Plug & Play:** Works everywhere Zig runs, cross compile in seconds

---

## 🚀 Why Flash?

* **Speed:** Near zero overhead, built for CLI tools that *feel* instant
* **Ergonomics:** Clean, declarative CLI specs (no macros, no black magic)
* **Modern Features:** Auto help, subcommands, typed arguments and flags
* **No Nonsense:** Pure Zig, no C glue, no runtime dependencies

---

## 🛠️ Features

### Stable
* [x] **Subcommands:** Hierarchical command structure with nested support
* [x] **Flags & Options:** Typed, validated, with defaults
* [x] **Positional Arguments:** Required/optional support
* [x] **Auto Help:** `-h/--help` generation
* [x] **Rich Error Handling:** Usage and parse errors with colorized output
* [x] **JSON Config:** Load configuration from JSON files
* [x] **TOML Config:** Load configuration from TOML files (via [zontom](https://github.com/ghostkellz/zontom))
* [x] **Nested Subcommands:** Full command path resolution (e.g., `app service admin restart`)
* [x] **Shell Completion:** Bash, Zsh, Fish, PowerShell, NuShell generation
* [x] **Typed Enums/Choices:** Constrained argument values with validation and completion

### Experimental
* [🧪] **Interactive Prompts:** Password and choice prompts (visible input, demo-quality)
* [🧪] **Declarative API:** Struct-based CLI definition with `fieldname_config` metadata
* [🧪] **Macro Helpers:** CLAP-style `command()`, `cmd()`, `deriveCommand()` builders

### Internal Only (Not Exported)
* **Async Runtime:** zsync integration exists but is not production ready
* **Security Module:** Credential storage withheld pending security audit

### Planned
* [ ] **YAML Config:** Currently returns unsupported format error
* [ ] **Plugin Architecture:** Runtime CLI extension
* [ ] **Command Tree Visualization:** Visual command hierarchy display

---

## 📦 Quick Start

### Install

```sh
zig fetch github.com/ghostkellz/flash
```

*Or clone and add as a dependency in your `build.zig` project:*

```zig
const flash_dep = b.dependency("flash", .{ .target = target, .optimize = optimize });
const flash = flash_dep.module("flash");
```

### Minimal Example

```zig
const std = @import("std");
const flash = @import("flash");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    const EchoCLI = flash.CLI(.{
        .name = "echo-tool",
        .version = flash.version_string,
        .about = "A demo CLI built with Flash",
    });

    const echo_cmd = flash.cmd("echo", (flash.CommandConfig{})
        .withAbout("Echo your message")
        .withArgs(&.{
            flash.arg("message", (flash.ArgumentConfig{})
                .withHelp("Text to echo")
                .setRequired()),
        })
        .withHandler(echoHandler));

    var cli = EchoCLI.init(allocator, (flash.CommandConfig{})
        .withSubcommands(&.{echo_cmd}));

    try cli.runWithInit(init);
}

fn echoHandler(ctx: flash.Context) flash.Error!void {
    if (ctx.getString("message")) |message| {
        std.debug.print("{s}\n", .{message});
    }
}
```

---

## 🔥 Advanced Features

* **Command Handlers:** Define handlers as regular Zig functions
* **Flag Chaining:** Builder pattern for ergonomic flag configuration
* **JSON Config Loading:** Merge file based configuration with CLI args
* **Nested Subcommands:** Full command path resolution for deep hierarchies
* **Prompt System:** Basic interactive prompts (experimental)

### Typed Enum/Choices Example

```zig
const format_arg = flash.arg("format", (flash.ArgumentConfig{})
    .withHelp("Output format")
    .withChoices(&.{ "json", "yaml", "toml" })
    .setRequired());

// Invalid choices are rejected with InvalidChoice error
// Shell completion suggests valid choices automatically
```

### Documentation

* [Declarative Config Guide](docs/guides/declarative-config.md)
* [Docker Verification Guide](docs/guides/docker-verification.md)
* [Shell Completions Guide](docs/guides/completions.md)
* [Getting Started](docs/guides/getting-started.md)

---

## 🗺️ Roadmap

* [x] Nested subcommand resolution
* [x] Shell completion (Bash, Zsh, Fish, PowerShell, NuShell)
* [x] Typed enum options with auto-completion
* [x] TOML config file support (via zontom)
* [ ] YAML config file support
* [ ] Security module with safe credential handling
* [ ] Plugin architecture for runtime extension
* [ ] Command tree visualization
* [ ] Interactive REPL mode

---

## 📋 v0.3.5 API Changes

The following modules were removed from the public API in v0.3.5:

| Module | Status | Reason | Reintroduction Criteria |
|--------|--------|--------|------------------------|
| `Async` | Internal | Incomplete zsync integration | Full async execution with tests |
| `Security` | Internal | Command injection vulnerabilities | Security audit and safe implementation |
| `flash-init` | Removed | Stale API incompatible with v0.3.x | Rewrite for v0.4.x API |

These modules still exist in the source but are not exported from `root.zig`.
Functions in these modules return `error.Unimplemented` or `error.SecurityDisabled`.

---

## 🤝 Contributing

PRs, issues, feature ideas, and benchmarking challenges welcome!
See [`CONTRIBUTING.md`](CONTRIBUTING.md).

---

