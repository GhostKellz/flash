const std = @import("std");
const flash = @import("flash");

const DeployArgs = struct {
    environment: []const u8,
    verbose: bool = false,
    dry_run: bool = false,

    pub const environment_config = flash.Declarative.FieldConfig{
        .help = "Target environment",
        .required = true,
    };
    pub const verbose_config = flash.Declarative.FieldConfig{
        .help = "Enable verbose output",
        .long = "verbose",
        .short = 'v',
    };
    pub const dry_run_config = flash.Declarative.FieldConfig{
        .help = "Show the deployment plan only",
        .long = "dry-run",
    };
};

pub fn main() !void {
    std.debug.print(
        "Declarative example is exercised through tests. Use flash.Declarative.parseWithArgs(...) with explicit argv slices on this Zig baseline.\n",
        .{},
    );
}

test "declarative example help" {
    const help_text = try flash.Declarative.generateHelp(DeployArgs, std.testing.allocator, .{
        .about = "Declarative Flash example",
    });
    defer std.testing.allocator.free(help_text);

    try std.testing.expect(std.mem.indexOf(u8, help_text, "Declarative Flash example") != null);
    try std.testing.expect(std.mem.indexOf(u8, help_text, "dry-run") != null);
}

test "declarative example parsing" {
    const parsed = try flash.Declarative.parseWithArgs(DeployArgs, std.testing.allocator, &.{
        "deploy",
        "prod",
        "--verbose",
        "--dry-run",
    }, .{
        .about = "Declarative Flash example",
    });

    try std.testing.expectEqualStrings("prod", parsed.environment);
    try std.testing.expectEqual(true, parsed.verbose);
    try std.testing.expectEqual(true, parsed.dry_run);
}
