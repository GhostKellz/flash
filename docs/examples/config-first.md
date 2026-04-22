# Config-First CLI Example

This example highlights one of Flash's strongest current stories:

- public CLI surface for commands and flags
- TOML via Flare for configuration
- explicit config merge behavior

```zig
const std = @import("std");
const flash = @import("flash");

const AppConfig = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 8080,
    debug: bool = false,
};

const ServeCLI = flash.CLI(.{
    .name = "servectl",
    .version = flash.version_string,
    .about = "Config-first service controller",
});

fn serve(ctx: flash.Context) flash.Error!void {
    const allocator = ctx.allocator;

const parser = flash.Config.ConfigParser.init(allocator);
const file_cfg = try parser.parseContent(AppConfig,
    \\host = "0.0.0.0"
    \\port = 9000
, .toml);

    var cli_cfg = AppConfig{};
    if (ctx.getString("host")) |host| cli_cfg.host = host;
    if (ctx.getInt("port")) |port| cli_cfg.port = @intCast(port);
    if (ctx.getBool("debug")) |debug| cli_cfg.debug = debug;

    const cfg = flash.Config.ConfigParser.merge(AppConfig, file_cfg, cli_cfg);
    std.debug.print("serving on {s}:{d} debug={}\n", .{ cfg.host, cfg.port, cfg.debug });
}
```

This is the recommended direction for config-heavy Flash applications in `v0.4.0`.
