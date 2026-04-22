//! INTERNAL MODULE - NOT PART OF PUBLIC API
//!
//! Flash owns a small async runtime that uses Zig threads underneath. The goal
//! is not to expose a public scheduler yet, but to provide real concurrent
//! execution for internal async hooks such as `run_async`, async completion,
//! async validation, and internal async CLI helpers.

const std = @import("std");
const Context = @import("context.zig");
const Error = @import("error.zig");

pub fn ReturnType(comptime func: anytype) type {
    return @typeInfo(@TypeOf(func)).@"fn".return_type.?;
}

pub fn ReturnTypeFromFnType(comptime Fn: type) type {
    return switch (@typeInfo(Fn)) {
        .@"fn" => |info| info.return_type.?,
        .pointer => |ptr| switch (@typeInfo(ptr.child)) {
            .@"fn" => |info| info.return_type.?,
            else => @compileError("Expected function or pointer-to-function type"),
        },
        else => @compileError("Expected function or pointer-to-function type"),
    };
}

pub fn Future(comptime Result: type) type {
    return struct {
        allocator: std.mem.Allocator,
        state: ?*State = null,
        inline_result: Result = undefined,
        is_ready: bool = false,

        const Self = @This();

        const State = struct {
            thread: ?std.Thread,
            result: Result = undefined,
        };

        pub fn ready(allocator: std.mem.Allocator, value: Result) Self {
            return .{
                .allocator = allocator,
                .inline_result = value,
                .is_ready = true,
            };
        }

        pub fn resolve(self: *Self) Result {
            return self.takeResult();
        }

        pub fn deinit(self: *Self) void {
            if (self.state) |state| {
                if (state.thread) |thread| {
                    thread.join();
                    state.thread = null;
                }
                self.allocator.destroy(state);
                self.state = null;
            }
            self.is_ready = false;
        }

        fn takeResult(self: *Self) Result {
            defer self.deinit();

            if (self.is_ready) return self.inline_result;

            const state = self.state orelse unreachable;
            if (state.thread) |thread| {
                thread.join();
                state.thread = null;
            }
            return state.result;
        }
    };
}

pub fn spawn(allocator: std.mem.Allocator, comptime func: anytype, args: anytype) !Future(ReturnType(func)) {
    const Result = ReturnType(func);
    const FutureType = Future(Result);

    const Task = struct {
        allocator: std.mem.Allocator,
        state: *FutureType.State,
        args: @TypeOf(args),

        fn run(task: *@This()) void {
            defer task.allocator.destroy(task);
            task.state.result = @call(.auto, func, task.args);
        }
    };

    const state = try allocator.create(FutureType.State);
    errdefer allocator.destroy(state);
    state.* = .{ .thread = null };

    const task = try allocator.create(Task);
    errdefer allocator.destroy(task);
    task.* = .{
        .allocator = allocator,
        .state = state,
        .args = args,
    };

    state.thread = try std.Thread.spawn(.{ .allocator = allocator }, Task.run, .{task});

    return .{
        .allocator = allocator,
        .state = state,
    };
}

pub fn spawnFn(allocator: std.mem.Allocator, comptime Fn: type, func: Fn, args: anytype) !Future(ReturnTypeFromFnType(Fn)) {
    const Result = ReturnTypeFromFnType(Fn);
    const FutureType = Future(Result);

    const Task = struct {
        allocator: std.mem.Allocator,
        func: Fn,
        state: *FutureType.State,
        args: @TypeOf(args),

        fn run(task: *@This()) void {
            defer task.allocator.destroy(task);
            task.state.result = @call(.auto, task.func, task.args);
        }
    };

    const state = try allocator.create(FutureType.State);
    errdefer allocator.destroy(state);
    state.* = .{ .thread = null };

    const task = try allocator.create(Task);
    errdefer allocator.destroy(task);
    task.* = .{
        .allocator = allocator,
        .func = func,
        .state = state,
        .args = args,
    };

    state.thread = try std.Thread.spawn(.{ .allocator = allocator }, Task.run, .{task});

    return .{
        .allocator = allocator,
        .state = state,
    };
}

pub fn runTask(allocator: std.mem.Allocator, comptime func: anytype, args: anytype) !ReturnType(func) {
    var future = try spawn(allocator, func, args);
    return future.resolve();
}

pub fn runFn(allocator: std.mem.Allocator, comptime Fn: type, func: Fn, args: anytype) !ReturnTypeFromFnType(Fn) {
    var future = try spawnFn(allocator, Fn, func, args);
    return future.resolve();
}

fn spawnRuntimeFn(allocator: std.mem.Allocator, comptime Fn: type, func: Fn, args: anytype) Error.FlashError!Future(ReturnTypeFromFnType(Fn)) {
    return spawnFn(allocator, Fn, func, args) catch Error.FlashError.AsyncExecutionFailed;
}

fn runRuntimeFn(allocator: std.mem.Allocator, comptime Fn: type, func: Fn, args: anytype) Error.FlashError!ReturnTypeFromFnType(Fn) {
    var future = try spawnRuntimeFn(allocator, Fn, func, args);
    return future.resolve();
}

pub const SimpleAsyncFn = *const fn (Context.Context) Error.FlashError!void;

pub const ExecutionModel = enum {
    blocking,
    cooperative,
    thread_pool,
};

pub const CancellationToken = struct {
    is_cancelled: std.atomic.Value(bool) = .init(false),
    reason: ?[]const u8 = null,

    pub fn init() CancellationToken {
        return .{};
    }

    pub fn cancel(self: *CancellationToken, reason: ?[]const u8) void {
        self.reason = reason;
        self.is_cancelled.store(true, .release);
    }

    pub fn checkCancellation(self: *const CancellationToken) Error.FlashError!void {
        if (self.is_cancelled.load(.acquire)) return Error.FlashError.OperationCancelled;
    }
};

pub const ConcurrentOp = struct {
    name: []const u8,
    func: SimpleAsyncFn,
    ctx: Context.Context,
};

pub const AsyncRuntime = struct {
    allocator: std.mem.Allocator,
    execution_model: ExecutionModel,

    pub fn init(allocator: std.mem.Allocator, model: ExecutionModel) AsyncRuntime {
        return .{
            .allocator = allocator,
            .execution_model = model,
        };
    }

    pub fn deinit(self: *AsyncRuntime) void {
        _ = self;
    }

    pub fn runAuto(allocator: std.mem.Allocator, task: anytype, args: anytype) !void {
        _ = try runTask(allocator, task, args);
    }

    pub fn runBlocking(allocator: std.mem.Allocator, task: anytype, args: anytype) !void {
        _ = try runTask(allocator, task, args);
    }

    pub fn runHighPerf(allocator: std.mem.Allocator, task: anytype, args: anytype) !void {
        _ = try runTask(allocator, task, args);
    }

    pub fn runAsync(self: *AsyncRuntime, handler: SimpleAsyncFn, ctx: Context.Context) Error.FlashError!void {
        _ = self.execution_model;
        var future = try spawnRuntimeFn(self.allocator, SimpleAsyncFn, handler, .{ctx});
        try future.resolve();
    }

    pub fn runWithCancellation(self: *AsyncRuntime, handler: SimpleAsyncFn, ctx: Context.Context, cancel_token: ?*CancellationToken) Error.FlashError!void {
        if (cancel_token) |token| try token.checkCancellation();
        try self.runAsync(handler, ctx);
    }

    pub fn createFuture(self: *AsyncRuntime, func: SimpleAsyncFn, ctx: Context.Context) !Future(Error.FlashError!void) {
        return spawnRuntimeFn(self.allocator, SimpleAsyncFn, func, .{ctx});
    }

    pub fn spawnConcurrent(self: *AsyncRuntime, operations: []const ConcurrentOp) Error.FlashError!void {
        var futures: std.ArrayList(Future(Error.FlashError!void)) = .empty;
        defer {
            for (futures.items) |*future| future.deinit();
            futures.deinit(self.allocator);
        }

        for (operations) |op| {
            _ = op.name;
            try futures.append(self.allocator, try spawnRuntimeFn(self.allocator, SimpleAsyncFn, op.func, .{op.ctx}));
        }

        for (futures.items) |*future| {
            try future.resolve();
        }
    }
};

test "spawn executes work on a thread" {
    const Work = struct {
        fn run(value: usize) usize {
            return value + 1;
        }
    };

    var future = try spawn(std.testing.allocator, Work.run, .{41});
    try std.testing.expectEqual(@as(usize, 42), future.resolve());
}

test "async runtime propagates handler errors" {
    const Handlers = struct {
        fn fail(_: Context.Context) Error.FlashError!void {
            return Error.FlashError.InvalidInput;
        }
    };

    var runtime = AsyncRuntime.init(std.testing.allocator, .thread_pool);
    defer runtime.deinit();

    var ctx = Context.Context.init(std.testing.allocator, &.{});
    defer ctx.deinit();

    try std.testing.expectError(Error.FlashError.InvalidInput, runtime.runAsync(Handlers.fail, ctx));
}

test "spawnConcurrent runs all operations" {
    const Ops = struct {
        var counter = std.atomic.Value(usize).init(0);

        fn run(_: Context.Context) Error.FlashError!void {
            _ = counter.fetchAdd(1, .acq_rel);
        }
    };

    Ops.counter.store(0, .release);

    var runtime = AsyncRuntime.init(std.testing.allocator, .thread_pool);
    defer runtime.deinit();

    var ctx = Context.Context.init(std.testing.allocator, &.{});
    defer ctx.deinit();

    const ops = [_]ConcurrentOp{
        .{ .name = "one", .func = Ops.run, .ctx = ctx },
        .{ .name = "two", .func = Ops.run, .ctx = ctx },
    };

    try runtime.spawnConcurrent(&ops);
    try std.testing.expectEqual(@as(usize, 2), Ops.counter.load(.acquire));
}
