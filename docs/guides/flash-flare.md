# Flash + Flare

Flash uses Flare for TOML-backed configuration parsing in `v0.4.0`.

## When To Use What

- Use `flash.Config.ConfigParser` when you want a simple Flash-owned config entrypoint for JSON or TOML.
- Use Flare directly when TOML is the primary format and you want lower-level parse or deserialization control.
- Use `parseTomlWithDiagnostics()` when you want line/column context for invalid TOML input.

## Basic TOML Parsing

```zig
const std = @import("std");
const flash = @import("flash");

const AppConfig = struct {
    host: []const u8 = "127.0.0.1",
    port: i64 = 8080,
    debug: bool = false,
};

pub fn loadConfig(allocator: std.mem.Allocator, content: []const u8) !AppConfig {
    const parser = flash.Config.ConfigParser.init(allocator);
    return parser.parseContent(AppConfig, content, .toml);
}
```

TOML-backed string data may be owned by the allocator used during parsing. Callers are responsible for cleanup according to the ownership rules documented in `src/config.zig`.

## TOML Diagnostics

```zig
const result = parser.parseTomlWithDiagnostics(AppConfig, content);

switch (result) {
    .success => |config| {
        _ = config;
    },
    .failure => |diag| {
        std.debug.print("TOML error at {d}:{d}: {s}\n", .{ diag.line, diag.column, diag.message });
        if (diag.source_line) |line| std.debug.print("{s}\n", .{line});
    },
}
```

## YAML Status

YAML remains unsupported in `v0.4.0`.
`flash.Config.ConfigParser.parseContent(..., .yaml)` returns `UnsupportedConfigFormat`.

## Merge Semantics

- `merge()` keeps the existing zero-value-based behavior for compatibility.
- `mergeWithPresence()` allows explicit overrides for values like `false`, `0`, and `""`.

Use `mergeWithPresence()` when you already know which fields were explicitly provided by the caller or config source.
