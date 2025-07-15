# Flash Integration Guide for Zeke AI

**⚡ Lightning-Fast CLI Framework Integration**

This guide shows how to integrate Flash CLI framework into your Zeke AI application - a Claude Code-style terminal and code editor app for multiple AI model APIs.

## 🚀 Quick Start

### 1. Add Flash to Your Project

```zig
// build.zig.zon
.{
    .name = "zeke",
    .version = "1.0.0",
    .dependencies = .{
        .flash = .{
            .url = "https://github.com/your-org/flash/archive/main.tar.gz",
            .hash = "...",
        },
    },
}
```

```zig
// build.zig
const flash_dep = b.dependency("flash", .{
    .target = target,
    .optimize = optimize,
});
const flash = flash_dep.module("flash");

exe.root_module.addImport("flash", flash);
```

### 2. Define Your Zeke Command Structure

```zig
const std = @import("std");
const flash = @import("flash");

/// Main Zeke AI configuration - declarative and type-safe
const ZekeCommand = struct {
    // Core chat functionality
    chat: ?[]const u8 = null,
    message: ?[]const u8 = null,
    
    // AI model configuration
    model: []const u8 = "gpt-4",
    provider: Provider = .openai,
    temperature: f32 = 0.7,
    max_tokens: i32 = 2048,
    
    // File handling
    files: [][]const u8 = &.{},
    context_files: [][]const u8 = &.{},
    
    // Output options
    output: ?[]const u8 = null,
    format: OutputFormat = .markdown,
    
    // Behavior flags
    stream: bool = false,
    interactive: bool = false,
    verbose: bool = false,
    debug: bool = false,
    
    // Authentication
    api_key: ?[]const u8 = null,
    
    // Use Flash's derive macro for automatic CLI generation
    pub usingnamespace flash.derive(.{
        .help = true,
        .version = "1.0.0",
        .author = "Zeke Team",
        .about = "AI-powered code editor and terminal assistant",
        .long_about = "Zeke combines the power of multiple AI models with a lightning-fast " ++
                      "CLI interface. Write code, analyze files, and interact with AI models " ++
                      "seamlessly from your terminal.",
    });
    
    // Custom validation for AI-specific constraints
    pub fn validate(self: ZekeCommand) !void {
        if (self.temperature < 0.0 or self.temperature > 2.0) {
            return error.InvalidTemperature;
        }
        if (self.max_tokens < 1 or self.max_tokens > 8192) {
            return error.InvalidMaxTokens;
        }
    }
    
    // Environment variable prefix for configuration
    pub fn envPrefix() []const u8 {
        return "ZEKE_";
    }
};

const Provider = enum {
    openai,
    anthropic,
    cohere,
    local,
    ollama,
    
    pub fn apiEndpoint(self: Provider) []const u8 {
        return switch (self) {
            .openai => "https://api.openai.com/v1",
            .anthropic => "https://api.anthropic.com/v1",
            .cohere => "https://api.cohere.ai/v1",
            .local => "http://localhost:8080/v1",
            .ollama => "http://localhost:11434/api",
        };
    }
};

const OutputFormat = enum {
    markdown,
    json,
    plain,
    html,
    code,
};
```

### 3. Build Your Main Application

```zig
const ZekeApp = struct {
    allocator: std.mem.Allocator,
    config: ZekeCommand,
    secure_store: flash.Security.SecureStore,
    
    pub fn init(allocator: std.mem.Allocator) !ZekeApp {
        // Parse command line with Flash's declarative API
        const config = try flash.parse(ZekeCommand, allocator);
        
        return ZekeApp{
            .allocator = allocator,
            .config = config,
            .secure_store = flash.Security.SecureStore.init(allocator, "zeke"),
        };
    }
    
    pub fn run(self: *ZekeApp) !void {
        // Validate configuration
        try self.config.validate();
        
        // Choose operation mode
        if (self.config.interactive) {
            try self.runInteractive();
        } else if (self.config.chat) |message| {
            try self.runChat(message);
        } else if (self.config.files.len > 0) {
            try self.runFileAnalysis();
        } else {
            try self.runDefault();
        }
    }
    
    fn runChat(self: *ZekeApp, message: []const u8) !void {
        // Get API key from secure storage or environment
        const api_key = try self.getApiKey();
        defer if (api_key.len > 0) self.allocator.free(api_key);
        
        // Create AI client
        var client = try self.createAIClient(api_key);
        
        // Display progress
        const progress = flash.Progress.ProgressBar.init(self.allocator, "Processing...", 100);
        defer progress.deinit();
        
        if (self.config.stream) {
            try self.streamResponse(&client, message);
        } else {
            progress.setProgress(50);
            const response = try client.chat(message);
            progress.setProgress(100);
            
            try self.displayResponse(response);
        }
    }
    
    fn runInteractive(self: *ZekeApp) !void {
        const colors = flash.Colors;
        const prompts = flash.Prompts;
        
        std.debug.print("{s}🤖 Zeke AI Interactive Mode{s}\n", .{ colors.bold(), colors.reset() });
        std.debug.print("Model: {s}{s}{s} | Provider: {s}{s}{s}\n", .{
            colors.cyan(), self.config.model, colors.reset(),
            colors.green(), @tagName(self.config.provider), colors.reset()
        });
        std.debug.print("Type 'exit' to quit, 'help' for commands.\n\n", .{});
        
        while (true) {
            const input = try prompts.prompt(self.allocator, "zeke> ");
            defer self.allocator.free(input);
            
            if (std.mem.eql(u8, input, "exit")) break;
            if (std.mem.eql(u8, input, "help")) {
                try self.showInteractiveHelp();
                continue;
            }
            
            try self.processInteractiveCommand(input);
        }
    }
    
    fn getApiKey(self: *ZekeApp) ![]const u8 {
        // Try command line first
        if (self.config.api_key) |key| {
            return try self.allocator.dupe(u8, key);
        }
        
        // Try secure storage
        if (try self.secure_store.retrieve("api_key")) |key| {
            return key;
        }
        
        // Try environment variable
        if (std.process.getEnvVarOwned(self.allocator, "ZEKE_API_KEY")) |key| {
            return key;
        } else |_| {}
        
        // Prompt user to set up API key
        std.debug.print("❌ No API key found. Please set up authentication:\n");
        std.debug.print("   1. zeke auth --provider {s}\n", .{@tagName(self.config.provider)});
        std.debug.print("   2. export ZEKE_API_KEY=your_key_here\n");
        std.debug.print("   3. zeke --api-key your_key_here\n");
        
        return error.NoApiKey;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var app = try ZekeApp.init(allocator);
    try app.run();
}
```

## 🔧 Advanced Features

### Environment Variable Configuration

Flash automatically supports environment variables with the `ZEKE_` prefix:

```bash
# Set default model
export ZEKE_MODEL=gpt-4
export ZEKE_PROVIDER=openai
export ZEKE_TEMPERATURE=0.8
export ZEKE_VERBOSE=true

# API authentication
export ZEKE_API_KEY=your_api_key_here

# Run with environment config
zeke --chat "Hello, world!"
```

### Configuration File Support

Create a `zeke.json` configuration file:

```json
{
  "model": "gpt-4",
  "provider": "openai",
  "temperature": 0.7,
  "max_tokens": 2048,
  "stream": false,
  "format": "markdown"
}
```

Use with Flash's config system:

```zig
const config_parser = flash.Config.ConfigParser.init(allocator);
const file_config = try config_parser.parseFile(ZekeCommand, "zeke.json", .json);
const merged_config = flash.Config.ConfigParser.merge(ZekeCommand, cli_config, file_config);
```

### Secure Credential Storage

Store API keys securely across platforms:

```zig
// Store API key in system keychain
const secure_store = flash.Security.SecureStore.init(allocator, "zeke");
try secure_store.store("openai_key", api_key);

// Retrieve later
const stored_key = try secure_store.retrieve("openai_key");
```

### Input Validation

Add custom validators for AI-specific inputs:

```zig
const ModelValidator = struct {
    fn validateModel(value: flash.Argument.ArgValue) !void {
        const model = value.asString();
        const valid_models = [_][]const u8{ "gpt-4", "gpt-3.5-turbo", "claude-3", "claude-2" };
        
        for (valid_models) |valid_model| {
            if (std.mem.eql(u8, model, valid_model)) return;
        }
        
        return error.InvalidModel;
    }
};
```

## 🎨 User Experience Features

### Rich Terminal Output

```zig
const colors = flash.Colors;

// Status indicators
std.debug.print("{s}🤖 AI Response:{s}\n", .{ colors.bold(), colors.reset() });
std.debug.print("{s}⚡ Processing with {s}...{s}\n", .{ 
    colors.yellow(), self.config.model, colors.reset() 
});

// Progress bars for long operations
const progress = flash.Progress.ProgressBar.init(allocator, "Analyzing files...", file_count);
defer progress.deinit();

for (files) |file| {
    // Process file
    progress.increment();
}
```

### Interactive Prompts

```zig
const prompts = flash.Prompts;

// Get user input
const message = try prompts.prompt(allocator, "Enter your message: ");

// Confirmation dialogs
const should_continue = try prompts.confirm("Continue with this action?");

// Selection menus
const model = try prompts.select("Choose model:", &[_][]const u8{
    "gpt-4", "gpt-3.5-turbo", "claude-3"
});
```

## 📱 Subcommands for Different Operations

```zig
// Define subcommands
const ChatCommand = struct {
    message: []const u8,
    stream: bool = false,
    files: [][]const u8 = &.{},
    
    pub usingnamespace flash.derive(.{
        .about = "Chat with AI models",
    });
};

const CodeCommand = struct {
    file: []const u8,
    language: ?[]const u8 = null,
    explain: bool = false,
    fix: bool = false,
    
    pub usingnamespace flash.derive(.{
        .about = "Code analysis and generation",
    });
};

const AuthCommand = struct {
    provider: Provider,
    list: bool = false,
    remove: bool = false,
    
    pub usingnamespace flash.derive(.{
        .about = "Manage API authentication",
    });
};
```

## 🔄 Real-World Usage Examples

### Basic Chat
```bash
zeke chat "Explain async/await in Zig"
zeke --message "Write a HTTP server in Zig" --stream
```

### File Analysis
```bash
zeke code --file main.zig --explain
zeke --files "*.zig" --message "Review this code for bugs"
```

### Configuration
```bash
zeke config --model gpt-4 --temperature 0.8
zeke --config-file ~/.zeke.json
```

### Authentication
```bash
zeke auth --provider openai
zeke auth --list
```

## 🚀 Performance Benefits

Flash provides:
- **Zero-allocation parsing** for common cases
- **Compile-time validation** of command structures
- **Lightning-fast startup** (< 5ms typical)
- **Memory-efficient** argument handling
- **Async-ready** with zsync integration

## 🛡️ Security Features

- **Secure credential storage** using system keychains
- **Rate limiting** for API calls
- **Input validation** and sanitization
- **Environment variable** security
- **OAuth flow** handling for complex authentication

## 📚 Integration Checklist

- [ ] Add Flash dependency to `build.zig.zon`
- [ ] Define command structure with `flash.derive`
- [ ] Implement main application loop
- [ ] Add environment variable support
- [ ] Set up secure credential storage
- [ ] Add input validation
- [ ] Implement progress indicators
- [ ] Add interactive mode support
- [ ] Configure help and version info
- [ ] Test with multiple AI providers

## 🎯 Result

With Flash integration, Zeke AI becomes:
- **Lightning-fast** CLI with < 5ms startup
- **Type-safe** with compile-time validation
- **User-friendly** with rich terminal output
- **Secure** with proper credential management
- **Configurable** with multiple configuration sources
- **Extensible** with modular architecture

Perfect for a Claude Code-style AI assistant that's both powerful and delightful to use! ⚡🤖