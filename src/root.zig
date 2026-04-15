//! ⚡️ Flash — The Lightning-Fast CLI Framework for Zig
//!
//! A declarative CLI framework inspired by Clap, Cobra, and structopt,
//! designed for idiomatic Zig with compile-time validation.
//!
//! Features:
//! - Fast startup with zero-allocation parsing paths
//! - Auto-generated help, subcommands, flags, positional arguments
//! - Declarative command definitions using Zig's type system
//! - Type-safe argument parsing with validation
//! - Shell completion generation (Bash, Zsh, Fish, PowerShell, NuShell)

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
// The module remains internal for future development when zsync integration is finalized
// Prompts: experimental, password input is VISIBLE (no echo suppression)
pub const Prompts = @import("prompts.zig");
pub const Validation = @import("validation.zig");
pub const Progress = @import("progress.zig");
pub const Colors = @import("colors.zig");
// Experimental modules - APIs may change
// Declarative: uses fieldname_config struct declarations; default values use struct field defaults
pub const Declarative = @import("declarative.zig");
// Validators: regex() is actually pattern presets (email, url), not true regex
pub const Validators = @import("validators.zig");
// Config: JSON and TOML parsing work; YAML returns UnsupportedConfigFormat error
pub const Config = @import("config.zig");
// Security module removed from public API pending safe implementation
// See: tasks/code_review.md for details on vulnerabilities
// Macros: command(), CommandDef, ChainBuilder, deriveCommand work; AttributeCommand is a stub
pub const Macros = @import("macros.zig");

// Convenience functions for declarative CLI building
pub const cmd = Command.init;
pub const arg = Argument.init;
pub const flag = Flag.init;

// New ergonomic macro-based builders (CLAP-style)
pub const chain = Macros.cmd;
pub const deriveStruct = Macros.deriveCommand;
pub const command = Macros.command;
pub const pattern = Macros.PatternMatcher.match;
pub const parse = Declarative.parse;
pub const parseWithConfig = Declarative.parseWithConfig;
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
    try std.testing.expect(version.minor == 3);
    try std.testing.expect(version.patch == 5);
}
