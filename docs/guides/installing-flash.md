# Installing Flash

Use the normal Zig package workflow.

## 1. Fetch The Source

```bash
zig fetch https://github.com/ghostkellz/flash/archive/main.tar.gz
```

Use the returned hash in `build.zig.zon`.

## 2. Add To `build.zig.zon`

```zig
.dependencies = .{
    .flash = .{
        .url = "https://github.com/ghostkellz/flash/archive/main.tar.gz",
        .hash = "<hash from zig fetch>",
    },
},
```

## 3. Add To `build.zig`

```zig
const flash_dep = b.dependency("flash", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("flash", flash_dep.module("flash"));
```

## 4. Use In Code

```zig
const flash = @import("flash");
```

Then continue with [Getting Started](getting-started.md).
