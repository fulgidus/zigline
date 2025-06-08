//! Simple Raylib-based GUI for Zigline terminal emulator
//! This replaces the complex DVUI implementation with a simple, working solution

const std = @import("std");
const rl = @import("raylib");
const Terminal = @import("../core/terminal.zig").Terminal;
const PTY = @import("../core/pty.zig").PTY;
const SessionManager = @import("session_manager.zig").SessionManager;
const Session = @import("session_manager.zig").Session;
const Config = @import("../config/config.zig").Config;
const ConfigManager = @import("../config/config.zig").ConfigManager;
const EmbeddedAssets = @import("../embedded_assets.zig");

fn getFontCodepoints() []i32 {
    const static = struct {
        var codepoints: [96]i32 = undefined;
        var initialized = false;
    };

    if (!static.initialized) {
        // ASCII 32-126
        var idx: usize = 0;
        while (idx < 95) : (idx += 1) {
            static.codepoints[idx] = @as(i32, @intCast(32 + idx));
        }
        static.codepoints[95] = 0x00D7; // × (Multiplication Sign U+00D7)
        static.initialized = true;
    }

    return &static.codepoints;
}

pub const RaylibGui = struct {
    allocator: std.mem.Allocator,
    session_manager: SessionManager,
    config_manager: *ConfigManager, // Changed from ConfigManager to *ConfigManager

    // Window settings
    width: i32,
    height: i32,

    // Font settings
    font_size: i32 = 16,
    char_width: f32 = 10.0, // Default char width
    char_height: f32 = 16.0,
    custom_font: ?rl.Font = null,

    // Terminal display settings (dynamically calculated)
    cols: u32 = 120,
    rows: u32 = 40,
    margin_x: f32 = 10.0,
    margin_y: f32 = 10.0,
    status_bar_height: f32 = 25.0,
    tab_bar_height: f32 = 30.0,

    // State
    should_exit: bool = false,
    frame_count: u64 = 0,
    last_window_width: i32 = 0,
    last_window_height: i32 = 0,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config_manager: *ConfigManager) Self { // Changed config_manager param to *ConfigManager
        const config = config_manager.getConfig();
        return Self{
            .allocator = allocator,
            .session_manager = SessionManager.init(allocator, config),
            .config_manager = config_manager, // Assign pointer
            .width = @intCast(config.window.width),
            .height = @intCast(config.window.height),
            .font_size = @intCast(config.font.size),
        };
    }

    pub fn deinit(self: *Self) void {
        self.session_manager.deinit();
        // self.config_manager.deinit(); // Removed: RaylibGui does not own ConfigManager
    }

    pub fn run(self: *Self) !void {
        // Initialize Raylib window
        rl.initWindow(self.width, self.height, "Zigline Terminal");
        defer rl.closeWindow();

        // Enable window resizing
        rl.setWindowState(rl.ConfigFlags{ .window_resizable = true });

        // Set minimum window size to ensure usability
        rl.setWindowMinSize(400, 300);

        rl.setTargetFPS(60);

        // Load FiraCode font
        self.loadCustomFont();
        defer if (self.custom_font) |font| {
            rl.unloadFont(font);
        };

        std.log.info("Raylib window initialized successfully with resizing enabled", .{});

        // Calculate initial terminal dimensions
        try self.updateTerminalDimensions();
        std.log.info("Initial terminal dimensions: {d}x{d}", .{ self.cols, self.rows });

        // Load persisted sessions if enabled
        try self.session_manager.loadPersistedSessions(self.cols, self.rows);

        // Create initial session if no sessions were restored
        if (self.session_manager.getSessionCount() == 0) {
            _ = try self.session_manager.createSession("Terminal 1", self.cols, self.rows);
        }

        // Main loop
        while (!rl.windowShouldClose() and !self.should_exit) {
            self.frame_count += 1;

            // Check for window resize and update terminal dimensions
            try self.updateTerminalDimensions();

            // Handle input
            try self.handleInput();

            // Read PTY output for active session
            try self.readPtyOutput();

            // Update window title if needed (every 60 frames to reduce overhead)
            if (self.frame_count % 60 == 0) {
                self.updateWindowTitle();
            }

            // Check for auto-save
            try self.session_manager.checkAutoSave();

            // Clean up dead sessions
            self.session_manager.cleanupDeadSessions();

            // Check if we have any sessions left
            if (self.session_manager.getSessionCount() == 0) {
                std.log.warn("No sessions remaining, exiting", .{});
                self.should_exit = true;
            }

            // Render
            self.render();
        }

        std.log.info("Raylib GUI exiting gracefully", .{});
    }

    fn loadCustomFont(self: *Self) void {
        const config = self.config_manager.getConfig();

        std.log.info("Loading font with path: {s}, size: {d}", .{ config.font.path, config.font.size });

        // First try to load from embedded assets
        if (self.tryLoadEmbeddedFont(config.font.path)) {
            return;
        }

        // Then try to load from file path directly
        if (self.tryLoadFontFromPath(config.font.path)) {
            return;
        }

        // Finally try fallback paths
        for (config.font.fallbacks) |fallback| {
            if (self.tryLoadFontFromPath(fallback)) {
                return;
            }
        }

        std.log.warn("Could not load any configured fonts, using default font", .{});
        self.custom_font = null;
    }

    fn tryLoadEmbeddedFont(self: *Self, font_path: []const u8) bool {
        // Extract font name from path (e.g., "assets/fonts/ttf/FiraCode-Regular.ttf" -> "FiraCode-Regular")
        var font_name: []const u8 = undefined;

        if (std.mem.endsWith(u8, font_path, "FiraCode-Regular.ttf")) {
            font_name = "FiraCode-Regular";
        } else if (std.mem.endsWith(u8, font_path, "FiraCode-Bold.ttf")) {
            font_name = "FiraCode-Bold";
        } else if (std.mem.endsWith(u8, font_path, "FiraCode-Light.ttf")) {
            font_name = "FiraCode-Light";
        } else if (std.mem.endsWith(u8, font_path, "FiraCode-Medium.ttf")) {
            font_name = "FiraCode-Medium";
        } else {
            return false; // Font not available in embedded assets
        }

        if (EmbeddedAssets.getFontData(font_name)) |font_data| {
            std.log.info("Loading embedded font: {s} ({d} bytes)", .{ font_name, font_data.len });

            // Load font from memory data
            const font = rl.loadFontFromMemory(".ttf", font_data, self.font_size, getFontCodepoints()) catch {
                std.log.warn("Failed to load embedded font: {s}", .{font_name});
                return false;
            };

            // Check if font loaded successfully
            if (font.texture.id != 0) {
                self.custom_font = font;

                // Update character dimensions for monospace font
                const sample_text = "M"; // Use 'M' as it's typically the widest character
                const text_size = rl.measureTextEx(font, sample_text, @as(f32, @floatFromInt(self.font_size)), 0);
                self.char_width = text_size.x;
                self.char_height = text_size.y;

                std.log.info("Embedded font loaded successfully: {s}", .{font_name});
                std.log.info("Character dimensions: {d}x{d}", .{ self.char_width, self.char_height });
                return true;
            }
        }

        return false;
    }

    fn tryLoadFontFromPath(self: *Self, font_path: []const u8) bool {
        // Check if file exists before trying to load
        if (std.fs.cwd().access(font_path, .{})) |_| {
            std.log.info("Attempting to load font from file: {s}", .{font_path});

            // Create null-terminated string for raylib
            const font_path_z = self.allocator.dupeZ(u8, font_path) catch return false;
            defer self.allocator.free(font_path_z);

            // Load font with the configured font size
            const font = rl.loadFontEx(font_path_z, self.font_size, getFontCodepoints()) catch {
                std.log.warn("Failed to load font from file: {s}", .{font_path});
                return false;
            };

            // Check if font loaded successfully (raylib returns default font on failure)
            if (font.texture.id != 0) {
                self.custom_font = font;

                // Update character dimensions for monospace font
                const sample_text = "M"; // Use 'M' as it's typically the widest character
                const text_size = rl.measureTextEx(font, sample_text, @as(f32, @floatFromInt(self.font_size)), 0);
                self.char_width = text_size.x;
                self.char_height = text_size.y;

                std.log.info("Font loaded successfully from file: {s}", .{font_path});
                std.log.info("Character dimensions: {d}x{d}", .{ self.char_width, self.char_height });
                return true;
            }
        } else |_| {
            std.log.debug("Font file not found: {s}", .{font_path});
        }

        return false;
    }

    fn handleInput(self: *Self) !void {
        // Handle mouse input first
        try self.handleMouseInput();

        // Check for control key combinations
        if (rl.isKeyDown(.left_control) or rl.isKeyDown(.right_control)) {
            const key = rl.getKeyPressed();
            if (key != .null) {
                switch (key) {
                    .t => {
                        // Ctrl+T: Create new session
                        var name_buffer: [32]u8 = undefined;
                        const session_name = std.fmt.bufPrint(&name_buffer, "Terminal {d}", .{self.session_manager.getSessionCount() + 1}) catch "New Terminal";
                        _ = try self.session_manager.createSession(session_name, self.cols, self.rows);
                        self.updateWindowTitle(); // Update title after creating session
                        std.log.info("Created new session: {s}", .{session_name});
                        return;
                    },
                    .w => {
                        // Ctrl+W: Close current session
                        if (self.session_manager.getActiveSession()) |session| {
                            _ = self.session_manager.closeSession(session.id);
                            self.updateWindowTitle(); // Update title after closing session
                            std.log.info("Closed session {d}", .{session.id});
                        }
                        return;
                    },
                    .tab => {
                        // Ctrl+Tab: Next session
                        self.session_manager.switchToNextSession();
                        self.updateWindowTitle(); // Update title after switching session
                        return;
                    },
                    .page_up => {
                        // Ctrl+PageUp: Previous session (alternative to Shift+Ctrl+Tab)
                        self.session_manager.switchToPrevSession();
                        self.updateWindowTitle(); // Update title after switching session
                        return;
                    },
                    .page_down => {
                        // Ctrl+PageDown: Next session (alternative to Ctrl+Tab)
                        self.session_manager.switchToNextSession();
                        self.updateWindowTitle(); // Update title after switching session
                        return;
                    },
                    else => {
                        // Let other Ctrl combinations fall through to terminal
                    },
                }
            }
        }

        // Check for Shift+Ctrl combinations
        if ((rl.isKeyDown(.left_control) or rl.isKeyDown(.right_control)) and
            (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)))
        {
            const key = rl.getKeyPressed();
            if (key == .tab) {
                // Shift+Ctrl+Tab: Previous session
                self.session_manager.switchToPrevSession();
                self.updateWindowTitle(); // Update title after switching session
                return;
            }
        }

        // Get active session for normal input
        const active_session = self.session_manager.getActiveSession() orelse return;

        // Handle keyboard input
        const key = rl.getKeyPressed();
        if (key != .null) {
            const key_data = try self.convertKeyToBytes(key);
            if (key_data.len > 0) {
                _ = try active_session.pty.write(key_data);
                std.log.debug("Sent key to PTY: '{s}'", .{key_data});
            }
        }

        // Handle text input
        const char = rl.getCharPressed();
        if (char != 0) {
            var char_buffer: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(@intCast(char), &char_buffer) catch 1;
            _ = try active_session.pty.write(char_buffer[0..len]);
            std.log.debug("Sent char to PTY: '{c}'", .{@as(u8, @intCast(char))});
        }
    }

    fn handleMouseInput(self: *Self) !void {
        // Handle mouse clicks
        if (rl.isMouseButtonPressed(.left)) {
            const mouse_pos = rl.getMousePosition();
            try self.handleMouseClick(mouse_pos);
        }

        // Handle mouse wheel
        const wheel_move = rl.getMouseWheelMove();
        if (wheel_move != 0) {
            const mouse_pos = rl.getMousePosition();

            // If mouse is over tab bar, use wheel to switch tabs
            if (mouse_pos.y >= self.margin_y and mouse_pos.y <= self.margin_y + self.tab_bar_height and
                self.session_manager.getSessionCount() > 1)
            {
                if (wheel_move > 0) {
                    self.session_manager.switchToPrevSession();
                    std.log.debug("Switched to previous session via mouse wheel", .{});
                } else {
                    self.session_manager.switchToNextSession();
                    std.log.debug("Switched to next session via mouse wheel", .{});
                }
            } else {
                // TODO: Implement terminal scrollback functionality
                std.log.debug("Mouse wheel in terminal area: {d}", .{wheel_move});
            }
        }

        // Handle right-click for context menu (future feature)
        if (rl.isMouseButtonPressed(.right)) {
            const mouse_pos = rl.getMousePosition();
            std.log.debug("Right-click at: {d}, {d}", .{ mouse_pos.x, mouse_pos.y });
            // TODO: Implement context menu (copy, paste, new tab, etc.)
        }
    }

    fn handleMouseClick(self: *Self, mouse_pos: rl.Vector2) !void {
        // Check if click is in tab bar area
        const sessions = self.session_manager.getAllSessions();
        if (sessions.len > 1 and mouse_pos.y >= self.margin_y and mouse_pos.y <= self.margin_y + self.tab_bar_height) {
            try self.handleTabBarClick(mouse_pos, sessions);
            return;
        }

        // TODO: Handle clicks in terminal content area (for text selection, copy/paste)
        // For now, just log the position
        if (mouse_pos.y > self.margin_y + self.tab_bar_height) {
            std.log.debug("Terminal content click at: {d}, {d}", .{ mouse_pos.x, mouse_pos.y });
        }
    }

    fn handleTabBarClick(self: *Self, mouse_pos: rl.Vector2, sessions: []Session) !void {
        const tab_width: f32 = 200.0;
        var x_offset: f32 = self.margin_x;

        for (sessions) |*session| {
            // Check if click is within this tab's bounds
            if (mouse_pos.x >= x_offset and mouse_pos.x <= x_offset + tab_width) {
                // Check if click is on close button (right 20px of tab)
                const close_button_x = x_offset + tab_width - 20;
                if (mouse_pos.x >= close_button_x) {
                    // Close button clicked
                    _ = self.session_manager.closeSession(session.id);
                    self.updateWindowTitle(); // Update title after closing session
                    std.log.info("Closed session {d} via mouse click", .{session.id});
                } else {
                    // Tab content clicked - switch to this session
                    _ = self.session_manager.switchToSession(session.id);
                    self.updateWindowTitle(); // Update title after switching session
                    std.log.info("Switched to session {d} via mouse click", .{session.id});
                }
                return;
            }
            x_offset += tab_width + 5; // 5px gap between tabs
        }
    }

    fn convertKeyToBytes(self: *Self, key: rl.KeyboardKey) ![]const u8 {
        _ = self;

        return switch (key) {
            .enter => "\r",
            .backspace => "\x7f",
            .tab => "\t",
            .escape => "\x1b",
            .up => "\x1b[A",
            .down => "\x1b[B",
            .right => "\x1b[C",
            .left => "\x1b[D",
            .home => "\x1b[H",
            .end => "\x1b[F",
            .page_up => "\x1b[5~",
            .page_down => "\x1b[6~",
            .delete => "\x1b[3~",
            .insert => "\x1b[2~",
            .f1 => "\x1b[OP",
            .f2 => "\x1b[OQ",
            .f3 => "\x1b[OR",
            .f4 => "\x1b[OS",
            .f5 => "\x1b[15~",
            .f6 => "\x1b[17~",
            .f7 => "\x1b[18~",
            .f8 => "\x1b[19~",
            .f9 => "\x1b[20~",
            .f10 => "\x1b[21~",
            .f11 => "\x1b[23~",
            .f12 => "\x1b[24~",
            else => "",
        };
    }

    fn readPtyOutput(self: *Self) !void {
        const active_session = self.session_manager.getActiveSession() orelse return;

        if (!active_session.pty.hasData()) return;

        var buffer: [4096]u8 = undefined;
        const bytes_read = active_session.pty.read(buffer[0..]) catch |err| switch (err) {
            error.WouldBlock => return,
            else => {
                std.log.warn("PTY read error: {any}", .{err});
                return;
            },
        };

        if (bytes_read > 0) {
            std.log.debug("Read {} bytes from PTY", .{bytes_read});
            try active_session.terminal.processData(buffer[0..bytes_read]);
        }
    }

    fn render(self: *Self) void {
        rl.beginDrawing();
        defer rl.endDrawing();

        // Clear with black background
        rl.clearBackground(rl.Color.black);

        // Render tab bar
        self.renderTabBar();

        // Render terminal content for active session
        self.renderTerminalContent();

        // Render cursor for active session
        self.renderCursor();

        // Render status info
        self.renderStatus();
    }

    fn renderTabBar(self: *Self) void {
        const sessions = self.session_manager.getAllSessions();
        if (sessions.len <= 1) return; // Don't show tab bar for single session

        const tab_width: f32 = 200.0;
        const tab_height: f32 = self.tab_bar_height;
        var x_offset: f32 = self.margin_x;
        const mouse_pos = rl.getMousePosition();

        for (sessions) |*session| {
            // Check if mouse is hovering over this tab
            const is_hovering = mouse_pos.x >= x_offset and mouse_pos.x <= x_offset + tab_width and
                mouse_pos.y >= self.margin_y and mouse_pos.y <= self.margin_y + tab_height;

            // Check if mouse is hovering over close button
            const close_button_x = x_offset + tab_width - 20;
            const is_hovering_close = is_hovering and mouse_pos.x >= close_button_x;

            // Determine tab colors with hover effects
            var bg_color = if (session.is_active) rl.Color.dark_gray else rl.Color.gray;
            var text_color = if (session.is_active) rl.Color.white else rl.Color.light_gray;
            var border_color = if (session.is_active) rl.Color.yellow else rl.Color.dark_gray;
            var close_color = text_color;

            // Apply hover effects
            if (is_hovering and !session.is_active) {
                bg_color = rl.Color.light_gray;
                text_color = rl.Color.white;
                border_color = rl.Color.white;
            }

            if (is_hovering_close) {
                close_color = rl.Color.red;
            }

            // Draw tab background
            rl.drawRectangle(@intFromFloat(x_offset), @intFromFloat(self.margin_y), @intFromFloat(tab_width), @intFromFloat(tab_height), bg_color);

            // Draw tab border
            rl.drawRectangleLines(@intFromFloat(x_offset), @intFromFloat(self.margin_y), @intFromFloat(tab_width), @intFromFloat(tab_height), border_color);

            // Draw session name (truncate if too long)
            const text_x = x_offset + 10;
            const text_y = self.margin_y + 5;
            var name_buffer: [20]u8 = undefined;
            const display_name = if (session.name.len > 18)
                std.fmt.bufPrint(&name_buffer, "{s}...", .{session.name[0..15]}) catch session.name
            else
                session.name;

            self.drawTextWithFont(@ptrCast(display_name), @intFromFloat(text_x), @intFromFloat(text_y), 14, text_color);

            // Draw close button (×) with hover color
            const close_x = x_offset + tab_width - 20;
            const close_y = self.margin_y + 5;
            self.drawTextWithFont("×", @intFromFloat(close_x), @intFromFloat(close_y), 14, close_color);

            x_offset += tab_width + 5; // 5px gap between tabs
        }
    }

    fn renderTerminalContent(self: *Self) void {
        const active_session = self.session_manager.getActiveSession() orelse return;
        const buffer = &active_session.terminal.buffer;

        // Calculate Y offset to account for tab bar
        const content_y_offset = self.margin_y + (if (self.session_manager.getSessionCount() > 1) self.tab_bar_height + 5 else 0);

        // Render each character in the terminal buffer using full available space
        for (0..buffer.height) |row| {
            for (0..buffer.width) |col| {
                if (buffer.getCell(@intCast(col), @intCast(row))) |cell| {
                    if (cell.char > 0 and cell.char != ' ') {
                        const x = @as(f32, @floatFromInt(col)) * self.char_width + self.margin_x;
                        const y = @as(f32, @floatFromInt(row)) * self.char_height + content_y_offset;

                        // Convert cell.char (u21) to a string for drawing
                        var char_buffer: [4]u8 = undefined;
                        const len = std.unicode.utf8Encode(cell.char, &char_buffer) catch 1;
                        char_buffer[len] = 0; // Null terminate

                        // Convert color
                        const color = self.convertColor(cell.fg_color);

                        // Use custom font if available, otherwise use default
                        if (self.custom_font) |font| {
                            const position = rl.Vector2{ .x = x, .y = y };
                            rl.drawTextEx(font, @ptrCast(&char_buffer), position, @as(f32, @floatFromInt(self.font_size)), 0, color);
                        } else {
                            rl.drawText(@ptrCast(&char_buffer), @intFromFloat(x), @intFromFloat(y), self.font_size, color);
                        }
                    }
                }
            }
        }
    }

    fn renderCursor(self: *Self) void {
        const active_session = self.session_manager.getActiveSession() orelse return;

        // Calculate Y offset to account for tab bar
        const content_y_offset = self.margin_y + (if (self.session_manager.getSessionCount() > 1) self.tab_bar_height + 5 else 0);

        // Blinking cursor
        if ((self.frame_count / 30) % 2 == 0) {
            const x = @as(f32, @floatFromInt(active_session.terminal.cursor_x)) * self.char_width + self.margin_x;
            const y = @as(f32, @floatFromInt(active_session.terminal.cursor_y)) * self.char_height + content_y_offset;

            rl.drawRectangle(@intFromFloat(x), @intFromFloat(y), @intFromFloat(self.char_width), @intFromFloat(self.char_height), rl.Color.yellow);
        }
    }

    fn renderStatus(self: *Self) void {
        const active_session = self.session_manager.getActiveSession();

        // Get current window dimensions
        const current_width = rl.getScreenWidth();
        const current_height = rl.getScreenHeight();

        // Status line at bottom with proper margins
        const status_y = current_height - @as(i32, @intFromFloat(self.status_bar_height));

        // Session info
        if (active_session) |session| {
            // PTY status
            const pty_color = if (session.pty.isChildAlive()) rl.Color.green else rl.Color.red;
            self.drawTextWithFont("PTY", @as(i32, @intFromFloat(self.margin_x)), status_y, 12, pty_color);

            // Session info
            var session_buffer: [64]u8 = undefined;
            const session_text = std.fmt.bufPrintZ(&session_buffer, "Session: {d}/{d}", .{ session.id, self.session_manager.getSessionCount() }) catch "Session: ?";
            self.drawTextWithFont(@ptrCast(session_text), @as(i32, @intFromFloat(self.margin_x)) + 60, status_y, 12, rl.Color{ .r = 0, .g = 255, .b = 255, .a = 255 });

            // Cursor position
            var pos_buffer: [64]u8 = undefined;
            const pos_text = std.fmt.bufPrintZ(&pos_buffer, "Cursor: {d},{d}", .{ session.terminal.cursor_x, session.terminal.cursor_y }) catch "Cursor: ?";
            self.drawTextWithFont(@ptrCast(pos_text), @as(i32, @intFromFloat(self.margin_x)) + 180, status_y, 12, rl.Color.white);
        } else {
            self.drawTextWithFont("No active session", @as(i32, @intFromFloat(self.margin_x)), status_y, 12, rl.Color.red);
        }

        // Terminal dimensions
        var dim_buffer: [64]u8 = undefined;
        const dim_text = std.fmt.bufPrintZ(&dim_buffer, "Size: {d}x{d}", .{ self.cols, self.rows }) catch "Size: ?";
        self.drawTextWithFont(@ptrCast(dim_text), @as(i32, @intFromFloat(self.margin_x)) + 300, status_y, 12, rl.Color.white);

        // Window dimensions
        var win_buffer: [64]u8 = undefined;
        const win_text = std.fmt.bufPrintZ(&win_buffer, "Window: {d}x{d}", .{ current_width, current_height }) catch "Window: ?";
        self.drawTextWithFont(@ptrCast(win_text), @as(i32, @intFromFloat(self.margin_x)) + 420, status_y, 12, rl.Color.gray);

        // Shortcuts help (right side)
        const help_text = "Ctrl+T:New Ctrl+W:Close Ctrl+Tab:Next";
        const help_width = if (self.custom_font) |font|
            rl.measureTextEx(font, help_text, 10, 0).x
        else
            @as(f32, @floatFromInt(help_text.len * 6));

        self.drawTextWithFont(help_text, current_width - @as(i32, @intFromFloat(help_width)) - 10, status_y, 10, rl.Color.gray);
    }

    fn drawTextWithFont(self: *Self, text: [*:0]const u8, x: i32, y: i32, size: i32, color: rl.Color) void {
        if (self.custom_font) |font| {
            const position = rl.Vector2{ .x = @as(f32, @floatFromInt(x)), .y = @as(f32, @floatFromInt(y)) };
            const text_slice: [:0]const u8 = std.mem.span(text);
            rl.drawTextEx(font, text_slice, position, @as(f32, @floatFromInt(size)), 0, color);
        } else {
            const text_slice: [:0]const u8 = std.mem.span(text);
            rl.drawText(text_slice, x, y, size, color);
        }
    }

    fn convertColor(self: *Self, color: anytype) rl.Color {
        _ = self;

        // Convert terminal color to Raylib color
        return switch (color) {
            .black => rl.Color.black,
            .red => rl.Color.red,
            .green => rl.Color.green,
            .yellow => rl.Color.yellow,
            .blue => rl.Color.blue,
            .magenta => rl.Color.magenta,
            .cyan => rl.Color{ .r = 0, .g = 255, .b = 255, .a = 255 },
            .white => rl.Color.white,
            // Bright colors
            .bright_black => rl.Color.gray,
            .bright_red => rl.Color{ .r = 255, .g = 85, .b = 85, .a = 255 },
            .bright_green => rl.Color{ .r = 85, .g = 255, .b = 85, .a = 255 },
            .bright_yellow => rl.Color{ .r = 255, .g = 255, .b = 85, .a = 255 },
            .bright_blue => rl.Color{ .r = 85, .g = 85, .b = 255, .a = 255 },
            .bright_magenta => rl.Color{ .r = 255, .g = 85, .b = 255, .a = 255 },
            .bright_cyan => rl.Color{ .r = 85, .g = 255, .b = 255, .a = 255 },
            .bright_white => rl.Color{ .r = 255, .g = 255, .b = 255, .a = 255 },
        };
    }

    fn updateTerminalDimensions(self: *Self) !void {
        // Get current window size
        const current_width = rl.getScreenWidth();
        const current_height = rl.getScreenHeight();

        // Check if window size changed
        if (current_width != self.last_window_width or current_height != self.last_window_height) {
            self.last_window_width = current_width;
            self.last_window_height = current_height;

            // Update internal width/height for consistency
            self.width = current_width;
            self.height = current_height;

            // Calculate available space for terminal content (account for tab bar)
            const tab_bar_space = if (self.session_manager.getSessionCount() > 1) self.tab_bar_height + 5 else 0;
            const available_width = @as(f32, @floatFromInt(current_width)) - (self.margin_x * 2);
            const available_height = @as(f32, @floatFromInt(current_height)) - (self.margin_y * 2) - self.status_bar_height - tab_bar_space;

            // Ensure we have minimum dimensions
            const min_available_width = @max(available_width, 100.0);
            const min_available_height = @max(available_height, 50.0);

            // Calculate new terminal dimensions based on character size
            const new_cols = @as(u32, @intFromFloat(@max(10, min_available_width / self.char_width)));
            const new_rows = @as(u32, @intFromFloat(@max(5, min_available_height / self.char_height)));

            // Update terminal dimensions if they changed
            if (new_cols != self.cols or new_rows != self.rows) {
                const old_cols = self.cols;
                const old_rows = self.rows;

                self.cols = new_cols;
                self.rows = new_rows;

                std.log.info("Window resized: {d}x{d} -> {d}x{d}, terminal: {d}x{d} -> {d}x{d}", .{ self.last_window_width, self.last_window_height, current_width, current_height, old_cols, old_rows, self.cols, self.rows });

                // Resize all sessions to new dimensions
                try self.session_manager.resizeAllSessions(@intCast(self.cols), @intCast(self.rows));

                std.log.debug("All sessions resized to new terminal dimensions", .{});
            }
        }
    }

    fn updateWindowTitle(self: *Self) void {
        const active_session = self.session_manager.getActiveSession();
        if (active_session) |session| {
            var title_buffer: [256]u8 = undefined;
            const title = std.fmt.bufPrint(&title_buffer, "Zigline Terminal - {s}", .{session.name}) catch "Zigline Terminal";
            const title_z = self.allocator.dupeZ(u8, title) catch return;
            defer self.allocator.free(title_z);
            rl.setWindowTitle(title_z);
        } else {
            rl.setWindowTitle("Zigline Terminal");
        }
    }
};
