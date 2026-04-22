//! Basic Flash CLI example using the current public API.

const std = @import("std");
const flash = @import("flash");

const HelloCLI = flash.CLI(.{
    .name = "hello",
    .version = flash.version_string,
    .about = "A simple greeting CLI",
});

fn greetHandler(ctx: flash.Context) flash.Error!void {
    const name = ctx.getString("name") orelse "World";
    const loud = ctx.getBool("loud") orelse false;

    if (loud) {
        std.debug.print("HELLO, {s}!\n", .{name});
    } else {
        std.debug.print("Hello, {s}.\n", .{name});
    }
}

pub fn main(init: std.process.Init) !void {
    const greet_cmd = flash.cmd("greet", (flash.CommandConfig{})
        .withAbout("Greet someone")
        .withArgs(&.{flash.arg("name", (flash.ArgumentConfig{})
            .withHelp("Name to greet")
            .withDefault(flash.ArgValue{ .string = "World" }))})
        .withFlags(&.{flash.flag("loud", (flash.FlagConfig{})
            .withShort('l')
            .withLong("loud")
            .withHelp("Use uppercase output"))})
        .withHandler(greetHandler));

    var cli = HelloCLI.init(init.gpa, (flash.CommandConfig{})
        .withSubcommands(&.{greet_cmd}));
    try cli.runWithInit(init);
}
