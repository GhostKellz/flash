const std = @import("std");
const flash = @import("flash");
const zsync = @import("zsync");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create a demo CLI application
    const DemoCLI = flash.CLI(.{
        .name = "lightning",
        .version = "0.1.0",
        .about = "A demo CLI built with Flash - The Lightning-Fast CLI Framework for Zig",
        .subcommand_required = false,
    });
    
    // Define some example commands
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
    
    const greet_cmd = flash.cmd("greet", (flash.CommandConfig{})
        .withAbout("Greet someone")
        .withAliases(&.{ "hello", "hi" })
        .withArgs(&.{
            flash.arg("name", (flash.ArgumentConfig{})
                .withHelp("Name to greet")
                .withDefault(flash.ArgValue{ .string = "World" })),
        })
        .withHandler(greetHandler));
    
    const math_add_cmd = flash.cmd("add", (flash.CommandConfig{})
        .withAbout("Add two numbers")
        .withArgs(&.{
            flash.Argument.typed(i32, "a", (flash.ArgumentConfig{})
                .withHelp("First number")
                .setRequired()),
            flash.Argument.typed(i32, "b", (flash.ArgumentConfig{})
                .withHelp("Second number")
                .setRequired()),
        })
        .withHandler(addHandler));
    
    const math_cmd = flash.cmd("math", (flash.CommandConfig{})
        .withAbout("Mathematical operations")
        .withSubcommands(&.{math_add_cmd}));
    
    // Example command with better arg handling
    const status_cmd = flash.cmd("status", (flash.CommandConfig{})
        .withAbout("Show status information")
        .withHandler(statusHandler));
    
    // Async demo command
    const async_cmd = flash.cmd("async", (flash.CommandConfig{})
        .withAbout("Demonstrate async operations with zsync")
        .withArgs(&.{
            flash.arg("operation", (flash.ArgumentConfig{})
                .withHelp("Type of async operation (network, file, db, concurrent)")
                .withDefault(flash.ArgValue{ .string = "network" })),
        })
        .withHandler(asyncHandler));
    
    // Example of new ergonomic chain syntax
    const ergonomic_cmd = flash.chain("ergonomic")
        .about("Showcase Flash's ergonomic API")
        .args(&.{
            flash.arg("action", (flash.ArgumentConfig{})
                .withHelp("Action to perform (deploy, build, test)")
                .withDefault(flash.ArgValue{ .string = "test" })),
        })
        .flags(&.{
            flash.flag("verbose", (flash.FlagConfig{})
                .withShort('v')
                .withHelp("Enable verbose output")),
            flash.flag("dry-run", (flash.FlagConfig{})
                .withLong("dry-run")
                .withHelp("Show what would happen without executing")),
        })
        .handler(ergonomicHandler);

    // Create the CLI with all commands
    var cli = DemoCLI.init(allocator, (flash.CommandConfig{})
        .withAbout("A demonstration of Flash CLI capabilities")
        .withSubcommands(&.{ echo_cmd, greet_cmd, math_cmd, status_cmd, async_cmd, ergonomic_cmd })
        .withHandler(defaultHandler));
    
    try cli.run();
}

fn defaultHandler(ctx: flash.Context) flash.Error!void {
    std.debug.print("⚡ Welcome to Flash - The Lightning-Fast CLI Framework!\n\n", .{});
    std.debug.print("Get started with these commands:\n", .{});
    std.debug.print("  lightning echo \"Hello Flash!\" --uppercase\n", .{});
    std.debug.print("  lightning greet Alice\n", .{});
    std.debug.print("  lightning math add 5 7\n", .{});
    std.debug.print("  lightning status\n", .{});
    std.debug.print("\nZig-style commands:\n", .{});
    std.debug.print("  lightning help     (instead of --help)\n", .{});
    std.debug.print("  lightning version  (instead of --version)\n", .{});
    std.debug.print("  lightning async network  (demo async features)\n", .{});
    std.debug.print("  lightning ergonomic deploy --verbose  (demo ergonomic API)\n", .{});
    std.debug.print("\n⚡ Fast. Async. Ergonomic. Zig-native.\n", .{});
    _ = ctx;
}

fn echoHandler(ctx: flash.Context) flash.Error!void {
    if (ctx.getString("message")) |message| {
        if (ctx.getFlag("uppercase")) {
            // Simple uppercase conversion
            var buffer: [256]u8 = undefined;
            const upper = std.ascii.upperString(buffer[0..message.len], message);
            std.debug.print("{s}\n", .{upper});
        } else {
            std.debug.print("{s}\n", .{message});
        }
    }
}

fn greetHandler(ctx: flash.Context) flash.Error!void {
    const name = ctx.getString("name") orelse "World";
    std.debug.print("Hello, {s}! 👋\n", .{name});
}

fn addHandler(ctx: flash.Context) flash.Error!void {
    const a = ctx.getInt("a") orelse 0;
    const b = ctx.getInt("b") orelse 0;
    std.debug.print("{d} + {d} = {d}\n", .{ a, b, a + b });
}

fn statusHandler(ctx: flash.Context) flash.Error!void {
    std.debug.print("⚡ Flash CLI Status:\n", .{});
    std.debug.print("  Version: 0.1.0\n", .{});
    std.debug.print("  Zig Version: 0.16+\n", .{});
    std.debug.print("  Features: ✅ Subcommands ✅ Args ✅ Flags ⚡ Lightning Fast\n", .{});
    std.debug.print("  Async Support: ✅ Powered by zsync\n", .{});
    
    // Demonstrate async capabilities
    std.debug.print("\n🚀 Testing async features:\n", .{});
    try flash.Async.AsyncHelpers.zsyncV4Example(ctx);
}

fn asyncHandler(ctx: flash.Context) flash.Error!void {
    const operation = ctx.getString("operation") orelse "network";
    
    std.debug.print("⚡ Flash Async Demo: {s} operation\n", .{operation});
    
    // Create async runtime with auto-detected execution model
    var runtime = flash.Async.AsyncRuntime.init(ctx.allocator, .blocking);
    defer runtime.deinit();
    
    if (std.mem.eql(u8, operation, "network")) {
        try runtime.runAsync(flash.Async.AsyncHelpers.networkFetch, ctx);
    } else if (std.mem.eql(u8, operation, "file")) {
        try runtime.runAsync(flash.Async.AsyncHelpers.fileProcessor, ctx);
    } else if (std.mem.eql(u8, operation, "db")) {
        try runtime.runAsync(flash.Async.AsyncHelpers.databaseQuery, ctx);
    } else if (std.mem.eql(u8, operation, "concurrent")) {
        try runtime.runAsync(flash.Async.AsyncHelpers.concurrentTasks, ctx);
    } else if (std.mem.eql(u8, operation, "colorblind")) {
        try flash.Async.AsyncHelpers.colorblindAsyncDemo(ctx);
    } else {
        std.debug.print("❌ Unknown operation: {s}\n", .{operation});
        std.debug.print("Available operations: network, file, db, concurrent, colorblind\n", .{});
        return flash.Error.InvalidArgument;
    }
}

fn ergonomicHandler(ctx: flash.Context) flash.Error!void {
    const action = ctx.getString("action") orelse "test";
    const verbose = ctx.getFlag("verbose");
    const dry_run = ctx.getFlag("dry-run");
    
    std.debug.print("🎨 Flash Ergonomic API Demo\n", .{});
    std.debug.print("Action: {s}\n", .{action});
    
    if (verbose) {
        std.debug.print("🔧 Verbose mode enabled\n", .{});
        std.debug.print("📊 This shows how the new chain() API reduces boilerplate\n", .{});
        std.debug.print("🚀 Making Flash as ergonomic as Rust's clap!\n", .{});
    }
    
    if (dry_run) {
        std.debug.print("🔍 DRY RUN: Would execute '{s}' action\n", .{action});
        return;
    }
    
    // Simulate different actions
    if (std.mem.eql(u8, action, "deploy")) {
        std.debug.print("🚀 Deploying application...\n", .{});
        std.Thread.sleep(500 * 1000 * 1000); // 500ms
        std.debug.print("✅ Deployment completed!\n", .{});
    } else if (std.mem.eql(u8, action, "build")) {
        std.debug.print("🔨 Building project...\n", .{});
        std.Thread.sleep(300 * 1000 * 1000); // 300ms
        std.debug.print("✅ Build completed!\n", .{});
    } else if (std.mem.eql(u8, action, "test")) {
        std.debug.print("🧪 Running tests...\n", .{});
        std.Thread.sleep(200 * 1000 * 1000); // 200ms
        std.debug.print("✅ All tests passed!\n", .{});
    } else {
        std.debug.print("❓ Unknown action: {s}\n", .{action});
        std.debug.print("Available actions: deploy, build, test\n", .{});
    }
}

test "simple test" {
    var list = try std.ArrayList(i32).initCapacity(std.testing.allocator, 0);
    defer list.deinit(std.testing.allocator);
    try list.append(std.testing.allocator, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
