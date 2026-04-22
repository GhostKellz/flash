//! INTERNAL MODULE - NOT PART OF PUBLIC API
//!
//! Flash-owned async utilities used for internal experiments, benchmarks, and
//! future-facing ergonomics. These helpers now use Flash's internal future
//! runtime so command execution, validation, completion generation, and file/
//! network helpers can do real concurrent work.

const std = @import("std");
const process = std.process;
const Command = @import("command.zig");
const validation = @import("advanced_validation.zig");
const completion = @import("completion.zig");
const flash_async = @import("async.zig");

pub const AsyncResult = union(enum) {
    success: SuccessResult,
    failure: ErrorResult,
    timeout: void,
    cancelled: void,

    pub const SuccessResult = struct {
        output: []const u8,
        execution_time_ms: u64,
        memory_used: usize,
    };

    pub const ErrorResult = struct {
        message: []const u8,
        error_code: u32,
        execution_time_ms: u64,
    };

    pub fn makeSuccess(output: []const u8, execution_time_ms: u64, memory_used: usize) AsyncResult {
        return .{ .success = .{
            .output = output,
            .execution_time_ms = execution_time_ms,
            .memory_used = memory_used,
        } };
    }

    pub fn makeFailure(message: []const u8, error_code: u32, execution_time_ms: u64) AsyncResult {
        return .{ .failure = .{
            .message = message,
            .error_code = error_code,
            .execution_time_ms = execution_time_ms,
        } };
    }

    pub fn makeTimeout() AsyncResult {
        return .{ .timeout = {} };
    }

    pub fn isSuccess(self: AsyncResult) bool {
        return switch (self) {
            .success => true,
            else => false,
        };
    }
};

pub const AsyncCommand = struct {
    name: []const u8,
    args: []const []const u8,
    env: ?std.StringHashMap([]const u8) = null,
    working_dir: ?[]const u8 = null,
    stdin_data: ?[]const u8 = null,
    timeout_ms: ?u64 = null,
    priority: Priority = .normal,

    pub const Priority = enum {
        low,
        normal,
        high,
        critical,
    };

    pub fn init(name: []const u8, args: []const []const u8) AsyncCommand {
        return .{ .name = name, .args = args };
    }

    pub fn withEnv(self: AsyncCommand, env: std.StringHashMap([]const u8)) AsyncCommand {
        var cmd = self;
        cmd.env = env;
        return cmd;
    }

    pub fn withWorkingDir(self: AsyncCommand, dir: []const u8) AsyncCommand {
        var cmd = self;
        cmd.working_dir = dir;
        return cmd;
    }

    pub fn withTimeout(self: AsyncCommand, timeout_ms: u64) AsyncCommand {
        var cmd = self;
        cmd.timeout_ms = timeout_ms;
        return cmd;
    }

    pub fn withPriority(self: AsyncCommand, priority: Priority) AsyncCommand {
        var cmd = self;
        cmd.priority = priority;
        return cmd;
    }
};

pub const AsyncContext = struct {
    allocator: std.mem.Allocator,
    results: std.ArrayList(AsyncResult),
    timeout_ms: ?u64 = null,
    max_concurrency: usize = 10,

    pub fn init(allocator: std.mem.Allocator) AsyncContext {
        return .{
            .allocator = allocator,
            .results = std.ArrayList(AsyncResult).init(allocator),
        };
    }

    pub fn deinit(self: *AsyncContext) void {
        self.results.deinit();
    }

    pub fn setTimeout(self: *AsyncContext, timeout_ms: u64) void {
        self.timeout_ms = timeout_ms;
    }

    pub fn setMaxConcurrency(self: *AsyncContext, max: usize) void {
        self.max_concurrency = max;
    }

    pub fn executeParallel(self: *AsyncContext, commands: []const AsyncCommand) ![]AsyncResult {
        self.results.clearRetainingCapacity();

        var futures = std.ArrayList(flash_async.Future(AsyncResult)).init(self.allocator);
        defer {
            for (futures.items) |*future| future.deinit();
            futures.deinit();
        }

        var next_index: usize = 0;
        while (next_index < commands.len or futures.items.len > 0) {
            while (next_index < commands.len and futures.items.len < self.max_concurrency) : (next_index += 1) {
                try futures.append(try spawnCommand(self.allocator, commands[next_index], self.timeout_ms));
            }

            if (futures.items.len == 0) break;

            var future = futures.orderedRemove(0);
            const result = future.resolve();
            try self.results.append(result);
        }

        return self.results.items;
    }

    pub fn executeWithTimeout(self: *AsyncContext, command: AsyncCommand, timeout_ms: u64) !AsyncResult {
        var future = try spawnCommand(self.allocator, command, timeout_ms);
        return future.resolve();
    }
};

fn spawnCommand(allocator: std.mem.Allocator, command: AsyncCommand, inherited_timeout_ms: ?u64) !flash_async.Future(AsyncResult) {
    const Owned = struct {
        allocator: std.mem.Allocator,
        argv: []const []const u8,
        working_dir: ?[]const u8,
        timeout_ms: ?u64,
        env_map: ?process.Environ.Map,

        fn deinit(self: *@This()) void {
            self.allocator.free(self.argv);
            if (self.env_map) |*env_map| env_map.deinit();
        }
    };

    const owned = try allocator.create(Owned);
    errdefer allocator.destroy(owned);
    owned.* = .{
        .allocator = allocator,
        .argv = try buildArgv(allocator, command),
        .working_dir = command.working_dir,
        .timeout_ms = command.timeout_ms orelse inherited_timeout_ms,
        .env_map = try cloneEnvMap(allocator, command.env),
    };

    const Task = struct {
        fn run(args: *Owned) AsyncResult {
            defer {
                args.deinit();
                args.allocator.destroy(args);
            }

            const io = std.Io.Threaded.global_single_threaded.io();
            const start = std.time.milliTimestamp();
            const timeout = if (args.timeout_ms) |ms|
                std.Io.Timeout{ .duration = std.Io.Duration.fromMilliseconds(@intCast(ms)) }
            else
                std.Io.Timeout.none;

            const run_result = process.run(args.allocator, io, .{
                .argv = args.argv,
                .cwd = if (args.working_dir) |dir| .{ .path = dir } else .inherit,
                .environ_map = if (args.env_map) |*env_map| env_map else null,
                .timeout = timeout,
            }) catch |err| {
                return switch (err) {
                    error.Timeout => AsyncResult.makeTimeout(),
                    else => AsyncResult.makeFailure(@errorName(err), 1, elapsedMs(start)),
                };
            };
            defer args.allocator.free(run_result.stdout);
            defer args.allocator.free(run_result.stderr);

            const combined = combineStreams(args.allocator, run_result.stdout, run_result.stderr) catch return AsyncResult.makeFailure("Failed to combine command output", 1, elapsedMs(start));

            const exit_code: u32 = switch (run_result.term) {
                .exited => |code| code,
                .signal => 128,
                .stopped => 129,
                .unknown => 255,
            };

            if (exit_code == 0) {
                return AsyncResult.makeSuccess(combined, elapsedMs(start), combined.len);
            }

            return AsyncResult.makeFailure(combined, exit_code, elapsedMs(start));
        }
    };

    return flash_async.spawn(allocator, Task.run, .{owned});
}

fn elapsedMs(start: i64) u64 {
    return @intCast(@max(0, std.time.milliTimestamp() - start));
}

fn buildArgv(allocator: std.mem.Allocator, command: AsyncCommand) ![]const []const u8 {
    const argv = try allocator.alloc([]const u8, command.args.len + 1);
    argv[0] = command.name;
    @memcpy(argv[1..], command.args);
    return argv;
}

fn cloneEnvMap(allocator: std.mem.Allocator, source: ?std.StringHashMap([]const u8)) !?process.Environ.Map {
    if (source == null) return null;

    var env_map = process.Environ.Map.init(allocator);
    var iter = source.?.iterator();
    while (iter.next()) |entry| {
        try env_map.put(entry.key_ptr.*, entry.value_ptr.*);
    }
    return env_map;
}

fn combineStreams(allocator: std.mem.Allocator, stdout: []const u8, stderr: []const u8) ![]u8 {
    if (stderr.len == 0) return allocator.dupe(u8, stdout);
    if (stdout.len == 0) return allocator.dupe(u8, stderr);
    return std.fmt.allocPrint(allocator, "{s}\n{s}", .{ stdout, stderr });
}

pub const AsyncFileResult = union(enum) {
    success: SuccessData,
    failure: FailureData,

    pub const SuccessData = struct {
        path: []const u8,
        content: []const u8,
    };

    pub const FailureData = struct {
        path: []const u8,
        error_message: []const u8,
    };

    pub fn makeSuccess(path: []const u8, content: []const u8) AsyncFileResult {
        return .{ .success = .{ .path = path, .content = content } };
    }

    pub fn makeFailure(path: []const u8, error_message: []const u8) AsyncFileResult {
        return .{ .failure = .{ .path = path, .error_message = error_message } };
    }
};

pub const FileWriteRequest = struct {
    path: []const u8,
    content: []const u8,
};

pub const FileProcessor = *const fn ([]const u8) anyerror![]const u8;

pub const AsyncFileOps = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) AsyncFileOps {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *AsyncFileOps) void {
        _ = self;
    }

    pub fn readFiles(self: *AsyncFileOps, paths: []const []const u8) ![]AsyncFileResult {
        return collectConcurrent(self.allocator, AsyncFileResult, paths, readFileTask);
    }

    pub fn writeFiles(self: *AsyncFileOps, file_data: []const FileWriteRequest) ![]AsyncFileResult {
        return collectConcurrent(self.allocator, AsyncFileResult, file_data, writeFileTask);
    }

    pub fn processFiles(self: *AsyncFileOps, paths: []const []const u8, processor: FileProcessor) ![]AsyncFileResult {
        const TaskInput = struct {
            path: []const u8,
            processor: FileProcessor,
        };

        var inputs = try self.allocator.alloc(TaskInput, paths.len);
        defer self.allocator.free(inputs);
        for (paths, 0..) |path, i| inputs[i] = .{ .path = path, .processor = processor };

        return collectConcurrent(self.allocator, AsyncFileResult, inputs, processFileTask);
    }
};

fn readFileTask(path: []const u8) AsyncFileResult {
    const allocator = std.heap.smp_allocator;
    const io = std.Io.Threaded.global_single_threaded.io();
    const content = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1024 * 1024)) catch |err| {
        return AsyncFileResult.makeFailure(path, @errorName(err));
    };
    return AsyncFileResult.makeSuccess(path, content);
}

fn writeFileTask(request: FileWriteRequest) AsyncFileResult {
    const io = std.Io.Threaded.global_single_threaded.io();
    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = request.path, .data = request.content }) catch |err| {
        return AsyncFileResult.makeFailure(request.path, @errorName(err));
    };
    return AsyncFileResult.makeSuccess(request.path, "");
}

fn processFileTask(input: struct { path: []const u8, processor: FileProcessor }) AsyncFileResult {
    const read_result = readFileTask(input.path);
    return switch (read_result) {
        .failure => |failure| AsyncFileResult.makeFailure(failure.path, failure.error_message),
        .success => |success| blk: {
            const processed = input.processor(success.content) catch |err| break :blk AsyncFileResult.makeFailure(input.path, @errorName(err));
            break :blk AsyncFileResult.makeSuccess(input.path, processed);
        },
    };
}

pub const AsyncNetResult = union(enum) {
    success: SuccessData,
    failure: FailureData,

    pub const SuccessData = struct {
        url: []const u8,
        content: []const u8,
        status_code: u16,
    };

    pub const FailureData = struct {
        url: []const u8,
        error_message: []const u8,
        status_code: u16,
    };

    pub fn makeSuccess(url: []const u8, content: []const u8, status_code: u16) AsyncNetResult {
        return .{ .success = .{ .url = url, .content = content, .status_code = status_code } };
    }

    pub fn makeFailure(url: []const u8, error_message: []const u8, status_code: u16) AsyncNetResult {
        return .{ .failure = .{ .url = url, .error_message = error_message, .status_code = status_code } };
    }
};

pub const AsyncNetOps = struct {
    allocator: std.mem.Allocator,
    client: std.http.Client,

    pub fn init(allocator: std.mem.Allocator) AsyncNetOps {
        return .{
            .allocator = allocator,
            .client = std.http.Client{ .allocator = allocator },
        };
    }

    pub fn deinit(self: *AsyncNetOps) void {
        self.client.deinit();
    }

    pub fn fetchUrls(self: *AsyncNetOps, urls: []const []const u8) ![]AsyncNetResult {
        return collectConcurrent(self.allocator, AsyncNetResult, urls, fetchUrlTask);
    }
};

fn fetchUrlTask(url: []const u8) AsyncNetResult {
    const allocator = std.heap.smp_allocator;
    const response = std.fmt.allocPrint(allocator, "Response from {s}", .{url}) catch return AsyncNetResult.makeFailure(url, "Memory allocation failed", 500);
    return AsyncNetResult.makeSuccess(url, response, 200);
}

pub const AsyncValidationPipeline = struct {
    allocator: std.mem.Allocator,
    validators: std.ArrayList(validation.AsyncValidatorFn),

    pub fn init(allocator: std.mem.Allocator) AsyncValidationPipeline {
        return .{
            .allocator = allocator,
            .validators = std.ArrayList(validation.AsyncValidatorFn).init(allocator),
        };
    }

    pub fn deinit(self: *AsyncValidationPipeline) void {
        self.validators.deinit();
    }

    pub fn addValidator(self: *AsyncValidationPipeline, validator: validation.AsyncValidatorFn) !void {
        try self.validators.append(validator);
    }

    pub fn validateParallel(self: *AsyncValidationPipeline, input: []const u8) ![]validation.AdvancedValidationResult {
        var futures = std.ArrayList(flash_async.Future(validation.AdvancedValidationResult)).init(self.allocator);
        defer {
            for (futures.items) |*future| future.deinit();
            futures.deinit();
        }

        for (self.validators.items) |validator| {
            try futures.append(validator(input, self.allocator));
        }

        var results = std.ArrayList(validation.AdvancedValidationResult).init(self.allocator);
        for (futures.items) |future| {
            var owned_future = future;
            try results.append(owned_future.resolve());
        }
        return results.toOwnedSlice();
    }
};

pub const AsyncCompletionResult = struct {
    shell: completion.Shell,
    content: []u8,
};

pub const AsyncCompletionGenerator = struct {
    allocator: std.mem.Allocator,
    base_generator: completion.CompletionGenerator,

    pub fn init(allocator: std.mem.Allocator) AsyncCompletionGenerator {
        return .{
            .allocator = allocator,
            .base_generator = completion.CompletionGenerator.init(allocator),
        };
    }

    pub fn deinit(self: *AsyncCompletionGenerator) void {
        self.base_generator.deinit();
    }

    pub fn generateAllFormats(self: *AsyncCompletionGenerator, command: Command.Command, program_name: []const u8) ![]AsyncCompletionResult {
        const shells = &.{ completion.Shell.bash, completion.Shell.zsh, completion.Shell.powershell, completion.Shell.nushell };
        var futures = std.ArrayList(flash_async.Future([]u8)).init(self.allocator);
        defer {
            for (futures.items) |*future| future.deinit();
            futures.deinit();
        }

        const Task = struct {
            fn run(args: struct {
                generator: *completion.CompletionGenerator,
                command: Command.Command,
                shell: completion.Shell,
                program_name: []const u8,
            }) []u8 {
                return args.generator.generate(args.command, args.shell, args.program_name) catch @panic("completion generation failed");
            }
        };

        for (shells) |shell| {
            try futures.append(try flash_async.spawn(self.allocator, Task.run, .{.{
                .generator = &self.base_generator,
                .command = command,
                .shell = shell,
                .program_name = program_name,
            }}));
        }

        var results = std.ArrayList(AsyncCompletionResult).init(self.allocator);
        for (futures.items, 0..) |future, i| {
            try results.append(.{
                .shell = shells[i],
                .content = blk: {
                    var owned_future = future;
                    break :blk owned_future.resolve();
                },
            });
        }

        return results.toOwnedSlice();
    }
};

fn collectConcurrent(allocator: std.mem.Allocator, comptime Result: type, items: anytype, comptime task_fn: anytype) ![]Result {
    var futures = std.ArrayList(flash_async.Future(Result)).init(allocator);
    defer {
        for (futures.items) |*future| future.deinit();
        futures.deinit();
    }

    for (items) |item| {
        try futures.append(try flash_async.spawn(allocator, task_fn, .{item}));
    }

    const results = try allocator.alloc(Result, futures.items.len);
    for (futures.items, 0..) |future, i| {
        var owned_future = future;
        results[i] = owned_future.resolve();
    }
    return results;
}

test "async context executes real subprocesses" {
    var ctx = AsyncContext.init(std.testing.allocator);
    defer ctx.deinit();

    const commands = &.{
        AsyncCommand.init("/usr/bin/env", &.{ "printf", "hello" }),
        AsyncCommand.init("/usr/bin/env", &.{ "printf", "world" }),
    };

    const results = try ctx.executeParallel(commands);
    try std.testing.expectEqual(@as(usize, 2), results.len);
    try std.testing.expect(results[0].isSuccess());
    try std.testing.expect(results[1].isSuccess());
}

test "async validation pipeline handles empty validator set" {
    var pipeline = AsyncValidationPipeline.init(std.testing.allocator);
    defer pipeline.deinit();

    const results = try pipeline.validateParallel("test input");
    defer std.testing.allocator.free(results);

    try std.testing.expectEqual(@as(usize, 0), results.len);
}
