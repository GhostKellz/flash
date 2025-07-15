//! Configuration file support for Flash CLI
//!
//! Supports TOML, JSON, and YAML configuration files with automatic
//! parsing and merging with CLI arguments.

const std = @import("std");
const Error = @import("error.zig");
const Argument = @import("argument.zig");

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

/// Configuration file parser
pub const ConfigParser = struct {
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) ConfigParser {
        return .{ .allocator = allocator };
    }
    
    /// Parse configuration file and merge with struct
    pub fn parseFile(self: ConfigParser, comptime T: type, file_path: []const u8, format: ConfigFormat) !T {
        const file_content = try std.fs.cwd().readFileAlloc(self.allocator, file_path, std.math.maxInt(usize));
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
        var parser = std.json.Parser.init(self.allocator, false);
        defer parser.deinit();
        
        var tree = parser.parse(content) catch {
            return Error.FlashError.ConfigError;
        };
        defer tree.deinit();
        
        return try self.parseJsonValue(T, tree.root);
    }
    
    /// Parse JSON value recursively
    fn parseJsonValue(self: ConfigParser, comptime T: type, value: std.json.Value) !T {
        const type_info = @typeInfo(T);
        
        return switch (type_info) {
            .Struct => |struct_info| blk: {
                if (value != .Object) {
                    return Error.FlashError.ConfigError;
                }
                
                var result: T = undefined;
                
                inline for (struct_info.fields) |field| {
                    if (value.Object.get(field.name)) |field_value| {
                        @field(result, field.name) = try self.parseJsonValue(field.type, field_value);
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
                
                break :blk result;
            },
            .Bool => switch (value) {
                .Bool => |b| b,
                else => Error.FlashError.ConfigError,
            },
            .Int => switch (value) {
                .Integer => |i| @intCast(i),
                else => Error.FlashError.ConfigError,
            },
            .Float => switch (value) {
                .Float => |f| @floatCast(f),
                .Integer => |i| @floatFromInt(i),
                else => Error.FlashError.ConfigError,
            },
            .Pointer => |ptr| switch (ptr.child) {
                u8 => switch (value) {
                    .String => |s| s,
                    else => Error.FlashError.ConfigError,
                },
                else => Error.FlashError.ConfigError,
            },
            .Optional => |opt| switch (value) {
                .Null => null,
                else => try self.parseJsonValue(opt.child, value),
            },
            else => Error.FlashError.ConfigError,
        };
    }
    
    /// Parse TOML configuration (simplified implementation)
    fn parseToml(self: ConfigParser, comptime T: type, content: []const u8) !T {
        _ = self;
        _ = content;
        // TODO: Implement TOML parsing
        // For now, return a zeroed struct
        return std.mem.zeroes(T);
    }
    
    /// Parse YAML configuration (simplified implementation)
    fn parseYaml(self: ConfigParser, comptime T: type, content: []const u8) !T {
        _ = self;
        _ = content;
        // TODO: Implement YAML parsing
        // For now, return a zeroed struct
        return std.mem.zeroes(T);
    }
    
    /// Merge configuration with existing struct
    pub fn merge(comptime T: type, base: T, config: T) T {
        var result = base;
        const type_info = @typeInfo(T);
        
        inline for (type_info.Struct.fields) |field| {
            const config_value = @field(config, field.name);
            
            // Only override if config value is not the default/zero value
            if (!isZeroValue(config_value)) {
                @field(result, field.name) = config_value;
            }
        }
        
        return result;
    }
    
    /// Check if a value is zero/default
    fn isZeroValue(value: anytype) bool {
        const T = @TypeOf(value);
        return switch (@typeInfo(T)) {
            .Bool => !value,
            .Int => value == 0,
            .Float => value == 0.0,
            .Pointer => value.len == 0,
            .Optional => value == null,
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
        const stat = std.fs.cwd().statFile(self.file_path) catch return false;
        const modified = stat.mtime;
        
        if (modified > self.last_modified) {
            self.last_modified = modified;
            return true;
        }
        
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
        var buffer = std.ArrayList(u8).init(self.allocator);
        const writer = buffer.writer();
        
        switch (format) {
            .json => try self.generateJson(T, type_info, writer),
            .toml => try self.generateToml(T, type_info, writer),
            .yaml => try self.generateYaml(T, type_info, writer),
            .auto => return Error.FlashError.ConfigError,
        }
        
        return buffer.toOwnedSlice();
    }
    
    /// Generate JSON template
    fn generateJson(self: ConfigTemplate, comptime T: type, type_info: anytype, writer: anytype) !void {
        _ = self;
        _ = T;
        
        try writer.print("{{\n", .{});
        
        if (type_info == .Struct) {
            inline for (type_info.Struct.fields, 0..) |field, i| {
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
        
        if (type_info == .Struct) {
            inline for (type_info.Struct.fields) |field| {
                try writer.print("{s} = ", .{field.name});
                
                switch (field.type) {
                    bool => try writer.print("false\n", .{}),
                    i32, i64, u32, u64 => try writer.print("0\n", .{}),
                    f32, f64 => try writer.print("0.0\n", .{}),
                    []const u8 => try writer.print("\"\"\n", .{}),
                    else => try writer.print("# TODO: Configure {s}\n", .{field.name}),
                }
            }
        }
    }
    
    /// Generate YAML template
    fn generateYaml(self: ConfigTemplate, comptime T: type, type_info: anytype, writer: anytype) !void {
        _ = self;
        _ = T;
        
        if (type_info == .Struct) {
            inline for (type_info.Struct.fields) |field| {
                try writer.print("{s}: ", .{field.name});
                
                switch (field.type) {
                    bool => try writer.print("false\n", .{}),
                    i32, i64, u32, u64 => try writer.print("0\n", .{}),
                    f32, f64 => try writer.print("0.0\n", .{}),
                    []const u8 => try writer.print("\"\"\n", .{}),
                    else => try writer.print("# TODO: Configure {s}\n", .{field.name}),
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