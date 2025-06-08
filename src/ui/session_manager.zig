//! Session Manager for handling multiple terminal sessions
//! Provides tab-based session management with PTY and buffer isolation

const std = @import("std");
const Terminal = @import("../core/terminal.zig").Terminal;
const PTY = @import("../core/pty.zig").PTY;
const Config = @import("../config/config.zig").Config;
const SessionPersistence = @import("../persistence/session_persistence.zig").SessionPersistence;

/// Individual terminal session
pub const Session = struct {
    id: u32,
    name: []const u8,
    terminal: *Terminal,
    pty: *PTY,
    is_active: bool = false,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, id: u32, name: []const u8, cols: u32, rows: u32) !Self {
        // Allocate and copy the name
        const owned_name = try allocator.dupe(u8, name);
        errdefer allocator.free(owned_name);

        // Create terminal for this session
        const terminal = try allocator.create(Terminal);
        errdefer allocator.destroy(terminal);
        terminal.* = try Terminal.init(allocator, @intCast(cols), @intCast(rows));
        errdefer terminal.deinit();

        // Create PTY for this session
        const pty = try allocator.create(PTY);
        errdefer allocator.destroy(pty);
        pty.* = try PTY.init(allocator);
        errdefer pty.deinit();

        return Self{
            .id = id,
            .name = owned_name,
            .terminal = terminal,
            .pty = pty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.pty.deinit();
        self.allocator.destroy(self.pty);
        self.terminal.deinit();
        self.allocator.destroy(self.terminal);
        self.allocator.free(self.name);
    }

    pub fn resize(self: *Self, cols: u32, rows: u32) !void {
        try self.terminal.resize(@intCast(cols), @intCast(rows));
        self.pty.resize(@intCast(cols), @intCast(rows));
    }

    pub fn isAlive(self: *Self) bool {
        return self.pty.isChildAlive();
    }
};

/// Session Manager handles multiple terminal sessions
pub const SessionManager = struct {
    allocator: std.mem.Allocator,
    sessions: std.ArrayList(Session),
    active_session_id: ?u32 = null,
    next_session_id: u32 = 1,
    config: *const Config,
    persistence: ?SessionPersistence = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: *const Config) Self {
        var manager = Self{
            .allocator = allocator,
            .sessions = std.ArrayList(Session).init(allocator),
            .config = config,
        };

        // Initialize persistence if enabled
        if (config.persistence.enabled) {
            manager.persistence = SessionPersistence.init(
                allocator,
                config.persistence.sessions_file,
                config.persistence.auto_save_interval,
            );
        }

        return manager;
    }

    pub fn deinit(self: *Self) void {
        // Save sessions before cleanup if persistence is enabled
        if (self.persistence) |*persistence| {
            self.saveSessions() catch |err| {
                std.log.warn("Failed to save sessions on shutdown: {}", .{err});
            };
            persistence.deinit();
        }

        // Clean up all sessions
        for (self.sessions.items) |*session| {
            session.deinit();
        }
        self.sessions.deinit();
    }

    /// Load persisted sessions if enabled
    pub fn loadPersistedSessions(self: *Self, default_cols: u32, default_rows: u32) !void {
        if (self.persistence) |*persistence| {
            try persistence.loadSessions();
            
            if (self.config.persistence.restore_on_startup) {
                const persisted_sessions = persistence.getPersistedSessions();
                
                for (persisted_sessions) |persisted| {
                    std.log.info("Restoring session {d}: {s}", .{ persisted.id, persisted.name });
                    
                    // Create session with persisted dimensions or defaults
                    const cols = if (persisted.width > 0) persisted.width else @as(u16, @intCast(default_cols));
                    const rows = if (persisted.height > 0) persisted.height else @as(u16, @intCast(default_rows));
                    
                    const session_id = try self.createSession(persisted.name, cols, rows);
                    
                    // TODO: Restore terminal buffer content
                    // This would require implementing buffer restoration in Terminal
                    std.log.debug("Session {d} restored (buffer restoration not yet implemented)", .{session_id});
                }
                
                std.log.info("Restored {d} sessions from persistence", .{persisted_sessions.len});
            }
        }
    }

    /// Save current sessions to persistence
    pub fn saveSessions(self: *Self) !void {
        if (self.persistence) |*persistence| {
            // Clear existing persisted sessions
            persistence.sessions.clearAndFree();
            
            // Persist all current sessions
            for (self.sessions.items) |*session| {
                try persistence.persistSession(session.id, session.name, session.terminal);
            }
            
            try persistence.saveSessions();
        }
    }

    /// Check for auto-save and perform if needed
    pub fn checkAutoSave(self: *Self) !void {
        if (self.persistence) |*persistence| {
            try persistence.checkAutoSave();
        }
    }

    /// Create a new session with a given name
    pub fn createSession(self: *Self, name: []const u8, cols: u32, rows: u32) !u32 {
        const session_id = self.next_session_id;
        self.next_session_id += 1;

        var session = try Session.init(self.allocator, session_id, name, cols, rows);
        try self.sessions.append(session);

        // If this is the first session, make it active
        if (self.active_session_id == null) {
            self.active_session_id = session_id;
            session.is_active = true;
        }

        std.log.info("Created session {d}: '{s}'", .{ session_id, name });
        return session_id;
    }

    /// Switch to a specific session by ID
    pub fn switchToSession(self: *Self, session_id: u32) bool {
        // Deactivate current session
        if (self.getActiveSession()) |current| {
            current.is_active = false;
        }

        // Find and activate the target session
        for (self.sessions.items) |*session| {
            if (session.id == session_id) {
                session.is_active = true;
                self.active_session_id = session_id;
                std.log.info("Switched to session {d}: '{s}'", .{ session_id, session.name });
                return true;
            }
        }

        // Session not found, revert to previous active session
        if (self.getActiveSession()) |current| {
            current.is_active = true;
        }
        return false;
    }

    /// Switch to next session (tab cycling)
    pub fn switchToNextSession(self: *Self) void {
        if (self.sessions.items.len <= 1) return;

        const current_index = self.getActiveSessionIndex() orelse return;
        const next_index = (current_index + 1) % self.sessions.items.len;
        const next_session_id = self.sessions.items[next_index].id;
        _ = self.switchToSession(next_session_id);
    }

    /// Switch to previous session (reverse tab cycling)
    pub fn switchToPrevSession(self: *Self) void {
        if (self.sessions.items.len <= 1) return;

        const current_index = self.getActiveSessionIndex() orelse return;
        const prev_index = if (current_index == 0) self.sessions.items.len - 1 else current_index - 1;
        const prev_session_id = self.sessions.items[prev_index].id;
        _ = self.switchToSession(prev_session_id);
    }

    /// Close a specific session
    pub fn closeSession(self: *Self, session_id: u32) bool {
        for (self.sessions.items, 0..) |*session, index| {
            if (session.id == session_id) {
                // If closing the active session, switch to another
                if (self.active_session_id == session_id) {
                    if (self.sessions.items.len > 1) {
                        // Switch to next session, or previous if this is the last
                        const next_index = if (index < self.sessions.items.len - 1) index + 1 else index - 1;
                        _ = self.switchToSession(self.sessions.items[next_index].id);
                    } else {
                        self.active_session_id = null;
                    }
                }

                std.log.info("Closing session {d}: '{s}'", .{ session_id, session.name });
                session.deinit();
                _ = self.sessions.orderedRemove(index);
                return true;
            }
        }
        return false;
    }

    /// Get currently active session
    pub fn getActiveSession(self: *Self) ?*Session {
        const session_id = self.active_session_id orelse return null;
        for (self.sessions.items) |*session| {
            if (session.id == session_id) {
                return session;
            }
        }
        return null;
    }

    /// Get active session index for cycling
    fn getActiveSessionIndex(self: *Self) ?usize {
        const session_id = self.active_session_id orelse return null;
        for (self.sessions.items, 0..) |session, index| {
            if (session.id == session_id) {
                return index;
            }
        }
        return null;
    }

    /// Get all sessions for UI rendering
    pub fn getAllSessions(self: *Self) []Session {
        return self.sessions.items;
    }

    /// Get session count
    pub fn getSessionCount(self: *Self) usize {
        return self.sessions.items.len;
    }

    /// Resize all sessions to new dimensions
    pub fn resizeAllSessions(self: *Self, cols: u32, rows: u32) !void {
        for (self.sessions.items) |*session| {
            try session.resize(cols, rows);
        }
    }

    /// Remove dead sessions automatically
    pub fn cleanupDeadSessions(self: *Self) void {
        var i: usize = 0;
        while (i < self.sessions.items.len) {
            if (!self.sessions.items[i].isAlive()) {
                const dead_session_id = self.sessions.items[i].id;
                std.log.warn("Session {d} process died, removing", .{dead_session_id});
                _ = self.closeSession(dead_session_id);
            } else {
                i += 1;
            }
        }
    }
};
