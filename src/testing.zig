//! ⚡ Flash Testing Infrastructure
//!
//! Comprehensive testing utilities for CLI applications, inspired by clap's
//! snapshot testing and Cobra's test helpers

const std = @import("std");
const Command = @import("command.zig");
const Parser = @import("parser.zig");
const Context = @import("context.zig");
const Help = @import("help.zig");
const Error = @import("error.zig");
const Completion = @import("completion.zig");
const Config = @import("config.zig");

const Managed = std.array_list.Managed;

const CaptureBuffers = struct {
    stdout: std.Io.Writer.Allocating,
    stderr: std.Io.Writer.Allocating,
};

fn nowNs() u64 {
    return switch (@import("builtin").os.tag) {
        .linux => blk: {
            var ts: std.os.linux.timespec = undefined;
            _ = std.os.linux.clock_gettime(.MONOTONIC, &ts);
            break :blk @as(u64, @intCast(ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(ts.nsec));
        },
        else => 0,
    };
}

fn nowMs() i64 {
    return @as(i64, @intCast(@divTrunc(nowNs(), std.time.ns_per_ms)));
}

fn trimTrailingNewlines(bytes: []const u8) []const u8 {
    var end = bytes.len;
    while (end > 0 and bytes[end - 1] == '\n') : (end -= 1) {}
    return bytes[0..end];
}

/// Test result containing output and errors
pub const TestResult = struct {
    exit_code: u8,
    stdout: []const u8,
    stderr: []const u8,
    execution_time: u64, // nanoseconds
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TestResult {
        return .{
            .exit_code = 0,
            .stdout = "",
            .stderr = "",
            .execution_time = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: TestResult) void {
        self.allocator.free(self.stdout);
        self.allocator.free(self.stderr);
    }

    pub fn expectExitCode(self: TestResult, expected: u8) !void {
        if (self.exit_code != expected) {
            return error.UnexpectedExitCode;
        }
    }

    pub fn expectStdout(self: TestResult, expected: []const u8) !void {
        if (!std.mem.eql(u8, self.stdout, expected)) {
            std.debug.print("Expected stdout: '{s}'\\n", .{expected});
            std.debug.print("Actual stdout: '{s}'\\n", .{self.stdout});
            return error.UnexpectedStdout;
        }
    }

    pub fn expectStderr(self: TestResult, expected: []const u8) !void {
        if (!std.mem.eql(u8, self.stderr, expected)) {
            std.debug.print("Expected stderr: '{s}'\\n", .{expected});
            std.debug.print("Actual stderr: '{s}'\\n", .{self.stderr});
            return error.UnexpectedStderr;
        }
    }

    pub fn expectStdoutContains(self: TestResult, substring: []const u8) !void {
        if (std.mem.indexOf(u8, self.stdout, substring) == null) {
            std.debug.print("Expected stdout to contain: '{s}'\\n", .{substring});
            std.debug.print("Actual stdout: '{s}'\\n", .{self.stdout});
            return error.StdoutMissingSubstring;
        }
    }

    pub fn expectStderrContains(self: TestResult, substring: []const u8) !void {
        if (std.mem.indexOf(u8, self.stderr, substring) == null) {
            std.debug.print("Expected stderr to contain: '{s}'\\n", .{substring});
            std.debug.print("Actual stderr: '{s}'\\n", .{self.stderr});
            return error.StderrMissingSubstring;
        }
    }

    pub fn expectExecutionTime(self: TestResult, max_ns: u64) !void {
        if (self.execution_time > max_ns) {
            std.debug.print("Expected execution time <= {d}ns, got {d}ns\\n", .{ max_ns, self.execution_time });
            return error.ExecutionTooSlow;
        }
    }
};

/// CLI test harness for running commands with captured output
pub const TestHarness = struct {
    allocator: std.mem.Allocator,
    stdout_buffer: Managed(u8),
    stderr_buffer: Managed(u8),
    env_vars: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) TestHarness {
        return .{
            .allocator = allocator,
            .stdout_buffer = Managed(u8).init(allocator),
            .stderr_buffer = Managed(u8).init(allocator),
            .env_vars = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *TestHarness) void {
        self.stdout_buffer.deinit();
        self.stderr_buffer.deinit();
        self.env_vars.deinit();
    }

    pub fn setEnv(self: *TestHarness, key: []const u8, value: []const u8) !void {
        try self.env_vars.put(key, value);
    }

    pub fn clearBuffers(self: *TestHarness) void {
        self.stdout_buffer.clearRetainingCapacity();
        self.stderr_buffer.clearRetainingCapacity();
    }

    /// Execute a CLI with arguments and capture output
    /// Note: Command handlers that use std.debug.print cannot have output captured.
    /// This harness captures help/version output and tracks execution/exit codes.
    pub fn execute(self: *TestHarness, cli: anytype, args: []const []const u8) !TestResult {
        self.clearBuffers();

        const start_time = nowNs();
        var exit_code: u8 = 0;

        var capture = CaptureBuffers{
            .stdout = .init(self.allocator),
            .stderr = .init(self.allocator),
        };
        defer capture.stdout.deinit();
        defer capture.stderr.deinit();

        // Get root command from CLI
        const root_command = cli.getRootCommand();
        const parser = Parser.Parser.init(self.allocator);
        const help = Help.Help.init(self.allocator);

        // Parse arguments
        var context = parser.parse(root_command, args) catch |err| {
            switch (err) {
                Error.FlashError.HelpRequested => {
                    // Write help to stdout buffer
                    const program_name = if (args.len > 0) args[0] else root_command.name;
                    try help.printCommandHelp(&capture.stdout.writer, root_command, program_name);
                    return self.buildResult(0, start_time, &capture);
                },
                Error.FlashError.VersionRequested => {
                    // Write version to stdout buffer
                    const program_name = if (args.len > 0) args[0] else root_command.name;
                    try capture.stdout.writer.print("⚡ {s}", .{program_name});
                    if (root_command.getVersion()) |version| {
                        try capture.stdout.writer.print(" {s}", .{version});
                    }
                    try capture.stdout.writer.print("\n", .{});
                    return self.buildResult(0, start_time, &capture);
                },
                else => {
                    try capture.stderr.writer.print("Error: {}\n", .{err});
                    return self.buildResult(1, start_time, &capture);
                },
            }
        };
        defer context.deinit();

        // Find command to execute using full command path
        var current_command = root_command;
        const command_path = context.getCommandPath();
        for (command_path) |segment| {
            if (current_command.findSubcommand(segment)) |found_cmd| {
                current_command = found_cmd;
            } else {
                try capture.stderr.writer.print("Unknown command: {s}\n", .{segment});
                return self.buildResult(1, start_time, &capture);
            }
        }

        // Execute command
        if (current_command.hasHandler()) {
            current_command.execute(context) catch |err| {
                try capture.stderr.writer.print("Execution error: {}\n", .{err});
                exit_code = 1;
            };
        }

        return self.buildResult(exit_code, start_time, &capture);
    }

    /// Build a TestResult from current buffers and timing
    fn buildResult(self: *TestHarness, exit_code: u8, start_time: u64, capture: *CaptureBuffers) !TestResult {
        const end_time = nowNs();
        const execution_time = end_time - start_time;

        const stdout_bytes = try capture.stdout.toOwnedSlice();
        defer self.allocator.free(stdout_bytes);
        const stderr_bytes = try capture.stderr.toOwnedSlice();
        defer self.allocator.free(stderr_bytes);

        return TestResult{
            .exit_code = exit_code,
            .stdout = try self.allocator.dupe(u8, stdout_bytes),
            .stderr = try self.allocator.dupe(u8, stderr_bytes),
            .execution_time = execution_time,
            .allocator = self.allocator,
        };
    }

    /// Execute with timeout
    pub fn executeWithTimeout(self: *TestHarness, cli: anytype, args: []const []const u8, timeout_ms: u64) !TestResult {
        _ = timeout_ms;
        // In real implementation, this would use async execution with timeout
        return self.execute(cli, args);
    }
};

/// Snapshot testing for CLI output
pub const SnapshotTester = struct {
    allocator: std.mem.Allocator,
    snapshot_dir: []const u8,
    update_snapshots: bool,
    normalize_trailing_newlines: bool,

    pub fn init(allocator: std.mem.Allocator, snapshot_dir: []const u8, update: bool) SnapshotTester {
        return .{
            .allocator = allocator,
            .snapshot_dir = snapshot_dir,
            .update_snapshots = update,
            .normalize_trailing_newlines = false,
        };
    }

    pub fn assertMatchesSnapshot(self: SnapshotTester, name: []const u8, output: []const u8) !void {
        const snapshot_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.snapshot", .{ self.snapshot_dir, name });
        defer self.allocator.free(snapshot_path);

        if (self.update_snapshots) {
            // Write new snapshot
            try std.Io.Dir.cwd().createDirPath(std.testing.io, self.snapshot_dir);

            const file = try std.Io.Dir.cwd().createFile(std.testing.io, snapshot_path, .{});
            defer file.close(std.testing.io);
            try file.writeStreamingAll(std.testing.io, output);
            return;
        }

        // Compare with existing snapshot
        const snapshot_content = blk: {
            const file = std.Io.Dir.cwd().openFile(std.testing.io, snapshot_path, .{}) catch |err| switch (err) {
                error.FileNotFound => {
                    std.debug.print("Snapshot not found: {s}\\n", .{snapshot_path});
                    std.debug.print("Run with --update-snapshots to create it\\n", .{});
                    return error.SnapshotNotFound;
                },
                else => return err,
            };
            defer file.close(std.testing.io);

            var reader = file.reader(std.testing.io, &.{});
            break :blk try reader.interface.allocRemaining(self.allocator, .limited(1024 * 1024));
        };
        defer self.allocator.free(snapshot_content);

        const normalized_output = if (self.normalize_trailing_newlines) trimTrailingNewlines(output) else output;
        const normalized_snapshot = if (self.normalize_trailing_newlines) trimTrailingNewlines(snapshot_content) else snapshot_content;

        if (!std.mem.eql(u8, normalized_output, normalized_snapshot)) {
            std.debug.print("Snapshot mismatch for: {s}\\n", .{name});
            std.debug.print("Expected:\\n{s}\\n", .{normalized_snapshot});
            std.debug.print("Actual:\\n{s}\\n", .{normalized_output});
            return error.SnapshotMismatch;
        }
    }

    pub fn assertHelpSnapshot(self: SnapshotTester, cli: anytype, command_path: []const []const u8) !void {
        var harness = TestHarness.init(self.allocator);
        defer harness.deinit();

        var args = Managed([]const u8).init(self.allocator);
        defer args.deinit();

        try args.appendSlice(command_path);
        try args.append("--help");

        const result = try harness.execute(cli, args.items);
        defer result.deinit();

        const snapshot_name = try std.mem.join(self.allocator, "_", command_path);
        defer self.allocator.free(snapshot_name);

        const full_name = try std.fmt.allocPrint(self.allocator, "{s}_help", .{snapshot_name});
        defer self.allocator.free(full_name);

        try self.assertMatchesSnapshot(full_name, result.stdout);
    }
};

/// Performance testing utilities
pub const PerformanceTester = struct {
    allocator: std.mem.Allocator,
    results: std.ArrayList(BenchmarkResult),

    pub const BenchmarkResult = struct {
        name: []const u8,
        iterations: usize,
        total_time_ns: u64,
        avg_time_ns: u64,
        min_time_ns: u64,
        max_time_ns: u64,
        memory_used: usize,

        pub fn print(self: BenchmarkResult) void {
            std.log.info("Benchmark: {s}", .{self.name});
            std.log.info("  Iterations: {d}", .{self.iterations});
            std.log.info("  Total time: {d}ms", .{self.total_time_ns / 1_000_000});
            std.log.info("  Average: {d}us", .{self.avg_time_ns / 1_000});
            std.log.info("  Min: {d}us", .{self.min_time_ns / 1_000});
            std.log.info("  Max: {d}us", .{self.max_time_ns / 1_000});
            std.log.info("  Memory: {d} bytes", .{self.memory_used});
        }
    };

    pub fn init(allocator: std.mem.Allocator) PerformanceTester {
        return .{
            .allocator = allocator,
            .results = .empty,
        };
    }

    pub fn deinit(self: *PerformanceTester) void {
        self.results.deinit(self.allocator);
    }

    pub fn benchmark(self: *PerformanceTester, name: []const u8, cli: anytype, args: []const []const u8, iterations: usize) !BenchmarkResult {
        var harness = TestHarness.init(self.allocator);
        defer harness.deinit();

        var times = try self.allocator.alloc(u64, iterations);
        defer self.allocator.free(times);

        var total_time: u64 = 0;
        var min_time: u64 = std.math.maxInt(u64);
        var max_time: u64 = 0;

        for (0..iterations) |i| {
            const result = try harness.execute(cli, args);
            defer result.deinit();

            times[i] = result.execution_time;
            total_time += result.execution_time;
            min_time = @min(min_time, result.execution_time);
            max_time = @max(max_time, result.execution_time);
        }

        const avg_time = total_time / iterations;

        const benchmark_result = BenchmarkResult{
            .name = name,
            .iterations = iterations,
            .total_time_ns = total_time,
            .avg_time_ns = avg_time,
            .min_time_ns = min_time,
            .max_time_ns = max_time,
            .memory_used = 0, // Would need to implement memory tracking
        };

        try self.results.append(self.allocator, benchmark_result);
        return benchmark_result;
    }

    pub fn printAllResults(self: PerformanceTester) void {
        std.log.info("Performance Test Results", .{});
        for (self.results.items) |result| {
            result.print();
        }
    }
};

/// Integration test runner
pub const IntegrationTester = struct {
    allocator: std.mem.Allocator,
    test_cases: std.ArrayList(TestCase),

    pub const TestCase = struct {
        name: []const u8,
        args: []const []const u8,
        expected_exit_code: u8,
        expected_stdout: ?[]const u8,
        expected_stderr: ?[]const u8,
        timeout_ms: ?u64,
        env_vars: ?std.StringHashMap([]const u8),

        pub fn run(self: TestCase, allocator: std.mem.Allocator, cli: anytype) !TestResult {
            var harness = TestHarness.init(allocator);
            defer harness.deinit();

            if (self.env_vars) |env| {
                var iter = env.iterator();
                while (iter.next()) |entry| {
                    try harness.setEnv(entry.key_ptr.*, entry.value_ptr.*);
                }
            }

            const result = if (self.timeout_ms) |timeout|
                try harness.executeWithTimeout(cli, self.args, timeout)
            else
                try harness.execute(cli, self.args);

            // Validate results
            try result.expectExitCode(self.expected_exit_code);

            if (self.expected_stdout) |expected| {
                try result.expectStdout(expected);
            }

            if (self.expected_stderr) |expected| {
                try result.expectStderr(expected);
            }

            return result;
        }
    };

    pub fn init(allocator: std.mem.Allocator) IntegrationTester {
        return .{
            .allocator = allocator,
            .test_cases = .empty,
        };
    }

    pub fn deinit(self: *IntegrationTester) void {
        self.test_cases.deinit(self.allocator);
    }

    pub fn addTestCase(self: *IntegrationTester, test_case: TestCase) !void {
        try self.test_cases.append(self.allocator, test_case);
    }

    pub fn runAll(self: IntegrationTester, cli: anytype) !void {
        var failed: usize = 0;

        for (self.test_cases.items) |test_case| {
            const result = test_case.run(self.allocator, cli) catch |err| {
                failed += 1;
                std.log.err("Integration test failed: {s} ({})", .{ test_case.name, err });
                continue;
            };
            defer result.deinit();
        }

        if (failed > 0) {
            return error.TestsFailed;
        }
    }
};

/// Test utilities for mocking and fixtures
pub const TestUtils = struct {
    /// Create a temporary directory for test files
    pub fn createTempDir(allocator: std.mem.Allocator, prefix: []const u8) ![]const u8 {
        const timestamp = nowMs();
        const dir_name = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}_{d}", .{ prefix, timestamp });

        try std.Io.Dir.cwd().createDirPath(std.testing.io, dir_name);
        return dir_name;
    }

    /// Create a test file with content
    pub fn createTestFile(dir: []const u8, name: []const u8, content: []const u8) !void {
        const file_path = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}", .{ dir, name });
        defer std.heap.page_allocator.free(file_path);

        const file = try std.Io.Dir.cwd().createFile(std.testing.io, file_path, .{});
        defer file.close(std.testing.io);
        try file.writeAll(std.testing.io, content);
    }

    /// Cleanup temporary directory
    pub fn cleanup(path: []const u8) void {
        var cwd = std.Io.Dir.cwd();
        cwd.deleteTree(std.testing.io, path) catch {};
    }

    /// Mock CLI for testing - provides minimal CLI interface for test harness
    pub fn mockCLI(allocator: std.mem.Allocator, name: []const u8) MockCLI {
        _ = allocator;
        return MockCLI.init(name);
    }

    /// Minimal mock CLI that satisfies TestHarness.execute() requirements
    pub const MockCLI = struct {
        name: []const u8,
        root_command: Command.Command,

        pub fn init(cli_name: []const u8) MockCLI {
            return .{
                .name = cli_name,
                .root_command = Command.Command.init(cli_name, Command.CommandConfig{}),
            };
        }

        pub fn initWithCommand(cli_name: []const u8, command: Command.Command) MockCLI {
            return .{
                .name = cli_name,
                .root_command = command,
            };
        }

        pub fn getRootCommand(self: MockCLI) Command.Command {
            return self.root_command;
        }
    };
};

// Tests for the testing infrastructure itself
test "test harness basic execution" {
    var harness = TestHarness.init(std.testing.allocator);
    defer harness.deinit();

    const mock_cli = TestUtils.mockCLI(std.testing.allocator, "test");
    const args = &.{"test"};

    const result = try harness.execute(mock_cli, args);
    defer result.deinit();

    // Basic CLI without handler should succeed with no output
    try result.expectExitCode(0);
}

test "test harness help request" {
    var harness = TestHarness.init(std.testing.allocator);
    defer harness.deinit();

    const cmd = Command.Command.init("myapp", (Command.CommandConfig{})
        .withAbout("A test application")
        .withVersion("1.0.0"));
    const mock_cli = TestUtils.MockCLI.initWithCommand("myapp", cmd);
    const args = &.{ "myapp", "--help" };

    const result = try harness.execute(mock_cli, args);
    defer result.deinit();

    try result.expectExitCode(0);
    try result.expectStdoutContains("myapp");
    try result.expectStdoutContains("A test application");
}

test "snapshot tester" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const snapshot_dir = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/snapshots", .{tmp.sub_path});
    defer allocator.free(snapshot_dir);

    var tester = SnapshotTester.init(allocator, snapshot_dir, true);

    const test_output = "Test output\\nLine 2\\n";
    try tester.assertMatchesSnapshot("test_command", test_output);

    // Test reading back the snapshot
    tester.update_snapshots = false;
    tester.normalize_trailing_newlines = true;
    try tester.assertMatchesSnapshot("test_command", test_output);
}

test "golden snapshot: help output" {
    const allocator = std.testing.allocator;
    const snapshot_dir = "tests/snapshots";

    const root = Command.Command.init("snapapp", (Command.CommandConfig{})
        .withAbout("Snapshot application")
        .withVersion("0.4.0")
        .withArgs(&.{@import("argument.zig").Argument.init("format", (@import("argument.zig").ArgumentConfig{})
            .withHelp("Output format")
            .withChoices(&.{ "json", "toml" }))})
        .withFlags(&.{@import("flag.zig").Flag.init("verbose", (@import("flag.zig").FlagConfig{})
            .withShort('v')
            .withLong("verbose")
            .withHelp("Enable verbose output"))})
        .withSubcommands(&.{Command.Command.init("serve", (Command.CommandConfig{})
        .withAbout("Run the server"))}));

    const cli = TestUtils.MockCLI.initWithCommand("snapapp", root);
    var tester = SnapshotTester.init(allocator, snapshot_dir, false);
    tester.normalize_trailing_newlines = true;
    try tester.assertHelpSnapshot(cli, &.{"snapapp"});
}

test "golden snapshot: bash completion" {
    const allocator = std.testing.allocator;
    const snapshot_dir = "tests/snapshots";

    const command = Command.Command.init("snapapp", (Command.CommandConfig{})
        .withAbout("Snapshot application")
        .withFlags(&.{@import("flag.zig").Flag.init("verbose", (@import("flag.zig").FlagConfig{})
            .withShort('v')
            .withLong("verbose")
            .withHelp("Enable verbose output"))})
        .withSubcommands(&.{Command.Command.init("serve", (Command.CommandConfig{})
        .withAbout("Run the server"))}));

    var generator = Completion.CompletionGenerator.init(allocator);
    defer generator.deinit();

    const script = try generator.generate(command, .bash, "snapapp");
    defer allocator.free(script);

    var tester = SnapshotTester.init(allocator, snapshot_dir, false);
    tester.normalize_trailing_newlines = true;
    try tester.assertMatchesSnapshot("snapapp_bash_completion", script);
}

test "golden snapshot: zsh completion" {
    const allocator = std.testing.allocator;
    const snapshot_dir = "tests/snapshots";

    const command = Command.Command.init("snapapp", (Command.CommandConfig{})
        .withAbout("Snapshot application")
        .withSubcommands(&.{Command.Command.init("serve", (Command.CommandConfig{})
        .withAbout("Run the server"))}));

    var generator = Completion.CompletionGenerator.init(allocator);
    defer generator.deinit();

    const script = try generator.generate(command, .zsh, "snapapp");
    defer allocator.free(script);

    var tester = SnapshotTester.init(allocator, snapshot_dir, false);
    tester.normalize_trailing_newlines = true;
    try tester.assertMatchesSnapshot("snapapp_zsh_completion", script);
}

test "golden snapshot: toml diagnostics" {
    const allocator = std.testing.allocator;
    const snapshot_dir = "tests/snapshots";

    const ExampleConfig = struct {
        name: []const u8 = "default",
    };

    const parser = Config.ConfigParser.init(allocator);
    const result = parser.parseTomlWithDiagnostics(ExampleConfig,
        \\name = "unterminated
    );

    const output = switch (result) {
        .success => return error.TestUnexpectedResult,
        .failure => |diag| try std.fmt.allocPrint(allocator, "line={d}\ncolumn={d}\nmessage={s}\nsuggestion={?s}\n", .{
            diag.line,
            diag.column,
            diag.message,
            diag.suggestion,
        }),
    };
    defer allocator.free(output);

    var tester = SnapshotTester.init(allocator, snapshot_dir, false);
    tester.normalize_trailing_newlines = true;
    try tester.assertMatchesSnapshot("toml_diagnostics", output);
}

test "performance tester" {
    var perf_tester = PerformanceTester.init(std.testing.allocator);
    defer perf_tester.deinit();

    const mock_cli = TestUtils.mockCLI(std.testing.allocator, "test");
    const args = &.{"benchmark"};

    const result = try perf_tester.benchmark("test_command", mock_cli, args, 5);
    try std.testing.expect(result.iterations == 5);
    try std.testing.expect(result.avg_time_ns > 0);
}

test "integration tester" {
    var integration = IntegrationTester.init(std.testing.allocator);
    defer integration.deinit();

    try integration.addTestCase(.{
        .name = "help command",
        .args = &.{"--help"},
        .expected_exit_code = 0,
        .expected_stdout = null, // Don't check exact output
        .expected_stderr = null,
        .timeout_ms = 1000,
        .env_vars = null,
    });

    const mock_cli = TestUtils.mockCLI(std.testing.allocator, "test");
    try integration.runAll(mock_cli);
}
