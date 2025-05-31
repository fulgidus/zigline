//! GUI module for DVUI integration
//! Handles window creation, event processing, and rendering coordination

const std = @import("std");
const dvui = @import("dvui");
const Buffer = @import("../terminal/buffer.zig").Buffer;
const AnsiParser = @import("../terminal/ansi.zig").AnsiParser;
const InputProcessor = @import("../input/processor.zig").InputProcessor;
const Terminal = @import("../core/terminal.zig").Terminal;
const PTY = @import("../core/pty.zig").PTY; // Added PTY import

/// DVUI backend type alias
const Backend = dvui.backend;

/// Font configuration constants
const FIRA_CODE_FONT_PATH = "assets/fonts/ttf/FiraCode-Regular.ttf";
const DEFAULT_FONT_SIZE: f32 = 16.0;

/// GUI application state
pub const Gui = struct {
    allocator: std.mem.Allocator,
    backend: Backend,
    window: dvui.Window,
    terminal: *Terminal,
    input_processor: *InputProcessor,
    pty: *PTY, // Added pty field

    // Font configuration
    font_size: f32 = DEFAULT_FONT_SIZE,
    font_loaded: bool = false,
    font_data: ?[]u8 = null, // Store font data to free it later

    // Window state
    window_title: []const u8 = "Zigline Terminal",

    const Self = @This();

    /// Initialize the GUI with DVUI backend
    pub fn init(
        allocator: std.mem.Allocator,
        terminal: *Terminal,
        input_processor: *InputProcessor,
        pty: *PTY, // Added pty argument
    ) !Self {
        // Initialize SDL3 backend with window
        var backend = try Backend.initWindow(.{
            .allocator = allocator,
            .size = .{ .w = 1200.0, .h = 800.0 },
            .min_size = .{ .w = 400.0, .h = 300.0 },
            .vsync = true,
            .title = "Zigline Terminal",
        });

        // Initialize DVUI window
        const dvui_backend = backend.backend();
        const window = try dvui.Window.init(@src(), allocator, dvui_backend, .{});

        const gui = Self{
            .allocator = allocator,
            .backend = backend,
            .window = window,
            .terminal = terminal,
            .input_processor = input_processor,
            .pty = pty, // Store pty
        };

        return gui;
    }

    /// Clean up GUI resources
    pub fn deinit(self: *Self) void {
        // Free font data if allocated
        if (self.font_data) |font_bytes| {
            self.allocator.free(font_bytes);
        }

        self.window.deinit();
        self.backend.deinit();
    }

    /// Load Fira Code font for terminal rendering
    fn loadFont(self: *Self) !void {
        // Try to load the Fira Code font
        const font_path = FIRA_CODE_FONT_PATH;
        const font_bytes = std.fs.cwd().readFileAlloc(self.allocator, font_path, 10 * 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => {
                std.log.warn("Fira Code font not found at '{s}', falling back to system font", .{font_path});
                return; // Early return, font_loaded will be set by caller
            },
            else => return err,
        };

        // Store font data for cleanup later
        self.font_data = font_bytes;

        std.log.info("Loaded font file '{s}' (size: {d} bytes)", .{ font_path, font_bytes.len });
        std.log.warn("Skipping custom font registration; using system monospace font for now.", .{});

        // Do NOT call dvui.addFont -- this will force system font usage
        // dvui.addFont("FiraCode", font_bytes, self.allocator) ...
        // std.log.info("Loaded Fira Code font successfully", .{});
    }

    /// Main GUI render loop
    pub fn run(self: *Self) !void {
        main_loop: while (true) {
            // Begin frame timing for variable framerate
            const nstime = self.window.beginWait(self.backend.hasEvent());

            // Mark beginning of DVUI frame
            try self.window.begin(nstime);

            // Load Fira Code font if not already loaded (must be inside DVUI frame)
            if (!self.font_loaded) {
                self.loadFont() catch |err| {
                    std.log.warn("Font load failed: {any}", .{err});
                };
                // Always mark as loaded to prevent retry, even on failure
                self.font_loaded = true;
            }

            // Process SDL events and forward to DVUI
            const quit = try self.backend.addAllEvents(&self.window);
            if (quit) break :main_loop;

            // Handle DVUI input events and forward to terminal
            try self.handleInput();

            // Clear the frame
            _ = Backend.c.SDL_SetRenderDrawColor(self.backend.renderer, 0, 0, 0, 255);
            _ = Backend.c.SDL_RenderClear(self.backend.renderer);

            // Render the terminal interface
            try self.renderTerminal();

            // End DVUI frame
            const end_micros = try self.window.end(.{});

            // Handle cursor and text input
            self.backend.setCursor(self.window.cursorRequested());
            self.backend.textInputRect(self.window.textInputRequested());

            // Present the frame
            self.backend.renderPresent();

            // Wait for next frame
            const wait_event_micros = self.window.waitTime(end_micros, null);
            self.backend.waitEventTimeout(wait_event_micros);
        }
    }

    /// Handle input from DVUI and forward to terminal
    fn handleInput(self: *Self) !void {
        // Check for key events that DVUI captured
        const events = dvui.events();
        for (events) |event| {
            switch (event.evt) {
                .key => |key_event| {
                    if (key_event.action == .down or key_event.action == .repeat) {
                        try self.processKeyEvent(key_event);
                    }
                },
                .text => |text_event| {
                    try self.processTextEvent(text_event);
                },
                .mouse => |mouse_event| {
                    // Handle mouse events (for future features like selection)
                    _ = mouse_event;
                    // std.log.debug("Mouse event: {any}", .{mouse_event});
                },
                .close_popup => {
                    // Handle popup close events
                },
                else => {
                    // Handle other events as needed
                },
            }
        }

        // Check for window resize events through DVUI window
        const current_size = self.window.wd.rect;
        const expected_cols: u32 = @intFromFloat(@max(20, current_size.w / 10)); // Rough char width estimate
        const expected_rows: u32 = @intFromFloat(@max(10, current_size.h / 16)); // Rough char height estimate

        // If window size changed significantly, update terminal dimensions
        if (expected_cols != self.terminal.buffer.width or expected_rows != self.terminal.buffer.height) {
            self.handleWindowResize(expected_cols, expected_rows) catch |err| {
                std.log.warn("Window resize handling failed: {any}", .{err});
            };
        }
    }

    /// Process keyboard events and send to terminal
    fn processKeyEvent(self: *Self, key_event: dvui.Event.Key) !void {
        // Convert DVUI key to terminal input
        const key_data = try self.dvuiKeyToBytes(key_event);
        if (key_data.len > 0) {
            // try self.terminal.writeInput(key_data); // Old line
            _ = try self.pty.write(key_data); // Changed to use pty.write
        }
    }

    /// Process text input events
    fn processTextEvent(self: *Self, text_event: dvui.Event.Text) !void {
        // try self.terminal.writeInput(text_event.text); // Old line
        _ = try self.pty.write(text_event.txt); // Correct field name
    }

    /// Convert DVUI key events to terminal byte sequences
    fn dvuiKeyToBytes(self: *Self, key_event: dvui.Event.Key) ![]const u8 {
        _ = self;

        // Match on the key code field and DVUI enums
        switch (key_event.code) {
            dvui.enums.Key.enter => return "\r",
            dvui.enums.Key.backspace => return "\x7f",
            dvui.enums.Key.tab => return "\t",
            dvui.enums.Key.escape => return "\x1b",

            // Arrow Keys
            dvui.enums.Key.up => return "\x1b[A",
            dvui.enums.Key.down => return "\x1b[B",
            dvui.enums.Key.right => return "\x1b[C",
            dvui.enums.Key.left => return "\x1b[D",

            // Other common special keys
            dvui.enums.Key.delete => return "\x1b[3~",

            else => {
                // This function is primarily for special (non-printable) keys.
                // Printable characters are expected to be handled by 'text' events.
                // If a printable key event (e.g. 'a' key) arrives here,
                // it means it wasn't processed as a text event, possibly due to modifiers
                // or DVUI's event generation logic. For now, we return an empty sequence.
                // std.log.debug("Unhandled key in dvuiKeyToBytes: {any}", .{key_event.key});
                return "";
            },
        }
    }

    /// Handle window resize events and update PTY dimensions
    fn handleWindowResize(self: *Self, new_cols: u32, new_rows: u32) !void {
        std.log.info("Window resize detected: {}x{} -> {}x{}", .{ self.terminal.buffer.width, self.terminal.buffer.height, new_cols, new_rows });

        // Update terminal buffer size
        self.terminal.resize(new_cols, new_rows) catch |err| {
            std.log.warn("Failed to resize terminal buffer: {any}", .{err});
        };

        // Update PTY window size (TIOCSWINSZ) - note: PTY expects (rows, cols) as u16
        const pty_rows: u16 = @intCast(@min(new_rows, 65535));
        const pty_cols: u16 = @intCast(@min(new_cols, 65535));
        self.pty.setSize(pty_rows, pty_cols) catch |err| {
            std.log.warn("Failed to update PTY window size: {any}", .{err});
        };

        std.log.debug("Terminal resized successfully to {}x{}", .{ new_cols, new_rows });
    }

    /// Render the terminal interface using DVUI
    fn renderTerminal(self: *Self) !void {
        // Create main window area with black background
        var scroll = try dvui.scrollArea(@src(), .{}, .{ .expand = .both, .color_fill = .{ .color = .{ .r = 0x00, .g = 0x00, .b = 0x00 } } });
        defer scroll.deinit();

        // PHASE 5 IMPLEMENTATION: Avoid text rendering due to DVUI font texture crashes
        // Show visual representation of terminal using colored rectangles

        // Header area (represents title bar)
        {
            var header = try dvui.box(@src(), .vertical, .{
                .expand = .horizontal,
                .min_size_content = .{ .h = 40 },
                .color_fill = .{ .color = .{ .r = 0x20, .g = 0x20, .b = 0x20 } }, // Dark gray
            });
            defer header.deinit();
        }

        // Get terminal buffer info for visual representation
        const buffer = &self.terminal.buffer;
        const cursor_pos = self.terminal.getCursorPosition();

        // Main terminal area (represents buffer content)
        {
            var terminal_area = try dvui.box(@src(), .vertical, .{
                .expand = .both,
                .color_fill = .{ .color = .{ .r = 0x00, .g = 0x00, .b = 0x00 } }, // Black background
                .margin = .{ .x = 5, .y = 5 },
            });
            defer terminal_area.deinit();

            // Show visual grid representing terminal buffer
            // Each "cell" is a small rectangle
            const cell_height = 12;
            const rows_to_show = @min(buffer.height, 20); // Limit for performance

            var row: u32 = 0;
            while (row < rows_to_show) : (row += 1) {
                var row_box = try dvui.box(@src(), .horizontal, .{
                    .expand = .horizontal,
                    .min_size_content = .{ .h = cell_height },
                    .color_fill = if (row == cursor_pos.y)
                        .{ .color = .{ .r = 0x40, .g = 0x40, .b = 0x40 } } // Highlight cursor row
                    else
                        .{ .color = .{ .r = 0x00, .g = 0x00, .b = 0x00 } }, // Normal row
                    .id_extra = row, // Make each row widget unique
                });
                defer row_box.deinit();
            }
        }

        // Status bar (represents cursor and buffer info)
        {
            var status = try dvui.box(@src(), .vertical, .{
                .expand = .horizontal,
                .min_size_content = .{ .h = 25 },
                .color_fill = .{ .color = .{ .r = 0x00, .g = 0x40, .b = 0x80 } }, // Blue status
            });
            defer status.deinit();
        }

        std.log.debug("Rendered terminal visual ({}x{}) cursor at ({},{})", .{ buffer.width, buffer.height, cursor_pos.x, cursor_pos.y });
    }

    /// Render the terminal buffer content
    fn renderTerminalBuffer(self: *Self) !void {
        // Access the terminal buffer directly and get cursor position
        const buffer = &self.terminal.buffer;
        const cursor_pos = self.terminal.getCursorPosition();

        // Create a simple text area for the terminal content
        var terminal_box = try dvui.box(@src(), .vertical, .{
            .expand = .both,
            .color_fill = .{ .color = .{ .r = 0x00, .g = 0x00, .b = 0x00 } }, // Black background
            .margin = .{ .x = 10, .y = 10 },
        });
        defer terminal_box.deinit();

        // Try to create simple labels for each line
        // Start with just the first few lines to test
        var row: u32 = 0;
        const max_display_rows = @min(buffer.height, 10); // Limit to 10 rows for testing

        while (row < max_display_rows) : (row += 1) {
            var line_text = std.ArrayList(u8).init(self.allocator);
            defer line_text.deinit();

            // Build line text, limiting width to prevent overly long lines
            var col: u32 = 0;
            const max_display_cols = @min(buffer.width, 80); // Limit to 80 columns

            while (col < max_display_cols) : (col += 1) {
                if (buffer.getCell(row, col)) |cell| {
                    const char_byte: u8 = @intCast(cell.char & 0xFF);
                    if (char_byte >= 32 and char_byte < 127) { // Printable ASCII only
                        try line_text.append(char_byte);
                    } else {
                        try line_text.append(' '); // Replace non-printable with space
                    }
                } else {
                    try line_text.append(' ');
                }
            }

            // Add cursor indicator if this is the cursor row
            if (row == cursor_pos.y) {
                try line_text.append('|'); // Simple cursor indicator
            }

            // Try to render this line as a label
            // Use white text on black background
            const line_str = try line_text.toOwnedSlice();
            defer self.allocator.free(line_str);

            try dvui.labelNoFmt(@src(), line_str, .{
                .color_text = .{ .color = .{ .r = 0xFF, .g = 0xFF, .b = 0xFF } },
            });
        }

        std.log.debug("Rendered {} rows of terminal buffer", .{max_display_rows});
    }
};
