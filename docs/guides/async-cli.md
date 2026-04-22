# ⚡ Async CLI Development with Flash

> **Note**: The async module is currently internal and not part of the public API.
> This documentation describes internal and future-facing functionality.

Flash has internal async implementation work in progress. This guide describes exploratory and future-facing patterns rather than the current stable public API.

## 🚀 Why Async CLI?

Traditional CLI frameworks process commands sequentially, but modern CLI tools often need to:
- Process multiple files concurrently
- Make parallel network requests
- Handle real-time data streams
- Manage background tasks
- Provide responsive user interfaces

These scenarios are relevant to Flash's long-term direction, but the async module is not part of the supported `v0.4.0` public surface.

## 🏗️ Async Architecture Overview

Flash now uses a Flash-owned internal async foundation for these exploratory patterns:

```zig
const flash = @import("flash");
pub fn main() !void {
    const cli = flash.CLI(.{
        .name = "async-example",
        .commands = &.{
            flash.cmd("process", .{
                .about = "Process files concurrently",
                .run_async = processFilesAsync,
            }),
        },
    });

    // Command-level async handlers are internal-only right now.
    // Public applications still run through runWithInit(init).
}
```

## 📁 Async File Operations

### Processing Multiple Files

```zig
const AsyncFileOps = @import("flash").async_cli.AsyncFileOps;

async fn processFilesAsync(ctx: flash.Context) !void {
    const files = ctx.getMany("files") orelse return;

    var file_ops = AsyncFileOps.init(ctx.allocator);
    defer file_ops.deinit();

    // Process all files concurrently
    const results = try file_ops.processFiles(files, processFile);
    defer ctx.allocator.free(results);

    // Handle results
    for (results) |result| {
        switch (result) {
            .success => |data| std.debug.print("✅ {s}: processed\n", .{data.path}),
            .failure => |err| std.debug.print("❌ {s}: {s}\n", .{err.path, err.error_message}),
        }
    }
}

fn processFile(content: []const u8) ![]const u8 {
    // Custom file processing logic
    return try std.fmt.allocPrint(
        std.heap.page_allocator,
        "Processed {} bytes",
        .{content.len}
    );
}
```

### Watching Files for Changes

```zig
async fn watchFiles(ctx: flash.Context) !void {
    const paths = ctx.getMany("paths") orelse return;

    var watcher = flash.FileWatcher.init(ctx.allocator);
    defer watcher.deinit();

    // Set up file watching
    for (paths) |path| {
        try watcher.watch(path, onFileChanged);
    }

    std.debug.print("👀 Watching {} files for changes...\n", .{paths.len});

    // Keep watching until interrupted
    try watcher.runUntilSignal();
}

fn onFileChanged(path: []const u8, event: flash.FileEvent) void {
    switch (event) {
        .modified => std.debug.print("📝 {s} was modified\n", .{path}),
        .created => std.debug.print("➕ {s} was created\n", .{path}),
        .deleted => std.debug.print("🗑️  {s} was deleted\n", .{path}),
    }
}
```

## 🌐 Async Network Operations

### Parallel HTTP Requests

```zig
const AsyncNetOps = @import("flash").async_cli.AsyncNetOps;

async fn fetchUrlsAsync(ctx: flash.Context) !void {
    const urls = ctx.getMany("urls") orelse return;

    var net_ops = AsyncNetOps.init(ctx.allocator);
    defer net_ops.deinit();

    std.debug.print("🌐 Fetching {} URLs...\n", .{urls.len});

    const results = try net_ops.fetchUrls(urls);
    defer ctx.allocator.free(results);

    for (results) |result| {
        switch (result) {
            .success => |data| {
                std.debug.print("✅ {s}: {} bytes (status: {})\n",
                    .{data.url, data.content.len, data.status_code});
            },
            .failure => |err| {
                std.debug.print("❌ {s}: {s} (status: {})\n",
                    .{err.url, err.error_message, err.status_code});
            },
        }
    }
}
```

### WebSocket Streaming

```zig
async fn streamData(ctx: flash.Context) !void {
    const url = ctx.get("websocket-url") orelse return flash.Error.MissingArgument;

    var stream = try flash.WebSocketStream.connect(ctx.allocator, url);
    defer stream.deinit();

    std.debug.print("🔗 Connected to {s}\n", .{url});

    // Handle incoming messages
    while (try stream.receive()) |message| {
        switch (message.type) {
            .text => std.debug.print("📨 {s}\n", .{message.data}),
            .binary => std.debug.print("📦 Binary data: {} bytes\n", .{message.data.len}),
            .close => break,
        }
    }
}
```

## ⚡ Parallel Command Execution

### Running Multiple Commands

```zig
const AsyncContext = @import("flash").async_cli.AsyncContext;

async fn deployServices(ctx: flash.Context) !void {
    const services = ctx.getMany("services") orelse return;

    var async_ctx = AsyncContext.init(ctx.allocator);
    defer async_ctx.deinit();

    // Configure parallel execution
    async_ctx.setMaxConcurrency(5);
    async_ctx.setTimeout(30_000); // 30 second timeout

    // Build deployment commands
    var commands = std.ArrayList(flash.AsyncCommand).init(ctx.allocator);
    defer commands.deinit();

    for (services) |service| {
        const cmd = flash.AsyncCommand.init("kubectl", &.{"apply", "-f", service})
            .withTimeout(30_000)
            .withPriority(.high);
        try commands.append(cmd);
    }

    std.debug.print("🚀 Deploying {} services...\n", .{services.len});

    // Execute all deployments in parallel
    const results = try async_ctx.executeParallel(commands.items);
    defer ctx.allocator.free(results);

    var success_count: usize = 0;
    for (results) |result| {
        switch (result) {
            .success => |data| {
                success_count += 1;
                std.debug.print("✅ Service deployed ({}ms)\n", .{data.execution_time_ms});
            },
            .error => |err| {
                std.debug.print("❌ Deployment failed: {s}\n", .{err.message});
            },
            .timeout => std.debug.print("⏰ Deployment timed out\n", .{}),
            .cancelled => std.debug.print("🚫 Deployment cancelled\n", .{}),
        }
    }

    std.debug.print("📊 Results: {}/{} deployments successful\n",
        .{success_count, services.len});
}
```

## 🔄 Real-Time Data Processing

### Log Streaming and Analysis

```zig
async fn analyzeLogsAsync(ctx: flash.Context) !void {
    const log_file = ctx.get("file") orelse return;
    const pattern = ctx.get("pattern") orelse "ERROR";

    var analyzer = flash.LogAnalyzer.init(ctx.allocator);
    defer analyzer.deinit();

    // Set up real-time analysis
    try analyzer.watchFile(log_file);
    try analyzer.addPattern(pattern, onPatternMatch);

    std.debug.print("📊 Analyzing logs in real-time...\n", .{});

    // Process log entries as they arrive
    try analyzer.start();
}

fn onPatternMatch(line: []const u8, pattern: []const u8, timestamp: i64) void {
    std.debug.print("🚨 [{d}] Found pattern '{s}': {s}\n",
        .{timestamp, pattern, line});
}
```

## 🎯 Progress Reporting

### Async Progress Bars

```zig
async fn downloadWithProgress(ctx: flash.Context) !void {
    const url = ctx.get("url") orelse return;
    const output = ctx.get("output") orelse return;

    var progress = flash.ProgressBar.init(ctx.allocator);
    defer progress.deinit();

    // Configure progress bar
    progress.setTemplate("[{bar}] {percent}% {bytes}/{total_bytes} ETA: {eta}");
    progress.setWidth(50);

    // Start download with progress callback
    var downloader = flash.HttpDownloader.init(ctx.allocator);
    defer downloader.deinit();

    try downloader.download(url, output, struct {
        fn onProgress(downloaded: usize, total: usize) void {
            progress.update(downloaded, total);
        }
    }.onProgress);

    progress.finish("✅ Download complete!");
}
```

## 🛡️ Error Handling and Resilience

### Retry Logic with Exponential Backoff

```zig
async fn resilientOperation(ctx: flash.Context) !void {
    const max_retries = ctx.getInt("retries") orelse 3;
    const base_delay = ctx.getInt("delay") orelse 1000; // ms

    var retries: usize = 0;
    while (retries < max_retries) {
        switch (try attemptOperation(ctx)) {
            .success => return,
            .retry => {
                retries += 1;
                const delay = base_delay * (@as(u64, 1) << @intCast(retries));
                std.debug.print("⏳ Retrying in {}ms... ({}/{})\n",
                    .{delay, retries, max_retries});
                std.time.sleep(delay * std.time.ns_per_ms);
            },
            .fail => return flash.Error.OperationFailed,
        }
    }

    return flash.Error.MaxRetriesExceeded;
}
```

## 🔧 Async Testing

### Testing Async Commands

Async testing helpers are not part of the supported public API in `v0.4.0`.
If you are experimenting with internal async code, prefer local module-level tests instead of depending on a stable Flash test harness for async execution.
        &.{"file1.txt", "file2.txt"}
    );

    try std.testing.expect(result.isSuccess());
    try std.testing.expect(result.execution_time_ms < 1000);
}
```

## 📊 Performance Monitoring

### Async Metrics Collection

```zig
async fn withMetrics(ctx: flash.Context, operation: anytype) !void {
    var metrics = flash.Metrics.init(ctx.allocator);
    defer metrics.deinit();

    const start_time = std.time.nanoTimestamp();
    const start_memory = metrics.getCurrentMemoryUsage();

    // Execute operation
    const result = try operation(ctx);

    const end_time = std.time.nanoTimestamp();
    const peak_memory = metrics.getPeakMemoryUsage();

    // Report metrics
    metrics.record(.{
        .operation = @typeName(@TypeOf(operation)),
        .duration_ns = end_time - start_time,
        .memory_peak = peak_memory,
        .memory_delta = peak_memory - start_memory,
        .success = result.isSuccess(),
    });

    if (ctx.getBool("verbose")) {
        metrics.printSummary();
    }
}
```

## 🎨 Best Practices

### 1. **Resource Management**
```zig
// Always use defer for cleanup
var resource = try allocateResource();
defer resource.deinit();

// Use context cancellation
if (ctx.isCancelled()) return;
```

### 2. **Error Propagation**
```zig
// Propagate errors properly in async functions
async fn processItem(item: Item) !Result {
    return processItemImpl(item) catch |err| switch (err) {
        error.Timeout => error.ProcessingTimeout,
        error.InvalidData => error.InvalidItem,
        else => err,
    };
}
```

### 3. **Concurrency Control**
```zig
// Keep concurrency explicit in your application code today
var async_ctx = flash.async_cli.AsyncContext.init(ctx.allocator);
defer async_ctx.deinit();

async_ctx.setMaxConcurrency(max_concurrent_operations);
```

### 4. **Progress Reporting**
```zig
// Always provide feedback for long-running operations
if (total_items > 100) {
    var progress = flash.ProgressBar.init(allocator);
    defer progress.deinit();
    // Update progress throughout operation
}
```

## 🔗 Related Documentation

- [API Reference: Async Operations](../api/async.md)
- [Architecture: Async System](../architecture/async-system.md)
- [Getting Started](getting-started.md)
- [Declarative Config](declarative-config.md)
- [Shell Completions](completions.md)

---

*Async CLI development opens up new possibilities for building responsive, efficient command-line tools. Flash makes async patterns natural and performant.*
