⚡️ Flash v0.1.0 TODO — The Zig CLI Framework
🚩 MVP Milestones

Argument Parsing Core

Typed argument/flag parsing (bool, int, string, enum, etc)

Variadic and positional argument support

Required/optional/defaulted arg logic

    Unified error model for parse errors

Subcommand System

Recursive subcommands (unlimited depth)

Async command handler dispatch

    Custom command metadata (about, usage, version, etc)

Auto-Help & Usage

Global -h/--help with banners

Per-command help and usage

    Auto-generated usage examples

Shell Completions

Bash, Zsh, Fish, PowerShell completion generators

    Dynamic completion hooks

Config & Env Integration

Merge CLI args, ENV, config files (TOML/JSON)

    Precedence rules and override logic

Prompt System

Interactive password/choice/confirm prompts (async)

    Optional: Fallback for non-interactive shells

Rich Error Handling

Parse errors (bad args/flags)

Usage/runtime errors with colors

    Custom error hooks

Testing Utilities

Arg injection for tests

        Command test harness

🛠️ Advanced Features (v0.2+)

Enum option auto-complete

Custom async validators

Plugin system for runtime extension

Interactive REPL mode

    Command tree visualization (ascii)

🧪 Dev Experience

Comprehensive Zig doc comments

Examples for all features

    Codegen for shell completions & docs


