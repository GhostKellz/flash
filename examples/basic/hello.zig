//! Basic Flash CLI Example
//! Demonstrates: Simple command, arguments, flags

const std = @import("std");
const flash = @import("flash");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a simple greet command
    const greet_cmd = flash.cmd("greet", (flash.CommandConfig{})
        .withAbout("Greet someone")
        .withArgs(&.{
            flash.arg("name", (flash.ArgumentConfig{})
                .withHelp("Name to greet")
                .withDefault(flash.ArgValue{ .string = "World" })),
        })
        .withFlags(&.{
            flash.flag("loud", (flash.FlagConfig{})
                .withShort('l')
                .withLong("loud")
                .withHelp("Greet loudly")),
            flash.flag("count", (flash.FlagConfig{})
                .withShort('c')
                .withLong("count")
                .withHelp("Number of times to greet")
                .withDefault(flash.ArgValue{ .int = 1 })),
        })
        .withHandler(greetHandler));

    // Create CLI with the command
    const CLI = flash.CLI(.{
        .name = "hello",
        .version = "1.0.0",
        .about = "A simple greeting CLI",
    });

    var cli = CLI.init(allocator, (flash.CommandConfig{})
        .withSubcommands(&.{greet_cmd}));

    try cli.run();
}

fn greetHandler(ctx: flash.Context) flash.Error!void {
    const name = ctx.getString("name") orelse "World";
    const loud = ctx.getBool("loud") orelse false;
    const count = ctx.getInt("count") orelse 1;

    var i: i64 = 0;
    while (i < count) : (i += 1) {
        if (loud) {
            std.debug.print("HELLO, {s}! ⚡\n", .{name});
        } else {
            std.debug.print("Hello, {s} ⚡\n", .{name});
        }
    }
}
