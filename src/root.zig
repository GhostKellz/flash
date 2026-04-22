//! ⚡️ Flash — The CLI Framework for Zig
//!
//! Flash is built to fill the same role for Zig that Clap fills for Rust
//! and Cobra fills for Go, while staying idiomatic to Zig `0.17.0-dev`.
//!
//! Features:
//! - Fast startup with zero-allocation parsing paths
//! - Auto-generated help, subcommands, flags, positional arguments
//! - Macro-first and declarative command definitions using Zig's type system
//! - Type-safe argument parsing with validation
//! - Shell completion generation with strongest support on Bash and Zsh

const std = @import("std");
const build_options = @import("build_options");

// Public API exports
pub const CLI = @import("cli.zig").CLI;
pub const Command = @import("command.zig").Command;
pub const CommandConfig = @import("command.zig").CommandConfig;
pub const Argument = @import("argument.zig").Argument;
pub const ArgumentConfig = @import("argument.zig").ArgumentConfig;
pub const ArgValue = @import("argument.zig").ArgValue;
pub const Flag = @import("flag.zig").Flag;
pub const FlagConfig = @import("flag.zig").FlagConfig;
pub const Context = @import("context.zig").Context;
pub const Parser = @import("parser.zig").Parser;
pub const Help = @import("help.zig").Help;
pub const Error = @import("error.zig").FlashError;
pub const Env = @import("env.zig");
pub const Completion = @import("completion.zig");
// Async module removed from public API - implementation is incomplete
// The module remains internal while Flash's owned async foundations mature
// Prompts: experimental; password input remains visible because echo suppression is not implemented yet
pub const Prompts = @import("prompts.zig");
pub const Validation = @import("validation.zig");
pub const Progress = @import("progress.zig");
pub const Colors = @import("colors.zig");
pub const Testing = @import("testing.zig");
// Experimental modules - APIs may change
// Declarative: uses fieldname_config declarations and struct defaults; generated commands require explicit cleanup when owned
pub const Declarative = @import("declarative.zig");
// Validators: regex() is actually pattern presets (email, url), not true regex
pub const Validators = @import("validators.zig");
// Config: JSON and TOML parsing are supported; YAML is explicitly unsupported in v0.4.0
pub const Config = @import("config.zig");
// Security module removed from public API pending safe implementation
// See: tasks/code_review.md for details on vulnerabilities
// Macros: macro-first command specs, richer parsing, middleware composition, and struct-derived commands work; true Zig attribute syntax remains limited
pub const Macros = @import("macros.zig");

// Convenience functions for declarative CLI building
pub const cmd = Command.init;
pub const arg = Argument.init;
pub const flag = Flag.init;

// Ergonomic macro-first builders for Clap/Cobra-style command definition
pub const chain = Macros.cmd;
pub const deriveStruct = Macros.deriveCommand;
pub const command = Macros.command;
pub const pattern = Macros.PatternMatcher.match;
pub const derive = Declarative.derive;

// Version information (injected from build.zig.zon at compile time)
pub const version = std.SemanticVersion{
    .major = build_options.version_major,
    .minor = build_options.version_minor,
    .patch = build_options.version_patch,
};
pub const version_string = build_options.version_string;

test "flash version" {
    try std.testing.expect(version.major == 0);
    try std.testing.expect(version.minor == 4);
    try std.testing.expect(version.patch == 0);
}

// Include all module tests in the test build
comptime {
    // Core modules
    _ = @import("cli.zig");
    _ = @import("command.zig");
    _ = @import("argument.zig");
    _ = @import("flag.zig");
    _ = @import("context.zig");
    _ = @import("parser.zig");
    _ = @import("help.zig");
    _ = @import("error.zig");
    _ = @import("env.zig");
    _ = @import("completion.zig");
    _ = @import("prompts.zig");
    _ = @import("validation.zig");
    _ = @import("progress.zig");
    _ = @import("colors.zig");
    _ = @import("declarative.zig");
    _ = @import("validators.zig");
    _ = @import("config.zig");
    _ = @import("macros.zig");
    // Internal/experimental modules (tests still run)
    _ = @import("testing.zig");
    _ = @import("advanced_validation.zig");
}
