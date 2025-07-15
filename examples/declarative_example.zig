const std = @import("std");
const flash = @import("flash");

// Example of declarative command definition using structs
const ZekeCommand = struct {
    // String arguments
    chat: ?[]const u8 = null,
    model: ?[]const u8 = null,
    
    // Authentication info
    provider: []const u8 = "openai",
    token: ?[]const u8 = null,
    
    // Boolean flags
    verbose: bool = false,
    stream: bool = false,
    help: bool = false,
    
    // Numeric arguments
    temperature: f32 = 0.7,
    max_tokens: i32 = 1000,
    
    // Use the derive macro for automatic help generation
    pub usingnamespace flash.derive(.{
        .help = true,
        .version = "1.0.0",
        .author = "Flash Team",
        .about = "A CLI tool for interacting with AI models",
    });
};

// Example of subcommand definition
const ChatCommand = struct {
    message: []const u8,
    stream: bool = false,
    temperature: f32 = 0.7,
    model: ?[]const u8 = null,
    
    pub usingnamespace flash.derive(.{
        .about = "Send a message to the AI",
    });
};

const ModelCommand = struct {
    list: bool = false,
    set: ?[]const u8 = null,
    current: bool = false,
    
    pub usingnamespace flash.derive(.{
        .about = "Manage AI models",
    });
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Parse the command line arguments directly into the struct
    const args = try flash.parse(ZekeCommand, allocator);
    
    // Use the parsed arguments
    if (args.help) {
        const help_text = try ZekeCommand.generateHelp(allocator);
        defer allocator.free(help_text);
        std.debug.print("{s}", .{help_text});
        return;
    }
    
    if (args.verbose) {
        std.debug.print("⚡ Verbose mode enabled\n", .{});
        std.debug.print("Model: {s}\n", .{args.model orelse "default"});
        std.debug.print("Provider: {s}\n", .{args.provider});
        std.debug.print("Temperature: {d}\n", .{args.temperature});
        std.debug.print("Max tokens: {d}\n", .{args.max_tokens});
    }
    
    if (args.chat) |message| {
        std.debug.print("🤖 Sending message: {s}\n", .{message});
        if (args.stream) {
            std.debug.print("📡 Streaming mode enabled\n", .{});
        }
    } else {
        std.debug.print("💬 Welcome to Zeke AI CLI!\n", .{});
        std.debug.print("Use --chat <message> to send a message.\n", .{});
        std.debug.print("Use --help for more options.\n", .{});
    }
}

// Example of using the traditional Flash API alongside declarative
pub fn traditionalExample() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // This is the traditional way (still supported)
    const DemoCLI = flash.CLI(.{
        .name = "traditional",
        .version = "1.0.0",
        .about = "Traditional Flash CLI example",
    });
    
    const echo_cmd = flash.cmd("echo", (flash.CommandConfig{})
        .withAbout("Echo your message back")
        .withArgs(&.{
            flash.arg("message", (flash.ArgumentConfig{})
                .withHelp("Text to echo back")
                .setRequired()),
        })
        .withFlags(&.{
            flash.flag("uppercase", (flash.FlagConfig{})
                .withShort('u')
                .withLong("uppercase")
                .withHelp("Convert to uppercase")),
        })
        .withHandler(echoHandler));
    
    var cli = DemoCLI.init(allocator, (flash.CommandConfig{})
        .withSubcommands(&.{echo_cmd}));
    
    try cli.run();
}

fn echoHandler(ctx: flash.Context) flash.Error!void {
    if (ctx.getString("message")) |message| {
        if (ctx.getFlag("uppercase")) {
            var buffer: [256]u8 = undefined;
            const upper = std.ascii.upperString(buffer[0..message.len], message);
            std.debug.print("{s}\n", .{upper});
        } else {
            std.debug.print("{s}\n", .{message});
        }
    }
}

test "declarative parsing" {
    const allocator = std.testing.allocator;
    
    // Test basic argument parsing
    const args = [_][]const u8{
        "zeke",
        "--chat", "Hello, world!",
        "--model", "gpt-4",
        "--verbose",
        "--stream",
        "--temperature", "0.8",
        "--max-tokens", "500",
    };
    
    const parsed = try flash.parseWithArgs(ZekeCommand, allocator, &args, .{
        .name = "zeke",
        .about = "AI CLI tool",
    });
    
    try std.testing.expectEqualStrings("Hello, world!", parsed.chat.?);
    try std.testing.expectEqualStrings("gpt-4", parsed.model.?);
    try std.testing.expectEqual(true, parsed.verbose);
    try std.testing.expectEqual(true, parsed.stream);
    try std.testing.expectEqual(@as(f32, 0.8), parsed.temperature);
    try std.testing.expectEqual(@as(i32, 500), parsed.max_tokens);
    try std.testing.expectEqualStrings("openai", parsed.provider); // Default value
}

test "declarative help generation" {
    const allocator = std.testing.allocator;
    
    const help_text = try ZekeCommand.generateHelp(allocator);
    defer allocator.free(help_text);
    
    // Check that help text contains expected elements
    try std.testing.expect(std.mem.indexOf(u8, help_text, "⚡") != null);
    try std.testing.expect(std.mem.indexOf(u8, help_text, "USAGE:") != null);
    try std.testing.expect(std.mem.indexOf(u8, help_text, "OPTIONS:") != null);
    try std.testing.expect(std.mem.indexOf(u8, help_text, "verbose") != null);
    try std.testing.expect(std.mem.indexOf(u8, help_text, "chat") != null);
}