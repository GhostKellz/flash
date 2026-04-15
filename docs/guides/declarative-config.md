# Declarative CLI Configuration

Flash supports declarative CLI definitions using Zig structs with compile-time validation.

## Basic Usage

Define a struct where fields become CLI arguments:

```zig
const flash = @import("flash");

const MyArgs = struct {
    name: []const u8,
    count: i32 = 1,
    verbose: bool = false,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const args = try flash.parse(MyArgs, allocator);
    std.debug.print("Name: {s}, Count: {d}, Verbose: {}\n", .{
        args.name, args.count, args.verbose
    });
}
```

## Field Configuration with `fieldname_config`

For advanced field metadata, define a `pub const fieldname_config` declaration:

```zig
const flash = @import("flash");
const FieldConfig = flash.Declarative.FieldConfig;

const MyArgs = struct {
    // Simple field - uses defaults
    name: []const u8,

    // Field with explicit configuration
    format: []const u8,
    pub const format_config = FieldConfig{
        .help = "Output format",
        .choices = &.{ "json", "yaml", "toml" },
        .required = true,
    };

    // Field with custom validation
    port: i64,
    pub const port_config = FieldConfig{
        .help = "Server port (1024-65535)",
        .validator = validatePort,
    };

    // Hidden field (not shown in help)
    debug_key: []const u8 = "",
    pub const debug_key_config = FieldConfig{
        .hidden = true,
    };
};

fn validatePort(value: flash.ArgValue) flash.Error!void {
    const port = value.asInt();
    if (port < 1024 or port > 65535) {
        return flash.Error.ValidationError;
    }
}
```

## FieldConfig Options

| Field | Type | Description |
|-------|------|-------------|
| `help` | `?[]const u8` | Help text shown in usage |
| `long` | `?[]const u8` | Long flag name (e.g., `--output`) |
| `short` | `?u8` | Short flag character (e.g., `-o`) |
| `required` | `bool` | Whether the field is required |
| `default` | `?[]const u8` | Default value as string |
| `hidden` | `bool` | Hide from help output |
| `multiple` | `bool` | Allow multiple values |
| `validator` | `?ValidatorFn` | Custom validation function |
| `choices` | `?[]const []const u8` | Constrained value set |

## Constrained Choices

Use `choices` for enum-like arguments:

```zig
pub const level_config = FieldConfig{
    .help = "Log level",
    .choices = &.{ "debug", "info", "warn", "error" },
};
```

This enables:
- Validation (rejects invalid values)
- Help text shows available choices
- Shell completion suggests choices

## Custom Validators

Validators receive the parsed value and return an error on failure:

```zig
fn validateEmail(value: flash.ArgValue) flash.Error!void {
    const email = value.asString();
    if (std.mem.indexOf(u8, email, "@") == null) {
        return flash.Error.ValidationError;
    }
}

pub const email_config = FieldConfig{
    .validator = validateEmail,
};
```

## Parsing with Config

Use `parseWithConfig` for additional options:

```zig
const args = try flash.parseWithConfig(MyArgs, allocator, .{
    .name = "myapp",
    .about = "My application",
    .version = "1.0.0",
});
```

## Generating Help

```zig
const help_text = try flash.Declarative.generateHelp(MyArgs, allocator, .{
    .about = "My CLI tool",
});
defer allocator.free(help_text);
std.debug.print("{s}", .{help_text});
```

## Limitations

- Default values use struct field defaults, not `FieldConfig.default`
- For environment variable support, use `env.zig` directly with your parsed struct

For full flexibility, use the imperative `Command` and `Argument` APIs directly.
