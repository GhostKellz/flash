const std = @import("std");
const flash = @import("flash");

// Comprehensive example showcasing all Flash features
// This demonstrates a complete AI CLI application like Zeke

/// Main application configuration with all Flash features
const ZekeConfig = struct {
    // Basic arguments
    message: ?[]const u8 = null,
    model: []const u8 = "gpt-4",
    
    // Multiple value support
    files: [][]const u8 = &[_][]const u8{},
    tags: [][]const u8 = &[_][]const u8{},
    
    // Typed arguments
    temperature: f32 = 0.7,
    max_tokens: i32 = 1000,
    timeout: i32 = 30,
    
    // Boolean flags
    verbose: bool = false,
    stream: bool = false,
    debug: bool = false,
    force: bool = false,
    
    // Optional fields
    output_file: ?[]const u8 = null,
    config_file: ?[]const u8 = null,
    api_key: ?[]const u8 = null,
    
    // Validation and custom types
    provider: ProviderType = .openai,
    format: OutputFormat = .text,
    
    // Use the derive macro for automatic implementation
    pub usingnamespace flash.derive(.{
        .help = true,
        .version = "1.0.0",
        .author = "Flash Team",
        .about = "A comprehensive AI CLI application built with Flash",
        .long_about = "Zeke is a powerful AI CLI tool that demonstrates all Flash features including " ++
                      "declarative configuration, validation, environment variables, secure storage, " ++
                      "and more. Perfect for interacting with multiple AI providers."
    });
    
    // Custom validation
    pub fn validate(self: ZekeConfig) !void {
        if (self.temperature < 0.0 or self.temperature > 2.0) {
            return error.InvalidTemperature;
        }
        
        if (self.max_tokens < 1 or self.max_tokens > 4096) {
            return error.InvalidMaxTokens;
        }
        
        if (self.timeout < 1 or self.timeout > 300) {
            return error.InvalidTimeout;
        }
    }
    
    // Environment variable configuration
    pub fn envPrefix() []const u8 {
        return "ZEKE_";
    }
};

/// AI provider types
const ProviderType = enum {
    openai,
    anthropic,
    cohere,
    local,
    
    pub fn toString(self: ProviderType) []const u8 {
        return switch (self) {
            .openai => "OpenAI",
            .anthropic => "Anthropic",
            .cohere => "Cohere",
            .local => "Local",
        };
    }
};

/// Output format types
const OutputFormat = enum {
    text,
    json,
    markdown,
    html,
    
    pub fn toString(self: OutputFormat) []const u8 {
        return switch (self) {
            .text => "Plain Text",
            .json => "JSON",
            .markdown => "Markdown",
            .html => "HTML",
        };
    }
};

/// Main application state
const ZekeApp = struct {
    allocator: std.mem.Allocator,
    config: ZekeConfig,
    secure_store: flash.Security.SecureStore,
    rate_limiter: flash.Security.RateLimiter,
    
    pub fn init(allocator: std.mem.Allocator, config: ZekeConfig) ZekeApp {
        return .{
            .allocator = allocator,
            .config = config,
            .secure_store = flash.Security.SecureStore.init(allocator, "zeke"),
            .rate_limiter = flash.Security.RateLimiter.init(allocator, 10.0, 20),
        };
    }
    
    pub fn run(self: *ZekeApp) !void {
        // Apply rate limiting
        try self.rate_limiter.acquire();
        
        // Display startup information
        if (self.config.verbose) {
            try self.displayStartupInfo();
        }
        
        // Handle different operations
        if (self.config.message) |message| {
            try self.handleChatMessage(message);
        } else {
            try self.handleInteractiveMode();
        }
    }
    
    fn displayStartupInfo(self: *ZekeApp) !void {
        const colors = flash.Colors;
        
        std.debug.print("🤖 {s}Zeke AI CLI{s} - Flash Powered\n", .{ colors.bold(), colors.reset() });
        std.debug.print("📡 Provider: {s}{s}{s}\n", .{ colors.cyan(), self.config.provider.toString(), colors.reset() });
        std.debug.print("🎯 Model: {s}{s}{s}\n", .{ colors.green(), self.config.model, colors.reset() });
        std.debug.print("🌡️  Temperature: {s}{d:.1}{s}\n", .{ colors.yellow(), self.config.temperature, colors.reset() });
        std.debug.print("📝 Max Tokens: {s}{d}{s}\n", .{ colors.blue(), self.config.max_tokens, colors.reset() });
        std.debug.print("⏰ Timeout: {s}{d}s{s}\n", .{ colors.magenta(), self.config.timeout, colors.reset() });
        
        if (self.config.files.len > 0) {
            std.debug.print("📁 Files: {s}", .{ colors.cyan() });
            for (self.config.files, 0..) |file, i| {
                if (i > 0) std.debug.print(", ", .{});
                std.debug.print("{s}", .{file});
            }
            std.debug.print("{s}\n", .{colors.reset()});
        }
        
        if (self.config.tags.len > 0) {
            std.debug.print("🏷️  Tags: {s}", .{ colors.purple() });
            for (self.config.tags, 0..) |tag, i| {
                if (i > 0) std.debug.print(", ", .{});
                std.debug.print("#{s}", .{tag});
            }
            std.debug.print("{s}\n", .{colors.reset()});
        }
        
        std.debug.print("\n", .{});
    }
    
    fn handleChatMessage(self: *ZekeApp, message: []const u8) !void {
        // Get API key from secure storage
        const api_key = self.config.api_key orelse blk: {
            const stored_key = try self.secure_store.retrieve("api_key");
            if (stored_key) |key| {
                break :blk key;
            } else {
                std.debug.print("⚠️  No API key found. Please set ZEKE_API_KEY or store it securely.\n", .{});
                return;
            }
        };
        defer if (self.config.api_key == null and api_key.len > 0) self.allocator.free(api_key);
        
        // Validate configuration
        try self.config.validate();
        
        // Display progress
        const progress = flash.Progress.ProgressBar.init(self.allocator, "Processing request...", 100);
        defer progress.deinit();
        
        progress.setProgress(10);
        
        // Simulate API call
        std.debug.print("🤖 Sending message to {s} ({s})...\n", .{ self.config.provider.toString(), self.config.model });
        
        if (self.config.stream) {
            std.debug.print("📡 Streaming response:\n", .{});
            try self.simulateStreamingResponse(message);
        } else {
            progress.setProgress(50);
            std.time.sleep(1 * std.time.ns_per_s); // Simulate processing
            progress.setProgress(100);
            
            try self.displayResponse(message);
        }
        
        // Save to output file if specified
        if (self.config.output_file) |output_file| {
            try self.saveToFile(output_file, message);
        }
    }
    
    fn simulateStreamingResponse(self: *ZekeApp, message: []const u8) !void {
        _ = self;
        
        const response = "This is a simulated streaming response to your message: \"" ++ "{s}" ++ "\". " ++
                        "In a real implementation, this would be connected to an actual AI API " ++
                        "and stream the response token by token.";
        
        const full_response = try std.fmt.allocPrint(self.allocator, response, .{message});
        defer self.allocator.free(full_response);
        
        // Simulate streaming by printing character by character
        for (full_response) |char| {
            std.debug.print("{c}", .{char});
            std.time.sleep(10 * std.time.ns_per_ms); // 10ms delay per character
        }
        std.debug.print("\n", .{});
    }
    
    fn displayResponse(self: *ZekeApp, message: []const u8) !void {
        const colors = flash.Colors;
        
        std.debug.print("{s}💬 Message:{s} {s}\n", .{ colors.bold(), colors.reset(), message });
        std.debug.print("{s}🤖 Response:{s} This is a simulated response from {s} using the {s} model.\n", .{ 
            colors.bold(), colors.reset(), self.config.provider.toString(), self.config.model 
        });
        std.debug.print("   The response would be formatted as {s} and include the processed ", .{self.config.format.toString()});
        std.debug.print("information with temperature {d:.1} and max tokens {d}.\n", .{ self.config.temperature, self.config.max_tokens });
    }
    
    fn saveToFile(self: *ZekeApp, filename: []const u8, content: []const u8) !void {
        try std.fs.cwd().writeFile(filename, content);
        std.debug.print("📄 Saved to: {s}\n", .{filename});
        
        if (self.config.verbose) {
            std.debug.print("   File size: {d} bytes\n", .{content.len});
        }
    }
    
    fn handleInteractiveMode(self: *ZekeApp) !void {
        const colors = flash.Colors;
        
        std.debug.print("{s}🚀 Interactive Mode{s}\n", .{ colors.bold(), colors.reset() });
        std.debug.print("Type your messages below. Use 'exit' to quit.\n\n", .{});
        
        const prompts = flash.Prompts;
        
        while (true) {
            const input = try prompts.prompt(self.allocator, "You: ");
            defer self.allocator.free(input);
            
            if (std.mem.eql(u8, input, "exit")) {
                std.debug.print("👋 Goodbye!\n", .{});
                break;
            }
            
            try self.handleChatMessage(input);
            std.debug.print("\n", .{});
        }
    }
};

/// Demonstration of configuration file support
fn demonstrateConfigSupport(allocator: std.mem.Allocator) !void {
    const colors = flash.Colors;
    
    std.debug.print("{s}📋 Configuration File Support{s}\n", .{ colors.bold(), colors.reset() });
    
    // Generate a configuration template
    const config_template = flash.Config.ConfigTemplate.init(allocator);
    const json_template = try config_template.generate(ZekeConfig, .json);
    defer allocator.free(json_template);
    
    std.debug.print("Generated JSON config template:\n{s}\n", .{json_template});
    
    // Save template to file
    try std.fs.cwd().writeFile("zeke_config.json", json_template);
    std.debug.print("📄 Template saved to zeke_config.json\n", .{});
}

/// Demonstration of environment variable integration
fn demonstrateEnvSupport(allocator: std.mem.Allocator) !void {
    const colors = flash.Colors;
    
    std.debug.print("{s}🌍 Environment Variable Support{s}\n", .{ colors.bold(), colors.reset() });
    
    // Create environment hierarchy
    const env_hierarchy = flash.Env.EnvHierarchy.init("ZEKE_");
    const env_config = try env_hierarchy.parseFromEnv(ZekeConfig, allocator);
    
    std.debug.print("Environment variables (with ZEKE_ prefix):\n", .{});
    std.debug.print("  Model: {s}\n", .{env_config.model});
    std.debug.print("  Temperature: {d:.1}\n", .{env_config.temperature});
    std.debug.print("  Verbose: {}\n", .{env_config.verbose});
    std.debug.print("  Debug: {}\n", .{env_config.debug});
}

/// Demonstration of security features
fn demonstrateSecuritySupport(allocator: std.mem.Allocator) !void {
    const colors = flash.Colors;
    
    std.debug.print("{s}🔐 Security Features{s}\n", .{ colors.bold(), colors.reset() });
    
    // Secure storage
    const secure_store = flash.Security.SecureStore.init(allocator, "zeke_demo");
    
    std.debug.print("📦 Storing API key securely...\n", .{});
    try secure_store.store("demo_key", "sk-demo-key-12345");
    
    std.debug.print("🔑 Retrieving API key...\n", .{});
    const retrieved_key = try secure_store.retrieve("demo_key");
    if (retrieved_key) |key| {
        defer allocator.free(key);
        std.debug.print("   Retrieved: {s}\n", .{key});
    }
    
    // Rate limiting
    var rate_limiter = flash.Security.RateLimiter.init(allocator, 5.0, 10);
    std.debug.print("⏱️  Rate limiting: 5 requests/second, burst of 10\n", .{});
    
    for (0..3) |i| {
        try rate_limiter.acquire();
        std.debug.print("   Request {d} processed\n", .{i + 1});
    }
    
    // Cleanup
    try secure_store.delete("demo_key");
}

/// Demonstration of validation features
fn demonstrateValidation(allocator: std.mem.Allocator) !void {
    const colors = flash.Colors;
    
    std.debug.print("{s}✅ Validation System{s}\n", .{ colors.bold(), colors.reset() });
    
    // Test built-in validators
    const validators = flash.Validators.Validators;
    
    std.debug.print("📧 Email validation:\n", .{});
    const email_value = flash.Argument.ArgValue{ .string = "test@example.com" };
    validators.email(email_value) catch |err| {
        std.debug.print("   Error: {}\n", .{err});
        return;
    };
    std.debug.print("   Valid email: {s}\n", .{email_value.asString()});
    
    std.debug.print("🔢 Range validation:\n", .{});
    const range_validator = validators.range(1, 100);
    const number_value = flash.Argument.ArgValue{ .int = 42 };
    range_validator(number_value) catch |err| {
        std.debug.print("   Error: {}\n", .{err});
        return;
    };
    std.debug.print("   Valid number: {d}\n", .{number_value.asInt()});
    
    // Test custom configuration validation
    const config = ZekeConfig{
        .temperature = 0.5,
        .max_tokens = 500,
        .timeout = 60,
    };
    
    std.debug.print("⚙️  Configuration validation:\n", .{});
    config.validate() catch |err| {
        std.debug.print("   Error: {}\n", .{err});
        return;
    };
    std.debug.print("   Configuration is valid!\n", .{});
    
    _ = allocator;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const colors = flash.Colors;
    
    // Display Flash banner
    std.debug.print("{s}⚡️ Flash CLI Framework - Comprehensive Example{s}\n", .{ colors.bold(), colors.reset() });
    std.debug.print("{s}Showcasing all implemented features{s}\n\n", .{ colors.dim(), colors.reset() });
    
    // Parse command line arguments with all features
    const args = try flash.parse(ZekeConfig, allocator);
    
    // Demonstrate configuration file support
    try demonstrateConfigSupport(allocator);
    std.debug.print("\n", .{});
    
    // Demonstrate environment variable support
    try demonstrateEnvSupport(allocator);
    std.debug.print("\n", .{});
    
    // Demonstrate security features
    try demonstrateSecuritySupport(allocator);
    std.debug.print("\n", .{});
    
    // Demonstrate validation system
    try demonstrateValidation(allocator);
    std.debug.print("\n", .{});
    
    // Create and run the main application
    var app = ZekeApp.init(allocator, args);
    try app.run();
}

// Example usage scenarios:
//
// Basic usage:
// ./zeke --message "Hello, world!" --model gpt-4 --temperature 0.8
//
// With files and tags:
// ./zeke --message "Analyze these files" --files "file1.txt,file2.txt" --tags "analysis,code"
//
// Streaming mode:
// ./zeke --message "Tell me a story" --stream --verbose
//
// Configuration file:
// ./zeke --config-file zeke_config.json --message "Hello"
//
// Environment variables:
// ZEKE_MODEL=gpt-4 ZEKE_TEMPERATURE=0.9 ZEKE_VERBOSE=true ./zeke --message "Hello"
//
// Interactive mode:
// ./zeke
//
// Help:
// ./zeke --help
//
// Version:
// ./zeke --version

test "comprehensive example compilation" {
    // This test ensures the comprehensive example compiles correctly
    const allocator = std.testing.allocator;
    
    const config = ZekeConfig{
        .message = "test message",
        .model = "gpt-4",
        .temperature = 0.7,
        .verbose = true,
    };
    
    try config.validate();
    
    var app = ZekeApp.init(allocator, config);
    _ = app;
    
    // Test environment prefix
    const prefix = ZekeConfig.envPrefix();
    try std.testing.expectEqualStrings("ZEKE_", prefix);
}

test "provider and format enums" {
    try std.testing.expectEqualStrings("OpenAI", ProviderType.openai.toString());
    try std.testing.expectEqualStrings("JSON", OutputFormat.json.toString());
}