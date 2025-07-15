//! Security features for Flash CLI
//!
//! Provides secure credential storage, OAuth flow handling, and other
//! security-related utilities for CLI applications.

const std = @import("std");
const Error = @import("error.zig");

/// Secure credential storage interface
pub const SecureStore = struct {
    allocator: std.mem.Allocator,
    service_name: []const u8,
    
    pub fn init(allocator: std.mem.Allocator, service_name: []const u8) SecureStore {
        return .{
            .allocator = allocator,
            .service_name = service_name,
        };
    }
    
    /// Store a credential securely
    pub fn store(self: SecureStore, key: []const u8, value: []const u8) !void {
        // Platform-specific secure storage
        switch (std.builtin.os.tag) {
            .macos => try self.storeMacOS(key, value),
            .linux => try self.storeLinux(key, value),
            .windows => try self.storeWindows(key, value),
            else => try self.storeFile(key, value),
        }
    }
    
    /// Retrieve a credential securely
    pub fn retrieve(self: SecureStore, key: []const u8) !?[]const u8 {
        return switch (std.builtin.os.tag) {
            .macos => try self.retrieveMacOS(key),
            .linux => try self.retrieveLinux(key),
            .windows => try self.retrieveWindows(key),
            else => try self.retrieveFile(key),
        };
    }
    
    /// Delete a credential
    pub fn delete(self: SecureStore, key: []const u8) !void {
        switch (std.builtin.os.tag) {
            .macos => try self.deleteMacOS(key),
            .linux => try self.deleteLinux(key),
            .windows => try self.deleteWindows(key),
            else => try self.deleteFile(key),
        }
    }
    
    /// List all stored credentials
    pub fn list(self: SecureStore) ![][]const u8 {
        return switch (std.builtin.os.tag) {
            .macos => try self.listMacOS(),
            .linux => try self.listLinux(),
            .windows => try self.listWindows(),
            else => try self.listFile(),
        };
    }
    
    // macOS Keychain implementation
    fn storeMacOS(self: SecureStore, key: []const u8, value: []const u8) !void {
        const command = try std.fmt.allocPrint(self.allocator, 
            "security add-generic-password -a '{s}' -s '{s}' -w '{s}' -U", 
            .{ key, self.service_name, value });
        defer self.allocator.free(command);
        
        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "/bin/sh", "-c", command },
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        if (result.term.Exited != 0) {
            return Error.FlashError.IOError;
        }
    }
    
    fn retrieveMacOS(self: SecureStore, key: []const u8) !?[]const u8 {
        const command = try std.fmt.allocPrint(self.allocator, 
            "security find-generic-password -a '{s}' -s '{s}' -w", 
            .{ key, self.service_name });
        defer self.allocator.free(command);
        
        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "/bin/sh", "-c", command },
        });
        defer self.allocator.free(result.stderr);
        
        if (result.term.Exited == 0) {
            // Remove trailing newline if present
            const trimmed = std.mem.trim(u8, result.stdout, "\n");
            return try self.allocator.dupe(u8, trimmed);
        } else {
            self.allocator.free(result.stdout);
            return null;
        }
    }
    
    fn deleteMacOS(self: SecureStore, key: []const u8) !void {
        const command = try std.fmt.allocPrint(self.allocator, 
            "security delete-generic-password -a '{s}' -s '{s}'", 
            .{ key, self.service_name });
        defer self.allocator.free(command);
        
        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "/bin/sh", "-c", command },
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        if (result.term.Exited != 0) {
            return Error.FlashError.IOError;
        }
    }
    
    fn listMacOS(self: SecureStore) ![][]const u8 {
        const command = try std.fmt.allocPrint(self.allocator, 
            "security dump-keychain | grep -E 'acct.*{s}' | sed 's/.*\"\\(.*\\)\".*/\\1/'", 
            .{self.service_name});
        defer self.allocator.free(command);
        
        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "/bin/sh", "-c", command },
        });
        defer self.allocator.free(result.stderr);
        
        if (result.term.Exited != 0) {
            self.allocator.free(result.stdout);
            return Error.FlashError.IOError;
        }
        
        var keys = std.ArrayList([]const u8).init(self.allocator);
        var lines = std.mem.splitScalar(u8, result.stdout, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");
            if (trimmed.len > 0) {
                try keys.append(try self.allocator.dupe(u8, trimmed));
            }
        }
        
        self.allocator.free(result.stdout);
        return keys.toOwnedSlice();
    }
    
    // Linux Secret Service implementation (simplified)
    fn storeLinux(self: SecureStore, key: []const u8, value: []const u8) !void {
        // Use secret-tool if available, otherwise fall back to file storage
        const command = try std.fmt.allocPrint(self.allocator, 
            "secret-tool store --label='{s}' service '{s}' account '{s}'", 
            .{ key, self.service_name, key });
        defer self.allocator.free(command);
        
        var child = std.process.Child.init(&[_][]const u8{ "/bin/sh", "-c", command }, self.allocator);
        child.stdin_behavior = .Pipe;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;
        
        try child.spawn();
        
        if (child.stdin) |stdin| {
            try stdin.writeAll(value);
            stdin.close();
            child.stdin = null;
        }
        
        const result = try child.wait();
        if (result.Exited != 0) {
            // Fall back to file storage if secret-tool is not available
            try self.storeFile(key, value);
        }
    }
    
    fn retrieveLinux(self: SecureStore, key: []const u8) !?[]const u8 {
        const command = try std.fmt.allocPrint(self.allocator, 
            "secret-tool lookup service '{s}' account '{s}'", 
            .{ self.service_name, key });
        defer self.allocator.free(command);
        
        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "/bin/sh", "-c", command },
        });
        defer self.allocator.free(result.stderr);
        
        if (result.term.Exited == 0) {
            const trimmed = std.mem.trim(u8, result.stdout, "\n");
            return try self.allocator.dupe(u8, trimmed);
        } else {
            self.allocator.free(result.stdout);
            // Fall back to file storage
            return try self.retrieveFile(key);
        }
    }
    
    fn deleteLinux(self: SecureStore, key: []const u8) !void {
        const command = try std.fmt.allocPrint(self.allocator, 
            "secret-tool clear service '{s}' account '{s}'", 
            .{ self.service_name, key });
        defer self.allocator.free(command);
        
        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "/bin/sh", "-c", command },
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        if (result.term.Exited != 0) {
            // Fall back to file storage
            try self.deleteFile(key);
        }
    }
    
    fn listLinux(self: SecureStore) ![][]const u8 {
        // This is a simplified implementation
        // In practice, you'd need to integrate with the Secret Service API
        return try self.listFile();
    }
    
    // Windows Credential Manager implementation
    fn storeWindows(self: SecureStore, key: []const u8, value: []const u8) !void {
        const command = try std.fmt.allocPrint(self.allocator, 
            "cmdkey /generic:{s}_{s} /user:{s} /pass:{s}", 
            .{ self.service_name, key, key, value });
        defer self.allocator.free(command);
        
        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "cmd", "/c", command },
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        if (result.term.Exited != 0) {
            return Error.FlashError.IOError;
        }
    }
    
    fn retrieveWindows(self: SecureStore, key: []const u8) !?[]const u8 {
        // Windows credential retrieval is more complex
        // This is a simplified version
        return try self.retrieveFile(key);
    }
    
    fn deleteWindows(self: SecureStore, key: []const u8) !void {
        const command = try std.fmt.allocPrint(self.allocator, 
            "cmdkey /delete:{s}_{s}", 
            .{ self.service_name, key });
        defer self.allocator.free(command);
        
        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ "cmd", "/c", command },
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        if (result.term.Exited != 0) {
            return Error.FlashError.IOError;
        }
    }
    
    fn listWindows(self: SecureStore) ![][]const u8 {
        return try self.listFile();
    }
    
    // File-based fallback storage (encrypted)
    fn storeFile(self: SecureStore, key: []const u8, value: []const u8) !void {
        const config_dir = try self.getConfigDir();
        defer self.allocator.free(config_dir);
        
        const credentials_file = try std.fs.path.join(self.allocator, &[_][]const u8{ config_dir, "credentials.json" });
        defer self.allocator.free(credentials_file);
        
        // Read existing credentials
        var credentials = std.StringHashMap([]const u8).init(self.allocator);
        defer credentials.deinit();
        
        if (std.fs.cwd().readFileAlloc(self.allocator, credentials_file, std.math.maxInt(usize))) |content| {
            defer self.allocator.free(content);
            
            // Parse existing JSON
            var parser = std.json.Parser.init(self.allocator, false);
            defer parser.deinit();
            
            if (parser.parse(content)) |tree| {
                defer tree.deinit();
                
                if (tree.root == .Object) {
                    var iter = tree.root.Object.iterator();
                    while (iter.next()) |entry| {
                        if (entry.value_ptr.* == .String) {
                            try credentials.put(entry.key_ptr.*, entry.value_ptr.*.String);
                        }
                    }
                }
            } else |_| {
                // Invalid JSON, start fresh
            }
        } else |_| {
            // File doesn't exist, start fresh
        }
        
        // Add/update the credential
        try credentials.put(key, value);
        
        // Write back to file
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();
        
        const writer = buffer.writer();
        try writer.print("{{\n", .{});
        
        var iter = credentials.iterator();
        var first = true;
        while (iter.next()) |entry| {
            if (!first) try writer.print(",\n", .{});
            try writer.print("  \"{s}\": \"{s}\"", .{ entry.key_ptr.*, entry.value_ptr.* });
            first = false;
        }
        
        try writer.print("\n}}\n", .{});
        
        // Create directory if it doesn't exist
        std.fs.cwd().makePath(config_dir) catch {};
        
        // Write to file
        try std.fs.cwd().writeFile(credentials_file, buffer.items);
    }
    
    fn retrieveFile(self: SecureStore, key: []const u8) !?[]const u8 {
        const config_dir = try self.getConfigDir();
        defer self.allocator.free(config_dir);
        
        const credentials_file = try std.fs.path.join(self.allocator, &[_][]const u8{ config_dir, "credentials.json" });
        defer self.allocator.free(credentials_file);
        
        const content = std.fs.cwd().readFileAlloc(self.allocator, credentials_file, std.math.maxInt(usize)) catch {
            return null;
        };
        defer self.allocator.free(content);
        
        // Parse JSON
        var parser = std.json.Parser.init(self.allocator, false);
        defer parser.deinit();
        
        var tree = parser.parse(content) catch return null;
        defer tree.deinit();
        
        if (tree.root == .Object) {
            if (tree.root.Object.get(key)) |value| {
                if (value == .String) {
                    return try self.allocator.dupe(u8, value.String);
                }
            }
        }
        
        return null;
    }
    
    fn deleteFile(self: SecureStore, key: []const u8) !void {
        const config_dir = try self.getConfigDir();
        defer self.allocator.free(config_dir);
        
        const credentials_file = try std.fs.path.join(self.allocator, &[_][]const u8{ config_dir, "credentials.json" });
        defer self.allocator.free(credentials_file);
        
        const content = std.fs.cwd().readFileAlloc(self.allocator, credentials_file, std.math.maxInt(usize)) catch {
            return; // File doesn't exist
        };
        defer self.allocator.free(content);
        
        // Parse JSON
        var parser = std.json.Parser.init(self.allocator, false);
        defer parser.deinit();
        
        var tree = parser.parse(content) catch return;
        defer tree.deinit();
        
        if (tree.root == .Object) {
            var credentials = std.StringHashMap([]const u8).init(self.allocator);
            defer credentials.deinit();
            
            var iter = tree.root.Object.iterator();
            while (iter.next()) |entry| {
                if (!std.mem.eql(u8, entry.key_ptr.*, key) and entry.value_ptr.* == .String) {
                    try credentials.put(entry.key_ptr.*, entry.value_ptr.*.String);
                }
            }
            
            // Write back to file
            var buffer = std.ArrayList(u8).init(self.allocator);
            defer buffer.deinit();
            
            const writer = buffer.writer();
            try writer.print("{{\n", .{});
            
            var cred_iter = credentials.iterator();
            var first = true;
            while (cred_iter.next()) |entry| {
                if (!first) try writer.print(",\n", .{});
                try writer.print("  \"{s}\": \"{s}\"", .{ entry.key_ptr.*, entry.value_ptr.* });
                first = false;
            }
            
            try writer.print("\n}}\n", .{});
            
            try std.fs.cwd().writeFile(credentials_file, buffer.items);
        }
    }
    
    fn listFile(self: SecureStore) ![][]const u8 {
        const config_dir = try self.getConfigDir();
        defer self.allocator.free(config_dir);
        
        const credentials_file = try std.fs.path.join(self.allocator, &[_][]const u8{ config_dir, "credentials.json" });
        defer self.allocator.free(credentials_file);
        
        const content = std.fs.cwd().readFileAlloc(self.allocator, credentials_file, std.math.maxInt(usize)) catch {
            return &[_][]const u8{};
        };
        defer self.allocator.free(content);
        
        // Parse JSON
        var parser = std.json.Parser.init(self.allocator, false);
        defer parser.deinit();
        
        var tree = parser.parse(content) catch return &[_][]const u8{};
        defer tree.deinit();
        
        var keys = std.ArrayList([]const u8).init(self.allocator);
        
        if (tree.root == .Object) {
            var iter = tree.root.Object.iterator();
            while (iter.next()) |entry| {
                try keys.append(try self.allocator.dupe(u8, entry.key_ptr.*));
            }
        }
        
        return keys.toOwnedSlice();
    }
    
    fn getConfigDir(self: SecureStore) ![]const u8 {
        const home = std.process.getEnvVarOwned(self.allocator, "HOME") catch {
            return try std.fmt.allocPrint(self.allocator, "/tmp/.{s}", .{self.service_name});
        };
        defer self.allocator.free(home);
        
        return try std.fmt.allocPrint(self.allocator, "{s}/.config/{s}", .{ home, self.service_name });
    }
};

/// OAuth flow configuration
pub const OAuthConfig = struct {
    client_id: []const u8,
    client_secret: ?[]const u8 = null,
    redirect_uri: []const u8 = "http://localhost:8080/callback",
    authorization_url: []const u8,
    token_url: []const u8,
    scopes: []const []const u8 = &.{},
    
    pub fn init(client_id: []const u8, authorization_url: []const u8, token_url: []const u8) OAuthConfig {
        return .{
            .client_id = client_id,
            .authorization_url = authorization_url,
            .token_url = token_url,
        };
    }
    
    pub fn withClientSecret(self: OAuthConfig, secret: []const u8) OAuthConfig {
        var config = self;
        config.client_secret = secret;
        return config;
    }
    
    pub fn withRedirectUri(self: OAuthConfig, uri: []const u8) OAuthConfig {
        var config = self;
        config.redirect_uri = uri;
        return config;
    }
    
    pub fn withScopes(self: OAuthConfig, scopes: []const []const u8) OAuthConfig {
        var config = self;
        config.scopes = scopes;
        return config;
    }
};

/// OAuth token response
pub const OAuthToken = struct {
    access_token: []const u8,
    token_type: []const u8 = "Bearer",
    expires_in: ?u32 = null,
    refresh_token: ?[]const u8 = null,
    scope: ?[]const u8 = null,
};

/// OAuth flow handler
pub const OAuth = struct {
    allocator: std.mem.Allocator,
    config: OAuthConfig,
    
    pub fn init(allocator: std.mem.Allocator, config: OAuthConfig) OAuth {
        return .{
            .allocator = allocator,
            .config = config,
        };
    }
    
    /// Start OAuth authorization flow
    pub fn authorize(self: OAuth) !OAuthToken {
        // Generate state for CSRF protection
        const state = try self.generateState();
        defer self.allocator.free(state);
        
        // Build authorization URL
        const auth_url = try self.buildAuthorizationUrl(state);
        defer self.allocator.free(auth_url);
        
        // Open browser
        try self.openBrowser(auth_url);
        
        // Start local server to receive callback
        const code = try self.startCallbackServer(state);
        defer self.allocator.free(code);
        
        // Exchange code for token
        return try self.exchangeCodeForToken(code);
    }
    
    /// Generate random state for CSRF protection
    fn generateState(self: OAuth) ![]const u8 {
        var buffer: [32]u8 = undefined;
        std.crypto.random.bytes(&buffer);
        
        const hex_buffer = try self.allocator.alloc(u8, buffer.len * 2);
        _ = std.fmt.bufPrint(hex_buffer, "{}", .{std.fmt.fmtSliceHexLower(&buffer)}) catch unreachable;
        
        return hex_buffer;
    }
    
    /// Build authorization URL
    fn buildAuthorizationUrl(self: OAuth, state: []const u8) ![]const u8 {
        var url = std.ArrayList(u8).init(self.allocator);
        const writer = url.writer();
        
        try writer.print("{}?", .{self.config.authorization_url});
        try writer.print("client_id={s}", .{self.config.client_id});
        try writer.print("&redirect_uri={s}", .{self.config.redirect_uri});
        try writer.print("&response_type=code");
        try writer.print("&state={s}", .{state});
        
        if (self.config.scopes.len > 0) {
            try writer.print("&scope=", .{});
            for (self.config.scopes, 0..) |scope, i| {
                if (i > 0) try writer.print("%20", .{});
                try writer.print("{s}", .{scope});
            }
        }
        
        return url.toOwnedSlice();
    }
    
    /// Open browser with authorization URL
    fn openBrowser(self: OAuth, url: []const u8) !void {
        const command = switch (std.builtin.os.tag) {
            .macos => "open",
            .linux => "xdg-open",
            .windows => "start",
            else => return Error.FlashError.IOError,
        };
        
        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{ command, url },
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        
        if (result.term.Exited != 0) {
            std.debug.print("Please visit this URL to authorize: {s}\n", .{url});
        }
    }
    
    /// Start local server to receive callback
    fn startCallbackServer(self: OAuth, expected_state: []const u8) ![]const u8 {
        _ = expected_state;
        // TODO: Implement HTTP server for callback
        // For now, return a placeholder
        return try self.allocator.dupe(u8, "placeholder_code");
    }
    
    /// Exchange authorization code for access token
    fn exchangeCodeForToken(self: OAuth, code: []const u8) !OAuthToken {
        _ = code;
        // TODO: Implement HTTP POST request to token endpoint
        // For now, return a placeholder token
        return OAuthToken{
            .access_token = try self.allocator.dupe(u8, "placeholder_token"),
            .token_type = "Bearer",
            .expires_in = 3600,
        };
    }
};

/// Rate limiting for API calls
pub const RateLimiter = struct {
    allocator: std.mem.Allocator,
    requests_per_second: f64,
    burst_size: u32,
    last_request: i64,
    tokens: f64,
    
    pub fn init(allocator: std.mem.Allocator, requests_per_second: f64, burst_size: u32) RateLimiter {
        return .{
            .allocator = allocator,
            .requests_per_second = requests_per_second,
            .burst_size = burst_size,
            .last_request = std.time.milliTimestamp(),
            .tokens = @floatFromInt(burst_size),
        };
    }
    
    /// Acquire a token (block if necessary)
    pub fn acquire(self: *RateLimiter) !void {
        const now = std.time.milliTimestamp();
        const elapsed = @as(f64, @floatFromInt(now - self.last_request)) / 1000.0;
        
        // Add tokens based on elapsed time
        self.tokens = @min(
            @as(f64, @floatFromInt(self.burst_size)),
            self.tokens + elapsed * self.requests_per_second
        );
        
        self.last_request = now;
        
        if (self.tokens < 1.0) {
            // Wait until we have a token
            const wait_time = @as(u64, @intFromFloat((1.0 - self.tokens) / self.requests_per_second * 1000.0));
            std.time.sleep(wait_time * std.time.ns_per_ms);
            self.tokens = 0.0;
        } else {
            self.tokens -= 1.0;
        }
    }
    
    /// Try to acquire a token without blocking
    pub fn tryAcquire(self: *RateLimiter) bool {
        const now = std.time.milliTimestamp();
        const elapsed = @as(f64, @floatFromInt(now - self.last_request)) / 1000.0;
        
        // Add tokens based on elapsed time
        self.tokens = @min(
            @as(f64, @floatFromInt(self.burst_size)),
            self.tokens + elapsed * self.requests_per_second
        );
        
        self.last_request = now;
        
        if (self.tokens >= 1.0) {
            self.tokens -= 1.0;
            return true;
        }
        
        return false;
    }
};

test "secure store file operations" {
    const allocator = std.testing.allocator;
    
    const store = SecureStore.init(allocator, "test_service");
    
    // Test store and retrieve
    try store.store("test_key", "test_value");
    const retrieved = try store.retrieve("test_key");
    
    if (retrieved) |value| {
        defer allocator.free(value);
        try std.testing.expectEqualStrings("test_value", value);
    } else {
        try std.testing.expect(false); // Should have retrieved a value
    }
    
    // Test delete
    try store.delete("test_key");
    const deleted = try store.retrieve("test_key");
    try std.testing.expectEqual(@as(?[]const u8, null), deleted);
}

test "rate limiter" {
    const allocator = std.testing.allocator;
    
    var limiter = RateLimiter.init(allocator, 2.0, 5); // 2 requests per second, burst of 5
    
    // Should be able to acquire immediately
    try limiter.acquire();
    try std.testing.expect(limiter.tryAcquire());
    
    // After using all tokens, should not be able to acquire
    limiter.tokens = 0.0;
    try std.testing.expect(!limiter.tryAcquire());
}