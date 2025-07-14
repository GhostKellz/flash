//! ⚡ Flash Progress Indicators
//!
//! Provides beautiful progress bars and spinners for long-running operations

const std = @import("std");

/// Progress indicator types
pub const IndicatorType = enum {
    spinner,
    progress_bar,
    dots,
    pulse,
};

/// Spinner characters
pub const SpinnerStyle = enum {
    dots,
    line,
    arrow,
    arc,
    bounce,
    lightning,
    
    pub fn getFrames(self: SpinnerStyle) []const []const u8 {
        return switch (self) {
            .dots => &.{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
            .line => &.{ "-", "\\", "|", "/" },
            .arrow => &.{ "←", "↖", "↑", "↗", "→", "↘", "↓", "↙" },
            .arc => &.{ "◜", "◠", "◝", "◞", "◡", "◟" },
            .bounce => &.{ "⠄", "⠆", "⠇", "⠋", "⠙", "⠸", "⠰", "⠠", "⠰", "⠸", "⠙", "⠋", "⠇", "⠆" },
            .lightning => &.{ "⚡", "✨", "⭐", "✨" },
        };
    }
};

/// Progress bar configuration
pub const ProgressConfig = struct {
    total: u64,
    width: usize = 40,
    fill_char: u8 = '█',
    empty_char: u8 = '░',
    show_percentage: bool = true,
    show_count: bool = true,
    show_rate: bool = false,
    prefix: []const u8 = "⚡",
    suffix: []const u8 = "",
    
    pub fn withTotal(total: u64) ProgressConfig {
        return .{ .total = total };
    }
    
    pub fn withWidth(self: ProgressConfig, width: usize) ProgressConfig {
        var config = self;
        config.width = width;
        return config;
    }
    
    pub fn withPrefix(self: ProgressConfig, prefix: []const u8) ProgressConfig {
        var config = self;
        config.prefix = prefix;
        return config;
    }
    
    pub fn withSuffix(self: ProgressConfig, suffix: []const u8) ProgressConfig {
        var config = self;
        config.suffix = suffix;
        return config;
    }
    
    pub fn showRate(self: ProgressConfig) ProgressConfig {
        var config = self;
        config.show_rate = true;
        return config;
    }
};

/// Spinner configuration
pub const SpinnerConfig = struct {
    style: SpinnerStyle = .lightning,
    message: []const u8 = "Processing",
    interval_ms: u64 = 100,
    show_time: bool = false,
    
    pub fn withStyle(style: SpinnerStyle) SpinnerConfig {
        return .{ .style = style };
    }
    
    pub fn withMessage(self: SpinnerConfig, message: []const u8) SpinnerConfig {
        var config = self;
        config.message = message;
        return config;
    }
    
    pub fn withInterval(self: SpinnerConfig, interval_ms: u64) SpinnerConfig {
        var config = self;
        config.interval_ms = interval_ms;
        return config;
    }
    
    pub fn showTime(self: SpinnerConfig) SpinnerConfig {
        var config = self;
        config.show_time = true;
        return config;
    }
};

/// Progress bar
pub const ProgressBar = struct {
    config: ProgressConfig,
    current: u64 = 0,
    start_time: i64,
    
    pub fn init(config: ProgressConfig) ProgressBar {
        return .{
            .config = config,
            .start_time = std.time.milliTimestamp(),
        };
    }
    
    pub fn update(self: *ProgressBar, current: u64) void {
        self.current = @min(current, self.config.total);
        self.render();
    }
    
    pub fn increment(self: *ProgressBar) void {
        self.update(self.current + 1);
    }
    
    pub fn finish(self: *ProgressBar) void {
        self.current = self.config.total;
        self.render();
        std.debug.print("\n", .{});
    }
    
    fn render(self: ProgressBar) void {
        const percentage = if (self.config.total > 0) 
            (self.current * 100) / self.config.total 
        else 0;
        
        const filled = (self.current * self.config.width) / @max(self.config.total, 1);
        
        // Clear current line and move to beginning
        std.debug.print("\r\x1b[K", .{});
        
        // Prefix
        std.debug.print("{s} ", .{self.config.prefix});
        
        // Progress bar
        std.debug.print("[", .{});
        var i: usize = 0;
        while (i < self.config.width) : (i += 1) {
            if (i < filled) {
                std.debug.print("{c}", .{self.config.fill_char});
            } else {
                std.debug.print("{c}", .{self.config.empty_char});
            }
        }
        std.debug.print("]", .{});
        
        // Percentage
        if (self.config.show_percentage) {
            std.debug.print(" {d}%", .{percentage});
        }
        
        // Count
        if (self.config.show_count) {
            std.debug.print(" ({d}/{d})", .{ self.current, self.config.total });
        }
        
        // Rate
        if (self.config.show_rate) {
            const elapsed = std.time.milliTimestamp() - self.start_time;
            if (elapsed > 0 and self.current > 0) {
                const rate = (self.current * 1000) / @as(u64, @intCast(elapsed));
                std.debug.print(" {d}/s", .{rate});
            }
        }
        
        // Suffix
        if (self.config.suffix.len > 0) {
            std.debug.print(" {s}", .{self.config.suffix});
        }
    }
};

/// Spinner
pub const Spinner = struct {
    config: SpinnerConfig,
    frame_index: usize = 0,
    start_time: i64,
    
    pub fn init(config: SpinnerConfig) Spinner {
        return .{
            .config = config,
            .start_time = std.time.milliTimestamp(),
        };
    }
    
    pub fn spin(self: *Spinner) void {
        const frames = self.config.style.getFrames();
        
        // Clear current line and move to beginning
        std.debug.print("\r\x1b[K", .{});
        
        // Show spinner frame
        std.debug.print("{s} {s}", .{ frames[self.frame_index], self.config.message });
        
        // Show elapsed time if enabled
        if (self.config.show_time) {
            const elapsed = std.time.milliTimestamp() - self.start_time;
            const seconds = elapsed / 1000;
            std.debug.print(" ({d}s)", .{seconds});
        }
        
        self.frame_index = (self.frame_index + 1) % frames.len;
    }
    
    pub fn finish(self: Spinner, success_message: ?[]const u8) void {
        // Clear current line
        std.debug.print("\r\x1b[K", .{});
        
        if (success_message) |msg| {
            std.debug.print("✅ {s}", .{msg});
            if (self.config.show_time) {
                const elapsed = std.time.milliTimestamp() - self.start_time;
                const seconds = elapsed / 1000;
                std.debug.print(" ({d}s)", .{seconds});
            }
            std.debug.print("\n", .{});
        }
    }
    
    pub fn fail(self: Spinner, error_message: []const u8) void {
        // Clear current line
        std.debug.print("\r\x1b[K", .{});
        std.debug.print("❌ {s}", .{error_message});
        if (self.config.show_time) {
            const elapsed = std.time.milliTimestamp() - self.start_time;
            const seconds = elapsed / 1000;
            std.debug.print(" ({d}s)", .{seconds});
        }
        std.debug.print("\n", .{});
    }
};

/// Progress utilities
pub const Progress = struct {
    /// Run function with spinner
    pub fn withSpinner(
        config: SpinnerConfig,
        comptime func: anytype,
        args: anytype,
        success_msg: ?[]const u8,
    ) !@TypeOf(@call(.auto, func, args)) {
        var spinner = Spinner.init(config);
        
        // Start spinner in background (simulated)
        const start_time = std.time.milliTimestamp();
        var last_spin = start_time;
        
        // Execute function while showing spinner
        const result = @call(.auto, func, args);
        
        // Show spinner frames during execution (simplified)
        const end_time = std.time.milliTimestamp();
        var current_time = start_time;
        while (current_time < end_time) {
            if (current_time - last_spin >= config.interval_ms) {
                spinner.spin();
                last_spin = current_time;
            }
            current_time += 10; // Simulate time passing
        }
        
        spinner.finish(success_msg);
        return result;
    }
    
    /// Run function with progress bar
    pub fn withProgressBar(
        config: ProgressConfig,
        comptime func: anytype,
        args: anytype,
        success_msg: ?[]const u8,
    ) !@TypeOf(@call(.auto, func, args)) {
        var progress = ProgressBar.init(config);
        
        // Simulate progress during execution
        var i: u64 = 0;
        while (i <= config.total) : (i += 1) {
            progress.update(i);
            std.time.sleep(10 * 1000 * 1000); // 10ms
        }
        
        const result = @call(.auto, func, args);
        
        progress.finish();
        if (success_msg) |msg| {
            std.debug.print("✅ {s}\n", .{msg});
        }
        
        return result;
    }
    
    /// Simple dots progress
    pub fn dots(message: []const u8, duration_ms: u64) void {
        std.debug.print("⚡ {s}", .{message});
        
        const dot_count = duration_ms / 200;
        var i: u64 = 0;
        while (i < dot_count) : (i += 1) {
            std.time.sleep(200 * 1000 * 1000); // 200ms
            std.debug.print(".", .{});
        }
        
        std.debug.print(" ✅\n", .{});
    }
};

test "progress bar basic functionality" {
    var progress = ProgressBar.init(ProgressConfig.withTotal(100).withWidth(20));
    
    progress.update(25);
    try std.testing.expectEqual(@as(u64, 25), progress.current);
    
    progress.increment();
    try std.testing.expectEqual(@as(u64, 26), progress.current);
}

test "spinner configuration" {
    const config = SpinnerConfig.withStyle(.lightning)
        .withMessage("Testing")
        .withInterval(50)
        .showTime();
    
    try std.testing.expectEqual(SpinnerStyle.lightning, config.style);
    try std.testing.expectEqualStrings("Testing", config.message);
    try std.testing.expectEqual(@as(u64, 50), config.interval_ms);
    try std.testing.expectEqual(true, config.show_time);
}