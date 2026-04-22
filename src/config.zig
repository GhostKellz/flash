//! Configuration file support for Flash CLI
//!
//! Supports TOML and JSON configuration files with automatic
//! parsing and merging with CLI arguments.
//!
//! TOML parsing is powered by flare (https://github.com/ghostkellz/flare)

const std = @import("std");
const Error = @import("error.zig");
const Argument = @import("argument.zig");
const flare = @import("flare");

/// Supported configuration file formats
pub const ConfigFormat = enum {
    toml,
    json,
    yaml,
    auto, // Auto-detect from file extension

    pub fn fromExtension(extension: []const u8) ConfigFormat {
        if (std.mem.eql(u8, extension, ".toml")) return .toml;
        if (std.mem.eql(u8, extension, ".json")) return .json;
        if (std.mem.eql(u8, extension, ".yaml") or std.mem.eql(u8, extension, ".yml")) return .yaml;
        return .auto;
    }
};

pub const TomlDiagnostics = struct {
    line: usize,
    column: usize,
    source_line: ?[]const u8,
    message: []const u8,
    suggestion: ?[]const u8,
};

/// Configuration file parser
pub const ConfigParser = struct {
    allocator: std.mem.Allocator,

    pub const FieldPresence = enum {
        missing,
        present,
    };

    /// Parsed config structs may contain owned strings or slices.
    /// JSON-backed strings are duplicated into `allocator`.
    /// TOML-backed parsing delegates to Flare and follows Flare ownership rules.
    /// Callers are responsible for freeing owned fields in parsed results.
    pub fn init(allocator: std.mem.Allocator) ConfigParser {
        return .{ .allocator = allocator };
    }

    /// Parse configuration file and merge with struct
    pub fn parseFile(self: ConfigParser, comptime T: type, file_path: []const u8, format: ConfigFormat) !T {
        const io = std.Io.Threaded.global_single_threaded.io();
        const file_content = try std.Io.Dir.cwd().readFileAlloc(io, file_path, self.allocator, .limited(std.math.maxInt(usize)));
        defer self.allocator.free(file_content);

        const actual_format = if (format == .auto) blk: {
            const ext = std.fs.path.extension(file_path);
            break :blk ConfigFormat.fromExtension(ext);
        } else format;

        return self.parseContent(T, file_content, actual_format);
    }

    /// Parse configuration content
    pub fn parseContent(self: ConfigParser, comptime T: type, content: []const u8, format: ConfigFormat) !T {
        return switch (format) {
            .json => try self.parseJson(T, content),
            .toml => try self.parseToml(T, content),
            .yaml => try self.parseYaml(T, content),
            .auto => Error.FlashError.ConfigError,
        };
    }

    /// Parse JSON configuration
    fn parseJson(self: ConfigParser, comptime T: type, content: []const u8) !T {
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, content, .{}) catch {
            return Error.FlashError.ConfigError;
        };
        defer parsed.deinit();

        return try self.parseJsonValue(T, parsed.value);
    }

    /// Parse JSON value recursively
    fn parseJsonValue(self: ConfigParser, comptime T: type, value: std.json.Value) !T {
        const type_info = @typeInfo(T);

        return switch (type_info) {
            .@"struct" => |struct_info| blk: {
                if (value != .object) {
                    return Error.FlashError.ConfigError;
                }

                var result: T = undefined;

                inline for (struct_info.fields) |field| {
                    if (value.object.get(field.name)) |field_value| {
                        @field(result, field.name) = try self.parseJsonValue(field.type, field_value);
                    } else {
                        // Use default value if available
                        if (field.default_value_ptr) |default_ptr| {
                            const default_value = @as(*const field.type, @ptrCast(@alignCast(default_ptr))).*;
                            @field(result, field.name) = default_value;
                        } else {
                            @field(result, field.name) = std.mem.zeroes(field.type);
                        }
                    }
                }

                break :blk result;
            },
            .bool => switch (value) {
                .bool => |b| b,
                else => Error.FlashError.ConfigError,
            },
            .int => switch (value) {
                .integer => |i| @intCast(i),
                else => Error.FlashError.ConfigError,
            },
            .float => switch (value) {
                .float => |f| @floatCast(f),
                .integer => |i| @floatFromInt(i),
                else => Error.FlashError.ConfigError,
            },
            .pointer => |ptr| switch (ptr.child) {
                u8 => switch (value) {
                    .string => |s| try self.allocator.dupe(u8, s),
                    else => Error.FlashError.ConfigError,
                },
                else => Error.FlashError.ConfigError,
            },
            .optional => |opt| switch (value) {
                .null => null,
                else => try self.parseJsonValue(opt.child, value),
            },
            else => Error.FlashError.ConfigError,
        };
    }

    /// Parse TOML configuration using flare
    fn parseToml(self: ConfigParser, comptime T: type, content: []const u8) !T {
        return flare.parseInto(T, self.allocator, content) catch {
            return Error.FlashError.ConfigError;
        };
    }

    /// Parse TOML and preserve Flare's diagnostic context on failure.
    pub fn parseTomlWithDiagnostics(self: ConfigParser, comptime T: type, content: []const u8) union(enum) {
        success: T,
        failure: TomlDiagnostics,
    } {
        const result = flare.parseTomlWithContext(self.allocator, content);
        if (result.table) |table| {
            defer {
                table.deinit();
                self.allocator.destroy(table);
            }

            const parsed = flare.deserialize(T, self.allocator, table) catch |err| {
                return .{ .failure = .{
                    .line = 0,
                    .column = 0,
                    .source_line = null,
                    .message = @errorName(err),
                    .suggestion = "Check that the TOML values match the target Zig struct field requirements",
                } };
            };

            return .{ .success = parsed };
        }

        const ctx = if (result.error_context) |error_context|
            TomlDiagnostics{
                .line = error_context.line,
                .column = error_context.column,
                .source_line = error_context.source_line,
                .message = error_context.message,
                .suggestion = error_context.suggestion,
            }
        else
            TomlDiagnostics{
                .line = 0,
                .column = 0,
                .source_line = null,
                .message = "Unknown TOML parse error",
                .suggestion = null,
            };

        return .{ .failure = .{
            .line = ctx.line,
            .column = ctx.column,
            .source_line = ctx.source_line,
            .message = ctx.message,
            .suggestion = ctx.suggestion,
        } };
    }

    /// Parse YAML configuration (not yet implemented)
    fn parseYaml(self: ConfigParser, comptime T: type, content: []const u8) Error.FlashError!T {
        _ = self;
        _ = content;
        return Error.FlashError.UnsupportedConfigFormat;
    }

    /// Merge configuration with existing struct
    pub fn merge(comptime T: type, base: T, config: T) T {
        var result = base;
        const type_info = @typeInfo(T);

        inline for (type_info.@"struct".fields) |field| {
            const config_value = @field(config, field.name);

            // Only override if config value is not the default/zero value
            if (!isZeroValue(config_value)) {
                @field(result, field.name) = config_value;
            }
        }

        return result;
    }

    /// Merge configuration with explicit per-field presence.
    /// This allows callers to intentionally override base values with `false`, `0`, or `""`.
    pub fn mergeWithPresence(comptime T: type, base: T, config: T, presence: anytype) T {
        var result = base;
        const type_info = @typeInfo(T);

        inline for (type_info.@"struct".fields) |field| {
            if (@field(presence, field.name) == .present) {
                @field(result, field.name) = @field(config, field.name);
            }
        }

        return result;
    }

    /// Check if a value is zero/default
    fn isZeroValue(value: anytype) bool {
        const T = @TypeOf(value);
        return switch (@typeInfo(T)) {
            .bool => !value,
            .int => value == 0,
            .float => value == 0.0,
            .pointer => value.len == 0,
            .optional => value == null,
            else => false,
        };
    }
};

/// Configuration file watcher
pub const ConfigWatcher = struct {
    allocator: std.mem.Allocator,
    file_path: []const u8,
    last_modified: i128,

    pub fn init(allocator: std.mem.Allocator, file_path: []const u8) ConfigWatcher {
        return .{
            .allocator = allocator,
            .file_path = file_path,
            .last_modified = 0,
        };
    }

    /// Check if config file has been modified
    pub fn hasChanged(self: *ConfigWatcher) bool {
        // Note: File stat requires Io instance in Zig 0.17 - returning false
        _ = self;
        return false;
    }

    /// Reload configuration if changed
    pub fn reloadIfChanged(self: *ConfigWatcher, comptime T: type, current: T, format: ConfigFormat) !T {
        if (self.hasChanged()) {
            const parser = ConfigParser.init(self.allocator);
            const new_config = try parser.parseFile(T, self.file_path, format);
            return ConfigParser.merge(T, current, new_config);
        }

        return current;
    }
};

/// Configuration hierarchy with multiple sources
pub const ConfigHierarchy = struct {
    allocator: std.mem.Allocator,
    sources: []const ConfigSource,

    pub const ConfigSource = struct {
        path: []const u8,
        format: ConfigFormat,
        is_required: bool = false,

        pub fn init(path: []const u8, format: ConfigFormat) ConfigSource {
            return .{ .path = path, .format = format };
        }

        pub fn required(self: ConfigSource) ConfigSource {
            var source = self;
            source.is_required = true;
            return source;
        }
    };

    pub fn init(allocator: std.mem.Allocator, sources: []const ConfigSource) ConfigHierarchy {
        return .{
            .allocator = allocator,
            .sources = sources,
        };
    }

    /// Parse configuration from multiple sources with priority
    pub fn parse(self: ConfigHierarchy, comptime T: type, base: T) !T {
        var result = base;
        const parser = ConfigParser.init(self.allocator);

        for (self.sources) |source| {
            const file_config = parser.parseFile(T, source.path, source.format) catch |err| {
                if (source.is_required) {
                    return err;
                }
                continue;
            };

            result = ConfigParser.merge(T, result, file_config);
        }

        return result;
    }
};

/// Configuration template generator
pub const ConfigTemplate = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ConfigTemplate {
        return .{ .allocator = allocator };
    }

    /// Generate configuration template
    pub fn generate(self: ConfigTemplate, comptime T: type, format: ConfigFormat) ![]u8 {
        const type_info = @typeInfo(T);
        var aw: std.Io.Writer.Allocating = .init(self.allocator);
        const writer = &aw.writer;

        switch (format) {
            .json => try self.generateJson(T, type_info, writer),
            .toml => try self.generateToml(T, type_info, writer),
            .yaml => try self.generateYaml(T, type_info, writer),
            .auto => return Error.FlashError.ConfigError,
        }

        return aw.toOwnedSlice();
    }

    /// Generate JSON template
    fn generateJson(self: ConfigTemplate, comptime T: type, type_info: anytype, writer: anytype) !void {
        _ = self;
        _ = T;

        try writer.print("{{\n", .{});

        if (type_info == .@"struct") {
            inline for (type_info.@"struct".fields, 0..) |field, i| {
                if (i > 0) try writer.print(",\n", .{});
                try writer.print("  \"{s}\": ", .{field.name});

                switch (field.type) {
                    bool => try writer.print("false", .{}),
                    i32, i64, u32, u64 => try writer.print("0", .{}),
                    f32, f64 => try writer.print("0.0", .{}),
                    []const u8 => try writer.print("\"\"", .{}),
                    else => try writer.print("null", .{}),
                }
            }
        }

        try writer.print("\n}}\n", .{});
    }

    /// Generate TOML template
    fn generateToml(self: ConfigTemplate, comptime T: type, type_info: anytype, writer: anytype) !void {
        _ = self;
        _ = T;

        if (type_info == .@"struct") {
            inline for (type_info.@"struct".fields) |field| {
                try writer.print("{s} = ", .{field.name});

                switch (field.type) {
                    bool => try writer.print("false\n", .{}),
                    i32, i64, u32, u64 => try writer.print("0\n", .{}),
                    f32, f64 => try writer.print("0.0\n", .{}),
                    []const u8 => try writer.print("\"\"\n", .{}),
                    else => try writer.print("\"\" # unsupported type\n", .{}),
                }
            }
        }
    }

    /// Generate YAML template
    fn generateYaml(self: ConfigTemplate, comptime T: type, type_info: anytype, writer: anytype) !void {
        _ = self;
        _ = T;

        if (type_info == .@"struct") {
            inline for (type_info.@"struct".fields) |field| {
                try writer.print("{s}: ", .{field.name});

                switch (field.type) {
                    bool => try writer.print("false\n", .{}),
                    i32, i64, u32, u64 => try writer.print("0\n", .{}),
                    f32, f64 => try writer.print("0.0\n", .{}),
                    []const u8 => try writer.print("\"\"\n", .{}),
                    else => try writer.print("\"\" # unsupported type\n", .{}),
                }
            }
        }
    }
};

test "config parser JSON" {
    const allocator = std.testing.allocator;

    const Config = struct {
        name: []const u8 = "default",
        count: i32 = 0,
        debug: bool = false,
    };

    const json_content =
        \\{
        \\  "name": "test",
        \\  "count": 42,
        \\  "debug": true
        \\}
    ;

    const parser = ConfigParser.init(allocator);
    const config = try parser.parseContent(Config, json_content, .json);
    defer allocator.free(config.name);

    try std.testing.expectEqualStrings("test", config.name);
    try std.testing.expectEqual(@as(i32, 42), config.count);
    try std.testing.expectEqual(true, config.debug);
}

test "config merge" {
    const Config = struct {
        name: []const u8 = "default",
        count: i32 = 0,
        debug: bool = false,
    };

    const base = Config{
        .name = "base",
        .count = 10,
        .debug = false,
    };

    const override = Config{
        .name = "override",
        .count = 0, // Should not override (zero value)
        .debug = true,
    };

    const result = ConfigParser.merge(Config, base, override);

    try std.testing.expectEqualStrings("override", result.name);
    try std.testing.expectEqual(@as(i32, 10), result.count); // Should keep base value
    try std.testing.expectEqual(true, result.debug);
}

test "config merge keeps base when override is false" {
    const Config = struct {
        debug: bool = false,
    };

    const base = Config{ .debug = true };
    const override = Config{ .debug = false };

    const result = ConfigParser.merge(Config, base, override);
    try std.testing.expectEqual(true, result.debug);
}

test "config merge keeps base when override is zero" {
    const Config = struct {
        retries: i32 = 0,
    };

    const base = Config{ .retries = 3 };
    const override = Config{ .retries = 0 };

    const result = ConfigParser.merge(Config, base, override);
    try std.testing.expectEqual(@as(i32, 3), result.retries);
}

test "config merge keeps base when override is empty string" {
    const Config = struct {
        name: []const u8 = "",
    };

    const base = Config{ .name = "flash" };
    const override = Config{ .name = "" };

    const result = ConfigParser.merge(Config, base, override);
    try std.testing.expectEqualStrings("flash", result.name);
}

test "config mergeWithPresence allows false override" {
    const Config = struct {
        debug: bool = false,
    };

    const Presence = struct {
        debug: ConfigParser.FieldPresence,
    };

    const base = Config{ .debug = true };
    const override = Config{ .debug = false };
    const presence = Presence{ .debug = .present };

    const result = ConfigParser.mergeWithPresence(Config, base, override, presence);
    try std.testing.expectEqual(false, result.debug);
}

test "config mergeWithPresence allows zero override" {
    const Config = struct {
        retries: i32 = 0,
    };

    const Presence = struct {
        retries: ConfigParser.FieldPresence,
    };

    const base = Config{ .retries = 3 };
    const override = Config{ .retries = 0 };
    const presence = Presence{ .retries = .present };

    const result = ConfigParser.mergeWithPresence(Config, base, override, presence);
    try std.testing.expectEqual(@as(i32, 0), result.retries);
}

test "config mergeWithPresence allows empty string override" {
    const Config = struct {
        name: []const u8 = "",
    };

    const Presence = struct {
        name: ConfigParser.FieldPresence,
    };

    const base = Config{ .name = "flash" };
    const override = Config{ .name = "" };
    const presence = Presence{ .name = .present };

    const result = ConfigParser.mergeWithPresence(Config, base, override, presence);
    try std.testing.expectEqualStrings("", result.name);
}

test "config mergeWithPresence keeps base for missing fields" {
    const Config = struct {
        name: []const u8 = "",
        debug: bool = false,
    };

    const Presence = struct {
        name: ConfigParser.FieldPresence,
        debug: ConfigParser.FieldPresence,
    };

    const base = Config{ .name = "flash", .debug = true };
    const override = Config{ .name = "override", .debug = false };
    const presence = Presence{ .name = .present, .debug = .missing };

    const result = ConfigParser.mergeWithPresence(Config, base, override, presence);
    try std.testing.expectEqualStrings("override", result.name);
    try std.testing.expectEqual(true, result.debug);
}

test "config template generation" {
    const allocator = std.testing.allocator;

    const Config = struct {
        name: []const u8 = "default",
        count: i32 = 0,
        debug: bool = false,
    };

    const template = ConfigTemplate.init(allocator);
    const json_template = try template.generate(Config, .json);
    defer allocator.free(json_template);

    // Check that template contains expected fields
    try std.testing.expect(std.mem.indexOf(u8, json_template, "name") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_template, "count") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_template, "debug") != null);
}

test "TOML parsing with flare" {
    const allocator = std.testing.allocator;
    const parser = ConfigParser.init(allocator);

    const Config = struct {
        name: []const u8 = "default",
        count: i64 = 0,
        enabled: bool = false,
    };

    const toml_content =
        \\name = "test"
        \\count = 42
        \\enabled = true
    ;

    const config = try parser.parseContent(Config, toml_content, .toml);
    defer flare.freeDeserialized(Config, allocator, config);
    try std.testing.expectEqualStrings("test", config.name);
    try std.testing.expectEqual(@as(i64, 42), config.count);
    try std.testing.expectEqual(true, config.enabled);
}

test "YAML parsing returns UnsupportedConfigFormat" {
    const allocator = std.testing.allocator;
    const parser = ConfigParser.init(allocator);

    const Config = struct {
        name: []const u8 = "default",
    };

    const result = parser.parseContent(Config, "name: test", .yaml);
    try std.testing.expectError(Error.FlashError.UnsupportedConfigFormat, result);
}

test "TOML parsing with nested tables" {
    const allocator = std.testing.allocator;
    const parser = ConfigParser.init(allocator);

    const Database = struct {
        host: []const u8 = "localhost",
        port: i64 = 5432,
    };

    const Config = struct {
        name: []const u8 = "app",
        debug: bool = false,
        database: Database = .{},
    };

    const toml_content =
        \\name = "myapp"
        \\debug = true
        \\
        \\[database]
        \\host = "db.example.com"
        \\port = 3306
    ;

    const config = try parser.parseContent(Config, toml_content, .toml);
    defer flare.freeDeserialized(Config, allocator, config);
    try std.testing.expectEqualStrings("myapp", config.name);
    try std.testing.expectEqual(true, config.debug);
    try std.testing.expectEqualStrings("db.example.com", config.database.host);
    try std.testing.expectEqual(@as(i64, 3306), config.database.port);
}

test "TOML parsing with diagnostics returns parse context" {
    const allocator = std.testing.allocator;
    const parser = ConfigParser.init(allocator);

    const Config = struct {
        name: []const u8 = "default",
    };

    const result = parser.parseTomlWithDiagnostics(Config,
        \\name = "unterminated
    );

    switch (result) {
        .success => |config| {
            defer flare.freeDeserialized(Config, allocator, config);
            return error.TestUnexpectedResult;
        },
        .failure => |diag| {
            try std.testing.expect(diag.line >= 1);
            try std.testing.expect(diag.column >= 1);
            try std.testing.expect(std.mem.indexOf(u8, diag.message, "Unterminated string") != null);
        },
    }
}

test "TOML parsing with diagnostics returns typed config" {
    const allocator = std.testing.allocator;
    const parser = ConfigParser.init(allocator);

    const Config = struct {
        name: []const u8 = "default",
        enabled: bool = false,
    };

    const result = parser.parseTomlWithDiagnostics(Config,
        \\name = "flash"
        \\enabled = true
    );

    switch (result) {
        .success => |config| {
            defer flare.freeDeserialized(Config, allocator, config);
            try std.testing.expectEqualStrings("flash", config.name);
            try std.testing.expectEqual(true, config.enabled);
        },
        .failure => return error.TestUnexpectedResult,
    }
}

test "config hierarchy returns error for missing required source" {
    const allocator = std.testing.allocator;

    const Config = struct {
        name: []const u8 = "default",
    };

    const hierarchy = ConfigHierarchy.init(allocator, &.{
        ConfigHierarchy.ConfigSource.init(".zig-cache/tmp/flash-config-that-should-not-exist.toml", .toml).required(),
    });

    const result = hierarchy.parse(Config, .{});
    try std.testing.expectError(error.FileNotFound, result);
}
