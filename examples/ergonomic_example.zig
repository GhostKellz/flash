//! ⚡ Flash Ergonomic API Example 
//!
//! This example demonstrates the new CLAP-style ergonomic API for Flash,
//! showing how to define commands with minimal boilerplate.

const std = @import("std");
const flash = @import("flash");

// Example 1: Chain-friendly builder syntax (like fluent interfaces)
fn createChainCommand() flash.Command {
    return flash.chain("deploy")
        .about("Deploy your application")
        .args(&.{
            flash.arg("environment")
                .withHelp("Target environment (dev, staging, prod)")
                .setRequired(),
        })
        .flags(&.{
            flash.flag("dry-run")
                .withShort('d')
                .withHelp("Show what would be deployed without actually deploying"),
            flash.flag("verbose")
                .withShort('v')
                .withHelp("Enable verbose output"),
        })
        .handler(deployHandler);
}

// Example 2: Struct-based command derivation (like Clap's derive)
const VMConfig = struct {
    name: []const u8,       // Auto-becomes required argument
    memory: ?i32 = null,    // Auto-becomes optional argument with default
    cpu_cores: i32 = 2,     // Auto-becomes argument with default value
    verbose: bool = false,  // Auto-becomes boolean flag
    dry_run: bool = false,  // Auto-becomes boolean flag
};

fn createDerivedCommand() flash.Command {
    return flash.deriveStruct(VMConfig, vmHandler);
}

// Example 3: Pattern matching for command dispatch
fn routeCommands(ctx: flash.Context) flash.Error!void {
    const Handlers = struct {
        fn handler_0(route_ctx: flash.Context) flash.Error!void {
            std.debug.print("🚀 Starting service...\n", .{});
            _ = route_ctx;
        }
        fn handler_1(route_ctx: flash.Context) flash.Error!void {
            std.debug.print("🛑 Stopping service...\n", .{});
            _ = route_ctx;
        }
        fn handler_2(route_ctx: flash.Context) flash.Error!void {
            std.debug.print("📊 Service status...\n", .{});
            _ = route_ctx;
        }
    };
    
    try flash.pattern(&.{"start", "stop", "status"}, ctx, Handlers);
}

// Example 4: Middleware-enhanced commands
fn createMiddlewareCommand() flash.Command {
    const enhanced_handler = flash.Macros.Middleware.chain(&.{
        flash.Macros.Middleware.logging(),
        flash.Macros.Middleware.timing(),
        flash.Macros.Middleware.authentication("admin"),
    }, adminHandler);
    
    return flash.chain("admin")
        .about("Admin-only commands with logging and timing")
        .handler(enhanced_handler);
}

// Command handlers
fn deployHandler(ctx: flash.Context) flash.Error!void {
    const env = ctx.getString("environment") orelse return flash.Error.MissingRequiredArgument;
    const dry_run = ctx.getFlag("dry-run");
    const verbose = ctx.getFlag("verbose");
    
    if (verbose) {
        std.debug.print("🔧 Verbose mode enabled\n", .{});
    }
    
    if (dry_run) {
        std.debug.print("🔍 DRY RUN: Would deploy to {s}\n", .{env});
    } else {
        std.debug.print("🚀 Deploying to {s}...\n", .{env});
        // Simulate deployment
        std.debug.print("✅ Deployment to {s} completed!\n", .{env});
    }
}

fn vmHandler(ctx: flash.Context) flash.Error!void {
    const name = ctx.getString("name") orelse return flash.Error.MissingRequiredArgument;
    const memory = ctx.getInt("memory") orelse 1024;
    const cpu_cores = ctx.getInt("cpu_cores") orelse 2;
    const verbose = ctx.getFlag("verbose");
    const dry_run = ctx.getFlag("dry_run");
    
    if (verbose) {
        std.debug.print("🔧 Verbose mode enabled\n", .{});
    }
    
    if (dry_run) {
        std.debug.print("🔍 DRY RUN: Would create VM '{s}' with {d}MB RAM and {d} CPU cores\n", .{name, memory, cpu_cores});
    } else {
        std.debug.print("🖥️  Creating VM: {s}\n", .{name});
        std.debug.print("   Memory: {d}MB\n", .{memory});
        std.debug.print("   CPU Cores: {d}\n", .{cpu_cores});
        std.debug.print("✅ VM '{s}' created successfully!\n", .{name});
    }
}

fn adminHandler(ctx: flash.Context) flash.Error!void {
    std.debug.print("👑 Admin command executed\n", .{});
    _ = ctx;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("⚡ Flash Ergonomic API Examples\n\n", .{});
    
    // Demo the different command creation styles
    std.debug.print("🎨 1. Chain-friendly builder syntax:\n", .{});
    const chain_cmd = createChainCommand();
    std.debug.print("   Created: {s} - {?s}\n\n", .{chain_cmd.name, chain_cmd.config.about});
    
    std.debug.print("🎨 2. Struct-derived command:\n", .{});
    const derived_cmd = createDerivedCommand();
    std.debug.print("   Created: {s} - {?s}\n\n", .{derived_cmd.name, derived_cmd.config.about});
    
    std.debug.print("🎨 3. Pattern matching demo:\n", .{});
    var ctx = try flash.Context.init(allocator, &.{});
    defer ctx.deinit();
    ctx.setSubcommand("start");
    try routeCommands(ctx);
    
    std.debug.print("\n🎨 4. Middleware-enhanced command:\n", .{});
    const middleware_cmd = createMiddlewareCommand();  
    std.debug.print("   Created: {s} - {?s}\n", .{middleware_cmd.name, middleware_cmd.config.about});
    
    std.debug.print("\n✨ All examples completed! These patterns make Flash as ergonomic as Rust's clap.\n", .{});
}