//! GUI module for DVUI integration
//! Handles window creation, event processing, and rendering coordination

const std = @import("std");
const dvui = @import("dvui");
const Buffer = @import("../terminal/buffer.zig").Buffer;
const AnsiParser = @import("../terminal/ansi.zig").AnsiParser;
const InputProcessor = @import("../input/processor.zig").InputProcessor;
const Terminal = @import("../core/terminal.zig").Terminal;
const PTY = @import("../core/pty.zig").PTY;

/// DVUI backend type alias
const Backend = dvui.backend;

/// GUI application state
pub const Gui = struct {
    allocator: std.mem.Allocator,
    backend: Backend,
    window: dvui.Window,
    terminal: *Terminal,
    input_processor: ?*InputProcessor,
    pty: *PTY,

    initial_test_sent: bool = false, // Flag to send initial test command

    // Frame counting for debugging
    frame_count: u64 = 0,

    // Window state
    window_title: []const u8 = "Zigline Terminal",

    const Self = @This();

    /// Initialize the GUI with DVUI backend
    /// Creates window, initializes DVUI, and sets up event handling
    pub fn init(
        allocator: std.mem.Allocator,
        terminal: *Terminal,
        input_processor: ?*InputProcessor,
        pty: *PTY,
    ) !Self {
        // Initialize SDL3 backend with macOS-optimized settings
        std.log.info("Initializing SDL3 backend for macOS...", .{});
        var backend = try Backend.initWindow(.{
            .allocator = allocator,
            .size = .{ .w = 1200.0, .h = 800.0 },
            .min_size = .{ .w = 400.0, .h = 300.0 },
            .vsync = true, // Enable vsync on macOS for better performance
            .title = "Zigline Terminal",
        });
        std.log.info("SDL3 backend initialized successfully", .{});

        // Initialize DVUI window
        std.log.info("Initializing DVUI window...", .{});
        const dvui_backend = backend.backend();
        const window = try dvui.Window.init(@src(), allocator, dvui_backend, .{});
        std.log.info("DVUI window initialized successfully", .{});

        const gui = Self{
            .allocator = allocator,
            .backend = backend,
            .window = window,
            .terminal = terminal,
            .input_processor = input_processor,
            .pty = pty, // Store pty
        };

        // Try to explicitly show the window using SDL calls
        std.log.info("Attempting to show SDL window explicitly...", .{});
        _ = Backend.c.SDL_ShowWindow(backend.window);
        _ = Backend.c.SDL_RaiseWindow(backend.window);
        std.log.info("Called SDL_ShowWindow and SDL_RaiseWindow", .{});

        std.log.info("GUI initialization complete", .{});
        return gui;
    }

    /// Clean up GUI resources
    /// Deinitializes DVUI window and SDL backend
    pub fn deinit(self: *Self) void {
        self.window.deinit();
        self.backend.deinit();
    }

    /// Main GUI render loop
    /// Handles events, rendering, and PTY communication
    pub fn run(self: *Self) !void {
        std.log.info("Starting main GUI render loop...", .{});
        
        main_loop: while (true) {
            // Increment frame counter for debugging
            self.frame_count += 1;

            // Log every frame to see what's happening with the loop
            if (self.frame_count <= 5 or self.frame_count % 30 == 0) {
                std.log.debug("GUI render loop active - frame {}", .{self.frame_count});
            }

            // Begin frame timing for variable framerate
            const nstime = self.window.beginWait(self.backend.hasEvent());

            // Mark beginning of DVUI frame
            try self.window.begin(nstime);

            // Read PTY output and process it (Phase 6)
            try self.readPtyOutput();

            // Send initial test command on first frame (for debugging)
            if (!self.initial_test_sent) {
                // First, let's add some content directly to the terminal buffer for immediate display
                self.populateInitialBuffer();
                
                // Then try to send command to PTY
                _ = self.pty.write("echo 'Hello from Zigline!' && ps1='$ '\n") catch |err| {
                    std.log.warn("Failed to send initial test command: {any}", .{err});
                };
                self.initial_test_sent = true;
                std.log.info("Sent initial test command to shell and populated buffer", .{});
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
    /// Processes keyboard, text, and mouse events
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
                    // Handle mouse events properly to maintain DVUI widget state
                    // For a terminal emulator, we mainly need to track focus and click position
                    switch (mouse_event.action) {
                        .press => {
                            // Mouse press - could be used for text selection in future
                            std.log.debug("Mouse press at ({}, {})", .{ mouse_event.p.x, mouse_event.p.y });
                        },
                        .release => {
                            // Mouse release
                            std.log.debug("Mouse release at ({}, {})", .{ mouse_event.p.x, mouse_event.p.y });
                        },
                        .motion => {
                            // Mouse motion - don't log to avoid spam, just consume the event
                        },
                        .focus => {
                            // Mouse focus events
                            std.log.debug("Mouse focus event", .{});
                        },
                        .wheel_x => |dx| {
                            // Horizontal wheel scrolling
                            std.log.debug("Mouse wheel X: {}", .{dx});
                        },
                        .wheel_y => |dy| {
                            // Vertical wheel scrolling 
                            std.log.debug("Mouse wheel Y: {}", .{dy});
                        },
                        .position => {
                            // Mouse position events
                            std.log.debug("Mouse position at ({}, {})", .{ mouse_event.p.x, mouse_event.p.y });
                        },
                    }
                    // Event is properly consumed by just processing it in the switch
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
    /// Converts DVUI key events to ANSI sequences for PTY
    fn processKeyEvent(self: *Self, key_event: dvui.Event.Key) !void {
        std.log.info("Key event detected: {any}", .{key_event});
        // Convert DVUI key to terminal input
        const key_data = try self.dvuiKeyToBytes(key_event);
        if (key_data.len > 0) {
            std.log.info("Sending key data to PTY: '{s}' (length: {})", .{ key_data, key_data.len });
            _ = try self.pty.write(key_data); // Changed to use pty.write
        } else {
            std.log.debug("No key data generated for key event", .{});
        }
    }

    /// Process text input events
    /// Sends typed text directly to PTY
    fn processTextEvent(self: *Self, text_event: dvui.Event.Text) !void {
        std.log.info("Text event detected: '{s}'", .{text_event.txt});
        // try self.terminal.writeInput(text_event.text); // Old line
        _ = try self.pty.write(text_event.txt); // Correct field name
    }

    /// Convert DVUI key events to terminal byte sequences
    /// Maps special keys to ANSI escape sequences for terminal compatibility
    fn dvuiKeyToBytes(self: *Self, key_event: dvui.Event.Key) ![]const u8 {
        _ = self;

        // Handle special keys first (basic functionality without modifiers for now)
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

            // Function keys
            dvui.enums.Key.f1 => return "\x1b[OP",
            dvui.enums.Key.f2 => return "\x1b[OQ",
            dvui.enums.Key.f3 => return "\x1b[OR",
            dvui.enums.Key.f4 => return "\x1b[OS",
            dvui.enums.Key.f5 => return "\x1b[15~",
            dvui.enums.Key.f6 => return "\x1b[17~",
            dvui.enums.Key.f7 => return "\x1b[18~",
            dvui.enums.Key.f8 => return "\x1b[19~",
            dvui.enums.Key.f9 => return "\x1b[20~",
            dvui.enums.Key.f10 => return "\x1b[21~",
            dvui.enums.Key.f11 => return "\x1b[23~",
            dvui.enums.Key.f12 => return "\x1b[24~",

            // Other navigation keys
            dvui.enums.Key.home => return "\x1b[H",
            dvui.enums.Key.end => return "\x1b[F",
            dvui.enums.Key.page_up => return "\x1b[5~",
            dvui.enums.Key.page_down => return "\x1b[6~",
            dvui.enums.Key.insert => return "\x1b[2~",
            dvui.enums.Key.delete => return "\x1b[3~",

            else => {
                // For unhandled keys, let text events handle them
                std.log.debug("Unhandled key in dvuiKeyToBytes: {any}", .{key_event.code});
                return "";
            },
        }
    }

    /// Handle window resize events and update PTY dimensions
    fn handleWindowResize(self: *Self, new_cols: u32, new_rows: u32) !void {
        std.log.info("Window resize detected: {}x{} -> {}x{}", .{ self.terminal.buffer.width, self.terminal.buffer.height, new_cols, new_rows });

        // Update terminal buffer size
        const term_cols: u16 = @intCast(@min(new_cols, 65535));
        const term_rows: u16 = @intCast(@min(new_rows, 65535));
        self.terminal.resize(term_cols, term_rows) catch |err| {
            std.log.warn("Failed to resize terminal buffer: {any}", .{err});
        };

        // Update PTY window size (TIOCSWINSZ) - note: PTY expects (cols, rows) as u16
        const pty_rows: u16 = @intCast(@min(new_rows, 65535));
        const pty_cols: u16 = @intCast(@min(new_cols, 65535));
        self.pty.resize(pty_cols, pty_rows);

        std.log.debug("Terminal resized successfully to {}x{}", .{ new_cols, new_rows });
    }

    /// Render the terminal interface using DVUI
    fn renderTerminal(self: *Self) !void {
        // Reduce debug logging frequency
        if (self.frame_count % 30 == 0) {
            std.log.debug("renderTerminal() called on frame {}", .{self.frame_count});
        }

        // Create main container for terminal with stable properties
        var main_container = try dvui.box(@src(), .vertical, .{
            .expand = .both,
            .background = true,
            .color_fill = .{ .color = dvui.Color{ .r = 10, .g = 10, .b = 10 } }, // Dark terminal background
        });
        defer main_container.deinit();

        // Get terminal buffer for rendering actual content
        const buffer = &self.terminal.buffer;

        // Debug: Count non-empty cells
        var non_empty_count: u32 = 0;
        for (0..buffer.height) |row| {
            for (0..buffer.width) |col| {
                if (buffer.getCell(@intCast(col), @intCast(row))) |cell| {
                    if (cell.char != ' ' and cell.char != 0) {
                        non_empty_count += 1;
                    }
                }
            }
        }

        // Terminal status - using debug output to avoid SDL texture crashes
        var status_buffer: [256]u8 = undefined;
        const status_text = try std.fmt.bufPrint(&status_buffer, "Terminal: {} chars, Frame: {}, Cursor: {},{}",
            .{ non_empty_count, self.frame_count, self.terminal.cursor_x, self.terminal.cursor_y });
        
        // Log status to console instead of rendering to avoid texture issues
        if (self.frame_count % 60 == 0) {
            std.log.debug("Status: {s}", .{status_text});
        }

        // Render the actual terminal buffer content - temporarily using safe rendering
        try self.renderTerminalContentSafe();

        // Log status occasionally
        if (self.frame_count % 30 == 0) {
            std.log.info("Rendered terminal with {} non-empty cells", .{non_empty_count});
        }
    }

    /// Render the terminal buffer content with actual text and cursor
    fn renderTerminalContentSafe(self: *Self) !void {
        // Create a visual container for the terminal area
        var terminal_container = try dvui.box(@src(), .vertical, .{
            .expand = .both,
            .color_fill = .{ .color = dvui.Color{ .r = 20, .g = 20, .b = 20 } }, // Dark terminal background
            .margin = .{ .x = 10, .y = 10, .w = 10, .h = 10 },
        });
        defer terminal_container.deinit();

        const buffer = &self.terminal.buffer;
        
        // Always show a prompt line even if buffer is empty (for debugging)
        try self.renderPromptLine();
        
        // Render the first few lines of terminal content
        for (0..@min(buffer.height, 10)) |row| {
            try self.renderTerminalLine(@intCast(row));
        }
        
        // Show cursor position indicator
        try self.renderCursor();

        // Log terminal content to console for debugging
        if (self.frame_count % 120 == 0) { // Every 2 seconds at 60fps
            self.logTerminalContent();
        }
    }

    /// Render a single terminal line with actual buffer content
    fn renderTerminalLine(self: *Self, row: u32) !void {
        const buffer = &self.terminal.buffer;
        
        // Build the line content
        var line_buffer: [128]u8 = undefined;
        var line_pos: usize = 0;
        var has_content = false;
        
        for (0..@min(buffer.width, 80)) |col| {
            if (buffer.getCell(@intCast(col), row)) |cell| {
                const char = if (cell.char == 0) ' ' else @as(u8, @intCast(@min(cell.char, 255)));
                if (line_pos < line_buffer.len - 1) {
                    line_buffer[line_pos] = if (char < 32 and char != 0) '?' else char;
                    line_pos += 1;
                    if (char != ' ' and char != 0) {
                        has_content = true;
                    }
                }
            }
        }
        
        // Only render lines with content or the first line (for prompt)
        if (has_content or row == 0) {
            line_buffer[line_pos] = 0;
            const line_text = line_buffer[0..line_pos];
            
            // Create a stable ID for this line
            var line_box = try dvui.box(@src(), .horizontal, .{
                .expand = .horizontal,
                .min_size_content = .{ .w = 0, .h = 16 },
            });
            defer line_box.deinit();
            
            // Use textEntry to show actual text content (it's more stable than label)
            if (line_text.len > 0) {
                var text_display = try dvui.textEntry(@src(), .{
                    .text = .{ .buffer = @constCast(line_text) },
                }, .{
                    .expand = .horizontal,
                });
                defer text_display.deinit();
            }
        }
    }

    /// Render a fallback prompt line when buffer is empty
    fn renderPromptLine(self: *Self) !void {
        const buffer = &self.terminal.buffer;
        
        // Check if the first line is empty and show a default prompt
        var first_line_empty = true;
        for (0..@min(buffer.width, 10)) |col| {
            if (buffer.getCell(@intCast(col), 0)) |cell| {
                if (cell.char != 0 and cell.char != ' ') {
                    first_line_empty = false;
                    break;
                }
            }
        }
        
        if (first_line_empty) {
            var prompt_box = try dvui.box(@src(), .horizontal, .{
                .expand = .horizontal,
                .min_size_content = .{ .w = 0, .h = 16 },
                .margin = .{ .x = 5, .y = 2, .w = 5, .h = 2 },
            });
            defer prompt_box.deinit();
            
            // Show a default shell prompt
            var prompt_text = try dvui.textEntry(@src(), .{
                .text = .{ .internal = .{ .limit = 10 } },
                .placeholder = "$ ",
            }, .{});
            defer prompt_text.deinit();
        }
    }

    /// Render cursor indicator
    fn renderCursor(self: *Self) !void {
        // Create a cursor indicator box
        var cursor_box = try dvui.box(@src(), .horizontal, .{
            .expand = .horizontal,
            .min_size_content = .{ .w = 0, .h = 20 },
            .margin = .{ .x = 5, .y = 5, .w = 5, .h = 5 },
        });
        defer cursor_box.deinit();
        
        // Show cursor position and blinking state
        const cursor_visible = (self.frame_count / 30) % 2 == 0; // Blink every 30 frames
        var cursor_buffer: [64]u8 = undefined;
        const cursor_text = try std.fmt.bufPrint(&cursor_buffer, "Cursor: ({},{}) {s}", 
            .{ self.terminal.cursor_x, self.terminal.cursor_y, if (cursor_visible) "█" else "_" });
        
        var cursor_display = try dvui.textEntry(@src(), .{
            .text = .{ .buffer = @constCast(cursor_text) },
        }, .{});
        defer cursor_display.deinit();
    }

    /// Log terminal buffer content to console for debugging
    fn logTerminalContent(self: *Self) void {
        const buffer = &self.terminal.buffer;
        var line_count: u32 = 0;
        var char_count: u32 = 0;
        
        std.log.debug("=== Terminal Buffer Content ===", .{});
        for (0..@min(buffer.height, 10)) |row| { // Show first 10 lines
            var line_buffer: [128]u8 = undefined;
            var line_pos: usize = 0;
            var has_content = false;
            
            for (0..@min(buffer.width, 80)) |col| { // Show first 80 chars
                if (buffer.getCell(@intCast(col), @intCast(row))) |cell| {
                    const char = if (cell.char == 0) ' ' else @as(u8, @intCast(@min(cell.char, 255)));
                    if (line_pos < line_buffer.len - 1) {
                        line_buffer[line_pos] = if (char < 32 and char != 0) '?' else char;
                        line_pos += 1;
                        if (char != ' ' and char != 0) {
                            has_content = true;
                            char_count += 1;
                        }
                    }
                }
            }
            
            if (has_content) {
                line_buffer[line_pos] = 0;
                std.log.debug("Line {d}: '{s}'", .{ row, line_buffer[0..line_pos] });
                line_count += 1;
            }
        }
        
        std.log.debug("Terminal: {d} lines with content, {d} total chars, cursor at ({d},{d})", 
            .{ line_count, char_count, self.terminal.cursor_x, self.terminal.cursor_y });
    }

    /// Read output from PTY and process it through the terminal (Phase 6)
    fn readPtyOutput(self: *Self) !void {
        std.log.debug("readPtyOutput() called - checking for PTY data", .{});

        // First check if data is available (non-blocking check)
        if (!self.pty.hasData()) {
            // Don't log every time, just occasionally for debugging
            if (self.frame_count % 120 == 0) { // Log every 120 frames (about once every 2 seconds)
                std.log.debug("PTY hasData() returned false - no data available (frame {})", .{self.frame_count});
            }
            return;
        }

        std.log.info("PTY hasData() returned true - attempting to read data!", .{});

        // Read available data from PTY (should be non-blocking now)
        var buffer: [4096]u8 = undefined;
        const bytes_read = self.pty.read(buffer[0..]) catch |err| switch (err) {
            error.WouldBlock => {
                std.log.debug("PTY read would block despite hasData() == true", .{});
                return;
            },
            else => {
                std.log.warn("PTY read error: {any}", .{err});
                return;
            },
        };

        std.log.info("PTY read returned {d} bytes", .{bytes_read});

        if (bytes_read > 0) {
            std.log.info("SUCCESS! Read {d} bytes from PTY: '{s}'", .{ bytes_read, buffer[0..bytes_read] });

            // Process the output through the terminal
            self.terminal.processData(buffer[0..bytes_read]) catch |err| {
                std.log.warn("Terminal processing error: {any}", .{err});
            };

            std.log.info("Processed PTY output through terminal successfully", .{});
        } else {
            std.log.debug("PTY read returned 0 bytes", .{});
        }
    }

    /// Populate terminal buffer with initial content for testing
    fn populateInitialBuffer(self: *Self) void {
        std.log.info("Populating initial buffer with test content", .{});
        
        // Add a welcome message to the buffer
        const welcome_msg = "Zigline Terminal v0.3.0";
        const prompt = "$ ";
        
        // Write welcome message to first line
        var col: u32 = 0;
        for (welcome_msg) |char| {
            if (col < self.terminal.buffer.width) {
                self.terminal.buffer.setCell(col, 0, .{
                    .char = char,
                    .fg_color = .green,
                    .bg_color = .black,
                    .attributes = .{},
                });
                col += 1;
            }
        }
        
        // Write prompt to second line
        col = 0;
        for (prompt) |char| {
            if (col < self.terminal.buffer.width) {
                self.terminal.buffer.setCell(col, 1, .{
                    .char = char,
                    .fg_color = .white,
                    .bg_color = .black,
                    .attributes = .{},
                });
                col += 1;
            }
        }
        
        // Set cursor position
        self.terminal.cursor_x = @intCast(col);
        self.terminal.cursor_y = 1;
        
        std.log.info("Initial buffer populated with welcome message and prompt", .{});
    }
};
