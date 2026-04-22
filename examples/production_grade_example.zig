const std = @import("std");
const flash = @import("flash");

const AppConfig = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 8080,
    debug: bool = false,
};

const App = flash.CLI(.{
    .name = "opsctl",
    .version = flash.version_string,
    .about = "Production-style Flash CLI",
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

    const merged = flash.Config.ConfigParser.merge(AppConfig, file_cfg, cli_cfg);
    std.debug.print("serving on {s}:{d} debug={}\n", .{ merged.host, merged.port, merged.debug });
}

pub fn main(init: std.process.Init) !void {
    const serve_cmd = flash.cmd("serve", (flash.CommandConfig{})
        .withAbout("Run the service")
        .withArgs(&.{
            flash.arg("host", (flash.ArgumentConfig{}).withHelp("Override host")),
            flash.arg("port", (flash.ArgumentConfig{}).withHelp("Override port")),
        })
        .withFlags(&.{flash.flag("debug", (flash.FlagConfig{})
            .withLong("debug")
            .withHelp("Enable debug mode"))})
        .withHandler(serve));

    var cli = App.init(init.gpa, (flash.CommandConfig{})
        .withFlags(&.{flash.flag("verbose", (flash.FlagConfig{})
            .withShort('v')
            .withLong("verbose")
            .withHelp("Verbose output")
            .setGlobal())})
        .withSubcommands(&.{serve_cmd}));

    try cli.runWithInit(init);
}
