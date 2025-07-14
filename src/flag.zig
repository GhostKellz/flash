//! Flag definitions for Flash CLI
//!
//! Flags are boolean arguments that can be turned on/off, typically
//! using --flag or -f syntax.

const std = @import("std");
const Argument = @import("argument.zig");
const Error = @import("error.zig");

/// Flag configuration
pub const FlagConfig = struct {
    help: ?[]const u8 = null,
    short: ?u8 = null,
    long: ?[]const u8 = null,
    default: bool = false,
    hidden: bool = false,
    global: bool = false, // Available in all subcommands

    pub fn withHelp(self: FlagConfig, help: []const u8) FlagConfig {
        var config = self;
        config.help = help;
        return config;
    }

    pub fn withShort(self: FlagConfig, short: u8) FlagConfig {
        var config = self;
        config.short = short;
        return config;
    }

    pub fn withLong(self: FlagConfig, long: []const u8) FlagConfig {
        var config = self;
        config.long = long;
        return config;
    }

    pub fn withDefault(self: FlagConfig, default: bool) FlagConfig {
        var config = self;
        config.default = default;
        return config;
    }

    pub fn setHidden(self: FlagConfig) FlagConfig {
        var config = self;
        config.hidden = true;
        return config;
    }

    pub fn setGlobal(self: FlagConfig) FlagConfig {
        var config = self;
        config.global = true;
        return config;
    }
};

/// Flag definition
pub const Flag = struct {
    name: []const u8,
    config: FlagConfig,

    pub fn init(name: []const u8, config: FlagConfig) Flag {
        return .{
            .name = name,
            .config = config,
        };
    }

    /// Check if this flag matches a flag name
    pub fn matchesFlag(self: Flag, flag: []const u8) bool {
        if (flag.len == 1) {
            return self.config.short != null and self.config.short.? == flag[0];
        } else {
            return self.config.long != null and std.mem.eql(u8, self.config.long.?, flag);
        }
    }

    /// Get the default value for this flag
    pub fn getDefault(self: Flag) bool {
        return self.config.default;
    }

    /// Get help text for this flag
    pub fn getHelp(self: Flag) ?[]const u8 {
        return self.config.help;
    }

    /// Check if this flag is hidden
    pub fn isHidden(self: Flag) bool {
        return self.config.hidden;
    }

    /// Check if this flag is global
    pub fn isGlobal(self: Flag) bool {
        return self.config.global;
    }

    /// Convert this flag to an argument for unified handling
    pub fn toArgument(self: Flag) Argument.Argument {
        return Argument.Argument{
            .name = self.name,
            .arg_type = .bool,
            .config = .{
                .help = self.config.help,
                .required = false,
                .default = Argument.ArgValue{ .bool = self.config.default },
                .short = self.config.short,
                .long = self.config.long,
                .multiple = false,
                .hidden = self.config.hidden,
                .validator = null,
            },
        };
    }
};

test "flag creation and matching" {
    const flag = Flag.init("verbose", (FlagConfig{})
        .withHelp("Enable verbose output")
        .withShort('v')
        .withLong("verbose")
        .withDefault(false));

    try std.testing.expectEqualStrings("Enable verbose output", flag.getHelp().?);
    try std.testing.expectEqual(false, flag.getDefault());
    try std.testing.expectEqual(true, flag.matchesFlag("v"));
    try std.testing.expectEqual(true, flag.matchesFlag("verbose"));
    try std.testing.expectEqual(false, flag.matchesFlag("other"));
}

test "flag to argument conversion" {
    const flag = Flag.init("debug", (FlagConfig{})
        .withHelp("Enable debug mode")
        .withShort('d')
        .withLong("debug"));

    const arg = flag.toArgument();
    try std.testing.expectEqualStrings("debug", arg.name);
    try std.testing.expectEqual(Argument.ArgType.bool, arg.arg_type);
    try std.testing.expectEqualStrings("Enable debug mode", arg.getHelp().?);
    try std.testing.expectEqual(false, arg.getDefault().?.asBool());
}
