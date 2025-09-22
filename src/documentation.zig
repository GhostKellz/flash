//! ⚡ Flash Documentation Generation
//!
//! Generate documentation in multiple formats: Markdown, HTML, Man pages, JSON
//! Inspired by clap_mangen and Cobra's doc generation

const std = @import("std");
const Command = @import("command.zig");
const Argument = @import("argument.zig");
const Flag = @import("flag.zig");
const CLI = @import("cli.zig");

/// Documentation format options
pub const DocFormat = enum {
    markdown,
    html,
    man,
    json,
    yaml,

    pub fn fileExtension(self: DocFormat) []const u8 {
        return switch (self) {
            .markdown => ".md",
            .html => ".html",
            .man => ".1",
            .json => ".json",
            .yaml => ".yaml",
        };
    }
};

/// Documentation configuration
pub const DocConfig = struct {
    output_dir: []const u8 = "docs",
    include_examples: bool = true,
    include_source_links: bool = false,
    source_base_url: ?[]const u8 = null,
    custom_css: ?[]const u8 = null,
    author: ?[]const u8 = null,
    version: ?[]const u8 = null,
    date: ?[]const u8 = null,

    pub fn withOutputDir(self: DocConfig, dir: []const u8) DocConfig {
        var config = self;
        config.output_dir = dir;
        return config;
    }

    pub fn withAuthor(self: DocConfig, author: []const u8) DocConfig {
        var config = self;
        config.author = author;
        return config;
    }

    pub fn withVersion(self: DocConfig, version: []const u8) DocConfig {
        var config = self;
        config.version = version;
        return config;
    }
};

/// Documentation generator
pub const DocGenerator = struct {
    allocator: std.mem.Allocator,
    config: DocConfig,

    pub fn init(allocator: std.mem.Allocator, config: DocConfig) DocGenerator {
        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    /// Generate documentation for a CLI in specified format
    pub fn generate(self: DocGenerator, command: Command.Command, format: DocFormat, program_name: []const u8) ![]u8 {
        return switch (format) {
            .markdown => self.generateMarkdown(command, program_name),
            .html => self.generateHTML(command, program_name),
            .man => self.generateMan(command, program_name),
            .json => self.generateJSON(command, program_name),
            .yaml => self.generateYAML(command, program_name),
        };
    }

    /// Generate all formats to files
    pub fn generateAll(self: DocGenerator, command: Command.Command, program_name: []const u8, formats: []const DocFormat) !void {
        // Ensure output directory exists
        try std.fs.cwd().makePath(self.config.output_dir);

        for (formats) |format| {
            const content = try self.generate(command, format, program_name);
            defer self.allocator.free(content);

            const filename = try std.fmt.allocPrint(self.allocator, "{s}/{s}{s}", .{
                self.config.output_dir,
                program_name,
                format.fileExtension(),
            });
            defer self.allocator.free(filename);

            try std.fs.cwd().writeFile(.{ .sub_path = filename, .data = content });
        }
    }

    /// Generate Markdown documentation
    fn generateMarkdown(self: DocGenerator, command: Command.Command, program_name: []const u8) ![]u8 {
        var buf = std.ArrayList(u8).init(self.allocator);
        const writer = buf.writer();

        // Header
        try writer.print("# {s}\n\n", .{program_name});

        if (command.getAbout()) |about| {
            try writer.print("{s}\n\n", .{about});
        }

        // Usage
        try writer.print("## Usage\n\n");
        try writer.print("```bash\n");
        try self.writeUsage(writer, command, program_name);
        try writer.print("```\n\n");

        // Description
        if (command.getLongAbout()) |long_about| {
            try writer.print("## Description\n\n");
            try writer.print("{s}\n\n", .{long_about});
        }

        // Arguments
        const args = command.getArguments();
        if (args.len > 0) {
            try writer.print("## Arguments\n\n");
            for (args) |arg| {
                try writer.print("### `{s}`\n\n", .{arg.name});
                if (arg.getHelp()) |help| {
                    try writer.print("{s}\n\n", .{help});
                }

                if (arg.isRequired()) {
                    try writer.print("**Required**\n\n");
                }

                if (arg.getDefaultValue()) |default| {
                    try writer.print("**Default:** `{s}`\n\n", .{default});
                }

                if (arg.getPossibleValues()) |values| {
                    try writer.print("**Possible values:** ", .{});
                    for (values, 0..) |value, i| {
                        if (i > 0) try writer.print(", ");
                        try writer.print("`{s}`", .{value});
                    }
                    try writer.print("\n\n");
                }
            }
        }

        // Flags/Options
        const flags = command.getFlags();
        if (flags.len > 0) {
            try writer.print("## Options\n\n");
            for (flags) |flag| {
                try writer.print("### ");
                if (flag.short) |short| {
                    try writer.print("`-{c}`", .{short});
                    if (flag.long) |long| {
                        try writer.print(", `--{s}`", .{long});
                    }
                } else if (flag.long) |long| {
                    try writer.print("`--{s}`", .{long});
                }
                try writer.print("\n\n");

                if (flag.help) |help| {
                    try writer.print("{s}\n\n", .{help});
                }

                if (flag.value_name) |value_name| {
                    try writer.print("**Value:** `{s}`\n\n", .{value_name});
                }
            }
        }

        // Subcommands
        const subcommands = command.getSubcommands();
        if (subcommands.len > 0) {
            try writer.print("## Subcommands\n\n");
            for (subcommands) |subcmd| {
                if (subcmd.isHidden()) continue;

                try writer.print("### `{s}`\n\n", .{subcmd.name});
                if (subcmd.getAbout()) |about| {
                    try writer.print("{s}\n\n", .{about});
                }

                // Recursive generation for subcommands
                if (self.config.include_examples) {
                    try writer.print("```bash\n");
                    try writer.print("{s} {s}", .{ program_name, subcmd.name });
                    // Add example args/flags
                    try writer.print("\n```\n\n");
                }
            }
        }

        // Examples
        if (self.config.include_examples) {
            try writer.print("## Examples\n\n");
            if (command.getExample()) |example| {
                try writer.print("```bash\n{s}\n```\n\n", .{example});
            } else {
                // Generate basic examples
                try writer.print("```bash\n");
                try writer.print("# Show help\n{s} --help\n\n", .{program_name});
                try writer.print("# Show version\n{s} --version\n", .{program_name});
                try writer.print("```\n\n");
            }
        }

        // Footer
        if (self.config.author) |author| {
            try writer.print("## Author\n\n{s}\n\n", .{author});
        }

        if (self.config.version) |version| {
            try writer.print("## Version\n\n{s}\n\n", .{version});
        }

        return buf.toOwnedSlice();
    }

    /// Generate HTML documentation
    fn generateHTML(self: DocGenerator, command: Command.Command, program_name: []const u8) ![]u8 {
        var buf = std.ArrayList(u8).init(self.allocator);
        const writer = buf.writer();

        // HTML header
        try writer.print("<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n");
        try writer.print("    <meta charset=\"UTF-8\">\n");
        try writer.print("    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n");
        try writer.print("    <title>{s} Documentation</title>\n", .{program_name});

        // CSS
        if (self.config.custom_css) |css| {
            try writer.print("    <link rel=\"stylesheet\" href=\"{s}\">\n", .{css});
        } else {
            try writer.print("    <style>\n");
            try writer.print("        body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; max-width: 800px; margin: 0 auto; padding: 2rem; line-height: 1.6; }}\n");
            try writer.print("        .command {{ background: #f5f5f5; padding: 1rem; border-radius: 4px; font-family: monospace; }}\n");
            try writer.print("        .flag {{ background: #e3f2fd; padding: 0.2rem 0.4rem; border-radius: 3px; font-family: monospace; }}\n");
            try writer.print("        h1, h2, h3 {{ color: #333; }}\n");
            try writer.print("        pre {{ background: #f8f8f8; padding: 1rem; border-radius: 4px; overflow-x: auto; }}\n");
            try writer.print("    </style>\n");
        }

        try writer.print("</head>\n<body>\n");

        // Content
        try writer.print("    <h1>⚡ {s}</h1>\n", .{program_name});

        if (command.getAbout()) |about| {
            try writer.print("    <p>{s}</p>\n", .{about});
        }

        // Usage
        try writer.print("    <h2>Usage</h2>\n");
        try writer.print("    <div class=\"command\">", .{});
        try self.writeUsage(writer, command, program_name);
        try writer.print("</div>\n");

        // Arguments
        const args = command.getArguments();
        if (args.len > 0) {
            try writer.print("    <h2>Arguments</h2>\n");
            try writer.print("    <dl>\n");
            for (args) |arg| {
                try writer.print("        <dt><code>{s}</code></dt>\n", .{arg.name});
                try writer.print("        <dd>");
                if (arg.getHelp()) |help| {
                    try writer.print("{s}", .{help});
                }
                if (arg.isRequired()) {
                    try writer.print(" <em>(required)</em>");
                }
                try writer.print("</dd>\n");
            }
            try writer.print("    </dl>\n");
        }

        // Flags
        const flags = command.getFlags();
        if (flags.len > 0) {
            try writer.print("    <h2>Options</h2>\n");
            try writer.print("    <dl>\n");
            for (flags) |flag| {
                try writer.print("        <dt>");
                if (flag.short) |short| {
                    try writer.print("<span class=\"flag\">-{c}</span>", .{short});
                    if (flag.long) |long| {
                        try writer.print(", <span class=\"flag\">--{s}</span>", .{long});
                    }
                } else if (flag.long) |long| {
                    try writer.print("<span class=\"flag\">--{s}</span>", .{long});
                }
                try writer.print("</dt>\n");
                try writer.print("        <dd>");
                if (flag.help) |help| {
                    try writer.print("{s}", .{help});
                }
                try writer.print("</dd>\n");
            }
            try writer.print("    </dl>\n");
        }

        // Subcommands
        const subcommands = command.getSubcommands();
        if (subcommands.len > 0) {
            try writer.print("    <h2>Subcommands</h2>\n");
            try writer.print("    <dl>\n");
            for (subcommands) |subcmd| {
                if (subcmd.isHidden()) continue;
                try writer.print("        <dt><code>{s}</code></dt>\n", .{subcmd.name});
                try writer.print("        <dd>");
                if (subcmd.getAbout()) |about| {
                    try writer.print("{s}", .{about});
                }
                try writer.print("</dd>\n");
            }
            try writer.print("    </dl>\n");
        }

        // Footer
        try writer.print("</body>\n</html>\n");

        return buf.toOwnedSlice();
    }

    /// Generate man page
    fn generateMan(self: DocGenerator, command: Command.Command, program_name: []const u8) ![]u8 {
        var buf = std.ArrayList(u8).init(self.allocator);
        const writer = buf.writer();

        // Man page header
        try writer.print(".TH {s} 1", .{program_name});
        if (self.config.date) |date| {
            try writer.print(" \"{s}\"", .{date});
        }
        if (self.config.version) |version| {
            try writer.print(" \"Version {s}\"", .{version});
        }
        try writer.print(" \"User Commands\"\n");

        // Name section
        try writer.print(".SH NAME\n");
        try writer.print("{s}", .{program_name});
        if (command.getAbout()) |about| {
            try writer.print(" \\- {s}", .{about});
        }
        try writer.print("\n");

        // Synopsis section
        try writer.print(".SH SYNOPSIS\n");
        try writer.print(".B {s}\n", .{program_name});

        const flags = command.getFlags();
        if (flags.len > 0) {
            try writer.print("[\\fIOPTIONS\\fR]\n");
        }

        const args = command.getArguments();
        for (args) |arg| {
            if (arg.isRequired()) {
                try writer.print("\\fI{s}\\fR\n", .{arg.name});
            } else {
                try writer.print("[\\fI{s}\\fR]\n", .{arg.name});
            }
        }

        // Description
        if (command.getLongAbout()) |long_about| {
            try writer.print(".SH DESCRIPTION\n");
            try writer.print("{s}\n", .{long_about});
        }

        // Options
        if (flags.len > 0) {
            try writer.print(".SH OPTIONS\n");
            for (flags) |flag| {
                try writer.print(".TP\n");
                if (flag.short) |short| {
                    try writer.print("\\fB\\-{c}\\fR", .{short});
                    if (flag.long) |long| {
                        try writer.print(", \\fB\\-\\-{s}\\fR", .{long});
                    }
                } else if (flag.long) |long| {
                    try writer.print("\\fB\\-\\-{s}\\fR", .{long});
                }
                try writer.print("\n");
                if (flag.help) |help| {
                    try writer.print("{s}\n", .{help});
                }
            }
        }

        // Author
        if (self.config.author) |author| {
            try writer.print(".SH AUTHOR\n");
            try writer.print("{s}\n", .{author});
        }

        return buf.toOwnedSlice();
    }

    /// Generate JSON documentation
    fn generateJSON(self: DocGenerator, command: Command.Command, program_name: []const u8) ![]u8 {
        var buf = std.ArrayList(u8).init(self.allocator);
        const writer = buf.writer();

        try writer.print("{{\n");
        try writer.print("  \"name\": \"{s}\",\n", .{program_name});

        if (command.getAbout()) |about| {
            try writer.print("  \"description\": \"{s}\",\n", .{about});
        }

        if (command.getLongAbout()) |long_about| {
            try writer.print("  \"long_description\": \"{s}\",\n", .{long_about});
        }

        if (self.config.version) |version| {
            try writer.print("  \"version\": \"{s}\",\n", .{version});
        }

        // Arguments
        const args = command.getArguments();
        if (args.len > 0) {
            try writer.print("  \"arguments\": [\n");
            for (args, 0..) |arg, i| {
                try writer.print("    {{\n");
                try writer.print("      \"name\": \"{s}\",\n", .{arg.name});
                if (arg.getHelp()) |help| {
                    try writer.print("      \"help\": \"{s}\",\n", .{help});
                }
                try writer.print("      \"required\": {s}\n", .{if (arg.isRequired()) "true" else "false"});
                try writer.print("    }}{s}\n", .{if (i < args.len - 1) "," else ""});
            }
            try writer.print("  ],\n");
        }

        // Flags
        const flags = command.getFlags();
        if (flags.len > 0) {
            try writer.print("  \"flags\": [\n");
            for (flags, 0..) |flag, i| {
                try writer.print("    {{\n");
                if (flag.long) |long| {
                    try writer.print("      \"long\": \"{s}\",\n", .{long});
                }
                if (flag.short) |short| {
                    try writer.print("      \"short\": \"{c}\",\n", .{short});
                }
                if (flag.help) |help| {
                    try writer.print("      \"help\": \"{s}\",\n", .{help});
                }
                try writer.print("      \"takes_value\": {s}\n", .{if (flag.takes_value) "true" else "false"});
                try writer.print("    }}{s}\n", .{if (i < flags.len - 1) "," else ""});
            }
            try writer.print("  ],\n");
        }

        // Subcommands
        const subcommands = command.getSubcommands();
        if (subcommands.len > 0) {
            try writer.print("  \"subcommands\": [\n");
            for (subcommands, 0..) |subcmd, i| {
                if (subcmd.isHidden()) continue;
                try writer.print("    {{\n");
                try writer.print("      \"name\": \"{s}\",\n", .{subcmd.name});
                if (subcmd.getAbout()) |about| {
                    try writer.print("      \"description\": \"{s}\",\n", .{about});
                }
                try writer.print("      \"hidden\": {s}\n", .{if (subcmd.isHidden()) "true" else "false"});
                try writer.print("    }}{s}\n", .{if (i < subcommands.len - 1) "," else ""});
            }
            try writer.print("  ]\n");
        }

        try writer.print("}}\n");

        return buf.toOwnedSlice();
    }

    /// Generate YAML documentation
    fn generateYAML(self: DocGenerator, command: Command.Command, program_name: []const u8) ![]u8 {
        var buf = std.ArrayList(u8).init(self.allocator);
        const writer = buf.writer();

        try writer.print("name: {s}\n", .{program_name});

        if (command.getAbout()) |about| {
            try writer.print("description: \"{s}\"\n", .{about});
        }

        if (self.config.version) |version| {
            try writer.print("version: \"{s}\"\n", .{version});
        }

        // Arguments
        const args = command.getArguments();
        if (args.len > 0) {
            try writer.print("arguments:\n");
            for (args) |arg| {
                try writer.print("  - name: {s}\n", .{arg.name});
                if (arg.getHelp()) |help| {
                    try writer.print("    help: \"{s}\"\n", .{help});
                }
                try writer.print("    required: {s}\n", .{if (arg.isRequired()) "true" else "false"});
            }
        }

        // Flags
        const flags = command.getFlags();
        if (flags.len > 0) {
            try writer.print("flags:\n");
            for (flags) |flag| {
                try writer.print("  - ");
                if (flag.long) |long| {
                    try writer.print("long: {s}\n", .{long});
                }
                if (flag.short) |short| {
                    try writer.print("    short: {c}\n", .{short});
                }
                if (flag.help) |help| {
                    try writer.print("    help: \"{s}\"\n", .{help});
                }
            }
        }

        return buf.toOwnedSlice();
    }

    /// Helper to write usage line
    fn writeUsage(self: DocGenerator, writer: anytype, command: Command.Command, program_name: []const u8) !void {
        _ = self;
        try writer.print("{s}", .{program_name});

        const flags = command.getFlags();
        if (flags.len > 0) {
            try writer.print(" [OPTIONS]");
        }

        const args = command.getArguments();
        for (args) |arg| {
            if (arg.isRequired()) {
                try writer.print(" <{s}>", .{arg.name});
            } else {
                try writer.print(" [{s}]", .{arg.name});
            }
        }

        const subcommands = command.getSubcommands();
        if (subcommands.len > 0) {
            try writer.print(" [SUBCOMMAND]");
        }

        try writer.print("\n");
    }
};

// Tests
test "markdown generation" {
    const allocator = std.testing.allocator;
    const config = DocConfig{};
    var generator = DocGenerator.init(allocator, config);

    const test_cmd = Command.Command.init("testcli", (Command.CommandConfig{})
        .withAbout("A test CLI application"));

    const markdown = try generator.generateMarkdown(test_cmd, "testcli");
    defer allocator.free(markdown);

    try std.testing.expect(std.mem.indexOf(u8, markdown, "# testcli") != null);
    try std.testing.expect(std.mem.indexOf(u8, markdown, "A test CLI application") != null);
}

test "html generation" {
    const allocator = std.testing.allocator;
    const config = DocConfig{};
    var generator = DocGenerator.init(allocator, config);

    const test_cmd = Command.Command.init("testcli", (Command.CommandConfig{})
        .withAbout("A test CLI application"));

    const html = try generator.generateHTML(test_cmd, "testcli");
    defer allocator.free(html);

    try std.testing.expect(std.mem.indexOf(u8, html, "<!DOCTYPE html>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "testcli") != null);
}

test "json generation" {
    const allocator = std.testing.allocator;
    const config = DocConfig{};
    var generator = DocGenerator.init(allocator, config);

    const test_cmd = Command.Command.init("testcli", (Command.CommandConfig{})
        .withAbout("A test CLI application"));

    const json = try generator.generateJSON(test_cmd, "testcli");
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"name\": \"testcli\"") != null);
}