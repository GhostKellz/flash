//! ⚡ Flash Advanced Validation Framework
//!
//! Enhanced validation system with async support, custom validators,
//! type-safe parsing, and sophisticated error handling matching clap/Cobra

const std = @import("std");
const zsync = @import("zsync");
const Argument = @import("argument.zig");
const Flag = @import("flag.zig");
const Context = @import("context.zig");
const Error = @import("error.zig");

/// Enhanced validation result with rich context
pub const AdvancedValidationResult = union(enum) {
    valid: ValidValue,
    invalid: AdvancedValidationError,

    pub fn isValid(self: AdvancedValidationResult) bool {
        return switch (self) {
            .valid => true,
            .invalid => false,
        };
    }

    pub fn getValue(self: AdvancedValidationResult) ?ValidValue {
        return switch (self) {
            .valid => |val| val,
            .invalid => null,
        };
    }

    pub fn getError(self: AdvancedValidationResult) ?AdvancedValidationError {
        return switch (self) {
            .valid => null,
            .invalid => |err| err,
        };
    }
};

/// Validated value with type information
pub const ValidValue = union(enum) {
    string: []const u8,
    int: i64,
    float: f64,
    bool: bool,
    path: std.fs.path,
    port: u16,
    email: []const u8,
    url: []const u8,
    json: []const u8,
    custom: []const u8,

    pub fn format(self: ValidValue, allocator: std.mem.Allocator) ![]u8 {
        return switch (self) {
            .string => |s| try allocator.dupe(u8, s),
            .int => |i| try std.fmt.allocPrint(allocator, "{d}", .{i}),
            .float => |f| try std.fmt.allocPrint(allocator, "{d}", .{f}),
            .bool => |b| try allocator.dupe(u8, if (b) "true" else "false"),
            .path => |p| try allocator.dupe(u8, p),
            .port => |p| try std.fmt.allocPrint(allocator, "{d}", .{p}),
            .email, .url, .json, .custom => |s| try allocator.dupe(u8, s),
        };
    }
};

/// Advanced validation error with suggestions and fixes
pub const AdvancedValidationError = struct {
    kind: ErrorKind,
    message: []const u8,
    suggestion: ?[]const u8 = null,
    expected_format: ?[]const u8 = null,
    provided_value: ?[]const u8 = null,
    similar_values: ?[]const []const u8 = null,
    help_text: ?[]const u8 = null,
    error_code: ?[]const u8 = null,

    pub const ErrorKind = enum {
        invalid_type,
        out_of_range,
        invalid_format,
        missing_required,
        conflicting_values,
        file_not_found,
        permission_denied,
        network_error,
        custom_error,
    };

    pub fn init(kind: ErrorKind, message: []const u8) AdvancedValidationError {
        return .{ .kind = kind, .message = message };
    }

    pub fn withSuggestion(self: AdvancedValidationError, suggestion: []const u8) AdvancedValidationError {
        var err = self;
        err.suggestion = suggestion;
        return err;
    }

    pub fn withFormat(self: AdvancedValidationError, format: []const u8) AdvancedValidationError {
        var err = self;
        err.expected_format = format;
        return err;
    }

    pub fn withSimilarValues(self: AdvancedValidationError, values: []const []const u8) AdvancedValidationError {
        var err = self;
        err.similar_values = values;
        return err;
    }

    pub fn withHelpText(self: AdvancedValidationError, help: []const u8) AdvancedValidationError {
        var err = self;
        err.help_text = help;
        return err;
    }

    pub fn printColored(self: AdvancedValidationError, writer: anytype, use_color: bool) !void {
        const red = if (use_color) "\x1b[31m" else "";
        const yellow = if (use_color) "\x1b[33m" else "";
        const blue = if (use_color) "\x1b[34m" else "";
        const reset = if (use_color) "\x1b[0m" else "";
        const bold = if (use_color) "\x1b[1m" else "";

        try writer.print("{s}{s}⚡ Validation Error:{s} {s}\n", .{ red, bold, reset, self.message });

        if (self.provided_value) |value| {
            try writer.print("{s}   Provided:{s} '{s}'\n", .{ yellow, reset, value });
        }

        if (self.expected_format) |format| {
            try writer.print("{s}   Expected:{s} {s}\n", .{ blue, reset, format });
        }

        if (self.similar_values) |similar| {
            try writer.print("{s}   Did you mean:{s} ", .{ blue, reset });
            for (similar, 0..) |val, i| {
                if (i > 0) try writer.print(", ");
                try writer.print("'{s}'", .{val});
            }
            try writer.print("\n", .{});
        }

        if (self.suggestion) |suggestion| {
            try writer.print("{s}   💡 Suggestion:{s} {s}\n", .{ yellow, reset, suggestion });
        }

        if (self.help_text) |help| {
            try writer.print("{s}   ℹ️  Help:{s} {s}\n", .{ blue, reset, help });
        }
    }
};

/// Advanced validator function signatures
pub const ValidatorFn = *const fn ([]const u8, std.mem.Allocator) AdvancedValidationResult;
pub const AsyncValidatorFn = *const fn ([]const u8, std.mem.Allocator) zsync.Future;
pub const TypedValidatorFn = fn (comptime T: type) *const fn ([]const u8, std.mem.Allocator) AdvancedValidationResult;

/// Port number validator (like clap's example)
pub fn portInRange(min_port: u16, max_port: u16) ValidatorFn {
    return struct {
        fn validate(input: []const u8, allocator: std.mem.Allocator) AdvancedValidationResult {
            _ = allocator;
            const port = std.fmt.parseInt(u16, input, 10) catch {
                return .{ .invalid = AdvancedValidationError.init(.invalid_type, "Invalid port number")
                    .withFormat("Number between 1 and 65535")
                    .withSuggestion("Enter a valid port number")
                    .withProvidedValue(input) };
            };

            if (port < min_port or port > max_port) {
                var buf: [256]u8 = undefined;
                const range_str = std.fmt.bufPrint(&buf, "Port between {d} and {d}", .{ min_port, max_port }) catch "Valid port range";

                return .{ .invalid = AdvancedValidationError.init(.out_of_range, "Port out of range")
                    .withFormat(range_str)
                    .withProvidedValue(input)
                    .withSuggestion("Choose a port within the valid range") };
            }

            return .{ .valid = .{ .port = port } };
        }
    }.validate;
}

/// Email validator with detailed error messages
pub fn emailValidator() ValidatorFn {
    return struct {
        fn validate(input: []const u8, allocator: std.mem.Allocator) AdvancedValidationResult {
            _ = allocator;

            // Basic email validation
            const at_pos = std.mem.indexOf(u8, input, "@") orelse {
                return .{ .invalid = AdvancedValidationError.init(.invalid_format, "Email missing @ symbol")
                    .withFormat("user@domain.com")
                    .withSuggestion("Add @ symbol between username and domain")
                    .withProvidedValue(input) };
            };

            if (at_pos == 0) {
                return .{ .invalid = AdvancedValidationError.init(.invalid_format, "Email missing username")
                    .withFormat("user@domain.com")
                    .withSuggestion("Add username before @ symbol")
                    .withProvidedValue(input) };
            }

            if (at_pos == input.len - 1) {
                return .{ .invalid = AdvancedValidationError.init(.invalid_format, "Email missing domain")
                    .withFormat("user@domain.com")
                    .withSuggestion("Add domain after @ symbol")
                    .withProvidedValue(input) };
            }

            const domain = input[at_pos + 1..];
            if (std.mem.indexOf(u8, domain, ".") == null) {
                return .{ .invalid = AdvancedValidationError.init(.invalid_format, "Domain missing extension")
                    .withFormat("user@domain.com")
                    .withSuggestion("Add domain extension (e.g., .com, .org)")
                    .withProvidedValue(input) };
            }

            return .{ .valid = .{ .email = input } };
        }
    }.validate;
}

/// File path validator with suggestions
pub fn fileValidator(must_exist: bool, extensions: ?[]const []const u8) ValidatorFn {
    return struct {
        fn validate(input: []const u8, allocator: std.mem.Allocator) AdvancedValidationResult {
            if (must_exist) {
                std.fs.cwd().access(input, .{}) catch |err| {
                    return switch (err) {
                        error.FileNotFound => .{ .invalid = AdvancedValidationError.init(.file_not_found, "File not found")
                            .withSuggestion("Check the file path and ensure the file exists")
                            .withProvidedValue(input)
                            .withHelpText("Use absolute path or ensure file is in current directory") },
                        error.AccessDenied => .{ .invalid = AdvancedValidationError.init(.permission_denied, "Permission denied")
                            .withSuggestion("Check file permissions or run with elevated privileges")
                            .withProvidedValue(input) },
                        else => .{ .invalid = AdvancedValidationError.init(.custom_error, "File access error")
                            .withProvidedValue(input) },
                    };
                };
            }

            if (extensions) |exts| {
                const file_ext = std.fs.path.extension(input);
                for (exts) |ext| {
                    if (std.mem.eql(u8, file_ext, ext)) {
                        return .{ .valid = .{ .path = input } };
                    }
                }

                // Create suggestion with valid extensions
                var buf: [512]u8 = undefined;
                var suggestion = std.fmt.bufPrint(&buf, "File must have extension: ", .{}) catch "Valid file extension required";
                for (exts, 0..) |ext, i| {
                    if (i > 0) {
                        suggestion = std.fmt.bufPrint(&buf, "{s}, ", .{suggestion}) catch suggestion;
                    }
                    suggestion = std.fmt.bufPrint(&buf, "{s}{s}", .{ suggestion, ext }) catch suggestion;
                }

                return .{ .invalid = AdvancedValidationError.init(.invalid_format, "Invalid file extension")
                    .withSuggestion(suggestion)
                    .withProvidedValue(input) };
            }

            return .{ .valid = .{ .path = input } };
        }
    }.validate;
}

/// URL validator with protocol checking
pub fn urlValidator(allowed_protocols: ?[]const []const u8) ValidatorFn {
    return struct {
        fn validate(input: []const u8, allocator: std.mem.Allocator) AdvancedValidationResult {
            _ = allocator;

            const protocols = allowed_protocols orelse &.{ "http", "https" };

            var valid_protocol = false;
            for (protocols) |protocol| {
                var buf: [64]u8 = undefined;
                const prefix = std.fmt.bufPrint(&buf, "{s}://", .{protocol}) catch continue;
                if (std.mem.startsWith(u8, input, prefix)) {
                    valid_protocol = true;
                    break;
                }
            }

            if (!valid_protocol) {
                var buf: [256]u8 = undefined;
                var suggestion = std.fmt.bufPrint(&buf, "URL must start with: ", .{}) catch "Valid protocol required";
                for (protocols, 0..) |protocol, i| {
                    if (i > 0) {
                        suggestion = std.fmt.bufPrint(&buf, "{s}, ", .{suggestion}) catch suggestion;
                    }
                    suggestion = std.fmt.bufPrint(&buf, "{s}{s}://", .{ suggestion, protocol }) catch suggestion;
                }

                return .{ .invalid = AdvancedValidationError.init(.invalid_format, "Invalid URL protocol")
                    .withSuggestion(suggestion)
                    .withProvidedValue(input) };
            }

            return .{ .valid = .{ .url = input } };
        }
    }.validate;
}

/// Choice validator with fuzzy matching (like Cobra's suggestions)
pub fn choiceValidator(choices: []const []const u8, case_sensitive: bool) ValidatorFn {
    return struct {
        fn validate(input: []const u8, allocator: std.mem.Allocator) AdvancedValidationResult {
            // Exact match first
            for (choices) |choice| {
                const matches = if (case_sensitive)
                    std.mem.eql(u8, input, choice)
                else
                    std.ascii.eqlIgnoreCase(input, choice);

                if (matches) {
                    return .{ .valid = .{ .string = input } };
                }
            }

            // Find similar choices using Levenshtein distance
            var similar = std.ArrayList([]const u8).init(allocator);
            defer similar.deinit();

            for (choices) |choice| {
                const distance = levenshteinDistance(input, choice);
                // If distance is small relative to choice length, consider it similar
                if (distance <= choice.len / 3 + 1) {
                    similar.append(choice) catch continue;
                }
            }

            var buf: [512]u8 = undefined;
            var all_choices = std.fmt.bufPrint(&buf, "Valid choices: ", .{}) catch "Valid choices";
            for (choices, 0..) |choice, i| {
                if (i > 0) {
                    all_choices = std.fmt.bufPrint(&buf, "{s}, ", .{all_choices}) catch all_choices;
                }
                all_choices = std.fmt.bufPrint(&buf, "{s}'{s}'", .{ all_choices, choice }) catch all_choices;
            }

            var error = AdvancedValidationError.init(.invalid_format, "Invalid choice")
                .withFormat(all_choices)
                .withProvidedValue(input);

            if (similar.items.len > 0) {
                error = error.withSimilarValues(similar.items);
            }

            return .{ .invalid = error };
        }
    }.validate;
}

/// JSON validator
pub fn jsonValidator() ValidatorFn {
    return struct {
        fn validate(input: []const u8, allocator: std.mem.Allocator) AdvancedValidationResult {
            std.json.parseFromSlice(std.json.Value, allocator, input, .{}) catch |err| {
                return switch (err) {
                    error.InvalidCharacter => .{ .invalid = AdvancedValidationError.init(.invalid_format, "Invalid JSON character")
                        .withSuggestion("Check for unescaped quotes or invalid characters")
                        .withFormat("Valid JSON string")
                        .withProvidedValue(input) },
                    error.UnexpectedToken => .{ .invalid = AdvancedValidationError.init(.invalid_format, "Unexpected JSON token")
                        .withSuggestion("Check JSON syntax - missing commas, brackets, or quotes")
                        .withFormat("Valid JSON string")
                        .withProvidedValue(input) },
                    else => .{ .invalid = AdvancedValidationError.init(.invalid_format, "Invalid JSON")
                        .withSuggestion("Check JSON syntax")
                        .withProvidedValue(input) },
                };
            };

            return .{ .valid = .{ .json = input } };
        }
    }.validate;
}

/// Async file validator (checks file remotely or with async I/O)
pub fn asyncFileValidator(check_remote: bool) AsyncValidatorFn {
    return struct {
        fn validate(input: []const u8, allocator: std.mem.Allocator) zsync.Future {
            _ = input;
            _ = allocator;
            _ = check_remote;
            // This would be implemented with actual async I/O operations
            // For now, return a mock future
            return zsync.Future.init();
        }
    }.validate;
}

/// Typed validator builder
pub fn TypedValidator(comptime T: type) type {
    return struct {
        pub fn range(min: T, max: T) ValidatorFn {
            return struct {
                fn validate(input: []const u8, allocator: std.mem.Allocator) AdvancedValidationResult {
                    _ = allocator;
                    const value = switch (T) {
                        i8, i16, i32, i64, isize => std.fmt.parseInt(T, input, 10) catch {
                            return .{ .invalid = AdvancedValidationError.init(.invalid_type, "Invalid integer")
                                .withFormat("Integer number")
                                .withProvidedValue(input) };
                        },
                        u8, u16, u32, u64, usize => std.fmt.parseUnsigned(T, input, 10) catch {
                            return .{ .invalid = AdvancedValidationError.init(.invalid_type, "Invalid unsigned integer")
                                .withFormat("Positive integer")
                                .withProvidedValue(input) };
                        },
                        f32, f64 => std.fmt.parseFloat(T, input) catch {
                            return .{ .invalid = AdvancedValidationError.init(.invalid_type, "Invalid float")
                                .withFormat("Decimal number")
                                .withProvidedValue(input) };
                        },
                        else => @compileError("Unsupported type for range validator"),
                    };

                    if (value < min or value > max) {
                        var buf: [256]u8 = undefined;
                        const range_str = std.fmt.bufPrint(&buf, "Between {any} and {any}", .{ min, max }) catch "Valid range";

                        return .{ .invalid = AdvancedValidationError.init(.out_of_range, "Value out of range")
                            .withFormat(range_str)
                            .withProvidedValue(input) };
                    }

                    return switch (T) {
                        i8, i16, i32, i64, isize => .{ .valid = .{ .int = @intCast(value) } },
                        u8, u16, u32, u64, usize => .{ .valid = .{ .int = @intCast(value) } },
                        f32, f64 => .{ .valid = .{ .float = @floatCast(value) } },
                        else => unreachable,
                    };
                }
            }.validate;
        }
    };
}

/// Levenshtein distance for fuzzy matching
fn levenshteinDistance(a: []const u8, b: []const u8) usize {
    if (a.len == 0) return b.len;
    if (b.len == 0) return a.len;

    var matrix = std.heap.page_allocator.alloc([]usize, a.len + 1) catch return std.math.maxInt(usize);
    defer std.heap.page_allocator.free(matrix);

    for (matrix, 0..) |*row, i| {
        row.* = std.heap.page_allocator.alloc(usize, b.len + 1) catch return std.math.maxInt(usize);
        defer std.heap.page_allocator.free(row.*);
        row.*[0] = i;
    }

    for (0..b.len + 1) |j| {
        matrix[0][j] = j;
    }

    for (1..a.len + 1) |i| {
        for (1..b.len + 1) |j| {
            const cost: usize = if (a[i - 1] == b[j - 1]) 0 else 1;
            matrix[i][j] = @min(
                @min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1),
                matrix[i - 1][j - 1] + cost
            );
        }
    }

    return matrix[a.len][b.len];
}

/// Validation chain for combining multiple validators
pub const ValidationChain = struct {
    validators: std.ArrayList(ValidatorFn),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ValidationChain {
        return .{
            .validators = std.ArrayList(ValidatorFn).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ValidationChain) void {
        self.validators.deinit();
    }

    pub fn add(self: *ValidationChain, validator: ValidatorFn) !void {
        try self.validators.append(validator);
    }

    pub fn validate(self: ValidationChain, input: []const u8) AdvancedValidationResult {
        for (self.validators.items) |validator| {
            const result = validator(input, self.allocator);
            if (!result.isValid()) {
                return result;
            }
        }
        return .{ .valid = .{ .string = input } };
    }
};

// Tests
test "port validator" {
    const allocator = std.testing.allocator;
    const validator = portInRange(1024, 8080);

    const valid_result = validator("3000", allocator);
    try std.testing.expect(valid_result.isValid());

    const invalid_result = validator("100", allocator);
    try std.testing.expect(!invalid_result.isValid());
}

test "email validator" {
    const allocator = std.testing.allocator;
    const validator = emailValidator();

    const valid_result = validator("test@example.com", allocator);
    try std.testing.expect(valid_result.isValid());

    const invalid_result = validator("not-an-email", allocator);
    try std.testing.expect(!invalid_result.isValid());
}

test "choice validator with fuzzy matching" {
    const allocator = std.testing.allocator;
    const choices = &.{ "build", "test", "deploy", "clean" };
    const validator = choiceValidator(choices, true);

    const valid_result = validator("build", allocator);
    try std.testing.expect(valid_result.isValid());

    const invalid_result = validator("bild", allocator);
    try std.testing.expect(!invalid_result.isValid());
    // Should suggest "build" as similar
}

test "typed validator" {
    const allocator = std.testing.allocator;
    const validator = TypedValidator(u16).range(1, 100);

    const valid_result = validator("50", allocator);
    try std.testing.expect(valid_result.isValid());

    const invalid_result = validator("200", allocator);
    try std.testing.expect(!invalid_result.isValid());
}

test "validation chain" {
    const allocator = std.testing.allocator;
    var chain = ValidationChain.init(allocator);
    defer chain.deinit();

    try chain.add(portInRange(1000, 9000));

    const result = chain.validate("8080");
    try std.testing.expect(result.isValid());
}