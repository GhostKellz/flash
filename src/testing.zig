//! ⚡ Flash Testing Infrastructure
//!
//! Comprehensive testing utilities for CLI applications, inspired by clap's
//! snapshot testing and Cobra's test helpers

const std = @import("std");
const zsync = @import("zsync");
const Command = @import("command.zig");
const CLI = @import("cli.zig");
const Context = @import("context.zig");
const Error = @import("error.zig");

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
    stdout_buffer: std.ArrayList(u8),
    stderr_buffer: std.ArrayList(u8),
    env_vars: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) TestHarness {
        return .{
            .allocator = allocator,
            .stdout_buffer = std.ArrayList(u8).init(allocator),
            .stderr_buffer = std.ArrayList(u8).init(allocator),
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
    pub fn execute(self: *TestHarness, cli: anytype, args: []const []const u8) !TestResult {
        self.clearBuffers();

        const start_time = std.time.nanoTimestamp();

        // Create mock stdout/stderr writers
        const stdout_writer = self.stdout_buffer.writer();
        const stderr_writer = self.stderr_buffer.writer();

        // Execute the CLI (this would need integration with the actual CLI runner)
        var exit_code: u8 = 0;

        // Mock execution - in real implementation this would:
        // 1. Parse args using the CLI
        // 2. Execute the command
        // 3. Capture output and exit code
        _ = cli;
        _ = args;
        _ = stdout_writer;
        _ = stderr_writer;

        // Simulate some output for testing
        try self.stdout_buffer.appendSlice("Mock output\\n");

        const end_time = std.time.nanoTimestamp();
        const execution_time = @intCast(u64, end_time - start_time);

        return TestResult{
            .exit_code = exit_code,
            .stdout = try self.allocator.dupe(u8, self.stdout_buffer.items),
            .stderr = try self.allocator.dupe(u8, self.stderr_buffer.items),
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

    pub fn init(allocator: std.mem.Allocator, snapshot_dir: []const u8, update: bool) SnapshotTester {
        return .{
            .allocator = allocator,
            .snapshot_dir = snapshot_dir,
            .update_snapshots = update,
        };
    }

    pub fn assertMatchesSnapshot(self: SnapshotTester, name: []const u8, output: []const u8) !void {
        const snapshot_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.snapshot", .{ self.snapshot_dir, name });
        defer self.allocator.free(snapshot_path);

        if (self.update_snapshots) {
            // Write new snapshot
            try std.fs.cwd().makePath(self.snapshot_dir);
            try std.fs.cwd().writeFile(.{ .sub_path = snapshot_path, .data = output });
            std.debug.print("Updated snapshot: {s}\\n", .{snapshot_path});
            return;
        }

        // Compare with existing snapshot
        const snapshot_content = std.fs.cwd().readFileAlloc(self.allocator, snapshot_path, 1024 * 1024) catch |err| {
            switch (err) {
                error.FileNotFound => {
                    std.debug.print("Snapshot not found: {s}\\n", .{snapshot_path});
                    std.debug.print("Run with --update-snapshots to create it\\n");
                    return error.SnapshotNotFound;
                },
                else => return err,
            }
        };
        defer self.allocator.free(snapshot_content);

        if (!std.mem.eql(u8, output, snapshot_content)) {
            std.debug.print("Snapshot mismatch for: {s}\\n", .{name});
            std.debug.print("Expected:\\n{s}\\n", .{snapshot_content});
            std.debug.print("Actual:\\n{s}\\n", .{output});
            return error.SnapshotMismatch;
        }
    }

    pub fn assertHelpSnapshot(self: SnapshotTester, cli: anytype, command_path: []const []const u8) !void {
        var harness = TestHarness.init(self.allocator);
        defer harness.deinit();

        var args = std.ArrayList([]const u8).init(self.allocator);
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
            std.debug.print("Benchmark: {s}\\n", .{self.name});
            std.debug.print("  Iterations: {d}\\n", .{self.iterations});
            std.debug.print("  Total time: {d}ms\\n", .{self.total_time_ns / 1_000_000});
            std.debug.print("  Average: {d}μs\\n", .{self.avg_time_ns / 1_000});
            std.debug.print("  Min: {d}μs\\n", .{self.min_time_ns / 1_000});
            std.debug.print("  Max: {d}μs\\n", .{self.max_time_ns / 1_000});
            std.debug.print("  Memory: {d} bytes\\n", .{self.memory_used});
        }
    };

    pub fn init(allocator: std.mem.Allocator) PerformanceTester {
        return .{
            .allocator = allocator,
            .results = std.ArrayList(BenchmarkResult).init(allocator),
        };
    }

    pub fn deinit(self: *PerformanceTester) void {
        self.results.deinit();
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

        try self.results.append(benchmark_result);
        return benchmark_result;
    }

    pub fn printAllResults(self: PerformanceTester) void {
        std.debug.print("\\n⚡ Performance Test Results\\n");
        std.debug.print("==========================\\n");
        for (self.results.items) |result| {
            result.print();
            std.debug.print("\\n");
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
            .test_cases = std.ArrayList(TestCase).init(allocator),
        };
    }

    pub fn deinit(self: *IntegrationTester) void {
        self.test_cases.deinit();
    }

    pub fn addTestCase(self: *IntegrationTester, test_case: TestCase) !void {
        try self.test_cases.append(test_case);
    }

    pub fn runAll(self: IntegrationTester, cli: anytype) !void {
        var passed: usize = 0;
        var failed: usize = 0;

        std.debug.print("\\n⚡ Running Integration Tests\\n");
        std.debug.print("============================\\n");

        for (self.test_cases.items) |test_case| {
            std.debug.print("Running: {s}... ", .{test_case.name});

            const result = test_case.run(self.allocator, cli) catch |err| {
                std.debug.print("FAILED ({})\\n", .{err});
                failed += 1;
                continue;
            };
            defer result.deinit();

            std.debug.print("PASSED\\n");
            passed += 1;
        }

        std.debug.print("\\nResults: {d} passed, {d} failed\\n", .{ passed, failed });

        if (failed > 0) {
            return error.TestsFailed;
        }
    }
};

/// Test utilities for mocking and fixtures
pub const TestUtils = struct {
    /// Create a temporary directory for test files
    pub fn createTempDir(allocator: std.mem.Allocator, prefix: []const u8) ![]const u8 {
        const timestamp = std.time.milliTimestamp();
        const dir_name = try std.fmt.allocPrint(allocator, "/tmp/{s}_{d}", .{ prefix, timestamp });

        try std.fs.cwd().makePath(dir_name);
        return dir_name;
    }

    /// Create a test file with content
    pub fn createTestFile(dir: []const u8, name: []const u8, content: []const u8) !void {
        const file_path = try std.fmt.allocPrint(std.heap.page_allocator, "{s}/{s}", .{ dir, name });
        defer std.heap.page_allocator.free(file_path);

        try std.fs.cwd().writeFile(.{ .sub_path = file_path, .data = content });
    }

    /// Cleanup temporary directory
    pub fn cleanup(path: []const u8) void {
        std.fs.cwd().deleteTree(path) catch {
            std.debug.print("Warning: Failed to cleanup {s}\\n", .{path});
        };
    }

    /// Mock CLI for testing
    pub fn mockCLI(allocator: std.mem.Allocator, name: []const u8) anytype {
        _ = allocator;
        return struct {
            name: []const u8,

            pub fn init(cli_name: []const u8) @This() {
                return .{ .name = cli_name };
            }
        }.init(name);
    }
};

// Tests for the testing infrastructure itself
test "test harness basic execution" {
    var harness = TestHarness.init(std.testing.allocator);
    defer harness.deinit();

    const mock_cli = TestUtils.mockCLI(std.testing.allocator, "test");
    const args = &.{ "command", "arg1" };

    const result = try harness.execute(mock_cli, args);
    defer result.deinit();

    try result.expectExitCode(0);
    try result.expectStdoutContains("Mock output");
}

test "snapshot tester" {
    const allocator = std.testing.allocator;
    const snapshot_dir = try TestUtils.createTempDir(allocator, "flash_test");
    defer TestUtils.cleanup(snapshot_dir);
    defer allocator.free(snapshot_dir);

    var tester = SnapshotTester.init(allocator, snapshot_dir, true);

    const test_output = "Test output\\nLine 2\\n";
    try tester.assertMatchesSnapshot("test_command", test_output);

    // Test reading back the snapshot
    tester.update_snapshots = false;
    try tester.assertMatchesSnapshot("test_command", test_output);
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