//! ⚡ Flash Benchmark Suite
//!
//! Comprehensive performance testing inspired by clap's benchmark infrastructure
//! Tests startup time, parsing performance, memory usage, and async operations

const std = @import("std");
const zsync = @import("zsync");
const Command = @import("command.zig");
const CLI = @import("cli.zig");
const testing_utils = @import("testing.zig");
const async_cli = @import("async_cli.zig");
const completion = @import("completion.zig");
const validation = @import("advanced_validation.zig");

/// Benchmark configuration
pub const BenchmarkConfig = struct {
    iterations: usize = 1000,
    warmup_iterations: usize = 100,
    timeout_ms: u64 = 30_000,
    memory_tracking: bool = true,
    detailed_output: bool = false,
    export_results: bool = false,
    export_format: ExportFormat = .json,
    export_path: ?[]const u8 = null,

    pub const ExportFormat = enum {
        json,
        csv,
        markdown,
    };
};

/// Benchmark result with detailed metrics
pub const BenchmarkResult = struct {
    name: []const u8,
    iterations: usize,
    total_time_ns: u64,
    avg_time_ns: u64,
    min_time_ns: u64,
    max_time_ns: u64,
    median_time_ns: u64,
    p95_time_ns: u64,
    p99_time_ns: u64,
    memory_peak_bytes: usize,
    memory_avg_bytes: usize,
    allocations_count: usize,
    throughput_ops_per_sec: f64,
    baseline_comparison: ?f64 = null, // Percentage difference from baseline

    pub fn print(self: BenchmarkResult, detailed: bool) void {
        std.debug.print("📊 {s}\n", .{self.name});
        std.debug.print("   Iterations: {d}\n", .{self.iterations});
        std.debug.print("   Average: {d:.2}ms\n", .{@as(f64, @floatFromInt(self.avg_time_ns)) / 1_000_000.0});
        std.debug.print("   Throughput: {d:.2} ops/sec\n", .{self.throughput_ops_per_sec});

        if (detailed) {
            std.debug.print("   Min: {d:.2}μs\n", .{@as(f64, @floatFromInt(self.min_time_ns)) / 1_000.0});
            std.debug.print("   Max: {d:.2}μs\n", .{@as(f64, @floatFromInt(self.max_time_ns)) / 1_000.0});
            std.debug.print("   Median: {d:.2}μs\n", .{@as(f64, @floatFromInt(self.median_time_ns)) / 1_000.0});
            std.debug.print("   P95: {d:.2}μs\n", .{@as(f64, @floatFromInt(self.p95_time_ns)) / 1_000.0});
            std.debug.print("   P99: {d:.2}μs\n", .{@as(f64, @floatFromInt(self.p99_time_ns)) / 1_000.0});
            std.debug.print("   Peak Memory: {d} KB\n", .{self.memory_peak_bytes / 1024});
            std.debug.print("   Avg Memory: {d} KB\n", .{self.memory_avg_bytes / 1024});
            std.debug.print("   Allocations: {d}\n", .{self.allocations_count});
        }

        if (self.baseline_comparison) |comparison| {
            const sign = if (comparison > 0) "+" else "";
            const color = if (comparison > 0) "\x1b[31m" else "\x1b[32m"; // Red for slower, green for faster
            std.debug.print("   {s}Baseline: {s}{d:.1}%\x1b[0m\n", .{ color, sign, comparison });
        }

        std.debug.print("\n");
    }

    pub fn toJson(self: BenchmarkResult, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator,
            \\{{
            \\  "name": "{s}",
            \\  "iterations": {d},
            \\  "avg_time_ns": {d},
            \\  "min_time_ns": {d},
            \\  "max_time_ns": {d},
            \\  "median_time_ns": {d},
            \\  "p95_time_ns": {d},
            \\  "p99_time_ns": {d},
            \\  "memory_peak_bytes": {d},
            \\  "memory_avg_bytes": {d},
            \\  "allocations_count": {d},
            \\  "throughput_ops_per_sec": {d:.2}
            \\}}
        , .{
            self.name,
            self.iterations,
            self.avg_time_ns,
            self.min_time_ns,
            self.max_time_ns,
            self.median_time_ns,
            self.p95_time_ns,
            self.p99_time_ns,
            self.memory_peak_bytes,
            self.memory_avg_bytes,
            self.allocations_count,
            self.throughput_ops_per_sec,
        });
    }
};

/// Memory tracking allocator
const TrackingAllocator = struct {
    backing_allocator: std.mem.Allocator,
    peak_bytes: usize = 0,
    current_bytes: usize = 0,
    total_allocations: usize = 0,
    total_frees: usize = 0,

    const Self = @This();

    pub fn allocator(self: *Self) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const result = self.backing_allocator.rawAlloc(len, ptr_align, ret_addr);
        if (result) |_| {
            self.current_bytes += len;
            self.peak_bytes = @max(self.peak_bytes, self.current_bytes);
            self.total_allocations += 1;
        }
        return result;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));
        const result = self.backing_allocator.rawResize(buf, buf_align, new_len, ret_addr);
        if (result) {
            self.current_bytes = self.current_bytes - buf.len + new_len;
            self.peak_bytes = @max(self.peak_bytes, self.current_bytes);
        }
        return result;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.backing_allocator.rawFree(buf, buf_align, ret_addr);
        self.current_bytes -= buf.len;
        self.total_frees += 1;
    }

    pub fn reset(self: *Self) void {
        self.peak_bytes = 0;
        self.current_bytes = 0;
        self.total_allocations = 0;
        self.total_frees = 0;
    }
};

/// Main benchmark runner
pub const BenchmarkRunner = struct {
    allocator: std.mem.Allocator,
    config: BenchmarkConfig,
    results: std.ArrayList(BenchmarkResult),
    tracking_allocator: TrackingAllocator,
    baseline_results: ?std.StringHashMap(BenchmarkResult) = null,

    pub fn init(allocator: std.mem.Allocator, config: BenchmarkConfig) BenchmarkRunner {
        return .{
            .allocator = allocator,
            .config = config,
            .results = std.ArrayList(BenchmarkResult).init(allocator),
            .tracking_allocator = .{ .backing_allocator = allocator },
        };
    }

    pub fn deinit(self: *BenchmarkRunner) void {
        self.results.deinit();
        if (self.baseline_results) |*baseline| {
            baseline.deinit();
        }
    }

    pub fn loadBaseline(self: *BenchmarkRunner, path: []const u8) !void {
        const content = try std.fs.cwd().readFileAlloc(self.allocator, path, 1024 * 1024);
        defer self.allocator.free(content);

        // Parse baseline results (simplified JSON parsing)
        self.baseline_results = std.StringHashMap(BenchmarkResult).init(self.allocator);
        // Implementation would parse JSON and populate baseline_results
    }

    /// Run a single benchmark
    pub fn benchmark(self: *BenchmarkRunner, comptime name: []const u8, func: anytype, args: anytype) !BenchmarkResult {
        std.debug.print("🏃 Running benchmark: {s}...\n", .{name});

        var times = try self.allocator.alloc(u64, self.config.iterations);
        defer self.allocator.free(times);

        var memory_samples = try self.allocator.alloc(usize, self.config.iterations);
        defer self.allocator.free(memory_samples);

        // Warmup
        for (0..self.config.warmup_iterations) |_| {
            self.tracking_allocator.reset();
            _ = @call(.auto, func, args);
        }

        // Actual benchmark
        var total_time: u64 = 0;
        var min_time: u64 = std.math.maxInt(u64);
        var max_time: u64 = 0;
        var total_memory: usize = 0;

        for (0..self.config.iterations) |i| {
            self.tracking_allocator.reset();

            const start_time = std.time.nanoTimestamp();
            _ = @call(.auto, func, args);
            const end_time = std.time.nanoTimestamp();

            const duration = @intCast(u64, end_time - start_time);
            times[i] = duration;
            memory_samples[i] = self.tracking_allocator.peak_bytes;

            total_time += duration;
            total_memory += self.tracking_allocator.peak_bytes;
            min_time = @min(min_time, duration);
            max_time = @max(max_time, duration);
        }

        // Calculate statistics
        std.mem.sort(u64, times, {}, comptime std.sort.asc(u64));
        const avg_time = total_time / self.config.iterations;
        const median_time = times[self.config.iterations / 2];
        const p95_time = times[(self.config.iterations * 95) / 100];
        const p99_time = times[(self.config.iterations * 99) / 100];

        std.mem.sort(usize, memory_samples, {}, comptime std.sort.asc(usize));
        const peak_memory = memory_samples[memory_samples.len - 1];
        const avg_memory = total_memory / self.config.iterations;

        const throughput = @as(f64, @floatFromInt(self.config.iterations)) / (@as(f64, @floatFromInt(total_time)) / 1_000_000_000.0);

        var result = BenchmarkResult{
            .name = name,
            .iterations = self.config.iterations,
            .total_time_ns = total_time,
            .avg_time_ns = avg_time,
            .min_time_ns = min_time,
            .max_time_ns = max_time,
            .median_time_ns = median_time,
            .p95_time_ns = p95_time,
            .p99_time_ns = p99_time,
            .memory_peak_bytes = peak_memory,
            .memory_avg_bytes = avg_memory,
            .allocations_count = self.tracking_allocator.total_allocations,
            .throughput_ops_per_sec = throughput,
        };

        // Compare with baseline if available
        if (self.baseline_results) |baseline| {
            if (baseline.get(name)) |baseline_result| {
                const diff = (@as(f64, @floatFromInt(avg_time)) - @as(f64, @floatFromInt(baseline_result.avg_time_ns))) / @as(f64, @floatFromInt(baseline_result.avg_time_ns)) * 100.0;
                result.baseline_comparison = diff;
            }
        }

        try self.results.append(result);
        result.print(self.config.detailed_output);

        return result;
    }

    /// Run all Flash CLI benchmarks
    pub fn runAllBenchmarks(self: *BenchmarkRunner) !void {
        std.debug.print("⚡ Flash CLI Framework Benchmarks\n");
        std.debug.print("================================\n\n");

        // Basic CLI creation and parsing
        _ = try self.benchmark("cli_creation", benchmarkCliCreation, .{});
        _ = try self.benchmark("simple_parsing", benchmarkSimpleParsing, .{});
        _ = try self.benchmark("complex_parsing", benchmarkComplexParsing, .{});

        // Help generation
        _ = try self.benchmark("help_generation", benchmarkHelpGeneration, .{});
        _ = try self.benchmark("long_help_generation", benchmarkLongHelpGeneration, .{});

        // Completion generation
        _ = try self.benchmark("bash_completion", benchmarkBashCompletion, .{});
        _ = try self.benchmark("zsh_completion", benchmarkZshCompletion, .{});

        // Validation
        _ = try self.benchmark("simple_validation", benchmarkSimpleValidation, .{});
        _ = try self.benchmark("complex_validation", benchmarkComplexValidation, .{});

        // Async operations
        _ = try self.benchmark("async_execution", benchmarkAsyncExecution, .{});
        _ = try self.benchmark("parallel_validation", benchmarkParallelValidation, .{});

        // Memory intensive operations
        _ = try self.benchmark("large_command_tree", benchmarkLargeCommandTree, .{});

        if (self.config.export_results) {
            try self.exportResults();
        }

        self.printSummary();
    }

    fn exportResults(self: *BenchmarkRunner) !void {
        const path = self.config.export_path orelse "benchmark_results";

        switch (self.config.export_format) {
            .json => try self.exportJson(path),
            .csv => try self.exportCsv(path),
            .markdown => try self.exportMarkdown(path),
        }
    }

    fn exportJson(self: *BenchmarkRunner, base_path: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "{s}.json", .{base_path});
        defer self.allocator.free(path);

        var file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        const writer = file.writer();
        try writer.print("{{\\n  \"benchmarks\": [\\n");

        for (self.results.items, 0..) |result, i| {
            const json = try result.toJson(self.allocator);
            defer self.allocator.free(json);

            try writer.print("    {s}", .{json});
            if (i < self.results.items.len - 1) {
                try writer.print(",");
            }
            try writer.print("\\n");
        }

        try writer.print("  ]\\n}}\\n");
    }

    fn exportCsv(self: *BenchmarkRunner, base_path: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "{s}.csv", .{base_path});
        defer self.allocator.free(path);

        var file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        const writer = file.writer();

        // Header
        try writer.print("name,iterations,avg_time_ns,min_time_ns,max_time_ns,median_time_ns,p95_time_ns,p99_time_ns,memory_peak_bytes,throughput_ops_per_sec\\n");

        // Data
        for (self.results.items) |result| {
            try writer.print("{s},{d},{d},{d},{d},{d},{d},{d},{d},{d:.2}\\n", .{
                result.name,
                result.iterations,
                result.avg_time_ns,
                result.min_time_ns,
                result.max_time_ns,
                result.median_time_ns,
                result.p95_time_ns,
                result.p99_time_ns,
                result.memory_peak_bytes,
                result.throughput_ops_per_sec,
            });
        }
    }

    fn exportMarkdown(self: *BenchmarkRunner, base_path: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "{s}.md", .{base_path});
        defer self.allocator.free(path);

        var file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        const writer = file.writer();

        try writer.print("# ⚡ Flash CLI Benchmark Results\\n\\n");
        try writer.print("| Benchmark | Avg Time | Throughput | Memory Peak |\\n");
        try writer.print("|-----------|----------|------------|-------------|\\n");

        for (self.results.items) |result| {
            try writer.print("| {s} | {d:.2}ms | {d:.2} ops/sec | {d} KB |\\n", .{
                result.name,
                @as(f64, @floatFromInt(result.avg_time_ns)) / 1_000_000.0,
                result.throughput_ops_per_sec,
                result.memory_peak_bytes / 1024,
            });
        }
    }

    fn printSummary(self: BenchmarkRunner) void {
        std.debug.print("📈 Benchmark Summary\\n");
        std.debug.print("===================\\n");

        var fastest_time: u64 = std.math.maxInt(u64);
        var fastest_name: []const u8 = "";
        var highest_throughput: f64 = 0;
        var highest_throughput_name: []const u8 = "";

        for (self.results.items) |result| {
            if (result.avg_time_ns < fastest_time) {
                fastest_time = result.avg_time_ns;
                fastest_name = result.name;
            }
            if (result.throughput_ops_per_sec > highest_throughput) {
                highest_throughput = result.throughput_ops_per_sec;
                highest_throughput_name = result.name;
            }
        }

        std.debug.print("🏆 Fastest: {s} ({d:.2}μs)\\n", .{ fastest_name, @as(f64, @floatFromInt(fastest_time)) / 1000.0 });
        std.debug.print("🚀 Highest throughput: {s} ({d:.2} ops/sec)\\n", .{ highest_throughput_name, highest_throughput });
        std.debug.print("📊 Total benchmarks: {d}\\n", .{self.results.items.len});
    }
};

// Benchmark implementations
fn benchmarkCliCreation() void {
    const allocator = std.heap.page_allocator;
    _ = CLI.CLI(.{
        .name = "benchmark_cli",
        .version = "1.0.0",
        .about = "Benchmark CLI application",
    });
    _ = allocator;
}

fn benchmarkSimpleParsing() void {
    // Mock simple argument parsing
    const args = [_][]const u8{ "program", "--help" };
    _ = args;
}

fn benchmarkComplexParsing() void {
    // Mock complex argument parsing with subcommands and multiple flags
    const args = [_][]const u8{ "program", "subcommand", "--flag1", "value1", "--flag2", "value2", "positional" };
    _ = args;
}

fn benchmarkHelpGeneration() void {
    // Mock help generation
    const help_text = "Usage: program [OPTIONS]\\nA test program\\n\\nOptions:\\n  -h, --help  Show help";
    _ = help_text;
}

fn benchmarkLongHelpGeneration() void {
    // Mock long help generation with many options
    var i: usize = 0;
    while (i < 50) {
        const flag_help = "  --flag{d}  Description for flag {d}\\n";
        _ = flag_help;
        i += 1;
    }
}

fn benchmarkBashCompletion() void {
    const allocator = std.heap.page_allocator;
    var generator = completion.CompletionGenerator.init(allocator);
    defer generator.deinit();

    const test_cmd = Command.Command.init("test", (Command.CommandConfig{}));
    _ = generator.generate(test_cmd, .bash, "test") catch unreachable;
}

fn benchmarkZshCompletion() void {
    const allocator = std.heap.page_allocator;
    var generator = completion.CompletionGenerator.init(allocator);
    defer generator.deinit();

    const test_cmd = Command.Command.init("test", (Command.CommandConfig{}));
    _ = generator.generate(test_cmd, .zsh, "test") catch unreachable;
}

fn benchmarkSimpleValidation() void {
    const allocator = std.heap.page_allocator;
    const validator = validation.emailValidator();
    _ = validator("test@example.com", allocator);
}

fn benchmarkComplexValidation() void {
    const allocator = std.heap.page_allocator;

    // Chain multiple validators
    const email_validator = validation.emailValidator();
    const port_validator = validation.portInRange(1024, 65535);
    const choice_validator = validation.choiceValidator(&.{ "option1", "option2", "option3" }, true);

    _ = email_validator("test@example.com", allocator);
    _ = port_validator("8080", allocator);
    _ = choice_validator("option1", allocator);
}

fn benchmarkAsyncExecution() void {
    const allocator = std.heap.page_allocator;
    var ctx = async_cli.AsyncContext.init(allocator);
    defer ctx.deinit();

    const commands = [_]async_cli.AsyncCommand{
        async_cli.AsyncCommand.init("echo", &.{"test1"}),
        async_cli.AsyncCommand.init("echo", &.{"test2"}),
    };

    _ = ctx.executeParallel(&commands) catch unreachable;
}

fn benchmarkParallelValidation() void {
    const allocator = std.heap.page_allocator;
    var pipeline = async_cli.AsyncValidationPipeline.init(allocator);
    defer pipeline.deinit();

    // Mock parallel validation
    _ = pipeline.validateParallel("test input") catch unreachable;
}

fn benchmarkLargeCommandTree() void {
    // Create a large command tree to test memory usage
    var commands: [100]Command.Command = undefined;
    for (&commands, 0..) |*cmd, i| {
        const name = std.fmt.allocPrint(std.heap.page_allocator, "command{d}", .{i}) catch unreachable;
        cmd.* = Command.Command.init(name, (Command.CommandConfig{}));
    }
}

// CLI entry point for running benchmarks
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = BenchmarkConfig{
        .iterations = 1000,
        .detailed_output = true,
        .export_results = true,
        .export_format = .json,
        .export_path = "flash_benchmarks",
    };

    var runner = BenchmarkRunner.init(allocator, config);
    defer runner.deinit();

    try runner.runAllBenchmarks();
}

// Tests
test "benchmark runner" {
    const config = BenchmarkConfig{ .iterations = 10, .warmup_iterations = 2 };
    var runner = BenchmarkRunner.init(std.testing.allocator, config);
    defer runner.deinit();

    const result = try runner.benchmark("test_benchmark", benchmarkCliCreation, .{});
    try std.testing.expect(result.iterations == 10);
    try std.testing.expect(result.avg_time_ns > 0);
}

test "tracking allocator" {
    var tracking = TrackingAllocator{ .backing_allocator = std.testing.allocator };
    const allocator = tracking.allocator();

    const memory = try allocator.alloc(u8, 1024);
    defer allocator.free(memory);

    try std.testing.expect(tracking.peak_bytes >= 1024);
    try std.testing.expect(tracking.total_allocations >= 1);
}