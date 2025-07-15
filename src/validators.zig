//! Validation system for Flash CLI arguments
//!
//! Provides built-in validators and support for custom validation functions.

const std = @import("std");
const Argument = @import("argument.zig");
const Error = @import("error.zig");

/// Built-in validator functions
pub const Validators = struct {
    /// Validate that a string is not empty
    pub fn nonEmpty(value: Argument.ArgValue) Error.FlashError!void {
        const str = value.asString();
        if (str.len == 0) {
            return Error.FlashError.ValidationError;
        }
    }
    
    /// Validate that a number is within a range
    pub fn range(comptime min: i64, comptime max: i64) *const fn (Argument.ArgValue) Error.FlashError!void {
        return struct {
            fn validate(value: Argument.ArgValue) Error.FlashError!void {
                const num = value.asInt();
                if (num < min or num > max) {
                    return Error.FlashError.ValidationError;
                }
            }
        }.validate;
    }
    
    /// Validate that a float is within a range
    pub fn floatRange(comptime min: f64, comptime max: f64) *const fn (Argument.ArgValue) Error.FlashError!void {
        return struct {
            fn validate(value: Argument.ArgValue) Error.FlashError!void {
                const num = value.asFloat();
                if (num < min or num > max) {
                    return Error.FlashError.ValidationError;
                }
            }
        }.validate;
    }
    
    /// Validate that a string matches a regex pattern
    pub fn regex(comptime pattern: []const u8) *const fn (Argument.ArgValue) Error.FlashError!void {
        return struct {
            fn validate(value: Argument.ArgValue) Error.FlashError!void {
                const str = value.asString();
                // Simple pattern matching for now
                // TODO: Implement proper regex support
                if (std.mem.eql(u8, pattern, "email")) {
                    if (std.mem.indexOf(u8, str, "@") == null) {
                        return Error.FlashError.ValidationError;
                    }
                } else if (std.mem.eql(u8, pattern, "url")) {
                    if (!std.mem.startsWith(u8, str, "http://") and !std.mem.startsWith(u8, str, "https://")) {
                        return Error.FlashError.ValidationError;
                    }
                }
            }
        }.validate;
    }
    
    /// Validate that a string is one of the allowed values
    pub fn oneOf(comptime allowed: []const []const u8) *const fn (Argument.ArgValue) Error.FlashError!void {
        return struct {
            fn validate(value: Argument.ArgValue) Error.FlashError!void {
                const str = value.asString();
                for (allowed) |allowed_value| {
                    if (std.mem.eql(u8, str, allowed_value)) {
                        return;
                    }
                }
                return Error.FlashError.ValidationError;
            }
        }.validate;
    }
    
    /// Validate that a string has a minimum length
    pub fn minLength(comptime min: usize) *const fn (Argument.ArgValue) Error.FlashError!void {
        return struct {
            fn validate(value: Argument.ArgValue) Error.FlashError!void {
                const str = value.asString();
                if (str.len < min) {
                    return Error.FlashError.ValidationError;
                }
            }
        }.validate;
    }
    
    /// Validate that a string has a maximum length
    pub fn maxLength(comptime max: usize) *const fn (Argument.ArgValue) Error.FlashError!void {
        return struct {
            fn validate(value: Argument.ArgValue) Error.FlashError!void {
                const str = value.asString();
                if (str.len > max) {
                    return Error.FlashError.ValidationError;
                }
            }
        }.validate;
    }
    
    /// Validate that a file exists
    pub fn fileExists(value: Argument.ArgValue) Error.FlashError!void {
        const path = value.asString();
        const file = std.fs.cwd().openFile(path, .{}) catch {
            return Error.FlashError.ValidationError;
        };
        file.close();
    }
    
    /// Validate that a directory exists
    pub fn dirExists(value: Argument.ArgValue) Error.FlashError!void {
        const path = value.asString();
        const dir = std.fs.cwd().openDir(path, .{}) catch {
            return Error.FlashError.ValidationError;
        };
        dir.close();
    }
    
    /// Validate that a path is writable
    pub fn writable(value: Argument.ArgValue) Error.FlashError!void {
        const path = value.asString();
        const file = std.fs.cwd().createFile(path, .{}) catch {
            return Error.FlashError.ValidationError;
        };
        file.close();
        std.fs.cwd().deleteFile(path) catch {};
    }
    
    /// Validate that a port number is valid
    pub fn port(value: Argument.ArgValue) Error.FlashError!void {
        const num = value.asInt();
        if (num < 1 or num > 65535) {
            return Error.FlashError.ValidationError;
        }
    }
    
    /// Validate that a URL is valid
    pub fn url(value: Argument.ArgValue) Error.FlashError!void {
        const str = value.asString();
        if (!std.mem.startsWith(u8, str, "http://") and !std.mem.startsWith(u8, str, "https://")) {
            return Error.FlashError.ValidationError;
        }
        if (std.mem.indexOf(u8, str, "://") == null) {
            return Error.FlashError.ValidationError;
        }
    }
    
    /// Validate that an email address is valid
    pub fn email(value: Argument.ArgValue) Error.FlashError!void {
        const str = value.asString();
        const at_pos = std.mem.indexOf(u8, str, "@") orelse return Error.FlashError.ValidationError;
        const dot_pos = std.mem.lastIndexOf(u8, str, ".") orelse return Error.FlashError.ValidationError;
        
        if (at_pos == 0 or at_pos >= dot_pos or dot_pos == str.len - 1) {
            return Error.FlashError.ValidationError;
        }
    }
    
    /// Validate that a UUID is valid
    pub fn uuid(value: Argument.ArgValue) Error.FlashError!void {
        const str = value.asString();
        if (str.len != 36) {
            return Error.FlashError.ValidationError;
        }
        
        // Check UUID format: 8-4-4-4-12
        const expected_dashes = [_]usize{ 8, 13, 18, 23 };
        for (expected_dashes) |pos| {
            if (str[pos] != '-') {
                return Error.FlashError.ValidationError;
            }
        }
        
        // Check that all other characters are hex digits
        for (str, 0..) |char, i| {
            if (i == 8 or i == 13 or i == 18 or i == 23) continue;
            if (!std.ascii.isHex(char)) {
                return Error.FlashError.ValidationError;
            }
        }
    }
    
    /// Validate that a string is a valid JSON
    pub fn json(value: Argument.ArgValue) Error.FlashError!void {
        const str = value.asString();
        var parser = std.json.Parser.init(std.heap.page_allocator, false);
        defer parser.deinit();
        
        var tree = parser.parse(str) catch {
            return Error.FlashError.ValidationError;
        };
        defer tree.deinit();
    }
};

/// Validation configuration for arguments
pub const ValidationConfig = struct {
    required: bool = false,
    validator: ?*const fn (Argument.ArgValue) Error.FlashError!void = null,
    error_message: ?[]const u8 = null,
    
    pub fn withValidator(self: ValidationConfig, validator: *const fn (Argument.ArgValue) Error.FlashError!void) ValidationConfig {
        var config = self;
        config.validator = validator;
        return config;
    }
    
    pub fn withErrorMessage(self: ValidationConfig, message: []const u8) ValidationConfig {
        var config = self;
        config.error_message = message;
        return config;
    }
    
    pub fn setRequired(self: ValidationConfig) ValidationConfig {
        var config = self;
        config.required = true;
        return config;
    }
};

/// Cross-field validation for command structs
pub const CrossFieldValidator = struct {
    validate_fn: *const fn (anytype) Error.FlashError!void,
    error_message: []const u8,
    
    pub fn init(validate_fn: *const fn (anytype) Error.FlashError!void, error_message: []const u8) CrossFieldValidator {
        return .{
            .validate_fn = validate_fn,
            .error_message = error_message,
        };
    }
};

/// Validation result
pub const ValidationResult = struct {
    valid: bool,
    error_message: ?[]const u8 = null,
    
    pub fn success() ValidationResult {
        return .{ .valid = true };
    }
    
    pub fn failure(message: []const u8) ValidationResult {
        return .{ .valid = false, .error_message = message };
    }
};

/// Validate multiple arguments with cross-field validation
pub fn validateStruct(comptime T: type, instance: T, validators: []const CrossFieldValidator) !ValidationResult {
    for (validators) |validator| {
        validator.validate_fn(instance) catch {
            return ValidationResult.failure(validator.error_message);
        };
    }
    return ValidationResult.success();
}

/// Example cross-field validators
pub const CrossFieldValidators = struct {
    /// Validate that start_date is before end_date
    pub fn dateRange(comptime start_field: []const u8, comptime end_field: []const u8) *const fn (anytype) Error.FlashError!void {
        return struct {
            fn validate(instance: anytype) Error.FlashError!void {
                const start = @field(instance, start_field);
                const end = @field(instance, end_field);
                
                // Simple string comparison for now
                if (std.mem.order(u8, start, end) == .gt) {
                    return Error.FlashError.ValidationError;
                }
            }
        }.validate;
    }
    
    /// Validate that min_value is less than max_value
    pub fn minMaxRange(comptime min_field: []const u8, comptime max_field: []const u8) *const fn (anytype) Error.FlashError!void {
        return struct {
            fn validate(instance: anytype) Error.FlashError!void {
                const min = @field(instance, min_field);
                const max = @field(instance, max_field);
                
                if (min >= max) {
                    return Error.FlashError.ValidationError;
                }
            }
        }.validate;
    }
    
    /// Validate that at least one of the fields is present
    pub fn atLeastOne(comptime fields: []const []const u8) *const fn (anytype) Error.FlashError!void {
        return struct {
            fn validate(instance: anytype) Error.FlashError!void {
                inline for (fields) |field| {
                    const value = @field(instance, field);
                    if (value != null) {
                        return;
                    }
                }
                return Error.FlashError.ValidationError;
            }
        }.validate;
    }
    
    /// Validate that only one of the fields is present
    pub fn exactlyOne(comptime fields: []const []const u8) *const fn (anytype) Error.FlashError!void {
        return struct {
            fn validate(instance: anytype) Error.FlashError!void {
                var count: usize = 0;
                inline for (fields) |field| {
                    const value = @field(instance, field);
                    if (value != null) {
                        count += 1;
                    }
                }
                if (count != 1) {
                    return Error.FlashError.ValidationError;
                }
            }
        }.validate;
    }
};

test "built-in validators" {
    // Test non-empty validator
    try Validators.nonEmpty(Argument.ArgValue{ .string = "hello" });
    try std.testing.expectError(Error.FlashError.ValidationError, Validators.nonEmpty(Argument.ArgValue{ .string = "" }));
    
    // Test range validator
    const range_validator = Validators.range(1, 10);
    try range_validator(Argument.ArgValue{ .int = 5 });
    try std.testing.expectError(Error.FlashError.ValidationError, range_validator(Argument.ArgValue{ .int = 15 }));
    
    // Test oneOf validator
    const oneOf_validator = Validators.oneOf(&.{ "apple", "banana", "cherry" });
    try oneOf_validator(Argument.ArgValue{ .string = "apple" });
    try std.testing.expectError(Error.FlashError.ValidationError, oneOf_validator(Argument.ArgValue{ .string = "grape" }));
    
    // Test email validator
    try Validators.email(Argument.ArgValue{ .string = "test@example.com" });
    try std.testing.expectError(Error.FlashError.ValidationError, Validators.email(Argument.ArgValue{ .string = "invalid-email" }));
    
    // Test port validator
    try Validators.port(Argument.ArgValue{ .int = 8080 });
    try std.testing.expectError(Error.FlashError.ValidationError, Validators.port(Argument.ArgValue{ .int = 70000 }));
}

test "cross-field validation" {
    const TestStruct = struct {
        min_value: i32,
        max_value: i32,
        optional_field: ?[]const u8 = null,
    };
    
    const instance = TestStruct{
        .min_value = 5,
        .max_value = 10,
        .optional_field = "hello",
    };
    
    const validators = [_]CrossFieldValidator{
        CrossFieldValidator.init(
            CrossFieldValidators.minMaxRange("min_value", "max_value"),
            "min_value must be less than max_value"
        ),
    };
    
    const result = try validateStruct(TestStruct, instance, &validators);
    try std.testing.expectEqual(true, result.valid);
    
    // Test with invalid data
    const invalid_instance = TestStruct{
        .min_value = 15,
        .max_value = 10,
    };
    
    const invalid_result = try validateStruct(TestStruct, invalid_instance, &validators);
    try std.testing.expectEqual(false, invalid_result.valid);
}