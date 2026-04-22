# Migrating To Flash 0.4

This guide covers the practical changes needed when moving to `v0.4.0`.

## What Changed

- `zsync` was removed from Flash entirely.
- Flash now owns its internal async foundations.
- TOML via Flare is the preferred config path.
- JSON config remains supported.
- YAML is still unsupported.
- Bash/Zsh completion support is now a primary product focus.

## Consumer Impact

If you only use the public CLI API, most migrations are small.

### Use `runWithInit(init)`

For Zig `0.17.0-dev`, prefer:

```zig
pub fn main(init: std.process.Init) !void {
    var cli = App.init(init.gpa, root_config);
    try cli.runWithInit(init);
}
```

Use `runWithInit(init)` or `runWithArgs(args)`; `cli.run()` is not part of the supported API on this Zig baseline.

### Keep Async In Your Application Layer

Flash's internal async runtime is real now, but it is still not public API.
If your app previously depended on internal async surfaces, move that orchestration into your own code for now.

### Prefer TOML Over YAML

Use:

```zig
const parser = flash.Config.ConfigParser.init(allocator);
```

Do not plan around YAML support in `v0.4.0`.

### Completion Guidance

- Bash dynamic completion is the strongest option
- Zsh generated completion is also first-class
- Fish, PowerShell, and NuShell are supported, but not as rich as Bash/Zsh

## Suggested Upgrade Checklist

1. update your `build.zig.zon` dependency version/hash
2. switch entrypoints to `runWithInit(init)` if needed
3. prefer TOML-backed config examples and docs
4. regenerate shell completion scripts
5. rerun your CLI help/completion/config tests
