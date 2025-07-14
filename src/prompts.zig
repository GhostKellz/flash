//! ⚡ Flash Interactive Prompts
//!
//! Provides interactive prompts for missing arguments, passwords, selections, and confirmations

const std = @import("std");
const Argument = @import("argument.zig");

pub const PromptType = enum {
    text,
    password,
    confirm,
    select,
    multiselect,
};

pub const PromptConfig = struct {
    prompt_type: PromptType = .text,
    message: []const u8,
    default_value: ?[]const u8 = null,
    choices: []const []const u8 = &.{},
    required: bool = true,
    mask_char: u8 = '*',
    
    pub fn text(message: []const u8) PromptConfig {
        return .{ .prompt_type = .text, .message = message };
    }
    
    pub fn password(message: []const u8) PromptConfig {
        return .{ .prompt_type = .password, .message = message };
    }
    
    pub fn confirm(message: []const u8) PromptConfig {
        return .{ .prompt_type = .confirm, .message = message };
    }
    
    pub fn select(message: []const u8, choices: []const []const u8) PromptConfig {
        return .{ .prompt_type = .select, .message = message, .choices = choices };
    }
    
    pub fn withDefault(self: PromptConfig, default: []const u8) PromptConfig {
        var config = self;
        config.default_value = default;
        return config;
    }
    
    pub fn optional(self: PromptConfig) PromptConfig {
        var config = self;
        config.required = false;
        return config;
    }
};

pub const PrompterConfig = struct {
    use_colors: bool = true,
    prompt_prefix: []const u8 = "⚡",
    success_prefix: []const u8 = "✅",
    error_prefix: []const u8 = "❌",
    
    pub fn noColors(self: PrompterConfig) PrompterConfig {
        var config = self;
        config.use_colors = false;
        return config;
    }
};

pub const Prompter = struct {
    allocator: std.mem.Allocator,
    config: PrompterConfig,
    stdin: std.fs.File.Reader,
    stdout: std.fs.File,
    
    pub fn init(allocator: std.mem.Allocator, config: PrompterConfig) Prompter {
        return .{
            .allocator = allocator,
            .config = config,
            .stdin = std.io.getStdIn().reader(),
            .stdout = std.fs.File.stdout(),
        };
    }
    
    /// Prompt for a text input
    pub fn promptText(self: Prompter, prompt_config: PromptConfig) ![]u8 {
        while (true) {
            try self.printPrompt(prompt_config.message, prompt_config.default_value);
            
            const input = try self.readLine();
            defer self.allocator.free(input);
            
            const trimmed = std.mem.trim(u8, input, " \t\n\r");
            
            if (trimmed.len == 0) {
                if (prompt_config.default_value) |default| {
                    return self.allocator.dupe(u8, default);
                } else if (!prompt_config.required) {
                    return self.allocator.dupe(u8, "");
                } else {
                    try self.printError("Input is required!");
                    continue;
                }
            }
            
            return self.allocator.dupe(u8, trimmed);
        }
    }
    
    /// Prompt for a password (hidden input)
    pub fn promptPassword(self: Prompter, prompt_config: PromptConfig) ![]u8 {
        try self.printPrompt(prompt_config.message, null);
        
        // Simple password input (in a real implementation, this would disable echo)
        std.debug.print("(Password input - characters will be visible in this demo)\n", .{});
        const input = try self.readLine();
        defer self.allocator.free(input);
        
        const trimmed = std.mem.trim(u8, input, " \t\n\r");
        
        if (trimmed.len == 0 and prompt_config.required) {
            try self.printError("Password is required!");
            return self.promptPassword(prompt_config);
        }
        
        return self.allocator.dupe(u8, trimmed);
    }
    
    /// Prompt for confirmation (y/n)
    pub fn promptConfirm(self: Prompter, prompt_config: PromptConfig) !bool {
        const default_str = if (prompt_config.default_value) |d| d else "n";
        const prompt_msg = try std.fmt.allocPrint(self.allocator, "{s} (y/n)", .{prompt_config.message});
        defer self.allocator.free(prompt_msg);
        
        while (true) {
            try self.printPrompt(prompt_msg, default_str);
            
            const input = try self.readLine();
            defer self.allocator.free(input);
            
            const trimmed = std.mem.trim(u8, input, " \t\n\r");
            
            if (trimmed.len == 0 and prompt_config.default_value != null) {
                return std.mem.eql(u8, default_str, "y") or std.mem.eql(u8, default_str, "yes");
            }
            
            if (std.mem.eql(u8, trimmed, "y") or std.mem.eql(u8, trimmed, "yes")) {
                return true;
            } else if (std.mem.eql(u8, trimmed, "n") or std.mem.eql(u8, trimmed, "no")) {
                return false;
            } else {
                try self.printError("Please enter 'y' or 'n'");
                continue;
            }
        }
    }
    
    /// Prompt for selection from choices
    pub fn promptSelect(self: Prompter, prompt_config: PromptConfig) ![]u8 {
        if (prompt_config.choices.len == 0) {
            return error.NoChoicesProvided;
        }
        
        try self.printChoices(prompt_config.choices);
        
        while (true) {
            const prompt_msg = try std.fmt.allocPrint(self.allocator, "{s} (1-{d})", .{prompt_config.message, prompt_config.choices.len});
            defer self.allocator.free(prompt_msg);
            
            try self.printPrompt(prompt_msg, null);
            
            const input = try self.readLine();
            defer self.allocator.free(input);
            
            const trimmed = std.mem.trim(u8, input, " \t\n\r");
            
            if (std.fmt.parseInt(usize, trimmed, 10)) |choice_idx| {
                if (choice_idx >= 1 and choice_idx <= prompt_config.choices.len) {
                    return self.allocator.dupe(u8, prompt_config.choices[choice_idx - 1]);
                }
            } else |_| {}
            
            try self.printError("Please enter a valid choice number");
        }
    }
    
    /// Prompt for missing argument with appropriate type
    pub fn promptForArgument(self: Prompter, arg: Argument.Argument) !Argument.ArgValue {
        const prompt_msg = if (arg.getHelp()) |help| 
            try std.fmt.allocPrint(self.allocator, "{s} ({s})", .{arg.name, help})
        else 
            try self.fmt.allocPrint(self.allocator, "{s}", .{arg.name});
        defer self.allocator.free(prompt_msg);
        
        const prompt_config = switch (arg.arg_type) {
            .bool => PromptConfig.confirm(prompt_msg),
            else => PromptConfig.text(prompt_msg),
        };
        
        switch (arg.arg_type) {
            .string => {
                const value = try self.promptText(prompt_config);
                return Argument.ArgValue{ .string = value };
            },
            .int => {
                const text = try self.promptText(prompt_config);
                defer self.allocator.free(text);
                const int_val = std.fmt.parseInt(i64, text, 10) catch {
                    try self.printError("Invalid integer value");
                    return self.promptForArgument(arg);
                };
                return Argument.ArgValue{ .int = int_val };
            },
            .float => {
                const text = try self.promptText(prompt_config);
                defer self.allocator.free(text);
                const float_val = std.fmt.parseFloat(f64, text) catch {
                    try self.printError("Invalid float value");
                    return self.promptForArgument(arg);
                };
                return Argument.ArgValue{ .float = float_val };
            },
            .bool => {
                const bool_val = try self.promptConfirm(prompt_config);
                return Argument.ArgValue{ .bool = bool_val };
            },
            .@"enum" => {
                const value = try self.promptText(prompt_config);
                return Argument.ArgValue{ .@"enum" = value };
            },
        }
    }
    
    // Helper functions
    fn printPrompt(self: Prompter, message: []const u8, default: ?[]const u8) !void {
        if (self.config.use_colors) {
            try self.stdout.writeAll("\x1b[36m"); // Cyan
        }
        
        try self.stdout.writeAll(self.config.prompt_prefix);
        try self.stdout.writeAll(" ");
        try self.stdout.writeAll(message);
        
        if (default) |d| {
            try self.stdout.writeAll(" [");
            try self.stdout.writeAll(d);
            try self.stdout.writeAll("]");
        }
        
        if (self.config.use_colors) {
            try self.stdout.writeAll("\x1b[0m"); // Reset
        }
        
        try self.stdout.writeAll(": ");
    }
    
    fn printError(self: Prompter, message: []const u8) !void {
        if (self.config.use_colors) {
            try self.stdout.writeAll("\x1b[31m"); // Red
        }
        
        try self.stdout.writeAll(self.config.error_prefix);
        try self.stdout.writeAll(" ");
        try self.stdout.writeAll(message);
        
        if (self.config.use_colors) {
            try self.stdout.writeAll("\x1b[0m"); // Reset
        }
        
        try self.stdout.writeAll("\n");
    }
    
    fn printChoices(self: Prompter, choices: []const []const u8) !void {
        try self.stdout.writeAll("Choose from:\n");
        for (choices, 0..) |choice, i| {
            const num_str = try std.fmt.allocPrint(self.allocator, "  {d}. {s}\n", .{i + 1, choice});
            defer self.allocator.free(num_str);
            try self.stdout.writeAll(num_str);
        }
    }
    
    fn readLine(self: Prompter) ![]u8 {
        const max_size = 1024;
        const input = try self.allocator.alloc(u8, max_size);
        
        if (try self.stdin.readUntilDelimiterOrEof(input, '\n')) |line| {
            return self.allocator.dupe(u8, line);
        } else {
            self.allocator.free(input);
            return error.EndOfFile;
        }
    }
};

test "prompt config creation" {
    const text_config = PromptConfig.text("Enter your name");
    try std.testing.expectEqual(PromptType.text, text_config.prompt_type);
    try std.testing.expectEqualStrings("Enter your name", text_config.message);
    
    const confirm_config = PromptConfig.confirm("Continue?").withDefault("y");
    try std.testing.expectEqual(PromptType.confirm, confirm_config.prompt_type);
    try std.testing.expectEqualStrings("y", confirm_config.default_value.?);
}