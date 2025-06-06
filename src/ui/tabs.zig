//! Tab Management System for Zigline Terminal Emulator
//!
//! This module handles multiple terminal sessions, allowing users to:
//! - Create new tabs with individual PTYs and buffers
//! - Switch between tabs using hotkeys (Ctrl+1, Ctrl+2, etc.)
//! - Close tabs individually while keeping others alive
//! - Display tab headers in the UI
//!
//! Phase 6: Advanced Features - Tabbed Sessions

const std = @import("std");
const dvui = @import("dvui");
const Terminal = @import("../core/terminal.zig").Terminal;
const PTY = @import("../core/pty.zig").PTY;

/// Maximum number of tabs supported
pub const MAX_TABS = 10;

/// Individual tab data structure
pub const Tab = struct {
    /// Unique tab identifier
    id: u32,

    /// Tab display name
    name: [64]u8,

    /// Terminal instance for this tab
    terminal: Terminal,

    /// PTY instance for this tab
    pty: PTY,

    /// Whether this tab is currently active
    is_active: bool,

    /// Last activity timestamp for sorting
    last_activity: i64,

    /// Tab creation timestamp
    created_at: i64,

    /// Initialize a new tab
    pub fn init(allocator: std.mem.Allocator, tab_id: u32, name: []const u8) !Tab {
        var tab = Tab{
            .id = tab_id,
            .name = [_]u8{0} ** 64,
            .terminal = undefined,
            .pty = undefined,
            .is_active = false,
            .last_activity = std.time.timestamp(),
            .created_at = std.time.timestamp(),
        };

        // Copy name with bounds checking
        const name_len = @min(name.len, tab.name.len - 1);
        @memcpy(tab.name[0..name_len], name[0..name_len]);
        tab.name[name_len] = 0;

        // Initialize terminal with default size
        tab.terminal = try Terminal.init(allocator, 80, 24);

        // Initialize PTY for this tab
        tab.pty = try PTY.init();

        std.log.info("Created new tab '{}' with ID {}", .{ name, tab_id });

        return tab;
    }

    /// Clean up tab resources
    pub fn deinit(self: *Tab) void {
        std.log.info("Cleaning up tab '{}' with ID {}", .{ self.name, self.id });
        self.pty.deinit();
        self.terminal.deinit();
    }

    /// Update tab activity timestamp
    pub fn updateActivity(self: *Tab) void {
        self.last_activity = std.time.timestamp();
    }

    /// Get tab name as string
    pub fn getName(self: *const Tab) []const u8 {
        return std.mem.sliceTo(&self.name, 0);
    }
};

/// Tab Manager - handles multiple terminal sessions
pub const TabManager = struct {
    /// Memory allocator
    allocator: std.mem.Allocator,

    /// Array of active tabs
    tabs: [MAX_TABS]?Tab,

    /// Currently active tab index
    active_tab_index: ?usize,

    /// Next tab ID to assign
    next_tab_id: u32,

    /// Number of active tabs
    tab_count: u32,

    /// Initialize tab manager
    pub fn init(allocator: std.mem.Allocator) TabManager {
        return TabManager{
            .allocator = allocator,
            .tabs = [_]?Tab{null} ** MAX_TABS,
            .active_tab_index = null,
            .next_tab_id = 1,
            .tab_count = 0,
        };
    }

    /// Clean up all tabs
    pub fn deinit(self: *TabManager) void {
        for (&self.tabs) |*maybe_tab| {
            if (maybe_tab.*) |*tab| {
                tab.deinit();
                maybe_tab.* = null;
            }
        }
        std.log.info("Tab manager cleanup complete");
    }

    /// Create a new tab
    pub fn createTab(self: *TabManager, name: []const u8) !u32 {
        if (self.tab_count >= MAX_TABS) {
            return error.TooManyTabs;
        }

        // Find first available slot
        for (&self.tabs, 0..) |*maybe_tab, index| {
            if (maybe_tab.* == null) {
                const tab_id = self.next_tab_id;
                self.next_tab_id += 1;

                maybe_tab.* = try Tab.init(self.allocator, tab_id, name);
                self.tab_count += 1;

                // If this is the first tab, make it active
                if (self.active_tab_index == null) {
                    self.active_tab_index = index;
                    maybe_tab.*.?.is_active = true;
                }

                std.log.info("Created tab '{}' in slot {} (total: {})", .{ name, index, self.tab_count });
                return tab_id;
            }
        }

        return error.NoAvailableSlots;
    }

    /// Switch to a specific tab by index (0-9)
    pub fn switchToTab(self: *TabManager, tab_index: usize) bool {
        if (tab_index >= MAX_TABS) return false;
        if (self.tabs[tab_index] == null) return false;

        // Deactivate current tab
        if (self.active_tab_index) |current_index| {
            if (self.tabs[current_index]) |*current_tab| {
                current_tab.is_active = false;
            }
        }

        // Activate new tab
        self.active_tab_index = tab_index;
        if (self.tabs[tab_index]) |*new_tab| {
            new_tab.is_active = true;
            new_tab.updateActivity();
            std.log.info("Switched to tab '{}' (index {})", .{ new_tab.getName(), tab_index });
            return true;
        }

        return false;
    }

    /// Close a specific tab
    pub fn closeTab(self: *TabManager, tab_index: usize) bool {
        if (tab_index >= MAX_TABS) return false;
        if (self.tabs[tab_index] == null) return false;

        // Clean up the tab
        if (self.tabs[tab_index]) |*tab| {
            const tab_name = tab.getName();
            std.log.info("Closing tab '{}' (index {})", .{ tab_name, tab_index });
            tab.deinit();
        }

        self.tabs[tab_index] = null;
        self.tab_count -= 1;

        // If we closed the active tab, switch to another one
        if (self.active_tab_index == tab_index) {
            self.active_tab_index = null;

            // Find the next available tab
            for (&self.tabs, 0..) |*maybe_tab, index| {
                if (maybe_tab.* != null) {
                    self.switchToTab(index);
                    break;
                }
            }
        }

        return true;
    }

    /// Get currently active tab
    pub fn getActiveTab(self: *TabManager) ?*Tab {
        if (self.active_tab_index) |index| {
            if (self.tabs[index]) |*tab| {
                return tab;
            }
        }
        return null;
    }

    /// Get tab by index
    pub fn getTab(self: *TabManager, index: usize) ?*Tab {
        if (index >= MAX_TABS) return null;
        if (self.tabs[index]) |*tab| {
            return tab;
        }
        return null;
    }

    /// Render tab headers in DVUI
    pub fn renderTabHeaders(self: *TabManager) !void {
        var tab_bar = try dvui.box(@src(), .horizontal, .{
            .expand = .horizontal,
            .min_size_content = .{ .w = 0, .h = 32 },
            .background = true,
            .color_fill = .{ .color = dvui.Color{ .r = 40, .g = 40, .b = 40 } }, // Dark gray tab bar
            .margin = .{ .x = 0, .y = 0, .w = 0, .h = 2 },
            .id_extra = 20000, // Unique ID for tab bar
        });
        defer tab_bar.deinit();

        // Render individual tab buttons
        for (&self.tabs, 0..) |*maybe_tab, index| {
            if (maybe_tab.*) |_| {
                const is_active = self.active_tab_index == index;
                // const tab_name = tab.getName();

                // Tab button with different colors for active/inactive
                var tab_button = try dvui.box(@src(), .horizontal, .{
                    .min_size_content = .{ .w = 120, .h = 28 },
                    .background = true,
                    .color_fill = .{
                        .color = if (is_active)
                            dvui.Color{ .r = 80, .g = 120, .b = 160 } // Blue for active
                        else
                            dvui.Color{ .r = 60, .g = 60, .b = 60 }, // Gray for inactive
                    },
                    .margin = .{ .x = 2, .y = 2, .w = 2, .h = 2 },
                    .id_extra = @as(u32, @intCast(20001 + index)), // Unique ID per tab
                });
                defer tab_button.deinit();

                // Tab close button (small red X)
                var close_button = try dvui.box(@src(), .horizontal, .{
                    .min_size_content = .{ .w = 16, .h = 16 },
                    .background = true,
                    .color_fill = .{ .color = dvui.Color{ .r = 180, .g = 60, .b = 60 } }, // Red close button
                    .margin = .{ .x = 2, .y = 2, .w = 2, .h = 2 },
                    .id_extra = @as(u32, @intCast(20011 + index)), // Unique ID per close button
                });
                defer close_button.deinit();
            }
        }

        // New tab button (+)
        if (self.tab_count < MAX_TABS) {
            var new_tab_button = try dvui.box(@src(), .horizontal, .{
                .min_size_content = .{ .w = 32, .h = 28 },
                .background = true,
                .color_fill = .{ .color = dvui.Color{ .r = 80, .g = 140, .b = 80 } }, // Green for new tab
                .margin = .{ .x = 2, .y = 2, .w = 2, .h = 2 },
                .id_extra = 20021, // Unique ID for new tab button
            });
            defer new_tab_button.deinit();
        }
    }

    /// Handle keyboard shortcuts for tab management
    pub fn handleTabShortcuts(self: *TabManager, key: u32, modifiers: u32) bool {
        // Ctrl+1 through Ctrl+9 to switch tabs
        if ((modifiers & 0x40) != 0) { // Ctrl modifier
            if (key >= '1' and key <= '9') {
                const tab_index = key - '1';
                return self.switchToTab(tab_index);
            }

            // Ctrl+T to create new tab
            if (key == 't' or key == 'T') {
                const tab_name = std.fmt.allocPrint(self.allocator, "Tab {}", .{self.tab_count + 1}) catch "New Tab";
                defer self.allocator.free(tab_name);
                _ = self.createTab(tab_name) catch false;
                return true;
            }

            // Ctrl+W to close current tab
            if (key == 'w' or key == 'W') {
                if (self.active_tab_index) |index| {
                    return self.closeTab(index);
                }
            }
        }

        return false;
    }
};
