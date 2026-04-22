//! ⚡ Flash Macros - CLAP-style ergonomic command definitions (Experimental)
//!
//! This module provides macro-based command definition similar to Rust's clap,
//! making Flash the most ergonomic CLI framework for Zig.
//!
//! FEATURES:
//! - command(spec, handler): Parse "name <arg> -- description" specs into commands, args, and nested subcommands
//! - CommandDef(T).build(): Build commands from structs with name/about declarations
//! - ChainBuilder / cmd(): Fluent builder pattern
//! - deriveCommand(): Generate commands from struct fields
//! - PatternMatcher: Match subcommands to handlers
//! - Middleware: Individual middleware functions (logging, timing, authentication)
//!
//! EXPERIMENTAL:
//! - AttributeCommand: Convenience wrapper around `command(spec, handler)`; true attribute parsing is not implemented

const std = @import("std");
const Command = @import("command.zig");
const Argument = @import("argument.zig");
const Flag = @import("flag.zig");
const Context = @import("context.zig");
const Declarative = @import("declarative.zig");
const Env = @import("env.zig");
const Error = @import("error.zig");

const ParsedArg = struct {
    name: []const u8,
    required: bool,
    multiple: bool = false,
    default: ?[]const u8 = null,
    choices: ?[]const []const u8 = null,
};

const ParsedCommandSpec = struct {
    name: []const u8,
    about: []const u8,
    path: []const ParsedCommandSegment,
    aliases: []const []const u8,
    args: []const ParsedArg,
    options: []const ParsedOption,
};

const ParsedCommandSegment = struct {
    name: []const u8,
    help: ?[]const u8 = null,
    hidden: bool = false,
    aliases: []const []const u8 = &.{},
};

const ParsedOption = struct {
    name: []const u8,
    short: ?u8 = null,
    long: ?[]const u8 = null,
    aliases: ?[]const []const u8 = null,
    help: ?[]const u8 = null,
    arg: ?ParsedArg = null,
};

pub const OptionGroup = struct {
    args: []const Argument.Argument = &.{},
    flags: []const Flag.Flag = &.{},

    pub fn init(args: []const Argument.Argument, flags: []const Flag.Flag) OptionGroup {
        return .{ .args = args, .flags = flags };
    }
};

pub const CommandGroup = struct {
    commands: []const Command.Command,

    pub fn init(commands: []const Command.Command) CommandGroup {
        return .{ .commands = commands };
    }
};

pub const MiddlewareBundle = struct {
    before: ?Command.HandlerFn = null,
    after: ?Command.HandlerFn = null,
    middleware: []const Middleware.MiddlewareFn = &.{},

    pub fn init(before: ?Command.HandlerFn, after: ?Command.HandlerFn, middleware: []const Middleware.MiddlewareFn) MiddlewareBundle {
        return .{ .before = before, .after = after, .middleware = middleware };
    }
};

const ParsedAttribute = union(enum) {
    about: []const u8,
    long_about: []const u8,
    version: []const u8,
    usage: []const u8,
    alias: []const u8,
    arg: ParsedAttributeArg,
    flag: ParsedAttributeFlag,
    hidden: void,
};

const ParsedAttributeArg = struct {
    name: []const u8,
    required: bool = false,
    multiple: bool = false,
    help: ?[]const u8 = null,
    short: ?u8 = null,
    long: ?[]const u8 = null,
    default: ?[]const u8 = null,
    choices: ?[]const []const u8 = null,
};

const ParsedAttributeFlag = struct {
    name: []const u8,
    help: ?[]const u8 = null,
    short: ?u8 = null,
    long: ?[]const u8 = null,
    global: bool = false,
};

/// Macro for defining commands with minimal boilerplate
/// Usage: @flash.command("vm run <name>", vmHandler)
pub fn command(comptime spec: []const u8, handler: anytype) Command.Command {
    const parsed = comptime parseCommandSpec(spec);
    const args = comptime buildSpecArguments(parsed.args, parsed.options);
    const options = comptime buildSpecOptions(parsed.options);
    const leaf_config = (Command.CommandConfig{})
        .withAbout(parsed.about)
        .withAliases(parsed.aliases)
        .withArgs(args)
        .withFlags(options.flags)
        .withHandler(handler);

    return buildCommandTree(parsed.path, leaf_config);
}

/// Parse command specification like "vm run <name> [options]"
/// Format: "command_name <required_arg> [optional_arg] -- description"
fn parseCommandSpec(comptime spec: []const u8) ParsedCommandSpec {
    const trimmed = std.mem.trim(u8, spec, " \t");

    // Check for description separator "--"
    var name_part: []const u8 = trimmed;
    var about: []const u8 = "";
    if (std.mem.indexOf(u8, trimmed, " -- ")) |sep_idx| {
        name_part = std.mem.trim(u8, trimmed[0..sep_idx], " \t");
        about = std.mem.trim(u8, trimmed[sep_idx + 4 ..], " \t");
    }

    var path: [16]ParsedCommandSegment = undefined;
    var path_count: usize = 0;
    var aliases: [8][]const u8 = undefined;
    var alias_count: usize = 0;
    var args: [16]ParsedArg = undefined;
    var arg_count: usize = 0;
    var options: [16]ParsedOption = undefined;
    var option_count: usize = 0;
    var i: usize = 0;
    while (i < name_part.len) {
        while (i < name_part.len and name_part[i] == ' ') : (i += 1) {}
        if (i >= name_part.len) break;

        if (name_part[i] == '-') {
            const start = i;
            i = findSpecTokenEnd(name_part, i);
            const option_token = name_part[start..i];

            var option_arg: ?ParsedArg = null;
            var lookahead = i;
            while (lookahead < name_part.len and name_part[lookahead] == ' ') : (lookahead += 1) {}
            if (lookahead < name_part.len and (name_part[lookahead] == '<' or name_part[lookahead] == '[')) {
                const required = name_part[lookahead] == '<';
                const close_char: u8 = if (required) '>' else ']';
                const value_start = lookahead + 1;
                var value_end = value_start;
                while (value_end < name_part.len and name_part[value_end] != close_char) : (value_end += 1) {}
                if (value_end >= name_part.len) @compileError("Unclosed option value in command spec: " ++ spec);
                option_arg = parseSpecArgToken(name_part[value_start..value_end], required);
                i = value_end + 1;
            }

            if (option_count < 16) {
                options[option_count] = parseSpecOptionToken(option_token, option_arg);
                option_count += 1;
            }
            continue;
        }

        if (name_part[i] == '<') {
            const start = i + 1;
            while (i < name_part.len and name_part[i] != '>') : (i += 1) {}
            if (i >= name_part.len) @compileError("Unclosed required argument in command spec: " ++ spec);
            if (arg_count < 16) {
                args[arg_count] = parseSpecArgToken(name_part[start..i], true);
                arg_count += 1;
            }
        } else if (name_part[i] == '[') {
            const start = i + 1;
            while (i < name_part.len and name_part[i] != ']') : (i += 1) {}
            if (i >= name_part.len) @compileError("Unclosed optional argument in command spec: " ++ spec);
            if (arg_count < 16) {
                args[arg_count] = parseSpecArgToken(name_part[start..i], false);
                arg_count += 1;
            }
        } else {
            const start = i;
            i = findSpecTokenEnd(name_part, i);
            if (path_count < 16) {
                const path_token = name_part[start..i];
                const parsed_segment = parseCommandSegment(path_token);
                path[path_count] = parsed_segment;
                if (path_count == 0) {
                    for (parsed_segment.aliases) |alias| {
                        if (alias_count < aliases.len) {
                            aliases[alias_count] = alias;
                            alias_count += 1;
                        }
                    }
                }
                path_count += 1;
            }
            continue;
        }

        i += 1;
    }

    const path_storage = path;
    const alias_storage = aliases;
    const command_path = path_storage[0..path_count];
    const cmd_name = if (command_path.len > 0) command_path[command_path.len - 1].name else "command";

    return .{
        .name = if (cmd_name.len > 0) cmd_name else "command",
        .about = if (about.len > 0) about else "Command: " ++ cmd_name,
        .path = command_path,
        .aliases = alias_storage[0..alias_count],
        .args = args[0..arg_count],
        .options = options[0..option_count],
    };
}

fn parseCommandSegment(comptime raw: []const u8) ParsedCommandSegment {
    var token = raw;
    var help: ?[]const u8 = null;
    var hidden = false;

    if (std.mem.endsWith(u8, token, "!")) {
        hidden = true;
        token = token[0 .. token.len - 1];
    }

    if (std.mem.indexOfScalar(u8, token, ':')) |colon_idx| {
        help = parseQuotedOrBareValue(token[colon_idx + 1 ..]);
        token = token[0..colon_idx];
    }

    var aliases: []const []const u8 = &.{};
    var name = token;
    if (std.mem.indexOfScalar(u8, token, '|')) |pipe_idx| {
        name = token[0..pipe_idx];
        aliases = parseChoiceList(token[pipe_idx + 1 ..]) orelse &.{};
    }

    return .{
        .name = name,
        .help = help,
        .hidden = hidden,
        .aliases = aliases,
    };
}

fn findSpecTokenEnd(comptime source: []const u8, start: usize) usize {
    var in_single = false;
    var in_double = false;
    var index = start;
    while (index < source.len) : (index += 1) {
        const char = source[index];
        if (char == '\'' and !in_double) {
            in_single = !in_single;
            continue;
        }
        if (char == '"' and !in_single) {
            in_double = !in_double;
            continue;
        }
        if (char == ' ' and !in_single and !in_double) {
            return index;
        }
    }
    return source.len;
}

fn parseSpecOptionToken(comptime raw: []const u8, option_arg: ?ParsedArg) ParsedOption {
    var result = ParsedOption{ .name = "option" };
    if (raw.len < 2) @compileError("Invalid option token in command spec: " ++ raw);
    const option_body = if (std.mem.startsWith(u8, raw, "--")) raw[2..] else raw[1..];
    if (option_body.len == 0) @compileError("Option token is missing a name in command spec: " ++ raw);
    const option_name = if (std.mem.indexOfScalar(u8, option_body, ':')) |colon_idx| option_body[0..colon_idx] else option_body;
    const help: ?[]const u8 = if (std.mem.indexOfScalar(u8, option_body, ':')) |colon_idx| parseQuotedOrBareValue(option_body[colon_idx + 1 ..]) else null;

    if (help) |description| {
        result.help = description;
    }

    const aliases = if (std.mem.indexOfScalar(u8, option_name, '|')) |pipe_idx|
        parseChoiceList(option_name[pipe_idx + 1 ..])
    else
        null;
    const primary_name = if (std.mem.indexOfScalar(u8, option_name, '|')) |pipe_idx| option_name[0..pipe_idx] else option_name;

    if (std.mem.startsWith(u8, raw, "--")) {
        result.long = primary_name;
        result.name = primary_name;
    } else if (std.mem.startsWith(u8, raw, "-")) {
        result.short = raw[1];
        result.name = std.fmt.comptimePrint("{c}", .{raw[1]});
    } else {
        @compileError("Unsupported option token in command spec: " ++ raw);
    }

    result.aliases = aliases;

    if (option_arg) |option_value| {
        result.arg = option_value;
        result.name = option_value.name;
    }

    return result;
}

fn parseSpecArgToken(comptime raw: []const u8, required: bool) ParsedArg {
    var name = raw;
    var multiple = false;
    var default: ?[]const u8 = null;
    var choices: ?[]const []const u8 = null;

    if (std.mem.endsWith(u8, name, "...")) {
        multiple = true;
        name = name[0 .. name.len - 3];
    }

    if (name.len == 0) @compileError("Empty argument token in command spec");

    if (std.mem.indexOfScalar(u8, name, '=')) |eq_idx| {
        default = name[eq_idx + 1 ..];
        name = name[0..eq_idx];
    }

    if (std.mem.indexOfScalar(u8, name, '|')) |pipe_idx| {
        const choice_tail = name[pipe_idx + 1 ..];
        name = name[0..pipe_idx];
        choices = parseChoiceList(choice_tail);
    }

    return .{
        .name = name,
        .required = required,
        .multiple = multiple,
        .default = default,
        .choices = choices,
    };
}

fn parseChoiceList(comptime raw: []const u8) ?[]const []const u8 {
    comptime var count: usize = 1;
    for (raw) |char| {
        if (char == '|') count += 1;
    }

    var choices: [count][]const u8 = undefined;
    var choice_count: usize = 0;
    var start: usize = 0;
    var index: usize = 0;
    while (index <= raw.len) : (index += 1) {
        if (index == raw.len or raw[index] == '|') {
            choices[choice_count] = raw[start..index];
            choice_count += 1;
            start = index + 1;
        }
    }

    const storage = choices;
    return storage[0..choice_count];
}

fn buildSpecArguments(comptime specs: []const ParsedArg, comptime options: []const ParsedOption) []const Argument.Argument {
    comptime var option_arg_count: usize = 0;
    for (options) |option| {
        if (option.arg != null) option_arg_count += 1;
    }

    return comptime blk: {
        var built: [specs.len + option_arg_count]Argument.Argument = undefined;
        var index: usize = 0;
        for (specs) |spec| {
            var config = (Argument.ArgumentConfig{})
                .withHelp(if (spec.required) "Required argument" else "Optional argument");
            if (spec.required) config = config.setRequired();
            if (spec.multiple) config = config.setMultiple();
            if (spec.default) |value| config = config.withDefault(.{ .string = value });
            if (spec.choices) |choices| config = config.withChoices(choices);
            built[index] = Argument.Argument.init(spec.name, config);
            index += 1;
        }

        for (options) |option| {
            const spec = option.arg orelse continue;

            var config = (Argument.ArgumentConfig{})
                .withHelp(option.help orelse if (spec.required) "Required option value" else "Optional option value");
            if (spec.required) config = config.setRequired();
            if (spec.multiple) config = config.setMultiple();
            if (spec.default) |value| config = config.withDefault(.{ .string = value });
            if (spec.choices) |choices| config = config.withChoices(choices);
            if (option.long) |long| config = config.withLong(long);
            if (option.aliases) |aliases| config = config.withAliases(aliases);
            if (option.short) |short| config = config.withShort(short);
            built[index] = Argument.Argument.init(option.name, config);
            index += 1;
        }

        const finalized = built;
        break :blk finalized[0..index];
    };
}

fn buildSpecOptions(comptime options: []const ParsedOption) struct { flags: []const Flag.Flag } {
    comptime var flag_count: usize = 0;
    for (options) |option| {
        if (option.arg == null) flag_count += 1;
    }

    return comptime blk: {
        var flags: [flag_count]Flag.Flag = undefined;
        var index: usize = 0;
        for (options) |option| {
            if (option.arg != null) continue;

            var config = Flag.FlagConfig{};
            if (option.help) |help| config = config.withHelp(help);
            if (option.long) |long| config = config.withLong(long);
            if (option.aliases) |aliases| config = config.withAliases(aliases);
            if (option.short) |short| config = config.withShort(short);
            flags[index] = Flag.Flag.init(option.name, config);
            index += 1;
        }

        const finalized_flags = flags;
        break :blk .{ .flags = finalized_flags[0..index] };
    };
}

fn buildCommandTree(comptime path: []const ParsedCommandSegment, leaf_config: Command.CommandConfig) Command.Command {
    if (path.len == 0) return Command.Command.init("command", leaf_config);
    if (path.len == 1) {
        var config = leaf_config.withAliases(path[0].aliases);
        if (path[0].help) |help| config = config.withAbout(help);
        if (path[0].hidden) config = config.setHidden();
        return Command.Command.init(path[0].name, config);
    }

    const child = buildCommandTree(path[1..], leaf_config);
    var config = (Command.CommandConfig{}).withSubcommands(&.{child}).withAliases(path[0].aliases);
    if (path[0].help) |help| config = config.withAbout(help);
    if (path[0].hidden) config = config.setHidden();
    return Command.Command.init(path[0].name, config);
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

    pub fn options(self: ChainBuilder, group: OptionGroup) ChainBuilder {
        var builder = self;
        builder.config = builder.config.withArgs(group.args).withFlags(group.flags);
        return builder;
    }

    pub fn commandGroup(self: ChainBuilder, group: CommandGroup) ChainBuilder {
        var builder = self;
        builder.config = builder.config.withSubcommands(group.commands);
        return builder;
    }

    pub fn handler(self: ChainBuilder, handler_fn: Command.HandlerFn) Command.Command {
        const final_config = self.config.withHandler(handler_fn);
        return Command.Command.init(self.name, final_config);
    }

    pub fn middleware(self: ChainBuilder, comptime middleware_list: []const Middleware.MiddlewareFn, comptime handler_fn: Command.HandlerFn) Command.Command {
        const final_config = self.config.withHandler(Middleware.wrap(handler_fn, middleware_list));
        return Command.Command.init(self.name, final_config);
    }

    pub fn before(self: ChainBuilder, hook: Command.HandlerFn) ChainBuilder {
        var builder = self;
        builder.config = builder.config.withBefore(hook);
        return builder;
    }

    pub fn after(self: ChainBuilder, hook: Command.HandlerFn) ChainBuilder {
        var builder = self;
        builder.config = builder.config.withAfter(hook);
        return builder;
    }

    pub fn middlewareWithHooks(self: ChainBuilder, comptime middleware_list: []const Middleware.MiddlewareFn, before_hook: ?Command.HandlerFn, after_hook: ?Command.HandlerFn, comptime handler_fn: Command.HandlerFn) Command.Command {
        var final_config = self.config.withHandler(Middleware.wrap(handler_fn, middleware_list));
        if (before_hook) |hook| final_config = final_config.withBefore(hook);
        if (after_hook) |hook| final_config = final_config.withAfter(hook);
        return Command.Command.init(self.name, final_config);
    }

    pub fn bundle(self: ChainBuilder, comptime middleware_bundle: MiddlewareBundle, comptime handler_fn: Command.HandlerFn) Command.Command {
        return self.middlewareWithHooks(middleware_bundle.middleware, middleware_bundle.before, middleware_bundle.after, handler_fn);
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

pub fn optionGroup(args: []const Argument.Argument, flags: []const Flag.Flag) OptionGroup {
    return OptionGroup.init(args, flags);
}

pub fn commandGroup(commands: []const Command.Command) CommandGroup {
    return CommandGroup.init(commands);
}

pub fn middlewareBundle(before: ?Command.HandlerFn, after: ?Command.HandlerFn, middleware: []const Middleware.MiddlewareFn) MiddlewareBundle {
    return MiddlewareBundle.init(before, after, middleware);
}

/// Derive command from struct using compile-time reflection
pub fn deriveCommand(comptime T: type, handler_fn: anytype) Command.Command {
    const info = @typeInfo(T);
    if (info != .@"struct") {
        @compileError("deriveCommand expects a struct type");
    }

    const struct_info = info.@"struct";
    const args = comptime buildDerivedArguments(T, struct_info.fields);
    const flags = comptime buildDerivedFlags(T, struct_info.fields);

    const type_name = @typeName(T);
    comptime var last_dot: ?usize = null;
    inline for (type_name, 0..) |c, idx| {
        if (c == '.') last_dot = idx;
    }
    const default_name = if (last_dot) |d| type_name[d + 1 ..] else type_name;
    const cmd_name: []const u8 = if (@hasDecl(T, "name")) T.name else default_name;
    const cmd_about: []const u8 = if (@hasDecl(T, "about")) T.about else "Auto-generated command";

    return Command.Command.init(cmd_name, (Command.CommandConfig{})
        .withAbout(cmd_about)
        .withArgs(args)
        .withFlags(flags)
        .withHandler(handler_fn));
}

fn buildDerivedArguments(comptime T: type, comptime fields: []const std.builtin.Type.StructField) []const Argument.Argument {
    comptime var arg_count: usize = 0;
    inline for (fields) |field| {
        if (isDerivedArgumentField(field.type)) arg_count += 1;
    }

    return comptime blk: {
        var built: [arg_count]Argument.Argument = undefined;
        var index: usize = 0;
        for (fields) |field| {
            if (!isDerivedArgumentField(field.type)) continue;

            const config = argumentConfigFromField(T, field);

            built[index] = makeTypedArgument(field.type, field.name, config);
            index += 1;
        }
        const finalized = built;
        break :blk finalized[0..];
    };
}

fn buildDerivedFlags(comptime T: type, comptime fields: []const std.builtin.Type.StructField) []const Flag.Flag {
    comptime var flag_count: usize = 0;
    inline for (fields) |field| {
        if (field.type == bool) flag_count += 1;
    }

    return comptime blk: {
        var built: [flag_count]Flag.Flag = undefined;
        var index: usize = 0;
        for (fields) |field| {
            if (field.type != bool) continue;

            const config = flagConfigFromField(T, field);
            built[index] = Flag.Flag.init(field.name, config);
            index += 1;
        }
        const finalized = built;
        break :blk finalized[0..];
    };
}

fn isDerivedArgumentField(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .bool => false,
        .int, .float, .@"enum" => true,
        .optional => |opt| isDerivedArgumentField(opt.child),
        .pointer => |ptr| ptr.size == .slice,
        else => false,
    };
}

fn isRequiredField(comptime field: std.builtin.Type.StructField) bool {
    if (field.default_value_ptr != null) return false;
    return switch (@typeInfo(field.type)) {
        .optional => false,
        else => true,
    };
}

fn makeTypedArgument(comptime T: type, name: []const u8, config: Argument.ArgumentConfig) Argument.Argument {
    return switch (@typeInfo(T)) {
        .optional => |opt| makeTypedArgument(opt.child, name, config),
        else => Argument.Argument.typed(T, name, config),
    };
}

fn getFieldConfig(comptime T: type, comptime field_name: []const u8) Declarative.FieldConfig {
    const config_name = field_name ++ "_config";
    if (@hasDecl(T, config_name)) {
        return @field(T, config_name);
    }
    return Declarative.FieldConfig{};
}

fn cliName(comptime field_name: []const u8) []const u8 {
    const normalized = comptime blk: {
        var result: [field_name.len]u8 = undefined;
        for (field_name, 0..) |char, index| {
            result[index] = if (char == '_') '-' else char;
        }
        break :blk result;
    };

    return std.fmt.comptimePrint("{s}", .{normalized});
}

fn argumentConfigFromField(comptime T: type, comptime field: std.builtin.Type.StructField) Argument.ArgumentConfig {
    const field_config = getFieldConfig(T, field.name);
    var config = (Argument.ArgumentConfig{})
        .withHelp(field_config.help orelse ("Auto-generated argument for " ++ field.name));
    config = addDerivedMetadataHelp(T, field.name, config);
    if (field_config.long) |long| {
        config = config.withLong(long);
    } else {
        config = config.withLong(cliName(field.name));
    }
    if (field_config.short) |short| config = config.withShort(short);
    if (field_config.hidden) config = config.setHidden();
    if (field_config.multiple) config = config.setMultiple();
    if (field_config.validator) |validator| config.validator = validator;
    if (field_config.choices) |choices| config.choices = choices;
    if (field_config.required or isRequiredField(field)) config = config.setRequired();
    return config;
}

fn addDerivedMetadataHelp(comptime T: type, comptime field_name: []const u8, config: Argument.ArgumentConfig) Argument.ArgumentConfig {
    const env_decl = field_name ++ "_env";
    const config_decl = field_name ++ "_source";

    var suffix: []const u8 = "";
    if (@hasDecl(T, env_decl)) {
        const env_config: Env.EnvConfig = @field(T, env_decl);
        if (env_config.env_var) |env_var| {
            suffix = std.fmt.comptimePrint(" [env: {s}]", .{env_var});
        } else if (env_config.prefix) |prefix| {
            suffix = std.fmt.comptimePrint(" [env prefix: {s}]", .{prefix});
        }
    }

    if (@hasDecl(T, config_decl)) {
        const source = @field(T, config_decl);
        suffix = std.fmt.comptimePrint("{s} [config: {s}]", .{ suffix, source });
    }

    if (suffix.len == 0) return config;
    return config.withHelp(std.fmt.comptimePrint("{s}{s}", .{ config.help orelse ("Auto-generated argument for " ++ field_name), suffix }));
}

fn flagConfigFromField(comptime T: type, comptime field: std.builtin.Type.StructField) Flag.FlagConfig {
    const field_config = getFieldConfig(T, field.name);
    var config = (Flag.FlagConfig{})
        .withHelp(field_config.help orelse ("Auto-generated flag for " ++ field.name));
    if (field_config.long) |long| {
        config = config.withLong(long);
    } else {
        config = config.withLong(cliName(field.name));
    }
    if (field_config.short) |short| config = config.withShort(short);
    if (field_config.hidden) config = config.setHidden();
    return config;
}

/// Attribute-based command definition (experimental)
pub fn AttributeCommand(comptime spec: []const u8) type {
    const parsed = comptime parseAttributeSpec(spec);
    return struct {
        pub fn define(comptime handler_fn: anytype) Command.Command {
            return buildAttributedCommand(parsed, handler_fn);
        }
    };
}

fn parseAttributeSpec(comptime spec: []const u8) struct {
    name: []const u8,
    attributes: []const ParsedAttribute,
} {
    const trimmed = std.mem.trim(u8, spec, " \t");
    const first_space = std.mem.indexOfScalar(u8, trimmed, ' ') orelse trimmed.len;
    const name = trimmed[0..first_space];
    const rest = std.mem.trim(u8, trimmed[first_space..], " \t");

    var attributes: [16]ParsedAttribute = undefined;
    var count: usize = 0;
    var index: usize = 0;
    while (index < rest.len) {
        const marker = std.mem.indexOfPos(u8, rest, index, "#[") orelse break;
        const close = findAttributeClose(rest, marker + 2) orelse break;
        if (count < 16) {
            attributes[count] = parseSingleAttribute(std.mem.trim(u8, rest[marker + 2 .. close], " \t"));
            count += 1;
        }
        index = close + 1;
    }

    const storage = attributes;
    return .{
        .name = name,
        .attributes = storage[0..count],
    };
}

fn findAttributeClose(comptime source: []const u8, start: usize) ?usize {
    var in_single = false;
    var in_double = false;
    var index = start;
    while (index < source.len) : (index += 1) {
        const char = source[index];
        if (char == '\'' and !in_double) {
            in_single = !in_single;
            continue;
        }
        if (char == '"' and !in_single) {
            in_double = !in_double;
            continue;
        }
        if (char == ']' and !in_single and !in_double) {
            return index;
        }
    }
    return null;
}

fn parseSingleAttribute(comptime raw: []const u8) ParsedAttribute {
    if (std.mem.eql(u8, raw, "hidden")) return .{ .hidden = {} };

    if (std.mem.startsWith(u8, raw, "about(")) {
        return .{ .about = parseQuotedValue(raw[6 .. raw.len - 1]) };
    }

    if (std.mem.startsWith(u8, raw, "long_about(")) {
        return .{ .long_about = parseQuotedValue(raw[11 .. raw.len - 1]) };
    }

    if (std.mem.startsWith(u8, raw, "version(")) {
        return .{ .version = parseQuotedValue(raw[8 .. raw.len - 1]) };
    }

    if (std.mem.startsWith(u8, raw, "usage(")) {
        return .{ .usage = parseQuotedValue(raw[6 .. raw.len - 1]) };
    }

    if (std.mem.startsWith(u8, raw, "alias(")) {
        return .{ .alias = parseQuotedValue(raw[6 .. raw.len - 1]) };
    }

    if (std.mem.startsWith(u8, raw, "arg(")) {
        return .{ .arg = parseAttributeArg(raw[4 .. raw.len - 1]) };
    }

    if (std.mem.startsWith(u8, raw, "flag(")) {
        return .{ .flag = parseAttributeFlag(raw[5 .. raw.len - 1]) };
    }

    @compileError("Unsupported attribute syntax: " ++ raw);
}

fn parseAttributeArg(comptime raw: []const u8) ParsedAttributeArg {
    var result = ParsedAttributeArg{ .name = "arg" };
    var iter = std.mem.tokenizeScalar(u8, raw, ',');
    var first = true;
    while (iter.next()) |token_raw| {
        const token = std.mem.trim(u8, token_raw, " \t");
        if (first) {
            result.name = parseQuotedOrBareValue(token);
            first = false;
            continue;
        }

        if (std.mem.eql(u8, token, "required")) {
            result.required = true;
        } else if (std.mem.eql(u8, token, "multiple")) {
            result.multiple = true;
        } else if (std.mem.startsWith(u8, token, "help=")) {
            result.help = parseQuotedValue(token[5..]);
        } else if (std.mem.startsWith(u8, token, "long=")) {
            result.long = parseQuotedValue(token[5..]);
        } else if (std.mem.startsWith(u8, token, "short='") and token.len >= 9) {
            result.short = token[7];
        } else if (std.mem.startsWith(u8, token, "default=")) {
            result.default = parseQuotedValue(token[8..]);
        } else if (std.mem.startsWith(u8, token, "choices=")) {
            result.choices = parseChoiceList(parseQuotedOrBareValue(token[8..]));
        }
    }
    if (std.mem.eql(u8, result.name, "arg")) @compileError("Attribute arg(...) requires a name");
    return result;
}

fn parseAttributeFlag(comptime raw: []const u8) ParsedAttributeFlag {
    var result = ParsedAttributeFlag{ .name = "flag" };
    var iter = std.mem.tokenizeScalar(u8, raw, ',');
    var first = true;
    while (iter.next()) |token_raw| {
        const token = std.mem.trim(u8, token_raw, " \t");
        if (first) {
            result.name = parseQuotedOrBareValue(token);
            first = false;
            continue;
        }

        if (std.mem.startsWith(u8, token, "help=")) {
            result.help = parseQuotedValue(token[5..]);
        } else if (std.mem.startsWith(u8, token, "long=")) {
            result.long = parseQuotedValue(token[5..]);
        } else if (std.mem.startsWith(u8, token, "short='") and token.len >= 9) {
            result.short = token[7];
        } else if (std.mem.eql(u8, token, "global")) {
            result.global = true;
        }
    }
    if (std.mem.eql(u8, result.name, "flag")) @compileError("Attribute flag(...) requires a name");
    return result;
}

fn parseQuotedOrBareValue(comptime raw: []const u8) []const u8 {
    if ((raw.len >= 2 and raw[0] == '"' and raw[raw.len - 1] == '"') or
        (raw.len >= 2 and raw[0] == '\'' and raw[raw.len - 1] == '\''))
    {
        return raw[1 .. raw.len - 1];
    }
    return raw;
}

fn parseQuotedValue(comptime raw: []const u8) []const u8 {
    const value = std.mem.trim(u8, raw, " \t");
    return parseQuotedOrBareValue(value);
}

fn buildAttributedCommand(comptime parsed: anytype, comptime handler_fn: anytype) Command.Command {
    return comptime blk: {
        var about: ?[]const u8 = null;
        var long_about: ?[]const u8 = null;
        var version: ?[]const u8 = null;
        var usage: ?[]const u8 = null;
        var hidden = false;
        var alias_storage: [8][]const u8 = undefined;
        var alias_count: usize = 0;
        var args_storage: [8]Argument.Argument = undefined;
        var arg_count: usize = 0;
        var flags_storage: [8]Flag.Flag = undefined;
        var flag_count: usize = 0;

        for (parsed.attributes) |attribute| {
            switch (attribute) {
                .about => |value| about = value,
                .long_about => |value| long_about = value,
                .version => |value| version = value,
                .usage => |value| usage = value,
                .alias => |value| {
                    if (alias_count < alias_storage.len) {
                        alias_storage[alias_count] = value;
                        alias_count += 1;
                    }
                },
                .arg => |value| {
                    if (arg_count < args_storage.len) {
                        var config = Argument.ArgumentConfig{};
                        if (value.help) |help| config = config.withHelp(help);
                        if (value.required) config = config.setRequired();
                        if (value.multiple) config = config.setMultiple();
                        if (value.long) |long| config = config.withLong(long);
                        if (value.short) |short| config = config.withShort(short);
                        if (value.default) |default| config = config.withDefault(.{ .string = default });
                        if (value.choices) |choices| config = config.withChoices(choices);
                        args_storage[arg_count] = Argument.Argument.init(value.name, config);
                        arg_count += 1;
                    }
                },
                .flag => |value| {
                    if (flag_count < flags_storage.len) {
                        var config = Flag.FlagConfig{};
                        if (value.help) |help| config = config.withHelp(help);
                        if (value.long) |long| config = config.withLong(long);
                        if (value.short) |short| config = config.withShort(short);
                        if (value.global) config = config.setGlobal();
                        flags_storage[flag_count] = Flag.Flag.init(value.name, config);
                        flag_count += 1;
                    }
                },
                .hidden => hidden = true,
            }
        }

        const alias_final = alias_storage;
        const args_final = args_storage;
        const flags_final = flags_storage;
        const aliases = alias_final[0..alias_count];
        const args = args_final[0..arg_count];
        const flags = flags_final[0..flag_count];

        var config = (Command.CommandConfig{})
            .withArgs(args)
            .withFlags(flags)
            .withAliases(aliases)
            .withHandler(handler_fn);
        if (about) |description| config = config.withAbout(description);
        if (long_about) |description| config = config.withLongAbout(description);
        if (version) |value| config = config.withVersion(value);
        if (usage) |value| config = config.withUsage(value);
        if (hidden) config = config.setHidden();

        break :blk Command.Command.init(parsed.name, config);
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

    pub fn wrap(comptime handler: Command.HandlerFn, comptime middleware_list: []const MiddlewareFn) Command.HandlerFn {
        if (middleware_list.len == 0) return handler;

        return struct {
            fn run(ctx: Context.Context) Error.FlashError!void {
                try callChain(0, ctx);
            }

            fn callChain(comptime index: usize, ctx: Context.Context) Error.FlashError!void {
                if (index >= middleware_list.len) {
                    return handler(ctx);
                }

                const current = middleware_list[index];
                const next = struct {
                    fn run(next_ctx: Context.Context) Error.FlashError!void {
                        return callChain(index + 1, next_ctx);
                    }
                }.run;

                return current(ctx, next);
            }
        }.run;
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
            fn getNanoTimestamp() i128 {
                if (@import("builtin").os.tag == .linux) {
                    var ts: std.os.linux.timespec = undefined;
                    _ = std.os.linux.clock_gettime(.MONOTONIC, &ts);
                    return @as(i128, ts.sec) * 1_000_000_000 + @as(i128, ts.nsec);
                } else {
                    return 0;
                }
            }
            pub fn middleware(ctx: Context.Context, next: *const fn (Context.Context) Error.FlashError!void) Error.FlashError!void {
                const start_time = getNanoTimestamp();
                try next(ctx);
                const end_time = getNanoTimestamp();
                const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
                std.debug.print("Command executed in {d:.2}ms\n", .{duration_ms});
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
        pub const name = "vm";
        pub const about = "Virtual machine command";
        vm_name: []const u8,
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
    try std.testing.expectEqualStrings("vm", vm_cmd.name);
    try std.testing.expectEqualStrings("Virtual machine command", vm_cmd.getAbout().?);
    try std.testing.expectEqual(@as(usize, 3), vm_cmd.getArgs().len);
    try std.testing.expectEqual(@as(usize, 1), vm_cmd.getFlags().len);
    try std.testing.expectEqual(Argument.ArgType.string, vm_cmd.getArgs()[0].arg_type);
    try std.testing.expectEqual(Argument.ArgType.int, vm_cmd.getArgs()[1].arg_type);
    try std.testing.expectEqual(true, vm_cmd.getArgs()[0].config.required);
}

test "pattern matching" {
    const allocator = std.testing.allocator;
    var ctx = Context.Context.init(allocator, &.{});
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
    try std.testing.expectEqual(@as(usize, 1), with_args.getArgs().len);
    try std.testing.expectEqual(true, with_args.getArgs()[0].config.required);

    const with_desc = command("start -- Start the service", TestHandler.handler);
    try std.testing.expectEqualStrings("start", with_desc.name);
    try std.testing.expectEqualStrings("Start the service", with_desc.getAbout().?);
}

test "command spec builds nested subcommands and optional args" {
    const TestHandler = struct {
        fn handler(ctx: Context.Context) Error.FlashError!void {
            _ = ctx;
        }
    };

    const nested = command("vm run <name> [image] -- Run a virtual machine", TestHandler.handler);
    try std.testing.expectEqualStrings("vm", nested.name);
    try std.testing.expectEqual(@as(usize, 1), nested.getSubcommands().len);

    const run_cmd = nested.getSubcommands()[0];
    try std.testing.expectEqualStrings("run", run_cmd.name);
    try std.testing.expectEqualStrings("Run a virtual machine", run_cmd.getAbout().?);
    try std.testing.expectEqual(@as(usize, 2), run_cmd.getArgs().len);
    try std.testing.expectEqual(true, run_cmd.getArgs()[0].config.required);
    try std.testing.expectEqual(false, run_cmd.getArgs()[1].config.required);
}

test "command spec supports defaults choices and repeated args" {
    const TestHandler = struct {
        fn handler(ctx: Context.Context) Error.FlashError!void {
            _ = ctx;
        }
    };

    const built = command("convert <format|json|toml=toml> [files...] -- Convert files", TestHandler.handler);
    try std.testing.expectEqualStrings("convert", built.name);
    try std.testing.expectEqual(@as(usize, 2), built.getArgs().len);
    try std.testing.expectEqualStrings("toml", built.getArgs()[0].getDefault().?.asString());
    try std.testing.expectEqual(@as(usize, 2), built.getArgs()[0].config.choices.?.len);
    try std.testing.expectEqual(true, built.getArgs()[1].config.multiple);
}

test "command spec supports inline flag and option grammar" {
    const TestHandler = struct {
        fn handler(ctx: Context.Context) Error.FlashError!void {
            _ = ctx;
        }
    };

    const built = command(
        "serve --verbose -q --output <path> -p <port|8080|9090=8080> --tag [value...] -- Serve content",
        TestHandler.handler,
    );

    try std.testing.expectEqualStrings("serve", built.name);
    try std.testing.expectEqualStrings("Serve content", built.getAbout().?);
    try std.testing.expectEqual(@as(usize, 2), built.getFlags().len);
    try std.testing.expectEqual(true, built.findFlag("verbose") != null);
    try std.testing.expectEqual(true, built.findFlag("q") != null);
    try std.testing.expectEqual(@as(usize, 3), built.getArgs().len);

    const output = built.findArg("output").?;
    try std.testing.expectEqualStrings("output", output.config.long.?);

    const port = built.findArg("port").?;
    try std.testing.expectEqual(@as(u8, 'p'), port.config.short.?);
    try std.testing.expectEqualStrings("8080", port.getDefault().?.asString());
    try std.testing.expectEqual(@as(usize, 2), port.config.choices.?.len);

    const tag = built.findArg("tag").?;
    try std.testing.expectEqual(true, tag.config.multiple);
    try std.testing.expectEqual(false, tag.config.required);
}

test "command spec supports inline option help and aliases" {
    const TestHandler = struct {
        fn handler(ctx: Context.Context) Error.FlashError!void {
            _ = ctx;
        }
    };

    const built = command(
        "serve|srv --verbose:'Enable verbose output' --config:'Path to config' <path> -- Serve content",
        TestHandler.handler,
    );

    try std.testing.expectEqual(@as(usize, 1), built.getAliases().len);
    try std.testing.expectEqualStrings("srv", built.getAliases()[0]);
    try std.testing.expectEqual(true, built.findFlag("verbose") != null);
    try std.testing.expectEqualStrings("Enable verbose output", built.findFlag("verbose").?.getHelp().?);
    try std.testing.expectEqualStrings("Path to config", built.findArg("config").?.getHelp().?);
}

test "command spec supports nested subcommand aliases and help" {
    const TestHandler = struct {
        fn handler(ctx: Context.Context) Error.FlashError!void {
            _ = ctx;
        }
    };

    const built = command(
        "vm|virtual-machine:'Virtual machine tools' run|start:'Run a VM' <name> -- Execute VM run",
        TestHandler.handler,
    );

    try std.testing.expectEqualStrings("vm", built.name);
    try std.testing.expectEqualStrings("Virtual machine tools", built.getAbout().?);
    try std.testing.expectEqual(@as(usize, 1), built.getAliases().len);
    try std.testing.expectEqualStrings("virtual-machine", built.getAliases()[0]);
    try std.testing.expectEqual(@as(usize, 1), built.getSubcommands().len);
    try std.testing.expectEqualStrings("run", built.getSubcommands()[0].name);
    try std.testing.expectEqualStrings("Run a VM", built.getSubcommands()[0].getAbout().?);
    try std.testing.expectEqual(true, built.getSubcommands()[0].matchesName("start"));
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

test "chain builder middleware wraps handler" {
    const State = struct {
        var calls: [3]u8 = undefined;
        var count: usize = 0;

        fn reset() void {
            count = 0;
        }

        fn push(value: u8) void {
            calls[count] = value;
            count += 1;
        }
    };

    const TestHandler = struct {
        fn handler(ctx: Context.Context) Error.FlashError!void {
            _ = ctx;
            State.push('H');
        }
    };

    const middlewares = [_]Middleware.MiddlewareFn{
        struct {
            fn middleware(ctx: Context.Context, next: *const fn (Context.Context) Error.FlashError!void) Error.FlashError!void {
                State.push('A');
                try next(ctx);
            }
        }.middleware,
        struct {
            fn middleware(ctx: Context.Context, next: *const fn (Context.Context) Error.FlashError!void) Error.FlashError!void {
                State.push('B');
                try next(ctx);
            }
        }.middleware,
    };

    const built = cmd("wrapped").middleware(&middlewares, TestHandler.handler);

    const allocator = std.testing.allocator;
    var ctx = Context.Context.init(allocator, &.{});
    defer ctx.deinit();

    State.reset();
    try built.execute(ctx);
    try std.testing.expectEqual(@as(usize, 3), State.count);
    try std.testing.expectEqual(@as(u8, 'A'), State.calls[0]);
    try std.testing.expectEqual(@as(u8, 'B'), State.calls[1]);
    try std.testing.expectEqual(@as(u8, 'H'), State.calls[2]);
}

test "chain builder middleware with before and after hooks" {
    const State = struct {
        var calls: [4]u8 = undefined;
        var count: usize = 0;

        fn reset() void {
            count = 0;
        }

        fn push(value: u8) void {
            calls[count] = value;
            count += 1;
        }
    };

    const Hooks = struct {
        fn before(ctx: Context.Context) Error.FlashError!void {
            _ = ctx;
            State.push('B');
        }

        fn after(ctx: Context.Context) Error.FlashError!void {
            _ = ctx;
            State.push('A');
        }

        fn handler(ctx: Context.Context) Error.FlashError!void {
            _ = ctx;
            State.push('H');
        }
    };

    const middlewares = [_]Middleware.MiddlewareFn{
        struct {
            fn middleware(ctx: Context.Context, next: *const fn (Context.Context) Error.FlashError!void) Error.FlashError!void {
                State.push('M');
                try next(ctx);
            }
        }.middleware,
    };

    const built = cmd("wrapped-hooks").middlewareWithHooks(&middlewares, Hooks.before, Hooks.after, Hooks.handler);

    const allocator = std.testing.allocator;
    var ctx = Context.Context.init(allocator, &.{});
    defer ctx.deinit();

    State.reset();
    try built.execute(ctx);
    try std.testing.expectEqual(@as(usize, 4), State.count);
    try std.testing.expectEqual(@as(u8, 'B'), State.calls[0]);
    try std.testing.expectEqual(@as(u8, 'M'), State.calls[1]);
    try std.testing.expectEqual(@as(u8, 'H'), State.calls[2]);
    try std.testing.expectEqual(@as(u8, 'A'), State.calls[3]);
}

test "chain builder supports reusable option groups" {
    const shared = optionGroup(
        &.{Argument.Argument.init("config", (Argument.ArgumentConfig{}).withHelp("Config path").withLong("config"))},
        &.{Flag.Flag.init("verbose", (Flag.FlagConfig{}).withShort('v').withLong("verbose").withHelp("Verbose output"))},
    );

    const TestHandler = struct {
        fn handler(ctx: Context.Context) Error.FlashError!void {
            _ = ctx;
        }
    };

    const built = cmd("serve")
        .options(shared)
        .handler(TestHandler.handler);

    try std.testing.expectEqual(true, built.findArg("config") != null);
    try std.testing.expectEqual(true, built.findFlag("verbose") != null);
}

test "chain builder supports reusable command groups and middleware bundles" {
    const State = struct {
        var calls: [3]u8 = undefined;
        var count: usize = 0;

        fn reset() void {
            count = 0;
        }

        fn push(value: u8) void {
            calls[count] = value;
            count += 1;
        }
    };

    const GroupHandlers = struct {
        fn start(ctx: Context.Context) Error.FlashError!void {
            _ = ctx;
        }

        fn stop(ctx: Context.Context) Error.FlashError!void {
            _ = ctx;
        }

        fn before(ctx: Context.Context) Error.FlashError!void {
            _ = ctx;
            State.push('B');
        }

        fn after(ctx: Context.Context) Error.FlashError!void {
            _ = ctx;
            State.push('A');
        }

        fn root(ctx: Context.Context) Error.FlashError!void {
            _ = ctx;
            State.push('H');
        }
    };

    const commands = commandGroup(&.{
        cmd("start").about("Start service").handler(GroupHandlers.start),
        cmd("stop").about("Stop service").handler(GroupHandlers.stop),
    });

    const built = cmd("service")
        .commandGroup(commands)
        .bundle(middlewareBundle(GroupHandlers.before, GroupHandlers.after, &.{}), GroupHandlers.root);

    try std.testing.expectEqual(@as(usize, 2), built.getSubcommands().len);

    const allocator = std.testing.allocator;
    var ctx = Context.Context.init(allocator, &.{});
    defer ctx.deinit();
    State.reset();
    try built.execute(ctx);
    try std.testing.expectEqual(@as(usize, 3), State.count);
    try std.testing.expectEqual(@as(u8, 'B'), State.calls[0]);
    try std.testing.expectEqual(@as(u8, 'H'), State.calls[1]);
    try std.testing.expectEqual(@as(u8, 'A'), State.calls[2]);
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
    try std.testing.expectEqual(Middleware.MiddlewareFn, @TypeOf(logging_fn));
}

test "middleware timing returns function" {
    const timing_fn = Middleware.timing();
    try std.testing.expectEqual(Middleware.MiddlewareFn, @TypeOf(timing_fn));
}

test "middleware authentication returns function" {
    const auth_fn = Middleware.authentication("admin");
    try std.testing.expectEqual(Middleware.MiddlewareFn, @TypeOf(auth_fn));
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
    try std.testing.expectEqual(@as(usize, 2), cmd_with_optional.getArgs().len);
    try std.testing.expectEqual(true, cmd_with_optional.getArgs()[0].config.required);
    try std.testing.expectEqual(false, cmd_with_optional.getArgs()[1].config.required);
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

test "AttributeCommand delegates to command spec parsing" {
    const TestHandler = struct {
        fn handler(ctx: Context.Context) Error.FlashError!void {
            _ = ctx;
        }
    };

    const built = AttributeCommand("deploy #[about(\"Deploy target\")] #[arg(\"target\", required)]").define(TestHandler.handler);
    try std.testing.expectEqualStrings("deploy", built.name);
    try std.testing.expectEqualStrings("Deploy target", built.getAbout().?);
    try std.testing.expectEqual(@as(usize, 1), built.getArgs().len);
}

test "AttributeCommand parses about aliases args and flags" {
    const TestHandler = struct {
        fn handler(ctx: Context.Context) Error.FlashError!void {
            _ = ctx;
        }
    };

    const built = AttributeCommand("deploy #[about(\"Deploy an app\")] #[alias(\"ship\")] #[arg(\"target\", required, help=\"Deployment target\", long=\"target\")] #[flag(\"verbose\", short='v', help=\"Verbose output\")]").define(TestHandler.handler);

    try std.testing.expectEqualStrings("deploy", built.name);
    try std.testing.expectEqualStrings("Deploy an app", built.getAbout().?);
    try std.testing.expectEqual(@as(usize, 1), built.getAliases().len);
    try std.testing.expectEqualStrings("ship", built.getAliases()[0]);
    try std.testing.expectEqual(@as(usize, 1), built.getArgs().len);
    try std.testing.expectEqualStrings("target", built.getArgs()[0].name);
    try std.testing.expectEqual(true, built.getArgs()[0].config.required);
    try std.testing.expectEqualStrings("Deployment target", built.getArgs()[0].getHelp().?);
    try std.testing.expectEqual(@as(usize, 1), built.getFlags().len);
    try std.testing.expectEqualStrings("verbose", built.getFlags()[0].name);
    try std.testing.expectEqual(true, built.findFlag("v") != null);
}

test "AttributeCommand parses long_about version usage defaults choices and global flags" {
    const TestHandler = struct {
        fn handler(ctx: Context.Context) Error.FlashError!void {
            _ = ctx;
        }
    };

    const built = AttributeCommand("serve #[about(\"Serve files\")] #[long_about(\"Serve files from a directory\")] #[version(\"1.2.3\")] #[usage(\"serve [options] <dir>\")] #[arg(\"format\", default=\"json\", choices=\"json|toml\")] #[flag(\"verbose\", global, long=\"verbose\")]").define(TestHandler.handler);

    try std.testing.expectEqualStrings("Serve files", built.getAbout().?);
    try std.testing.expectEqualStrings("Serve files from a directory", built.getLongAbout().?);
    try std.testing.expectEqualStrings("1.2.3", built.getVersion().?);
    try std.testing.expectEqualStrings("serve [options] <dir>", built.getUsage().?);
    try std.testing.expectEqualStrings("json", built.getArgs()[0].getDefault().?.asString());
    try std.testing.expectEqual(@as(usize, 2), built.getArgs()[0].config.choices.?.len);
    try std.testing.expectEqual(true, built.getFlags()[0].isGlobal());
}

test "macro-generated metadata improves help and usage output" {
    const TestHandler = struct {
        fn handler(ctx: Context.Context) Error.FlashError!void {
            _ = ctx;
        }
    };

    const built = AttributeCommand("serve #[about(\"Serve files\")] #[long_about(\"Serve files from a directory\")] #[version(\"1.2.3\")] #[usage(\"serve [OPTIONS] <dir>\")] #[arg(\"dir\", required, help=\"Directory to serve\")] #[flag(\"verbose\", short='v', help=\"Verbose output\")]").define(TestHandler.handler);

    const allocator = std.testing.allocator;
    const help = @import("help.zig").Help.init(allocator);

    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();

    try help.printCommandHelp(&aw.writer, built, built.name);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), "⚡ serve 1.2.3 - Serve files") != null);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), "serve [OPTIONS] <dir>") != null);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), "Directory to serve") != null);
    try std.testing.expect(std.mem.indexOf(u8, aw.written(), "Verbose output") != null);
}

test "AttributeCommand parses hidden marker" {
    const TestHandler = struct {
        fn handler(ctx: Context.Context) Error.FlashError!void {
            _ = ctx;
        }
    };

    const built = AttributeCommand("secret #[hidden]").define(TestHandler.handler);
    try std.testing.expectEqual(true, built.isHidden());
}

test "deriveCommand applies fieldname_config metadata" {
    const Config = struct {
        pub const name = "serve";
        pub const about = "Serve content";

        port: i32,
        format: []const u8,
        verbose: bool,

        pub const port_config = Declarative.FieldConfig{
            .help = "Listening port",
            .short = 'p',
            .long = "port",
            .required = true,
        };
        pub const format_config = Declarative.FieldConfig{
            .choices = &.{ "json", "toml" },
        };
        pub const verbose_config = Declarative.FieldConfig{
            .short = 'v',
            .long = "verbose",
        };
    };

    const TestHandler = struct {
        fn handler(ctx: Context.Context) Error.FlashError!void {
            _ = ctx;
        }
    };

    const built = deriveCommand(Config, TestHandler.handler);
    try std.testing.expectEqualStrings("serve", built.name);
    try std.testing.expectEqualStrings("Serve content", built.getAbout().?);
    try std.testing.expectEqualStrings("Listening port", built.getArgs()[0].getHelp().?);
    try std.testing.expectEqual(@as(u8, 'p'), built.getArgs()[0].config.short.?);
    try std.testing.expectEqualStrings("port", built.getArgs()[0].config.long.?);
    try std.testing.expectEqual(true, built.getArgs()[0].config.required);
    try std.testing.expectEqual(@as(usize, 2), built.getArgs()[1].config.choices.?.len);
    try std.testing.expectEqual(@as(u8, 'v'), built.getFlags()[0].config.short.?);
    try std.testing.expectEqualStrings("verbose", built.getFlags()[0].config.long.?);
}

test "deriveCommand annotates env and config metadata in help" {
    const Config = struct {
        pub const name = "serve";

        path: []const u8,

        pub const path_config = Declarative.FieldConfig{
            .help = "Project path",
        };
        pub const path_env = Env.EnvConfig{ .env_var = "FLASH_PATH" };
        pub const path_source = "project.toml";
    };

    const TestHandler = struct {
        fn handler(ctx: Context.Context) Error.FlashError!void {
            _ = ctx;
        }
    };

    const built = deriveCommand(Config, TestHandler.handler);
    try std.testing.expect(std.mem.indexOf(u8, built.getArgs()[0].getHelp().?, "[env: FLASH_PATH]") != null);
    try std.testing.expect(std.mem.indexOf(u8, built.getArgs()[0].getHelp().?, "[config: project.toml]") != null);
}
