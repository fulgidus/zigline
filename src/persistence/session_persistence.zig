//! Session persistence for Zigline terminal emulator
//! Provides functionality to save and restore terminal sessions

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Terminal = @import("../core/terminal.zig").Terminal;

/// Persisted session data
pub const PersistedSession = struct {
    /// Session ID
    id: u32,
    /// Session name/title
    name: []u8,
    /// Working directory
    working_directory: []u8,
    /// Terminal buffer content (serialized)
    buffer_content: []u8,
    /// Cursor position
    cursor_x: u16,
    cursor_y: u16,
    /// Terminal dimensions
    width: u16,
    height: u16,
    /// Creation timestamp
    created_at: i64,
    /// Last accessed timestamp
    last_accessed: i64,
    /// Shell command used
    shell_command: []u8,

    /// Initialize a new persisted session
    pub fn init(allocator: Allocator, id: u32, name: []const u8, terminal: *const Terminal) !PersistedSession {
        const now = std.time.timestamp();

        // Get current working directory
        var cwd_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const cwd = try std.process.getCwd(&cwd_buffer);

        return PersistedSession{
            .id = id,
            .name = try allocator.dupe(u8, name),
            .working_directory = try allocator.dupe(u8, cwd),
            .buffer_content = try serializeTerminalBuffer(allocator, terminal),
            .cursor_x = @intCast(terminal.cursor_x),
            .cursor_y = @intCast(terminal.cursor_y),
            .width = @intCast(terminal.buffer.width),
            .height = @intCast(terminal.buffer.height),
            .created_at = now,
            .last_accessed = now,
            .shell_command = try allocator.dupe(u8, "/bin/bash"),
        };
    }

    /// Update session data from terminal
    pub fn updateFromTerminal(self: *PersistedSession, allocator: Allocator, terminal: *const Terminal) !void {
        // Free old buffer content
        allocator.free(self.buffer_content);

        // Update with new data
        self.buffer_content = try serializeTerminalBuffer(allocator, terminal);
        self.cursor_x = @intCast(terminal.cursor_x);
        self.cursor_y = @intCast(terminal.cursor_y);
        self.width = @intCast(terminal.buffer.width);
        self.height = @intCast(terminal.buffer.height);
        self.last_accessed = std.time.timestamp();

        // Update working directory
        allocator.free(self.working_directory);
        var cwd_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const cwd = try std.process.getCwd(&cwd_buffer);
        self.working_directory = try allocator.dupe(u8, cwd);
    }

    /// Convert to JSON string
    pub fn toJson(self: *const PersistedSession, allocator: Allocator) ![]u8 {
        var json = ArrayList(u8).init(allocator);
        defer json.deinit();

        try json.appendSlice("{\n");
        try json.appendSlice("  \"id\": ");
        try json.writer().print("{d}", .{self.id});
        try json.appendSlice(",\n  \"name\": \"");
        try json.appendSlice(self.name);
        try json.appendSlice("\",\n  \"working_directory\": \"");
        try json.appendSlice(self.working_directory);
        try json.appendSlice("\",\n  \"cursor_x\": ");
        try json.writer().print("{d}", .{self.cursor_x});
        try json.appendSlice(",\n  \"cursor_y\": ");
        try json.writer().print("{d}", .{self.cursor_y});
        try json.appendSlice(",\n  \"width\": ");
        try json.writer().print("{d}", .{self.width});
        try json.appendSlice(",\n  \"height\": ");
        try json.writer().print("{d}", .{self.height});
        try json.appendSlice(",\n  \"created_at\": ");
        try json.writer().print("{d}", .{self.created_at});
        try json.appendSlice(",\n  \"last_accessed\": ");
        try json.writer().print("{d}", .{self.last_accessed});
        try json.appendSlice(",\n  \"shell_command\": \"");
        try json.appendSlice(self.shell_command);
        try json.appendSlice("\",\n  \"buffer_content\": \"");

        // Encode buffer content as base64 or escaped string
        const encoded_buffer = try encodeBufferContent(allocator, self.buffer_content);
        defer allocator.free(encoded_buffer);
        try json.appendSlice(encoded_buffer);

        try json.appendSlice("\"\n}");

        return json.toOwnedSlice();
    }

    /// Cleanup allocated memory
    pub fn deinit(self: *PersistedSession, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.working_directory);
        allocator.free(self.buffer_content);
        allocator.free(self.shell_command);
    }
};

/// Session persistence manager
pub const SessionPersistence = struct {
    allocator: Allocator,
    sessions_file: []const u8,
    sessions: ArrayList(PersistedSession),
    auto_save_timer: i64,
    auto_save_interval: u32,

    /// Initialize session persistence
    pub fn init(allocator: Allocator, sessions_file: []const u8, auto_save_interval: u32) SessionPersistence {
        return SessionPersistence{
            .allocator = allocator,
            .sessions_file = sessions_file,
            .sessions = ArrayList(PersistedSession).init(allocator),
            .auto_save_timer = std.time.timestamp(),
            .auto_save_interval = auto_save_interval,
        };
    }

    /// Load sessions from file
    pub fn loadSessions(self: *SessionPersistence) !void {
        const file = std.fs.cwd().openFile(self.sessions_file, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                std.log.info("Sessions file not found: {s}, starting with empty sessions", .{self.sessions_file});
                return;
            },
            else => return err,
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024); // 10MB max
        defer self.allocator.free(content);

        try self.parseSessionsJson(content);
        std.log.info("Loaded {d} sessions from {s}", .{ self.sessions.items.len, self.sessions_file });
    }

    /// Save sessions to file
    pub fn saveSessions(self: *const SessionPersistence) !void {
        const file = try std.fs.cwd().createFile(self.sessions_file, .{});
        defer file.close();

        try file.writeAll("{\n  \"sessions\": [\n");

        for (self.sessions.items, 0..) |session, i| {
            const json = try session.toJson(self.allocator);
            defer self.allocator.free(json);

            // Indent the session JSON
            var lines = std.mem.splitScalar(u8, json, '\n');
            while (lines.next()) |line| {
                if (line.len > 0) {
                    try file.writeAll("    ");
                    try file.writeAll(line);
                    try file.writeAll("\n");
                }
            }

            if (i < self.sessions.items.len - 1) {
                try file.writeAll(",\n");
            }
        }

        try file.writeAll("  ],\n  \"saved_at\": ");
        try file.writer().print("{d}", .{std.time.timestamp()});
        try file.writeAll("\n}\n");

        std.log.info("Saved {d} sessions to {s}", .{ self.sessions.items.len, self.sessions_file });
    }

    /// Add or update a session
    pub fn persistSession(self: *SessionPersistence, id: u32, name: []const u8, terminal: *const Terminal) !void {
        // Check if session already exists
        for (self.sessions.items) |*session| {
            if (session.id == id) {
                try session.updateFromTerminal(self.allocator, terminal);
                std.log.debug("Updated persisted session {d}: {s}", .{ id, name });
                return;
            }
        }

        // Create new session
        const new_session = try PersistedSession.init(self.allocator, id, name, terminal);
        try self.sessions.append(new_session);
        std.log.debug("Created new persisted session {d}: {s}", .{ id, name });
    }

    /// Remove a session
    pub fn removeSession(self: *SessionPersistence, id: u32) void {
        for (self.sessions.items, 0..) |session, i| {
            if (session.id == id) {
                var removed_session = self.sessions.swapRemove(i);
                removed_session.deinit(self.allocator);
                std.log.debug("Removed persisted session {d}", .{id});
                return;
            }
        }
    }

    /// Get list of persisted sessions
    pub fn getPersistedSessions(self: *const SessionPersistence) []const PersistedSession {
        return self.sessions.items;
    }

    /// Check if auto-save is needed and perform it
    pub fn checkAutoSave(self: *SessionPersistence) !void {
        if (self.auto_save_interval == 0) return;

        const now = std.time.timestamp();
        if (now - self.auto_save_timer >= self.auto_save_interval) {
            try self.saveSessions();
            self.auto_save_timer = now;
        }
    }

    /// Parse sessions JSON (simplified parser)
    fn parseSessionsJson(_: *SessionPersistence, content: []const u8) !void {
        // This is a simplified JSON parser for demonstration
        // In a production system, you'd want to use a proper JSON parser

        if (std.mem.indexOf(u8, content, "\"sessions\": [")) |_| {
            // For now, just log that we found the sessions array
            std.log.info("Found sessions array in persistence file", .{});
            // TODO: Implement proper JSON parsing for session restoration
        }
    }

    /// Cleanup resources
    pub fn deinit(self: *SessionPersistence) void {
        for (self.sessions.items) |*session| {
            session.deinit(self.allocator);
        }
        self.sessions.deinit();
    }
};

/// Serialize terminal buffer to string
fn serializeTerminalBuffer(allocator: Allocator, terminal: *const Terminal) ![]u8 {
    var buffer = ArrayList(u8).init(allocator);
    defer buffer.deinit();

    // Simple serialization: store each cell as "char:fg:bg\n"
    for (0..terminal.buffer.height) |y| {
        for (0..terminal.buffer.width) |x| {
            if (terminal.buffer.getCell(@intCast(x), @intCast(y))) |cell| {
                try buffer.writer().print("{}:{}:{}:", .{ cell.char, cell.fg_color, cell.bg_color });

                // Add attributes
                if (cell.attributes.bold) try buffer.appendSlice("B");
                if (cell.attributes.italic) try buffer.appendSlice("I");
                if (cell.attributes.underline) try buffer.appendSlice("U");

                try buffer.appendSlice("\n");
            }
        }
    }

    return buffer.toOwnedSlice();
}

/// Encode buffer content for JSON storage
fn encodeBufferContent(allocator: Allocator, content: []const u8) ![]u8 {
    // Simple base64-like encoding to avoid JSON escape issues
    var encoded = ArrayList(u8).init(allocator);
    defer encoded.deinit();

    for (content) |byte| {
        if (byte == '"') {
            try encoded.appendSlice("\\\"");
        } else if (byte == '\\') {
            try encoded.appendSlice("\\\\");
        } else if (byte == '\n') {
            try encoded.appendSlice("\\n");
        } else if (byte == '\r') {
            try encoded.appendSlice("\\r");
        } else if (byte == '\t') {
            try encoded.appendSlice("\\t");
        } else if (byte >= 32 and byte <= 126) {
            try encoded.append(byte);
        } else {
            try encoded.writer().print("\\x{X:0>2}", .{byte});
        }
    }

    return encoded.toOwnedSlice();
}
