# 📝 Example: Basic CLI Application

This example demonstrates building a simple but complete CLI application with Flash, covering the most common patterns you'll use.

## 🎯 What We're Building

A file utility CLI called `futil` that can:
- Count lines, words, and characters in files
- Convert between different formats
- Generate checksums
- Search text patterns

## 📁 Project Structure

```
futil/
├── build.zig
├── build.zig.zon
├── src/
│   ├── main.zig
│   ├── commands/
│   │   ├── count.zig
│   │   ├── convert.zig
│   │   ├── checksum.zig
│   │   └── search.zig
│   └── utils/
│       └── file_reader.zig
├── tests/
│   └── integration.zig
└── completions/
    ├── futil.bash
    ├── _futil.zsh
    └── futil.fish
```

## 🚀 Implementation

### `src/main.zig`

```zig
const std = @import("std");
const flash = @import("flash");

// Import command handlers
const count = @import("commands/count.zig");
const convert = @import("commands/convert.zig");
const checksum = @import("commands/checksum.zig");
const search = @import("commands/search.zig");

const FUtil = flash.CLI(.{
    .name = "futil",
    .version = "1.0.0",
    .about = "File utility CLI with async operations",
    .author = "Flash Team <team@flash-cli.dev>",
    .long_about =
        \\A modern file utility tool built with Flash CLI framework.
        \\
        \\Features:
        \\  • Count lines, words, and characters
        \\  • Convert between file formats
        \\  • Generate various checksums
        \\  • Search text patterns with regex
        \\  • Async operations for better performance
    ,

    // Global flags available to all commands
    .global_flags = &.{
        flash.flag("verbose", .{
            .short = 'v',
            .long = "verbose",
            .help = "Enable verbose output",
            .count = true, // -v, -vv, -vvv for different levels
        }),
        flash.flag("quiet", .{
            .short = 'q',
            .long = "quiet",
            .help = "Suppress output except errors",
        }),
        flash.flag("no-color", .{
            .long = "no-color",
            .help = "Disable colored output",
        }),
    },

    .commands = &.{
        // Line/word/character counting
        flash.cmd("count", .{
            .about = "Count lines, words, and characters in files",
            .long_about =
                \\Count statistics for one or more files.
                \\
                \\By default, shows lines, words, and characters.
                \\Use flags to show specific counts only.
            ,
            .args = &.{
                flash.arg("files", .{
                    .help = "Files to process",
                    .multiple = true,
                    .required = true,
                    .value_name = "FILE",
                }),
            },
            .flags = &.{
                flash.flag("lines", .{
                    .short = 'l',
                    .long = "lines",
                    .help = "Show only line count",
                }),
                flash.flag("words", .{
                    .short = 'w',
                    .long = "words",
                    .help = "Show only word count",
                }),
                flash.flag("chars", .{
                    .short = 'c',
                    .long = "chars",
                    .help = "Show only character count",
                }),
                flash.flag("bytes", .{
                    .short = 'b',
                    .long = "bytes",
                    .help = "Show only byte count",
                }),
                flash.flag("parallel", .{
                    .short = 'p',
                    .long = "parallel",
                    .help = "Process files in parallel",
                }),
            },
            .examples = &.{
                "futil count file.txt",
                "futil count *.txt --lines",
                "futil count --parallel **/*.md",
            },
            .run_async = count.execute,
        }),

        // Format conversion
        flash.cmd("convert", .{
            .about = "Convert files between different formats",
            .args = &.{
                flash.arg("input", .{
                    .help = "Input file",
                    .required = true,
                    .value_name = "INPUT_FILE",
                }),
                flash.arg("output", .{
                    .help = "Output file",
                    .required = true,
                    .value_name = "OUTPUT_FILE",
                }),
            },
            .flags = &.{
                flash.flag("from", .{
                    .short = 'f',
                    .long = "from",
                    .help = "Input format (auto-detected if not specified)",
                    .value_name = "FORMAT",
                    .possible_values = &.{ "json", "yaml", "toml", "csv", "xml" },
                }),
                flash.flag("to", .{
                    .short = 't',
                    .long = "to",
                    .help = "Output format",
                    .value_name = "FORMAT",
                    .required = true,
                    .possible_values = &.{ "json", "yaml", "toml", "csv", "xml" },
                }),
                flash.flag("pretty", .{
                    .long = "pretty",
                    .help = "Pretty-print output",
                }),
                flash.flag("compact", .{
                    .long = "compact",
                    .help = "Compact output (no formatting)",
                }),
            },
            .run = convert.execute,
        }),

        // Checksum generation
        flash.cmd("checksum", .{
            .about = "Generate checksums for files",
            .aliases = &.{"hash", "sum"},
            .args = &.{
                flash.arg("files", .{
                    .help = "Files to checksum",
                    .multiple = true,
                    .required = true,
                }),
            },
            .flags = &.{
                flash.flag("algorithm", .{
                    .short = 'a',
                    .long = "algorithm",
                    .help = "Checksum algorithm",
                    .value_name = "ALGO",
                    .default_value = "sha256",
                    .possible_values = &.{ "md5", "sha1", "sha256", "sha512" },
                }),
                flash.flag("check", .{
                    .short = 'c',
                    .long = "check",
                    .help = "Verify checksums from file",
                    .value_name = "CHECKSUM_FILE",
                }),
                flash.flag("output", .{
                    .short = 'o',
                    .long = "output",
                    .help = "Write checksums to file",
                    .value_name = "OUTPUT_FILE",
                }),
            },
            .run_async = checksum.execute,
        }),

        // Text searching
        flash.cmd("search", .{
            .about = "Search for patterns in files",
            .aliases = &.{"grep", "find"},
            .args = &.{
                flash.arg("pattern", .{
                    .help = "Pattern to search for",
                    .required = true,
                }),
                flash.arg("files", .{
                    .help = "Files to search (or stdin if not provided)",
                    .multiple = true,
                }),
            },
            .flags = &.{
                flash.flag("regex", .{
                    .short = 'E',
                    .long = "regex",
                    .help = "Use regular expressions",
                }),
                flash.flag("ignore-case", .{
                    .short = 'i',
                    .long = "ignore-case",
                    .help = "Case insensitive search",
                }),
                flash.flag("line-number", .{
                    .short = 'n',
                    .long = "line-number",
                    .help = "Show line numbers",
                }),
                flash.flag("count", .{
                    .short = 'c',
                    .long = "count",
                    .help = "Show only count of matches",
                }),
                flash.flag("context", .{
                    .short = 'C',
                    .long = "context",
                    .help = "Show lines around matches",
                    .value_name = "NUM",
                    .default_value = "0",
                }),
                flash.flag("recursive", .{
                    .short = 'r',
                    .long = "recursive",
                    .help = "Search directories recursively",
                }),
            },
            .run_async = search.execute,
        }),

        // Shell completion generation
        flash.cmd("completion", .{
            .about = "Generate shell completion scripts",
            .args = &.{
                flash.arg("shell", .{
                    .help = "Shell to generate completion for",
                    .required = true,
                    .possible_values = &.{ "bash", "zsh", "fish", "powershell" },
                }),
            },
            .flags = &.{
                flash.flag("output", .{
                    .short = 'o',
                    .long = "output",
                    .help = "Output file (default: stdout)",
                    .value_name = "FILE",
                }),
            },
            .run = generateCompletion,
        }),
    },
});

fn generateCompletion(ctx: flash.Context) !void {
    const shell_str = ctx.get("shell").?;
    const shell = flash.completion.Shell.fromString(shell_str) orelse {
        return flash.Error.InvalidArgument;
    };

    var generator = flash.completion.CompletionGenerator.init(ctx.allocator);
    defer generator.deinit();

    const completion_script = try generator.generate(
        FUtil.getRootCommand(),
        shell,
        "futil"
    );
    defer ctx.allocator.free(completion_script);

    if (ctx.get("output")) |output_file| {
        try std.fs.cwd().writeFile(.{ .sub_path = output_file, .data = completion_script });
        std.debug.print("✅ Completion script written to {s}\n", .{output_file});
    } else {
        try std.io.getStdOut().writeAll(completion_script);
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var cli = FUtil.init(gpa.allocator());
    defer cli.deinit();

    try cli.run();
}
```

### `src/commands/count.zig`

```zig
const std = @import("std");
const flash = @import("flash");

pub async fn execute(ctx: flash.Context) !void {
    const files = ctx.getMany("files").?;
    const parallel = ctx.getBool("parallel");
    const verbose = ctx.getVerbosity();

    // Determine what to count
    const show_lines = ctx.getBool("lines") or (!ctx.getBool("words") and !ctx.getBool("chars") and !ctx.getBool("bytes"));
    const show_words = ctx.getBool("words") or (!ctx.getBool("lines") and !ctx.getBool("chars") and !ctx.getBool("bytes"));
    const show_chars = ctx.getBool("chars") or (!ctx.getBool("lines") and !ctx.getBool("words") and !ctx.getBool("bytes"));
    const show_bytes = ctx.getBool("bytes");

    if (parallel and files.len > 1) {
        try countFilesParallel(ctx, files, show_lines, show_words, show_chars, show_bytes, verbose);
    } else {
        try countFilesSequential(ctx, files, show_lines, show_words, show_chars, show_bytes, verbose);
    }
}

async fn countFilesParallel(
    ctx: flash.Context,
    files: []const []const u8,
    show_lines: bool,
    show_words: bool,
    show_chars: bool,
    show_bytes: bool,
    verbose: u8,
) !void {
    var file_ops = flash.async_cli.AsyncFileOps.init(ctx.allocator);
    defer file_ops.deinit();

    if (verbose > 0) {
        std.debug.print("📊 Counting {} files in parallel...\n", .{files.len});
    }

    const results = try file_ops.processFiles(files, struct {
        fn process(content: []const u8) ![]const u8 {
            const stats = countContent(content);
            return try std.fmt.allocPrint(
                std.heap.page_allocator,
                "{},{},{},{}",
                .{ stats.lines, stats.words, stats.chars, stats.bytes }
            );
        }
    }.process);
    defer ctx.allocator.free(results);

    var total_lines: usize = 0;
    var total_words: usize = 0;
    var total_chars: usize = 0;
    var total_bytes: usize = 0;
    var success_count: usize = 0;

    for (results, 0..) |result, i| {
        switch (result) {
            .success => |data| {
                var iter = std.mem.split(u8, data.content, ",");
                const lines = std.fmt.parseInt(usize, iter.next().?, 10) catch 0;
                const words = std.fmt.parseInt(usize, iter.next().?, 10) catch 0;
                const chars = std.fmt.parseInt(usize, iter.next().?, 10) catch 0;
                const bytes = std.fmt.parseInt(usize, iter.next().?, 10) catch 0;

                printCounts(files[i], lines, words, chars, bytes, show_lines, show_words, show_chars, show_bytes);

                total_lines += lines;
                total_words += words;
                total_chars += chars;
                total_bytes += bytes;
                success_count += 1;
            },
            .failure => |err| {
                std.debug.print("❌ Error processing {s}: {s}\n", .{ err.path, err.error_message });
            },
        }
    }

    if (files.len > 1 and success_count > 1) {
        printCounts("total", total_lines, total_words, total_chars, total_bytes, show_lines, show_words, show_chars, show_bytes);
    }

    if (verbose > 0) {
        std.debug.print("✅ Processed {}/{} files successfully\n", .{ success_count, files.len });
    }
}

fn countFilesSequential(
    ctx: flash.Context,
    files: []const []const u8,
    show_lines: bool,
    show_words: bool,
    show_chars: bool,
    show_bytes: bool,
    verbose: u8,
) !void {
    var total_lines: usize = 0;
    var total_words: usize = 0;
    var total_chars: usize = 0;
    var total_bytes: usize = 0;

    for (files) |file| {
        const content = std.fs.cwd().readFileAlloc(ctx.allocator, file, 1024 * 1024 * 1024) catch |err| {
            std.debug.print("❌ Error reading {s}: {}\n", .{ file, err });
            continue;
        };
        defer ctx.allocator.free(content);

        const stats = countContent(content);
        printCounts(file, stats.lines, stats.words, stats.chars, stats.bytes, show_lines, show_words, show_chars, show_bytes);

        total_lines += stats.lines;
        total_words += stats.words;
        total_chars += stats.chars;
        total_bytes += stats.bytes;
    }

    if (files.len > 1) {
        printCounts("total", total_lines, total_words, total_chars, total_bytes, show_lines, show_words, show_chars, show_bytes);
    }
}

const CountStats = struct {
    lines: usize,
    words: usize,
    chars: usize,
    bytes: usize,
};

fn countContent(content: []const u8) CountStats {
    var lines: usize = 0;
    var words: usize = 0;
    var chars: usize = 0;
    var in_word = false;

    for (content) |char| {
        chars += 1;

        if (char == '\n') {
            lines += 1;
        }

        if (std.ascii.isWhitespace(char)) {
            in_word = false;
        } else if (!in_word) {
            words += 1;
            in_word = true;
        }
    }

    // If file doesn't end with newline, count the last line
    if (content.len > 0 and content[content.len - 1] != '\n') {
        lines += 1;
    }

    return CountStats{
        .lines = lines,
        .words = words,
        .chars = chars,
        .bytes = content.len,
    };
}

fn printCounts(
    filename: []const u8,
    lines: usize,
    words: usize,
    chars: usize,
    bytes: usize,
    show_lines: bool,
    show_words: bool,
    show_chars: bool,
    show_bytes: bool,
) void {
    if (show_lines) std.debug.print("{d:>8} ", .{lines});
    if (show_words) std.debug.print("{d:>8} ", .{words});
    if (show_chars) std.debug.print("{d:>8} ", .{chars});
    if (show_bytes) std.debug.print("{d:>8} ", .{bytes});
    std.debug.print("{s}\n", .{filename});
}
```

## 🧪 Testing

### `tests/integration.zig`

```zig
const std = @import("std");
const flash = @import("flash");
const FUtil = @import("../src/main.zig").FUtil;

test "count command basic functionality" {
    var harness = flash.testing.TestHarness.init(std.testing.allocator);
    defer harness.deinit();

    // Create test file
    const temp_dir = try harness.createTempDir("futil_test");
    defer harness.cleanup(temp_dir);

    try harness.createFile("test.txt", "Hello world\nSecond line\nThird line");

    const result = try harness.execute(FUtil, &.{ "count", "test.txt" });
    defer result.deinit();

    try result.expectExitCode(0);
    try result.expectStdoutContains("3"); // lines
    try result.expectStdoutContains("6"); // words
}

test "checksum command" {
    var harness = flash.testing.TestHarness.init(std.testing.allocator);
    defer harness.deinit();

    const temp_dir = try harness.createTempDir("futil_test");
    defer harness.cleanup(temp_dir);

    try harness.createFile("test.txt", "Hello world");

    const result = try harness.execute(FUtil, &.{ "checksum", "test.txt" });
    defer result.deinit();

    try result.expectExitCode(0);
    try result.expectStdoutContains("test.txt");
}

test "help generation" {
    var harness = flash.testing.TestHarness.init(std.testing.allocator);
    defer harness.deinit();

    const result = try harness.execute(FUtil, &.{"--help"});
    defer result.deinit();

    try result.expectExitCode(0);
    try result.expectStdoutContains("File utility CLI");
    try result.expectStdoutContains("count");
    try result.expectStdoutContains("checksum");
    try result.expectStdoutContains("convert");
    try result.expectStdoutContains("search");
}

test "completion generation" {
    var harness = flash.testing.TestHarness.init(std.testing.allocator);
    defer harness.deinit();

    const result = try harness.execute(FUtil, &.{ "completion", "bash" });
    defer result.deinit();

    try result.expectExitCode(0);
    try result.expectStdoutContains("_futil_completions");
    try result.expectStdoutContains("count");
}
```

## 🚀 Build and Run

### Build Configuration

```zig
// build.zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const flash_dep = b.dependency("flash", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "futil",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("flash", flash_dep.module("flash"));
    b.installArtifact(exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run futil");
    run_step.dependOn(&run_cmd.step);

    // Test step
    const tests = b.addTest(.{
        .root_source_file = .{ .path = "tests/integration.zig" },
        .target = target,
        .optimize = optimize,
    });
    tests.root_module.addImport("flash", flash_dep.module("flash"));

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);

    // Completion generation
    const completion_step = b.step("completions", "Generate shell completions");
    const bash_completion = b.addRunArtifact(exe);
    bash_completion.addArgs(&.{ "completion", "bash", "-o", "completions/futil.bash" });
    completion_step.dependOn(&bash_completion.step);

    const zsh_completion = b.addRunArtifact(exe);
    zsh_completion.addArgs(&.{ "completion", "zsh", "-o", "completions/_futil" });
    completion_step.dependOn(&zsh_completion.step);
}
```

### Usage Examples

```bash
# Build the project
zig build

# Basic usage
zig build run -- count README.md
zig build run -- checksum *.zig

# With flags
zig build run -- count --parallel --lines **/*.zig
zig build run -- search "TODO" src/ --recursive --line-number

# Generate completions
zig build completions

# Run tests
zig build test
```

## 💡 Key Patterns Demonstrated

1. **Structured Command Organization** - Clear command hierarchy
2. **Global Flags** - Flags available to all commands
3. **Async Operations** - Parallel file processing
4. **Comprehensive Validation** - Input validation and error handling
5. **Testing Integration** - Unit and integration tests
6. **Shell Completions** - Auto-generated completion scripts
7. **Rich Help Text** - Detailed help and examples
8. **Error Handling** - Graceful error reporting

## 🔗 Related Examples

- [Git-like Tool](git-like.md) - More complex subcommand structure
- [File Processor](file-processor.md) - Advanced async file operations
- [API Client](api-client.md) - Network operations and JSON handling

---

*This example shows how Flash enables building feature-rich CLI applications with minimal boilerplate and maximum performance.*