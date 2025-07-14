//! ⚡ Flash Environment Variable Support
//!
//! Provides environment variable integration for CLI arguments

const std = @import("std");
const Argument = @import("argument.zig");

pub const EnvConfig = struct {
    /// Environment variable name (e.g., "MY_CLI_DEBUG")
    env_var: ?[]const u8 = null,
    /// Prefix for auto-generated env vars (e.g., "MYCLI_" -> "MYCLI_VERBOSE")
    prefix: ?[]const u8 = null,
    /// Whether to transform arg names (kebab-case to SCREAMING_SNAKE_CASE)
    transform_names: bool = true,

    pub fn withEnvVar(self: EnvConfig, env_var: []const u8) EnvConfig {
        var config = self;
        config.env_var = env_var;
        return config;
    }

    pub fn withPrefix(self: EnvConfig, prefix: []const u8) EnvConfig {
        var config = self;
        config.prefix = prefix;
        return config;
    }

    pub fn disableTransform(self: EnvConfig) EnvConfig {
        var config = self;
        config.transform_names = false;
        return config;
    }
};

/// Enhanced argument config with environment variable support
pub const EnvArgument = struct {
    base: Argument.Argument,
    env_config: EnvConfig,

    pub fn init(name: []const u8, arg_config: Argument.ArgumentConfig, env_config: EnvConfig) EnvArgument {
        return .{
            .base = Argument.Argument.init(name, arg_config),
            .env_config = env_config,
        };
    }

    /// Get value from environment variable if present
    pub fn getEnvValue(self: EnvArgument, allocator: std.mem.Allocator) ?[]const u8 {
        var env_name_buf: [256]u8 = undefined;
        var env_name: []const u8 = undefined;

        if (self.env_config.env_var) |explicit_env| {
            env_name = explicit_env;
        } else if (self.env_config.prefix) |prefix| {
            // Auto-generate: prefix + transformed name
            const transformed = if (self.env_config.transform_names) 
                transformToEnvName(allocator, self.base.name) catch return null
            else 
                self.base.name;
            defer if (self.env_config.transform_names) allocator.free(transformed);
            
            env_name = std.fmt.bufPrint(&env_name_buf, "{s}{s}", .{prefix, transformed}) catch return null;
        } else {
            // Use argument name directly
            env_name = if (self.env_config.transform_names)
                transformToEnvName(allocator, self.base.name) catch return null
            else
                self.base.name;
            defer if (self.env_config.transform_names and env_name.ptr != self.base.name.ptr) allocator.free(env_name);
        }

        return std.process.getEnvVarOwned(allocator, env_name) catch null;
    }
};

/// Transform kebab-case to SCREAMING_SNAKE_CASE
fn transformToEnvName(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    var result = try allocator.alloc(u8, name.len);
    for (name, 0..) |c, i| {
        result[i] = switch (c) {
            '-' => '_',
            'a'...'z' => c - 32, // Convert to uppercase
            else => c,
        };
    }
    return result;
}

test "env variable transformation" {
    const allocator = std.testing.allocator;
    
    const result = try transformToEnvName(allocator, "my-long-name");
    defer allocator.free(result);
    
    try std.testing.expectEqualStrings("MY_LONG_NAME", result);
}

test "env argument with explicit var" {
    const env_arg = EnvArgument.init(
        "debug", 
        (Argument.ArgumentConfig{}).withHelp("Enable debug mode"),
        (EnvConfig{}).withEnvVar("MY_DEBUG_FLAG")
    );
    
    try std.testing.expectEqualStrings("debug", env_arg.base.name);
    try std.testing.expectEqualStrings("MY_DEBUG_FLAG", env_arg.env_config.env_var.?);
}