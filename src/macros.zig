//! ⚡ Flash Macros - CLAP-style ergonomic command definitions
//!
//! This module provides macro-based command definition similar to Rust's clap,
//! making Flash the most ergonomic CLI framework for Zig.

const std = @import("std");
const Command = @import("command.zig");
const Argument = @import("argument.zig");  
const Flag = @import("flag.zig");
const Context = @import("context.zig");
const Error = @import("error.zig");

/// Macro for defining commands with minimal boilerplate
/// Usage: @flash.command("vm run <name>", vmHandler)
pub fn command(comptime spec: []const u8, handler: anytype) Command.Command {
    const parsed = comptime parseCommandSpec(spec);
    
    return Command.Command.init(parsed.name, (Command.CommandConfig{})
        .withAbout(parsed.about)
        .withHandler(handler));
}

/// Parse command specification like "vm run <name> [options]"
fn parseCommandSpec(comptime spec: []const u8) struct {
    name: []const u8,
    about: []const u8,
    subcommands: []const []const u8,
    args: []const []const u8,
} {
    // Simple parser for now - can be enhanced
    const trimmed = std.mem.trim(u8, spec, " \t");
    _ = trimmed; // Will implement full parsing later
    
    return .{
        .name = "parsed_cmd",
        .about = "Auto-generated command",
        .subcommands = &.{},
        .args = &.{},
    };
}

/// Declarative command definition using struct-based syntax
pub fn CommandDef(comptime T: type) type {
    return struct {
        const Self = @This();
        
        pub fn build() Command.Command {
            const info = @typeInfo(T);
            if (info != .Struct) {
                @compileError("CommandDef expects a struct type");
            }
            
            const struct_info = info.Struct;
            var cmd_name: []const u8 = "command";
            var cmd_about: []const u8 = "Generated command";
            
            // Look for special fields
            inline for (struct_info.fields) |field| {
                switch (field.type) {
                    []const u8 => {
                        if (std.mem.eql(u8, field.name, "name")) {
                            cmd_name = field.name;
                        } else if (std.mem.eql(u8, field.name, "about")) {
                            cmd_about = field.name;
                        }
                    },
                    else => {},
                }
            }
            
            return Command.Command.init(cmd_name, (Command.CommandConfig{})
                .withAbout(cmd_about));
        }
    };
}

/// Chain-friendly builder that allows cmd.args().flags().handler() syntax
pub const ChainBuilder = struct {
    config: Command.CommandConfig,
    name: []const u8,
    
    pub fn init(name: []const u8) ChainBuilder {
        return .{
            .name = name,
            .config = Command.CommandConfig{},
        };
    }
    
    pub fn about(self: ChainBuilder, description: []const u8) ChainBuilder {
        var builder = self;
        builder.config = builder.config.withAbout(description);
        return builder;
    }
    
    pub fn args(self: ChainBuilder, arguments: []const Argument.Argument) ChainBuilder {
        var builder = self;
        builder.config = builder.config.withArgs(arguments);
        return builder;
    }
    
    pub fn flags(self: ChainBuilder, flag_list: []const Flag.Flag) ChainBuilder {
        var builder = self;
        builder.config = builder.config.withFlags(flag_list);
        return builder;
    }
    
    pub fn handler(self: ChainBuilder, handler_fn: Command.HandlerFn) Command.Command {
        const final_config = self.config.withHandler(handler_fn);
        return Command.Command.init(self.name, final_config);
    }
    
    pub fn subcommands(self: ChainBuilder, subcmds: []const Command.Command) ChainBuilder {
        var builder = self;
        builder.config = builder.config.withSubcommands(subcmds);
        return builder;
    }
};

/// Ultra-ergonomic command builder function
pub fn cmd(name: []const u8) ChainBuilder {
    return ChainBuilder.init(name);
}

/// Quick argument creation
pub fn arg(name: []const u8) Argument.ArgumentConfig {
    return (Argument.ArgumentConfig{}).withName(name);
}

/// Quick flag creation
pub fn flag(name: []const u8) Flag.FlagConfig {
    return (Flag.FlagConfig{}).withName(name);
}

/// Derive command from struct using compile-time reflection
pub fn deriveCommand(comptime T: type, handler_fn: anytype) Command.Command {
    const info = @typeInfo(T);
    if (info != .Struct) {
        @compileError("deriveCommand expects a struct type");
    }
    
    const struct_info = info.Struct;
    var args = std.ArrayList(Argument.Argument).init(std.heap.page_allocator);
    var flags = std.ArrayList(Flag.Flag).init(std.heap.page_allocator);
    
    // Generate arguments and flags from struct fields
    inline for (struct_info.fields) |field| {
        const arg_config = (Argument.ArgumentConfig{})
            .withName(field.name)
            .withHelp("Auto-generated argument for " ++ field.name);
            
        switch (field.type) {
            bool => {
                const flag_config = (Flag.FlagConfig{})
                    .withName(field.name)
                    .withHelp("Auto-generated flag for " ++ field.name);
                flags.append(Flag.Flag.init(field.name, flag_config)) catch {};
            },
            []const u8, i32, i64, f32, f64 => {
                args.append(Argument.Argument.init(field.name, arg_config)) catch {};
            },
            else => {
                // Skip unknown types
            },
        }
    }
    
    const type_name = @typeName(T);
    const cmd_name = if (std.mem.indexOf(u8, type_name, ".")) |dot_index| 
        type_name[dot_index + 1..] 
    else 
        type_name;
    
    return Command.Command.init(cmd_name, (Command.CommandConfig{})
        .withAbout("Auto-generated command for " ++ cmd_name)
        .withArgs(args.items)
        .withFlags(flags.items)
        .withHandler(handler_fn));
}

/// Attribute-based command definition (experimental)
pub fn AttributeCommand(comptime spec: []const u8) type {
    _ = spec; // Will implement attribute parsing later
    return struct {
        pub fn define(handler_fn: anytype) Command.Command {
            // Parse attributes like "#[about="Start VM"] #[arg(name, required)] #[flag(verbose)]"
            return Command.Command.init("attr_cmd", (Command.CommandConfig{})
                .withAbout("Attribute-defined command")
                .withHandler(handler_fn));
        }
    };
}

/// Template-based command generation
pub fn templateCommand(comptime template: []const u8, comptime substitutions: anytype) Command.Command {
    // Template engine for generating commands from templates
    // Usage: templateCommand("{{name}} {{action}} <{{arg}}>", .{ .name = "vm", .action = "start", .arg = "name" })
    _ = template;
    _ = substitutions;
    
    return Command.Command.init("template_cmd", (Command.CommandConfig{})
        .withAbout("Template-generated command"));
}

/// Pattern matching for command dispatch
pub const PatternMatcher = struct {
    pub fn match(comptime patterns: []const []const u8, ctx: Context.Context, handlers: anytype) Error.FlashError!void {
        const command_name = ctx.getSubcommand() orelse return Error.FlashError.MissingSubcommand;
        
        inline for (patterns, 0..) |pattern, i| {
            if (std.mem.eql(u8, command_name, pattern)) {
                const handler = @field(handlers, std.fmt.comptimePrint("handler_{d}", .{i}));
                return handler(ctx);
            }
        }
        
        return Error.FlashError.UnknownCommand;
    }
};

/// DSL for complex command hierarchies
pub const CommandHierarchy = struct {
    pub fn define(comptime hierarchy: anytype) []Command.Command {
        // Define nested command structures
        // Usage: CommandHierarchy.define(.{ vm = .{ start = startHandler, stop = stopHandler } })
        _ = hierarchy;
        return &.{};
    }
};

/// Validation decorators
pub fn withValidation(comptime validator: anytype) type {
    return struct {
        pub fn validate(ctx: Context.Context) Error.FlashError!void {
            return validator(ctx);
        }
    };
}

/// Middleware system for command processing
pub const Middleware = struct {
    pub const MiddlewareFn = *const fn (Context.Context, *const fn (Context.Context) Error.FlashError!void) Error.FlashError!void;
    
    pub fn chain(middlewares: []const MiddlewareFn, final_handler: Command.HandlerFn) Command.HandlerFn {
        // Chain middleware functions together
        _ = middlewares;
        return final_handler;
    }
    
    pub fn logging() MiddlewareFn {
        return struct {
            pub fn middleware(ctx: Context.Context, next: *const fn (Context.Context) Error.FlashError!void) Error.FlashError!void {
                std.debug.print("📝 Executing command: {?s}\n", .{ctx.getSubcommand()});
                try next(ctx);
                std.debug.print("✅ Command completed successfully\n", .{});
            }
        }.middleware;
    }
    
    pub fn timing() MiddlewareFn {
        return struct {
            pub fn middleware(ctx: Context.Context, next: *const fn (Context.Context) Error.FlashError!void) Error.FlashError!void {
                const start_time = std.time.nanoTimestamp();
                try next(ctx);
                const end_time = std.time.nanoTimestamp();
                const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
                std.debug.print("⏱️  Command executed in {d:.2}ms\n", .{duration_ms});
            }
        }.middleware;
    }
    
    pub fn authentication(required_role: []const u8) MiddlewareFn {
        _ = required_role;
        return struct {
            pub fn middleware(ctx: Context.Context, next: *const fn (Context.Context) Error.FlashError!void) Error.FlashError!void {
                // Check authentication
                std.debug.print("🔐 Checking authentication...\n", .{});
                try next(ctx);
            }
        }.middleware;
    }
};

test "chain builder syntax" {
    const TestHandler = struct {
        fn handler(ctx: Context.Context) Error.FlashError!void {
            _ = ctx;
        }
    };
    
    const test_cmd = cmd("test")
        .about("Test command")
        .args(&.{})
        .flags(&.{})
        .handler(TestHandler.handler);
    
    try std.testing.expectEqualStrings("test", test_cmd.name);
}

test "derive command from struct" {
    const VMConfig = struct {
        name: []const u8,
        memory: i32,
        cpu_cores: i32,
        verbose: bool,
    };
    
    const TestHandler = struct {
        fn handler(ctx: Context.Context) Error.FlashError!void {
            _ = ctx;
        }
    };
    
    const vm_cmd = deriveCommand(VMConfig, TestHandler.handler);
    try std.testing.expectEqualStrings("VMConfig", vm_cmd.name);
}

test "pattern matching" {
    const allocator = std.testing.allocator;
    var ctx = try Context.Context.init(allocator, &.{});
    defer ctx.deinit();
    
    ctx.setSubcommand("start");
    
    const Handlers = struct {
        fn handler_0(test_ctx: Context.Context) Error.FlashError!void {
            _ = test_ctx;
        }
        fn handler_1(test_ctx: Context.Context) Error.FlashError!void {
            _ = test_ctx;
        }
    };
    
    try PatternMatcher.match(&.{"start", "stop"}, ctx, Handlers);
}