//! ⚡ Flash Argument Validation
//!
//! Provides custom validators and enhanced error context for CLI arguments

const std = @import("std");
const Argument = @import("argument.zig");
const Error = @import("error.zig");

/// Validation result
pub const ValidationResult = union(enum) {
    valid,
    invalid: ValidationError,
    
    pub fn isValid(self: ValidationResult) bool {
        return switch (self) {
            .valid => true,
            .invalid => false,
        };
    }
    
    pub fn getError(self: ValidationResult) ?ValidationError {
        return switch (self) {
            .valid => null,
            .invalid => |err| err,
        };
    }
};

/// Validation error with detailed context
pub const ValidationError = struct {
    message: []const u8,
    suggestion: ?[]const u8 = null,
    expected_format: ?[]const u8 = null,
    provided_value: ?[]const u8 = null,
    
    pub fn init(message: []const u8) ValidationError {
        return .{ .message = message };
    }
    
    pub fn withSuggestion(self: ValidationError, suggestion: []const u8) ValidationError {
        var err = self;
        err.suggestion = suggestion;
        return err;
    }
    
    pub fn withFormat(self: ValidationError, format: []const u8) ValidationError {
        var err = self;
        err.expected_format = format;
        return err;
    }
    
    pub fn withProvidedValue(self: ValidationError, value: []const u8) ValidationError {
        var err = self;
        err.provided_value = value;
        return err;
    }
    
    pub fn print(self: ValidationError, writer: anytype) !void {
        try writer.print("⚡ Validation Error: {s}\n", .{self.message});
        
        if (self.provided_value) |value| {
            try writer.print("   Provided: '{s}'\n", .{value});
        }
        
        if (self.expected_format) |format| {
            try writer.print("   Expected: {s}\n", .{format});
        }
        
        if (self.suggestion) |suggestion| {
            try writer.print("   💡 Suggestion: {s}\n", .{suggestion});
        }
    }
};

/// Validator function signature
pub const ValidatorFn = *const fn (Argument.ArgValue) ValidationResult;

/// Common validators
pub const Validators = struct {
    /// Validate string length
    pub fn stringLength(min: ?usize, max: ?usize) ValidatorFn {
        return struct {
            fn validate(value: Argument.ArgValue) ValidationResult {
                const str = value.asString();
                
                if (min) |min_len| {
                    if (str.len < min_len) {
                        return .{ .invalid = ValidationError.init("String too short")
                            .withFormat(if (max) |max_len| 
                                std.fmt.allocPrint(std.heap.page_allocator, "Length between {d} and {d} characters", .{min_len, max_len}) catch "Valid length range"
                            else 
                                std.fmt.allocPrint(std.heap.page_allocator, "At least {d} characters", .{min_len}) catch "Minimum length")
                            .withProvidedValue(str) };
                    }
                }
                
                if (max) |max_len| {
                    if (str.len > max_len) {
                        return .{ .invalid = ValidationError.init("String too long")
                            .withFormat(if (min) |min_len|
                                std.fmt.allocPrint(std.heap.page_allocator, "Length between {d} and {d} characters", .{min_len, max_len}) catch "Valid length range"
                            else
                                std.fmt.allocPrint(std.heap.page_allocator, "At most {d} characters", .{max_len}) catch "Maximum length")
                            .withProvidedValue(str) };
                    }
                }
                
                return .valid;
            }
        }.validate;
    }
    
    /// Validate number range
    pub fn numberRange(min: ?i64, max: ?i64) ValidatorFn {
        return struct {
            fn validate(value: Argument.ArgValue) ValidationResult {
                const num = value.asInt();
                
                if (min) |min_val| {
                    if (num < min_val) {
                        return .{ .invalid = ValidationError.init("Number too small")
                            .withFormat(if (max) |max_val|
                                std.fmt.allocPrint(std.heap.page_allocator, "Between {d} and {d}", .{min_val, max_val}) catch "Valid range"
                            else
                                std.fmt.allocPrint(std.heap.page_allocator, "At least {d}", .{min_val}) catch "Minimum value")
                            .withProvidedValue(std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{num}) catch "invalid") };
                    }
                }
                
                if (max) |max_val| {
                    if (num > max_val) {
                        return .{ .invalid = ValidationError.init("Number too large")
                            .withFormat(if (min) |min_val|
                                std.fmt.allocPrint(std.heap.page_allocator, "Between {d} and {d}", .{min_val, max_val}) catch "Valid range"
                            else
                                std.fmt.allocPrint(std.heap.page_allocator, "At most {d}", .{max_val}) catch "Maximum value")
                            .withProvidedValue(std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{num}) catch "invalid") };
                    }
                }
                
                return .valid;
            }
        }.validate;
    }
    
    /// Validate email format
    pub fn email() ValidatorFn {
        return struct {
            fn validate(value: Argument.ArgValue) ValidationResult {
                const str = value.asString();
                
                if (std.mem.indexOf(u8, str, "@") == null) {
                    return .{ .invalid = ValidationError.init("Invalid email format")
                        .withFormat("user@domain.com")
                        .withSuggestion("Include @ symbol")
                        .withProvidedValue(str) };
                }
                
                if (std.mem.indexOf(u8, str, ".") == null) {
                    return .{ .invalid = ValidationError.init("Invalid email format")
                        .withFormat("user@domain.com")
                        .withSuggestion("Include domain extension")
                        .withProvidedValue(str) };
                }
                
                return .valid;
            }
        }.validate;
    }
    
    /// Validate URL format
    pub fn url() ValidatorFn {
        return struct {
            fn validate(value: Argument.ArgValue) ValidationResult {
                const str = value.asString();
                
                if (!std.mem.startsWith(u8, str, "http://") and !std.mem.startsWith(u8, str, "https://")) {
                    return .{ .invalid = ValidationError.init("Invalid URL format")
                        .withFormat("https://example.com")
                        .withSuggestion("URL must start with http:// or https://")
                        .withProvidedValue(str) };
                }
                
                return .valid;
            }
        }.validate;
    }
    
    /// Validate file exists
    pub fn fileExists() ValidatorFn {
        return struct {
            fn validate(value: Argument.ArgValue) ValidationResult {
                const path = value.asString();
                
                std.fs.cwd().access(path, .{}) catch {
                    return .{ .invalid = ValidationError.init("File does not exist")
                        .withSuggestion("Check the file path and ensure the file exists")
                        .withProvidedValue(path) };
                };
                
                return .valid;
            }
        }.validate;
    }
    
    /// Validate one of allowed values
    pub fn oneOf(allowed: []const []const u8) ValidatorFn {
        return struct {
            fn validate(value: Argument.ArgValue) ValidationResult {
                const str = value.asString();
                
                for (allowed) |allowed_value| {
                    if (std.mem.eql(u8, str, allowed_value)) {
                        return .valid;
                    }
                }
                
                // Create suggestion string
                var suggestion_buf: [1024]u8 = undefined;
                var suggestion = std.fmt.bufPrint(&suggestion_buf, "Must be one of: ", .{}) catch "Invalid choice";
                for (allowed, 0..) |choice, i| {
                    if (i > 0) {
                        suggestion = std.fmt.bufPrint(&suggestion_buf, "{s}, ", .{suggestion}) catch suggestion;
                    }
                    suggestion = std.fmt.bufPrint(&suggestion_buf, "{s}{s}", .{suggestion, choice}) catch suggestion;
                }
                
                return .{ .invalid = ValidationError.init("Invalid choice")
                    .withSuggestion(suggestion)
                    .withProvidedValue(str) };
            }
        }.validate;
    }
    
    /// Validate regex pattern
    pub fn regex(pattern: []const u8) ValidatorFn {
        return struct {
            fn validate(value: Argument.ArgValue) ValidationResult {
                const str = value.asString();
                _ = pattern; // In a real implementation, would use regex library
                
                // Simple validation for demo - just check if it's not empty
                if (str.len == 0) {
                    return .{ .invalid = ValidationError.init("Value cannot be empty")
                        .withFormat("Non-empty string matching pattern")
                        .withProvidedValue(str) };
                }
                
                return .valid;
            }
        }.validate;
    }
};

/// Enhanced argument with validation
pub const ValidatedArgument = struct {
    base: Argument.Argument,
    validators: []const ValidatorFn,
    
    pub fn init(name: []const u8, config: Argument.ArgumentConfig, validators: []const ValidatorFn) ValidatedArgument {
        return .{
            .base = Argument.Argument.init(name, config),
            .validators = validators,
        };
    }
    
    /// Validate the argument value
    pub fn validate(self: ValidatedArgument, value: Argument.ArgValue) ValidationResult {
        for (self.validators) |validator| {
            const result = validator(value);
            if (!result.isValid()) {
                return result;
            }
        }
        return .valid;
    }
    
    /// Parse and validate value
    pub fn parseAndValidate(self: ValidatedArgument, allocator: std.mem.Allocator, input: []const u8) Error.FlashError!Argument.ArgValue {
        const value = try self.base.parseValue(allocator, input);
        
        const validation_result = self.validate(value);
        if (!validation_result.isValid()) {
            if (validation_result.getError()) |err| {
                std.debug.print("", .{});
                err.print(std.io.getStdErr().writer()) catch {};
            }
            return Error.FlashError.ValidationError;
        }
        
        return value;
    }
};

test "string length validator" {
    const validator = Validators.stringLength(3, 10);
    
    const valid_value = Argument.ArgValue{ .string = "hello" };
    const result = validator(valid_value);
    try std.testing.expect(result.isValid());
    
    const too_short = Argument.ArgValue{ .string = "hi" };
    const short_result = validator(too_short);
    try std.testing.expect(!short_result.isValid());
}

test "number range validator" {
    const validator = Validators.numberRange(1, 100);
    
    const valid_value = Argument.ArgValue{ .int = 50 };
    const result = validator(valid_value);
    try std.testing.expect(result.isValid());
    
    const too_small = Argument.ArgValue{ .int = 0 };
    const small_result = validator(too_small);
    try std.testing.expect(!small_result.isValid());
}

test "email validator" {
    const validator = Validators.email();
    
    const valid_email = Argument.ArgValue{ .string = "test@example.com" };
    const result = validator(valid_email);
    try std.testing.expect(result.isValid());
    
    const invalid_email = Argument.ArgValue{ .string = "not-an-email" };
    const invalid_result = validator(invalid_email);
    try std.testing.expect(!invalid_result.isValid());
}