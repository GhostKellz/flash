const std = @import("std");
const flash = @import("flash");

fn deploy(ctx: flash.Context) flash.Error!void {
    const env = ctx.getString("environment") orelse return flash.Error.MissingRequiredArgument;
    const verbose = ctx.getBool("verbose") orelse false;

    if (verbose) std.debug.print("deploying with verbose output\n", .{});
    std.debug.print("deploying to {s}\n", .{env});
}

pub fn main(init: std.process.Init) !void {
    const deploy_cmd = flash.command(
        "deploy|dep --verbose <environment> -- Deploy an application",
        deploy,
    );

    const App = flash.CLI(.{
        .name = "ergonomic-example",
        .version = flash.version_string,
        .about = "Macro-first Flash example",
    });

    var cli = App.init(init.gpa, (flash.CommandConfig{})
        .withSubcommands(&.{deploy_cmd}));
    try cli.runWithInit(init);
}
