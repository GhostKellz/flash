//! ⚡️ Flash — The Lightning-Fast CLI Framework for Zig
//!
//! Flash is the definitive CLI framework for Zig — inspired by Clap, Cobra, and structopt,
//! but rebuilt for next-generation async, idiomatic Zig.
//!
//! Features:
//! - Blazing fast with lightning startup and zero-alloc CLI paths
//! - Batteries included: auto-generated help, subcommands, flags, shell completions
//! - Async-first: all parsing and dispatch is async (zsync-powered)
//! - Declarative: use Zig's struct/enum power for arguments and commands
//! - Error-proof: predictable, type-safe, memory-safe; no panics, no segfaults

const std = @import("std");

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
pub const Async = @import("async.zig");
pub const Prompts = @import("prompts.zig");
pub const Validation = @import("validation.zig");
pub const Progress = @import("progress.zig");
pub const Colors = @import("colors.zig");
pub const Declarative = @import("declarative.zig");
pub const Validators = @import("validators.zig");
pub const Config = @import("config.zig");
pub const Security = @import("security.zig");
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

// Version information
pub const version = std.SemanticVersion{ .major = 0, .minor = 1, .patch = 0 };

test "flash version" {
    try std.testing.expect(version.major == 0);
    try std.testing.expect(version.minor == 1);
    try std.testing.expect(version.patch == 0);
}
