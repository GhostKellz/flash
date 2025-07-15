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

/// Environment variable hierarchy for configuration
pub const EnvHierarchy = struct {
    prefix: []const u8,
    transform_names: bool = true,
    case_sensitive: bool = false,
    override_cli: bool = false, // Whether env vars override CLI args
    
    pub fn init(prefix: []const u8) EnvHierarchy {
        return .{ .prefix = prefix };
    }
    
    pub fn withCaseSensitive(self: EnvHierarchy, case_sensitive: bool) EnvHierarchy {
        var config = self;
        config.case_sensitive = case_sensitive;
        return config;
    }
    
    pub fn withOverrideCli(self: EnvHierarchy, override_cli: bool) EnvHierarchy {
        var config = self;
        config.override_cli = override_cli;
        return config;
    }
    
    pub fn disableTransform(self: EnvHierarchy) EnvHierarchy {
        var config = self;
        config.transform_names = false;
        return config;
    }
    
    /// Get environment variable value for a field
    pub fn getEnvValue(self: EnvHierarchy, allocator: std.mem.Allocator, field_name: []const u8) !?[]const u8 {
        var env_name_buf: [256]u8 = undefined;
        
        const transformed_name = if (self.transform_names) 
            try transformToEnvName(allocator, field_name)
        else 
            field_name;
        defer if (self.transform_names and transformed_name.ptr != field_name.ptr) allocator.free(transformed_name);
        
        const env_name = try std.fmt.bufPrint(&env_name_buf, "{s}{s}", .{ self.prefix, transformed_name });
        
        return std.process.getEnvVarOwned(allocator, env_name) catch null;
    }
    
    /// Parse struct from environment variables
    pub fn parseFromEnv(self: EnvHierarchy, comptime T: type, allocator: std.mem.Allocator) !T {
        var result: T = undefined;
        const type_info = @typeInfo(T);
        
        inline for (type_info.Struct.fields) |field| {
            if (try self.getEnvValue(allocator, field.name)) |env_value| {
                defer allocator.free(env_value);
                
                @field(result, field.name) = switch (field.type) {
                    bool => std.mem.eql(u8, env_value, "true") or std.mem.eql(u8, env_value, "1"),
                    []const u8 => try allocator.dupe(u8, env_value),
                    ?[]const u8 => try allocator.dupe(u8, env_value),
                    i32 => try std.fmt.parseInt(i32, env_value, 10),
                    ?i32 => try std.fmt.parseInt(i32, env_value, 10),
                    f64 => try std.fmt.parseFloat(f64, env_value),
                    ?f64 => try std.fmt.parseFloat(f64, env_value),
                    else => {
                        // Use default value if available
                        if (field.default_value) |default_ptr| {
                            const default_value = @as(*const field.type, @ptrCast(@alignCast(default_ptr))).*;
                            @field(result, field.name) = default_value;
                        } else {
                            @field(result, field.name) = std.mem.zeroes(field.type);
                        }
                        continue;
                    },
                };
            } else {
                // Use default value if available
                if (field.default_value) |default_ptr| {
                    const default_value = @as(*const field.type, @ptrCast(@alignCast(default_ptr))).*;
                    @field(result, field.name) = default_value;
                } else {
                    @field(result, field.name) = std.mem.zeroes(field.type);
                }
            }
        }
        
        return result;
    }
    
    /// Merge environment variables with CLI arguments
    pub fn mergeWithCli(self: EnvHierarchy, comptime T: type, allocator: std.mem.Allocator, cli_args: T) !T {
        var result = cli_args;
        
        if (self.override_cli) {
            // Environment variables override CLI arguments
            const env_args = try self.parseFromEnv(T, allocator);
            
            const type_info = @typeInfo(T);
            inline for (type_info.Struct.fields) |field| {
                if (try self.getEnvValue(allocator, field.name)) |_| {
                    @field(result, field.name) = @field(env_args, field.name);
                }
            }
        } else {
            // CLI arguments override environment variables
            const env_args = try self.parseFromEnv(T, allocator);
            
            const type_info = @typeInfo(T);
            inline for (type_info.Struct.fields) |field| {
                const cli_value = @field(cli_args, field.name);
                const env_value = @field(env_args, field.name);
                
                // Use CLI value if provided, otherwise use env value
                @field(result, field.name) = switch (field.type) {
                    bool => cli_value or env_value,
                    ?[]const u8 => cli_value orelse env_value,
                    ?i32 => cli_value orelse env_value,
                    ?f64 => cli_value orelse env_value,
                    else => if (hasNonZeroValue(cli_value)) cli_value else env_value,
                };
            }
        }
        
        return result;
    }
};

/// Check if a value is non-zero/non-null
fn hasNonZeroValue(value: anytype) bool {
    const T = @TypeOf(value);
    return switch (@typeInfo(T)) {
        .optional => value != null,
        .bool => value,
        .int => value != 0,
        .float => value != 0.0,
        .pointer => value.len > 0,
        else => true,
    };
}

/// Configuration source for layered configuration
pub const ConfigSource = enum {
    environment,
    file,
    cli,
    defaults,
};

/// Layered configuration parser
pub const LayeredConfig = struct {
    allocator: std.mem.Allocator,
    sources: []const ConfigSource,
    env_hierarchy: ?EnvHierarchy = null,
    config_file: ?[]const u8 = null,
    
    pub fn init(allocator: std.mem.Allocator, sources: []const ConfigSource) LayeredConfig {
        return .{
            .allocator = allocator,
            .sources = sources,
        };
    }
    
    pub fn withEnvHierarchy(self: LayeredConfig, hierarchy: EnvHierarchy) LayeredConfig {
        var config = self;
        config.env_hierarchy = hierarchy;
        return config;
    }
    
    pub fn withConfigFile(self: LayeredConfig, file_path: []const u8) LayeredConfig {
        var config = self;
        config.config_file = file_path;
        return config;
    }
    
    /// Parse configuration from multiple sources with priority
    pub fn parse(self: LayeredConfig, comptime T: type, cli_args: T) !T {
        var result: T = undefined;
        
        // Apply sources in order of priority
        for (self.sources) |source| {
            switch (source) {
                .defaults => {
                    // Apply struct defaults
                    const type_info = @typeInfo(T);
                    inline for (type_info.Struct.fields) |field| {
                        if (field.default_value) |default_ptr| {
                            const default_value = @as(*const field.type, @ptrCast(@alignCast(default_ptr))).*;
                            @field(result, field.name) = default_value;
                        } else {
                            @field(result, field.name) = std.mem.zeroes(field.type);
                        }
                    }
                },
                .environment => {
                    if (self.env_hierarchy) |hierarchy| {
                        const env_config = try hierarchy.parseFromEnv(T, self.allocator);
                        result = try mergeConfigs(T, result, env_config);
                    }
                },
                .file => {
                    // TODO: Implement file configuration parsing
                    // This would read from JSON/TOML/YAML files
                },
                .cli => {
                    result = try mergeConfigs(T, result, cli_args);
                },
            }
        }
        
        return result;
    }
};

/// Merge two configuration structs
fn mergeConfigs(comptime T: type, base: T, overlay: T) !T {
    var result = base;
    const type_info = @typeInfo(T);
    
    inline for (type_info.Struct.fields) |field| {
        const overlay_value = @field(overlay, field.name);
        
        if (hasNonZeroValue(overlay_value)) {
            @field(result, field.name) = overlay_value;
        }
    }
    
    return result;
}

/// Auto-generate environment variable prefix from struct name
pub fn envPrefix(comptime T: type) []const u8 {
    const type_name = @typeName(T);
    // Extract the last part after the last dot
    const last_dot = std.mem.lastIndexOf(u8, type_name, ".") orelse return type_name;
    const struct_name = type_name[last_dot + 1 ..];
    
    // Transform to uppercase with underscore
    comptime var result: [struct_name.len + 1]u8 = undefined;
    comptime var i = 0;
    inline for (struct_name) |c| {
        result[i] = switch (c) {
            'a'...'z' => c - 32,
            'A'...'Z' => c,
            else => '_',
        };
        i += 1;
    }
    result[i] = '_';
    
    return result[0..i+1];
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

test "env hierarchy parsing" {
    const TestStruct = struct {
        name: []const u8 = "default",
        count: i32 = 1,
        verbose: bool = false,
    };
    
    const hierarchy = EnvHierarchy.init("TEST_");
    
    // Test with no environment variables (should use defaults)
    const allocator = std.testing.allocator;
    const result = try hierarchy.parseFromEnv(TestStruct, allocator);
    
    try std.testing.expectEqualStrings("default", result.name);
    try std.testing.expectEqual(@as(i32, 1), result.count);
    try std.testing.expectEqual(false, result.verbose);
}

test "env prefix generation" {
    const TestStruct = struct {
        field: i32 = 0,
    };
    
    const prefix = envPrefix(TestStruct);
    try std.testing.expectEqualStrings("TESTSTRUCT_", prefix);
}

test "layered configuration" {
    const allocator = std.testing.allocator;
    
    const ConfigStruct = struct {
        name: []const u8 = "default",
        count: i32 = 1,
        verbose: bool = false,
    };
    
    const sources = [_]ConfigSource{ .defaults, .environment, .cli };
    const config = LayeredConfig.init(allocator, &sources)
        .withEnvHierarchy(EnvHierarchy.init("TEST_"));
    
    const cli_args = ConfigStruct{
        .name = "cli_name",
        .count = 5,
        .verbose = true,
    };
    
    const result = try config.parse(ConfigStruct, cli_args);
    
    // CLI should override defaults
    try std.testing.expectEqualStrings("cli_name", result.name);
    try std.testing.expectEqual(@as(i32, 5), result.count);
    try std.testing.expectEqual(true, result.verbose);
}