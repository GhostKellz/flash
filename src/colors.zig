//! ⚡ Flash Colored Output
//!
//! Provides beautiful terminal colors with auto-detection and NO_COLOR support

const std = @import("std");

/// Color support detection
pub const ColorSupport = enum {
    none,
    basic,      // 16 colors
    extended,   // 256 colors
    truecolor,  // 24-bit RGB
    
    pub fn detect() ColorSupport {
        // Check NO_COLOR environment variable
        if (std.process.getEnvVarOwned(std.heap.page_allocator, "NO_COLOR")) |no_color| {
            defer std.heap.page_allocator.free(no_color);
            if (no_color.len > 0) return .none;
        } else |_| {}
        
        // Check FORCE_COLOR environment variable
        if (std.process.getEnvVarOwned(std.heap.page_allocator, "FORCE_COLOR")) |force_color| {
            defer std.heap.page_allocator.free(force_color);
            if (force_color.len > 0) return .truecolor;
        } else |_| {}
        
        // Check if stdout is a TTY
        if (!std.fs.File.stdout().isTty()) {
            return .none;
        }
        
        // Check TERM environment variable
        if (std.process.getEnvVarOwned(std.heap.page_allocator, "TERM")) |term| {
            defer std.heap.page_allocator.free(term);
            
            if (std.mem.indexOf(u8, term, "truecolor") != null or 
                std.mem.indexOf(u8, term, "24bit") != null) {
                return .truecolor;
            }
            
            if (std.mem.indexOf(u8, term, "256") != null) {
                return .extended;
            }
            
            if (std.mem.eql(u8, term, "dumb")) {
                return .none;
            }
            
            return .basic;
        } else |_| {
            return .basic;
        }
    }
};

/// Basic ANSI colors
pub const Color = enum(u8) {
    black = 30,
    red = 31,
    green = 32,
    yellow = 33,
    blue = 34,
    magenta = 35,
    cyan = 36,
    white = 37,
    bright_black = 90,
    bright_red = 91,
    bright_green = 92,
    bright_yellow = 93,
    bright_blue = 94,
    bright_magenta = 95,
    bright_cyan = 96,
    bright_white = 97,
    
    pub fn toAnsi(self: Color) []const u8 {
        return switch (self) {
            .black => "\x1b[30m",
            .red => "\x1b[31m",
            .green => "\x1b[32m",
            .yellow => "\x1b[33m",
            .blue => "\x1b[34m",
            .magenta => "\x1b[35m",
            .cyan => "\x1b[36m",
            .white => "\x1b[37m",
            .bright_black => "\x1b[90m",
            .bright_red => "\x1b[91m",
            .bright_green => "\x1b[92m",
            .bright_yellow => "\x1b[93m",
            .bright_blue => "\x1b[94m",
            .bright_magenta => "\x1b[95m",
            .bright_cyan => "\x1b[96m",
            .bright_white => "\x1b[97m",
        };
    }
};

/// Text styles
pub const Style = enum {
    reset,
    bold,
    dim,
    italic,
    underline,
    strikethrough,
    
    pub fn toAnsi(self: Style) []const u8 {
        return switch (self) {
            .reset => "\x1b[0m",
            .bold => "\x1b[1m",
            .dim => "\x1b[2m",
            .italic => "\x1b[3m",
            .underline => "\x1b[4m",
            .strikethrough => "\x1b[9m",
        };
    }
};

/// RGB color for truecolor support
pub const RGB = struct {
    r: u8,
    g: u8,
    b: u8,
    
    pub fn init(r: u8, g: u8, b: u8) RGB {
        return .{ .r = r, .g = g, .b = b };
    }
    
    pub fn toAnsi(self: RGB, background: bool) []u8 {
        const prefix = if (background) "\x1b[48;2;" else "\x1b[38;2;";
        return std.fmt.allocPrint(std.heap.page_allocator, "{s}{d};{d};{d}m", .{ prefix, self.r, self.g, self.b }) catch "\x1b[0m";
    }
};

/// Color configuration
pub const ColorConfig = struct {
    support: ColorSupport,
    enabled: bool,
    
    pub fn init() ColorConfig {
        const support = ColorSupport.detect();
        return .{
            .support = support,
            .enabled = support != .none,
        };
    }
    
    pub fn disable(self: ColorConfig) ColorConfig {
        var config = self;
        config.enabled = false;
        return config;
    }
    
    pub fn enable(self: ColorConfig) ColorConfig {
        var config = self;
        config.enabled = self.support != .none;
        return config;
    }
};

/// Colored text formatter
pub const Colorizer = struct {
    config: ColorConfig,
    
    pub fn init(config: ColorConfig) Colorizer {
        return .{ .config = config };
    }
    
    /// Apply color to text
    pub fn color(self: Colorizer, text: []const u8, text_color: Color) []u8 {
        if (!self.config.enabled) {
            return std.heap.page_allocator.dupe(u8, text) catch text;
        }
        
        return std.fmt.allocPrint(std.heap.page_allocator, "{s}{s}{s}", .{ 
            text_color.toAnsi(), 
            text, 
            Style.reset.toAnsi() 
        }) catch text;
    }
    
    /// Apply style to text
    pub fn style(self: Colorizer, text: []const u8, text_style: Style) []u8 {
        if (!self.config.enabled) {
            return std.heap.page_allocator.dupe(u8, text) catch text;
        }
        
        return std.fmt.allocPrint(std.heap.page_allocator, "{s}{s}{s}", .{ 
            text_style.toAnsi(), 
            text, 
            Style.reset.toAnsi() 
        }) catch text;
    }
    
    /// Apply RGB color to text (truecolor)
    pub fn rgb(self: Colorizer, text: []const u8, color_rgb: RGB) []u8 {
        if (!self.config.enabled or self.config.support != .truecolor) {
            return std.heap.page_allocator.dupe(u8, text) catch text;
        }
        
        const color_code = color_rgb.toAnsi(false);
        defer std.heap.page_allocator.free(color_code);
        
        return std.fmt.allocPrint(std.heap.page_allocator, "{s}{s}{s}", .{ 
            color_code, 
            text, 
            Style.reset.toAnsi() 
        }) catch text;
    }
    
    /// Create styled text with multiple attributes
    pub fn styled(self: Colorizer, text: []const u8, text_color: ?Color, text_style: ?Style) []u8 {
        if (!self.config.enabled) {
            return std.heap.page_allocator.dupe(u8, text) catch text;
        }
        
        var result = std.ArrayList(u8).init(std.heap.page_allocator);
        
        if (text_color) |tc| {
            result.appendSlice(tc.toAnsi()) catch {};
        }
        
        if (text_style) |s| {
            result.appendSlice(s.toAnsi()) catch {};
        }
        
        result.appendSlice(text) catch {};
        result.appendSlice(Style.reset.toAnsi()) catch {};
        
        return result.toOwnedSlice() catch text;
    }
};

/// Pre-defined color themes for Flash
pub const FlashThemes = struct {
    /// Lightning theme colors
    pub const lightning = struct {
        pub const primary = Color.bright_yellow;
        pub const secondary = Color.cyan;
        pub const success = Color.bright_green;
        pub const warning = Color.yellow;
        pub const err = Color.bright_red;
        pub const info = Color.blue;
        pub const muted = Color.bright_black;
    };
    
    /// Electric theme colors
    pub const electric = struct {
        pub const primary = Color.bright_blue;
        pub const secondary = Color.bright_magenta;
        pub const success = Color.green;
        pub const warning = Color.bright_yellow;
        pub const err = Color.red;
        pub const info = Color.cyan;
        pub const muted = Color.white;
    };
};

/// Convenient color functions
pub const c = struct {
    var global_colorizer: ?Colorizer = null;
    
    fn getColorizer() Colorizer {
        if (global_colorizer == null) {
            global_colorizer = Colorizer.init(ColorConfig.init());
        }
        return global_colorizer.?;
    }
    
    pub fn red(text: []const u8) []u8 {
        return getColorizer().color(text, .red);
    }
    
    pub fn green(text: []const u8) []u8 {
        return getColorizer().color(text, .green);
    }
    
    pub fn yellow(text: []const u8) []u8 {
        return getColorizer().color(text, .yellow);
    }
    
    pub fn blue(text: []const u8) []u8 {
        return getColorizer().color(text, .blue);
    }
    
    pub fn cyan(text: []const u8) []u8 {
        return getColorizer().color(text, .cyan);
    }
    
    pub fn magenta(text: []const u8) []u8 {
        return getColorizer().color(text, .magenta);
    }
    
    pub fn bold(text: []const u8) []u8 {
        return getColorizer().style(text, .bold);
    }
    
    pub fn dim(text: []const u8) []u8 {
        return getColorizer().style(text, .dim);
    }
    
    pub fn success(text: []const u8) []u8 {
        return getColorizer().color(text, FlashThemes.lightning.success);
    }
    
    pub fn err(text: []const u8) []u8 {
        return getColorizer().color(text, FlashThemes.lightning.err);
    }
    
    pub fn warning(text: []const u8) []u8 {
        return getColorizer().color(text, FlashThemes.lightning.warning);
    }
    
    pub fn info(text: []const u8) []u8 {
        return getColorizer().color(text, FlashThemes.lightning.info);
    }
    
    pub fn lightning(text: []const u8) []u8 {
        return getColorizer().color(text, FlashThemes.lightning.primary);
    }
};

test "color support detection" {
    const support = ColorSupport.detect();
    // Should return some valid color support level
    try std.testing.expect(@as(u8, @intFromEnum(support)) <= @as(u8, @intFromEnum(ColorSupport.truecolor)));
}

test "color formatting" {
    const config = ColorConfig.init();
    const colorizer = Colorizer.init(config);
    
    const red_text = colorizer.color("Hello", .red);
    defer std.heap.page_allocator.free(red_text);
    
    // Should contain ANSI escape codes if colors are enabled
    if (config.enabled) {
        try std.testing.expect(std.mem.indexOf(u8, red_text, "\x1b[") != null);
    }
}

test "rgb color" {
    const rgb_color = RGB.init(255, 100, 50);
    try std.testing.expectEqual(@as(u8, 255), rgb_color.r);
    try std.testing.expectEqual(@as(u8, 100), rgb_color.g);
    try std.testing.expectEqual(@as(u8, 50), rgb_color.b);
}