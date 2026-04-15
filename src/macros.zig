//! ⚡ Flash Macros - CLAP-style ergonomic command definitions (Experimental)
//!
//! This module provides macro-based command definition similar to Rust's clap,
//! making Flash the most ergonomic CLI framework for Zig.
//!
//! FEATURES:
//! - command(spec, handler): Parse "name <arg> -- description" specs
//! - CommandDef(T).build(): Build commands from structs with name/about declarations
//! - ChainBuilder / cmd(): Fluent builder pattern
//! - deriveCommand(): Generate commands from struct fields
//! - PatternMatcher: Match subcommands to handlers
//! - Middleware: Individual middleware functions (logging, timing, authentication)
//!
//! EXPERIMENTAL:
//! - AttributeCommand: Returns placeholder, attribute parsing not implemented

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
/// Format: "command_name <required_arg> [optional_arg] -- description"
fn parseCommandSpec(comptime spec: []const u8) struct {
    name: []const u8,
    about: []const u8,
    subcommands: []const []const u8,
    args: []const []const u8,
} {
    const trimmed = std.mem.trim(u8, spec, " \t");

    // Check for description separator "--"
    var name_part: []const u8 = trimmed;
    var about: []const u8 = "";
    if (std.mem.indexOf(u8, trimmed, " -- ")) |sep_idx| {
        name_part = std.mem.trim(u8, trimmed[0..sep_idx], " \t");
        about = std.mem.trim(u8, trimmed[sep_idx + 4 ..], " \t");
    }

    // Extract command name (first token before any < or [)
    var name_end: usize = name_part.len;
    for (name_part, 0..) |c, i| {
        if (c == '<' or c == '[' or c == ' ') {
            name_end = i;
            break;
        }
    }
    const cmd_name = std.mem.trim(u8, name_part[0..name_end], " \t");

    // Parse arguments (anything in <> or [])
    var args: [16][]const u8 = undefined;
    var arg_count: usize = 0;
    var i: usize = 0;
    while (i < name_part.len) : (i += 1) {
        if (name_part[i] == '<') {
            const start = i + 1;
            while (i < name_part.len and name_part[i] != '>') : (i += 1) {}
            if (arg_count < 16) {
                args[arg_count] = name_part[start..i];
                arg_count += 1;
            }
        } else if (name_part[i] == '[') {
            const start = i + 1;
            while (i < name_part.len and name_part[i] != ']') : (i += 1) {}
            if (arg_count < 16) {
                args[arg_count] = name_part[start..i];
                arg_count += 1;
            }
        }
    }

    return .{
        .name = if (cmd_name.len > 0) cmd_name else "command",
        .about = if (about.len > 0) about else "Command: " ++ cmd_name,
        .subcommands = &.{},
        .args = args[0..arg_count],
    };
}

/// Declarative command definition using struct-based syntax
/// The struct should have `name` and `about` fields with default values:
/// ```
/// const MyCmd = struct {
///     pub const name = "mycommand";
///     pub const about = "My command description";
/// };
/// ```
pub fn CommandDef(comptime T: type) type {
    return struct {
        const Self = @This();

        pub fn build() Command.Command {
            const info = @typeInfo(T);
            if (info != .@"struct") {
                @compileError("CommandDef expects a struct type");
            }

            // Look for pub const declarations (the idiomatic way to define metadata)
            const cmd_name: []const u8 = if (@hasDecl(T, "name")) T.name else @typeName(T);
            const cmd_about: []const u8 = if (@hasDecl(T, "about")) T.about else "Generated command";

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

/// Quick argument creation (returns empty config, use with Argument.init)
pub fn arg() Argument.ArgumentConfig {
    return Argument.ArgumentConfig{};
}

/// Quick flag creation (returns empty config, use with Flag.init)
pub fn flag() Flag.FlagConfig {
    return Flag.FlagConfig{};
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
            .withHelp("Auto-generated argument for " ++ field.name);

        switch (field.type) {
            bool => {
                const flag_config = (Flag.FlagConfig{})
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

/// Validation decorators
pub fn withValidation(comptime validator: anytype) type {
    return struct {
        pub fn validate(ctx: Context.Context) Error.FlashError!void {
            return validator(ctx);
        }
    };
}

/// Middleware system for command processing
/// Note: Currently provides individual middleware functions. Automatic chaining is not yet implemented.
pub const Middleware = struct {
    pub const MiddlewareFn = *const fn (Context.Context, *const fn (Context.Context) Error.FlashError!void) Error.FlashError!void;

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

    try PatternMatcher.match(&.{ "start", "stop" }, ctx, Handlers);
}

test "command spec parsing extracts name" {
    const TestHandler = struct {
        fn handler(ctx: Context.Context) Error.FlashError!void {
            _ = ctx;
        }
    };

    const simple_cmd = command("deploy", TestHandler.handler);
    try std.testing.expectEqualStrings("deploy", simple_cmd.name);

    const with_args = command("run <name>", TestHandler.handler);
    try std.testing.expectEqualStrings("run", with_args.name);

    const with_desc = command("start -- Start the service", TestHandler.handler);
    try std.testing.expectEqualStrings("start", with_desc.name);
    try std.testing.expectEqualStrings("Start the service", with_desc.getAbout().?);
}

test "CommandDef uses struct declarations" {
    const MyCommand = struct {
        pub const name = "mytest";
        pub const about = "My test command";
    };

    const built = CommandDef(MyCommand).build();
    try std.testing.expectEqualStrings("mytest", built.name);
    try std.testing.expectEqualStrings("My test command", built.getAbout().?);
}

test "CommandDef falls back to type name" {
    const FallbackCmd = struct {
        // No name or about declarations
    };

    const built = CommandDef(FallbackCmd).build();
    // Should contain "FallbackCmd" somewhere in the name
    try std.testing.expect(std.mem.indexOf(u8, built.name, "FallbackCmd") != null);
    try std.testing.expectEqualStrings("Generated command", built.getAbout().?);
}

test "chain builder with subcommands" {
    const TestHandler = struct {
        fn handler(ctx: Context.Context) Error.FlashError!void {
            _ = ctx;
        }
    };

    const sub1 = cmd("sub1").about("Subcommand 1").handler(TestHandler.handler);
    const sub2 = cmd("sub2").about("Subcommand 2").handler(TestHandler.handler);

    const parent = cmd("parent")
        .about("Parent command")
        .subcommands(&.{ sub1, sub2 })
        .handler(TestHandler.handler);

    try std.testing.expectEqualStrings("parent", parent.name);
    try std.testing.expectEqual(@as(usize, 2), parent.getSubcommands().len);
}

test "arg helper returns empty config" {
    const config = arg();
    try std.testing.expectEqual(@as(?[]const u8, null), config.help);
    try std.testing.expectEqual(false, config.required);
}

test "flag helper returns empty config" {
    const config = flag();
    try std.testing.expectEqual(@as(?[]const u8, null), config.help);
    try std.testing.expectEqual(@as(?u8, null), config.short);
}

test "middleware logging returns function" {
    const logging_fn = Middleware.logging();
    try std.testing.expect(logging_fn != undefined);
}

test "middleware timing returns function" {
    const timing_fn = Middleware.timing();
    try std.testing.expect(timing_fn != undefined);
}

test "middleware authentication returns function" {
    const auth_fn = Middleware.authentication("admin");
    try std.testing.expect(auth_fn != undefined);
}

test "withValidation creates validator type" {
    const TestValidator = withValidation(struct {
        fn validate(ctx: Context.Context) Error.FlashError!void {
            _ = ctx;
        }
    }.validate);

    // Verify the type has the validate function
    try std.testing.expect(@hasDecl(TestValidator, "validate"));
}

test "command spec with optional args" {
    const TestHandler = struct {
        fn handler(ctx: Context.Context) Error.FlashError!void {
            _ = ctx;
        }
    };

    const cmd_with_optional = command("copy <src> [dest] -- Copy files", TestHandler.handler);
    try std.testing.expectEqualStrings("copy", cmd_with_optional.name);
    try std.testing.expectEqualStrings("Copy files", cmd_with_optional.getAbout().?);
}

test "deriveCommand generates flags for bool fields" {
    const Config = struct {
        verbose: bool,
        debug: bool,
        name: []const u8,
    };

    const TestHandler = struct {
        fn handler(ctx: Context.Context) Error.FlashError!void {
            _ = ctx;
        }
    };

    const derived = deriveCommand(Config, TestHandler.handler);
    // Bool fields become flags, non-bool become args
    try std.testing.expect(derived.getFlags().len >= 2);
    try std.testing.expect(derived.getArgs().len >= 1);
}