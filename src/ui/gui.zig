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
    should_exit: bool = false, // Exit flag for clean shutdown

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
        std.log.info("Starting GUI cleanup...", .{});

        // Ensure window is properly closed
        self.window.deinit();
        std.log.debug("DVUI window deinitialized", .{});

        // Force SDL cleanup if not already done
        _ = Backend.c.SDL_DestroyWindow(self.backend.window);
        self.backend.deinit();
        _ = Backend.c.SDL_QuitSubSystem(Backend.c.SDL_INIT_VIDEO);
        Backend.c.SDL_Quit();

        std.log.info("GUI cleanup complete", .{});
    }

    /// Main GUI render loop
    /// Handles events, rendering, and PTY communication
    pub fn run(self: *Self) !void {
        std.log.info("Starting main GUI render loop...", .{});

        main_loop: while (!self.should_exit) {
            // Increment frame counter for debugging
            self.frame_count += 1;

            // Log every frame to see what's happening with the loop
            if (self.frame_count <= 5 or self.frame_count % 30 == 0) {
                std.log.debug("GUI render loop active - frame {}", .{self.frame_count});
            }

            // Check if child process is still alive - exit if dead
            if (!self.pty.isChildAlive()) {
                std.log.warn("Child shell process has died - initiating shutdown", .{});
                self.should_exit = true;
                break :main_loop;
            }

            // Begin frame timing for variable framerate
            const nstime = self.window.beginWait(self.backend.hasEvent());

            // Mark beginning of DVUI frame
            try self.window.begin(nstime);

            // Read PTY output and process it (Phase 6) - catch errors to prevent hanging
            self.readPtyOutput() catch |err| {
                std.log.warn("PTY output read error: {any} - continuing", .{err});
            };

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
            if (quit) {
                std.log.info("Quit event received, setting exit flag", .{});
                self.should_exit = true;
                continue; // Continue to properly end the frame
            }

            // Check for DVUI close events and window size
            if (self.window.wd.rect.w == 0 or self.window.wd.rect.h == 0) {
                std.log.info("Window closed (zero dimensions), setting exit flag", .{});
                self.should_exit = true;
                continue; // Continue to properly end the frame
            }

            // Check for ESC key as additional quit method
            const events = dvui.events();
            for (events) |event| {
                switch (event.evt) {
                    .key => |key_event| {
                        if (key_event.action == .down and key_event.code == dvui.enums.Key.escape) {
                            // ESC key quits immediately for testing
                            std.log.info("ESC key detected - setting exit flag", .{});
                            self.should_exit = true;
                            continue; // Continue to properly end the frame
                        }
                    },
                    else => {},
                }
            }

            // If exit was requested, break after properly ending the frame
            if (self.should_exit) {
                std.log.info("Exit requested, ending frame and breaking loop", .{});

                // Properly end the DVUI frame before exiting
                _ = self.window.end(.{}) catch |err| {
                    std.log.warn("Error ending DVUI frame during shutdown: {any}", .{err});
                };

                break :main_loop;
            }

            // Handle DVUI input events and forward to terminal
            self.handleInput() catch |err| {
                std.log.warn("Input handling error: {any} - continuing", .{err});
            };

            // Clear the frame with a more visible background color
            _ = Backend.c.SDL_SetRenderDrawColor(self.backend.renderer, 50, 50, 50, 255);
            _ = Backend.c.SDL_RenderClear(self.backend.renderer);

            // Render the terminal interface using only colored boxes (no text to avoid SDL crashes)
            self.renderTerminalBoxes() catch |err| {
                std.log.warn("Terminal rendering error: {any} - continuing", .{err});
            };

            // End DVUI frame
            const end_micros = self.window.end(.{}) catch |err| blk: {
                std.log.warn("Error ending DVUI frame: {any} - continuing", .{err});
                break :blk 0; // Default to 0 if end() fails
            };

            // Handle cursor and text input
            self.backend.setCursor(self.window.cursorRequested());
            self.backend.textInputRect(self.window.textInputRequested());

            // Present the frame
            self.backend.renderPresent();

            // Wait for next frame
            const wait_event_micros = self.window.waitTime(end_micros, null);
            self.backend.waitEventTimeout(wait_event_micros);
        }

        std.log.info("Main loop exited, performing final cleanup...", .{});

        // Terminate PTY child process before GUI cleanup
        std.log.info("Terminating PTY child process...", .{});
        self.pty.terminateChild();

        // Perform final cleanup
        _ = Backend.c.SDL_DestroyWindow(self.backend.window);
        _ = Backend.c.SDL_QuitSubSystem(Backend.c.SDL_INIT_VIDEO);
        Backend.c.SDL_Quit();

        std.log.info("Final cleanup complete", .{});
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

        // Handle Ctrl combinations first - these are critical for terminal control
        if (key_event.mod.control()) {
            switch (key_event.code) {
                dvui.enums.Key.a => return "\x01", // Ctrl+A
                dvui.enums.Key.b => return "\x02", // Ctrl+B
                dvui.enums.Key.c => return "\x03", // Ctrl+C (SIGINT)
                dvui.enums.Key.d => return "\x04", // Ctrl+D (EOF)
                dvui.enums.Key.e => return "\x05", // Ctrl+E
                dvui.enums.Key.f => return "\x06", // Ctrl+F
                dvui.enums.Key.g => return "\x07", // Ctrl+G
                dvui.enums.Key.h => return "\x08", // Ctrl+H (Backspace)
                dvui.enums.Key.i => return "\x09", // Ctrl+I (Tab)
                dvui.enums.Key.j => return "\x0A", // Ctrl+J (Line Feed)
                dvui.enums.Key.k => return "\x0B", // Ctrl+K
                dvui.enums.Key.l => return "\x0C", // Ctrl+L (Clear screen)
                dvui.enums.Key.m => return "\x0D", // Ctrl+M (Carriage Return)
                dvui.enums.Key.n => return "\x0E", // Ctrl+N
                dvui.enums.Key.o => return "\x0F", // Ctrl+O
                dvui.enums.Key.p => return "\x10", // Ctrl+P
                dvui.enums.Key.q => return "\x11", // Ctrl+Q
                dvui.enums.Key.r => return "\x12", // Ctrl+R
                dvui.enums.Key.s => return "\x13", // Ctrl+S
                dvui.enums.Key.t => return "\x14", // Ctrl+T
                dvui.enums.Key.u => return "\x15", // Ctrl+U
                dvui.enums.Key.v => return "\x16", // Ctrl+V
                dvui.enums.Key.w => return "\x17", // Ctrl+W
                dvui.enums.Key.x => return "\x18", // Ctrl+X
                dvui.enums.Key.y => return "\x19", // Ctrl+Y
                dvui.enums.Key.z => return "\x1A", // Ctrl+Z (SIGTSTP)
                else => {},
            }
        }

        // Handle special keys (basic functionality without modifiers)
        switch (key_event.code) {
            dvui.enums.Key.enter => return "\r",
            dvui.enums.Key.backspace => return "\x7f",
            dvui.enums.Key.tab => return "\t",
            dvui.enums.Key.escape => {
                std.log.info("ESC key detected - this could be used to exit the application", .{});
                return "\x1b";
            },

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

            // Basic alphanumeric keys - only if no modifiers
            dvui.enums.Key.a => return if (key_event.mod == .none) "a" else "",
            dvui.enums.Key.b => return if (key_event.mod == .none) "b" else "",
            dvui.enums.Key.c => return if (key_event.mod == .none) "c" else "",
            dvui.enums.Key.d => return if (key_event.mod == .none) "d" else "",
            dvui.enums.Key.e => return if (key_event.mod == .none) "e" else "",
            dvui.enums.Key.f => return if (key_event.mod == .none) "f" else "",
            dvui.enums.Key.g => return if (key_event.mod == .none) "g" else "",
            dvui.enums.Key.h => return if (key_event.mod == .none) "h" else "",
            dvui.enums.Key.i => return if (key_event.mod == .none) "i" else "",
            dvui.enums.Key.j => return if (key_event.mod == .none) "j" else "",
            dvui.enums.Key.k => return if (key_event.mod == .none) "k" else "",
            dvui.enums.Key.l => return if (key_event.mod == .none) "l" else "",
            dvui.enums.Key.m => return if (key_event.mod == .none) "m" else "",
            dvui.enums.Key.n => return if (key_event.mod == .none) "n" else "",
            dvui.enums.Key.o => return if (key_event.mod == .none) "o" else "",
            dvui.enums.Key.p => return if (key_event.mod == .none) "p" else "",
            dvui.enums.Key.q => return if (key_event.mod == .none) "q" else "",
            dvui.enums.Key.r => return if (key_event.mod == .none) "r" else "",
            dvui.enums.Key.s => return if (key_event.mod == .none) "s" else "",
            dvui.enums.Key.t => return if (key_event.mod == .none) "t" else "",
            dvui.enums.Key.u => return if (key_event.mod == .none) "u" else "",
            dvui.enums.Key.v => return if (key_event.mod == .none) "v" else "",
            dvui.enums.Key.w => return if (key_event.mod == .none) "w" else "",
            dvui.enums.Key.x => return if (key_event.mod == .none) "x" else "",
            dvui.enums.Key.y => return if (key_event.mod == .none) "y" else "",
            dvui.enums.Key.z => return if (key_event.mod == .none) "z" else "",
            dvui.enums.Key.space => return " ",

            // Numbers
            dvui.enums.Key.zero => return "0",
            dvui.enums.Key.one => return "1",
            dvui.enums.Key.two => return "2",
            dvui.enums.Key.three => return "3",
            dvui.enums.Key.four => return "4",
            dvui.enums.Key.five => return "5",
            dvui.enums.Key.six => return "6",
            dvui.enums.Key.seven => return "7",
            dvui.enums.Key.eight => return "8",
            dvui.enums.Key.nine => return "9",

            // Control keys that don't produce output but are important for terminal
            dvui.enums.Key.left_control, dvui.enums.Key.right_control, dvui.enums.Key.left_shift, dvui.enums.Key.right_shift, dvui.enums.Key.left_alt, dvui.enums.Key.right_alt => return "",

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
        const status_text = try std.fmt.bufPrint(&status_buffer, "Terminal: {d} chars, Frame: {d}, Cursor: {d},{d}", .{ non_empty_count, self.frame_count, self.terminal.cursor_x, self.terminal.cursor_y });

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

            // Use a simple label instead of textEntry to avoid font texture issues
            if (line_text.len > 0) {
                try dvui.labelNoFmt(@src(), line_text, .{
                    .expand = .horizontal,
                });
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

            // Show a default shell prompt with simple label
            try dvui.labelNoFmt(@src(), "$ ", .{});
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
        const cursor_text = try std.fmt.bufPrint(&cursor_buffer, "Cursor: ({d},{d}) {s}", .{ self.terminal.cursor_x, self.terminal.cursor_y, if (cursor_visible) "█" else "_" });

        try dvui.labelNoFmt(@src(), cursor_text, .{});
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

        std.log.debug("Terminal: {d} lines with content, {d} total chars, cursor at ({d},{d})", .{ line_count, char_count, self.terminal.cursor_x, self.terminal.cursor_y });
    }

    /// Read output from PTY and process it through the terminal (Phase 6)
    fn readPtyOutput(self: *Self) !void {
        std.log.debug("readPtyOutput() called - checking for PTY data", .{});

        // First check if the child process is still alive
        if (!self.pty.isChildAlive()) {
            std.log.err("Child shell process has died! Terminating GUI.", .{});
            return; // This will eventually exit the main loop
        }

        // Then check if data is available (non-blocking check)
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

    /// Render the actual terminal interface with working text rendering
    fn renderTerminalVisual(self: *Self) !void {
        // Create main terminal container with black background like a real terminal
        var terminal_window = try dvui.box(@src(), .vertical, .{
            .expand = .both,
            .background = true,
            .color_fill = .{ .color = dvui.Color{ .r = 0, .g = 0, .b = 0 } }, // Black terminal background
            .margin = .{ .x = 5, .y = 5, .w = 5, .h = 5 },
            .id_extra = 20000,
        });
        defer terminal_window.deinit();

        // Try to render a simple text title first to test text rendering capabilities
        // Use a scroll area for the terminal content
        var scroll_area = try dvui.scrollArea(@src(), .{}, .{
            .expand = .both,
            .color_fill = .{ .color = dvui.Color{ .r = 0, .g = 0, .b = 0 } }, // Black background
        });
        defer scroll_area.deinit();

        // Terminal content container within scroll area
        var content_container = try dvui.box(@src(), .vertical, .{
            .expand = .horizontal,
            .min_size_content = .{ .h = 400 }, // Fixed height for now
            .padding = .{ .x = 10, .y = 10, .w = 10, .h = 10 },
        });
        defer content_container.deinit();

        // Since DVUI text rendering causes SDL texture crashes, use only box rendering
        // This provides a working terminal interface using colored rectangles to represent characters
        try self.renderTerminalWithBoxes();
    }

    /// Render terminal using colored boxes to represent characters (no text to avoid SDL crashes)
    fn renderTerminalWithBoxes(self: *Self) !void {
        const buffer = &self.terminal.buffer;
        
        // Create a grid of boxes to represent the terminal characters
        var grid_container = try dvui.box(@src(), .vertical, .{
            .expand = .both,
            .background = true,
            .color_fill = .{ .color = dvui.Color{ .r = 0, .g = 0, .b = 0 } }, // Black terminal background
            .padding = .{ .x = 5, .y = 5, .w = 5, .h = 5 },
        });
        defer grid_container.deinit();

        // Render rows of the terminal buffer
        for (0..@min(buffer.height, 20)) |row| {
            var row_container = try dvui.box(@src(), .horizontal, .{
                .expand = .horizontal,
                .min_size_content = .{ .h = 16 }, // Character height
                .id_extra = @as(u32, @intCast(row + 1000)), // Unique ID for each row
            });
            defer row_container.deinit();

            // Render each character position as a small box
            for (0..@min(buffer.width, 80)) |col| {
                const has_char = if (buffer.getCell(@intCast(col), @intCast(row))) |cell| cell.char > 0 and cell.char != ' ' else false;
                const is_cursor = (row == self.terminal.cursor_y and col == self.terminal.cursor_x);
                
                // Choose color based on content and cursor position
                const box_color = if (is_cursor and (self.frame_count / 30) % 2 == 0) 
                    dvui.Color{ .r = 255, .g = 255, .b = 0 } // Yellow cursor
                else if (has_char)
                    dvui.Color{ .r = 0, .g = 200, .b = 0 } // Green for characters
                else if (row < 3) // Show first few lines as slightly visible
                    dvui.Color{ .r = 20, .g = 20, .b = 20 } // Dark gray
                else
                    dvui.Color{ .r = 0, .g = 0, .b = 0 }; // Black for empty

                // Create a small box for each character position
                var char_box = try dvui.box(@src(), .horizontal, .{
                    .min_size_content = .{ .w = 8, .h = 14 }, // Character cell size
                    .background = has_char or is_cursor or row < 3,
                    .color_fill = .{ .color = box_color },
                    .margin = .{ .x = 1, .y = 0, .w = 0, .h = 1 },
                    .id_extra = @as(u32, @intCast(50000 + row * 100 + col)),
                });
                defer char_box.deinit();
            }
        }

        // Add a status indicator at the bottom using colored boxes
        var status_container = try dvui.box(@src(), .horizontal, .{
            .expand = .horizontal,
            .min_size_content = .{ .h = 20 },
            .margin = .{ .x = 0, .y = 10, .w = 0, .h = 0 },
        });
        defer status_container.deinit();

        // Status indicators using colored boxes (PTY alive, cursor position, etc.)
        const pty_alive = self.pty.isChildAlive();
        var pty_status_box = try dvui.box(@src(), .horizontal, .{
            .min_size_content = .{ .w = 20, .h = 15 },
            .background = true,
            .color_fill = .{ .color = if (pty_alive) 
                dvui.Color{ .r = 0, .g = 255, .b = 0 } // Green if alive
            else 
                dvui.Color{ .r = 255, .g = 0, .b = 0 } }, // Red if dead
            .margin = .{ .x = 5, .y = 0, .w = 5, .h = 0 },
            .id_extra = 60000,
        });
        defer pty_status_box.deinit();

        // Cursor position indicator
        var cursor_status_box = try dvui.box(@src(), .horizontal, .{
            .min_size_content = .{ .w = 30, .h = 15 },
            .background = true,
            .color_fill = .{ .color = dvui.Color{ .r = 100, .g = 100, .b = 255 } }, // Blue for cursor info
            .margin = .{ .x = 5, .y = 0, .w = 5, .h = 0 },
            .id_extra = 60001,
        });
        defer cursor_status_box.deinit();

        // Frame counter indicator
        var frame_status_box = try dvui.box(@src(), .horizontal, .{
            .min_size_content = .{ .w = 40, .h = 15 },
            .background = true,
            .color_fill = .{ .color = dvui.Color{ .r = 200, .g = 200, .b = 0 } }, // Yellow for frame info
            .margin = .{ .x = 5, .y = 0, .w = 5, .h = 0 },
            .id_extra = 60002,
        });
        defer frame_status_box.deinit();

        // Log status occasionally
        if (self.frame_count % 60 == 0) {
            std.log.info("Terminal rendered using boxes: cursor ({d},{d}), PTY alive: {}, frame: {d}", .{
                self.terminal.cursor_x, self.terminal.cursor_y, pty_alive, self.frame_count
            });
            
            // Log some buffer content
            var content_count: u32 = 0;
            for (0..@min(buffer.height, 5)) |row| {
                for (0..@min(buffer.width, 20)) |col| {
                    if (buffer.getCell(@intCast(col), @intCast(row))) |cell| {
                        if (cell.char > 0 and cell.char != ' ') {
                            content_count += 1;
                        }
                    }
                }
            }
            std.log.info("Terminal buffer has {d} non-empty characters in first 5 lines", .{content_count});
        }
    }

    /// Fallback rendering using colored boxes (current working method)
    fn renderTerminalBoxes(self: *Self) !void {
        const buffer = &self.terminal.buffer;
        var rendered_lines: u32 = 0;
        
        for (0..@min(buffer.height, 25)) |row| {
            var line_has_content = false;

            // Check if line has content
            for (0..@min(buffer.width, 120)) |col| {
                if (buffer.getCell(@intCast(col), @intCast(row))) |cell| {
                    if (cell.char > 0 and cell.char != ' ') {
                        line_has_content = true;
                        break;
                    }
                }
            }
            
            // Show line if it has content, or if it's cursor line, or first few lines
            if (line_has_content or row == self.terminal.cursor_y or row < 5) {
                // Create a line box to represent terminal text
                var line_box = try dvui.box(@src(), .horizontal, .{
                    .expand = .horizontal,
                    .min_size_content = .{ .w = 0, .h = 18 },
                    .background = true,
                    .color_fill = .{ 
                        .color = if (row == self.terminal.cursor_y)
                            dvui.Color{ .r = 50, .g = 50, .b = 100 } // Blue for cursor line
                        else if (line_has_content)
                            dvui.Color{ .r = 30, .g = 30, .b = 30 } // Dark gray for content
                        else
                            dvui.Color{ .r = 10, .g = 10, .b = 10 } // Very dark for empty lines
                    },
                    .margin = .{ .x = 0, .y = 1, .w = 0, .h = 1 },
                    .id_extra = @as(u32, @intCast(20010 + row)),
                });
                defer line_box.deinit();

                // Add cursor indicator as a small colored box
                if (row == self.terminal.cursor_y) {
                    const cursor_visible = (self.frame_count / 30) % 2 == 0;
                    if (cursor_visible) {
                        var cursor_box = try dvui.box(@src(), .horizontal, .{
                            .min_size_content = .{ .w = 10, .h = 16 },
                            .background = true,
                            .color_fill = .{ .color = dvui.Color{ .r = 255, .g = 255, .b = 0 } }, // Yellow cursor
                            .margin = .{ .x = @as(f32, @floatFromInt(self.terminal.cursor_x * 8)), .y = 0, .w = 0, .h = 0 },
                            .id_extra = @as(u32, @intCast(20050 + row)),
                        });
                        defer cursor_box.deinit();
                    }
                }
                
                rendered_lines += 1;
            }
        }

        // Status bar at bottom - simple colored box
        var status_bar = try dvui.box(@src(), .horizontal, .{
            .expand = .horizontal,
            .min_size_content = .{ .w = 0, .h = 25 },
            .background = true,
            .color_fill = .{ .color = dvui.Color{ .r = 40, .g = 40, .b = 40 } }, // Gray status bar
            .margin = .{ .x = 0, .y = 5, .w = 0, .h = 0 },
            .id_extra = 40000,
        });
        defer status_bar.deinit();
        // Log debug info occasionally - use std.log instead of labels to avoid font issues
        if (self.frame_count % 60 == 0) {
            std.log.info("Terminal UI: {d} lines rendered, cursor at ({d},{d}), PTY alive: {}", .{
                rendered_lines, self.terminal.cursor_x, self.terminal.cursor_y, self.pty.isChildAlive()
            });
            
            // Log some buffer content for debugging
            for (0..@min(buffer.height, 3)) |row| {
                var line_content: [81]u8 = undefined;
                var line_pos: usize = 0;

                for (0..@min(buffer.width, 80)) |col| {
                    if (buffer.getCell(@intCast(col), @intCast(row))) |cell| {
                        const char = if (cell.char > 0 and cell.char <= 127) @as(u8, @intCast(cell.char)) else ' ';
                        if (line_pos < line_content.len - 1) {
                            line_content[line_pos] = if (char >= 32) char else '?';
                            line_pos += 1;
                        }
                    }
                }
                
                if (line_pos > 0) {
                    line_content[line_pos] = 0;
                    std.log.info("Buffer Line {d}: '{s}'", .{ row, line_content[0..line_pos] });
                }
            }
        }
    }

    /// Simple terminal rendering WITHOUT text display (avoids SDL texture crash)
    fn renderTerminalText(self: *Self) !void {
        // Create main terminal container
        var terminal_container = try dvui.box(@src(), .vertical, .{
            .expand = .both,
            .background = true,
            .color_fill = .{ .color = dvui.Color{ .r = 0, .g = 0, .b = 0 } },
            .padding = .{ .x = 10, .y = 10, .w = 10, .h = 10 },
        });
        defer terminal_container.deinit();

        const buffer = &self.terminal.buffer;

        // TEMPORARILY DISABLED: Show terminal title - causes SDL texture crash
        // try dvui.labelNoFmt(@src(), "Zigline Terminal v0.3.0", .{
        //     .color_text = .{ .color = dvui.Color{ .r = 0, .g = 255, .b = 0 } }, // Green text
        //     .font_style = .title,
        // });
        
        // Show terminal title as a colored box instead
        var title_box = try dvui.box(@src(), .horizontal, .{
            .expand = .horizontal,
            .min_size_content = .{ .h = 30 },
            .background = true,
            .color_fill = .{ .color = dvui.Color{ .r = 0, .g = 100, .b = 0 } }, // Green title bar
            .margin = .{ .x = 0, .y = 0, .w = 0, .h = 10 },
        });
        defer title_box.deinit();

        // Render first 15 lines of terminal buffer
        for (0..@min(buffer.height, 15)) |row| {
            // Build line content
            var line_text: [128]u8 = undefined;
            var pos: usize = 0;
            var has_content = false;

            for (0..@min(buffer.width, 100)) |col| {
                if (buffer.getCell(@intCast(col), @intCast(row))) |cell| {
                    const char = if (cell.char == 0) ' ' else @as(u8, @intCast(@min(cell.char, 255)));
                    if (pos < line_text.len - 1) {
                        // Convert control characters to printable
                        line_text[pos] = if (char < 32 and char != 0) '?' else char;
                        pos += 1;
                        if (char != ' ' and char != 0) has_content = true;
                    }
                }
            }

            // Show line if it has content or is first few lines
            if (has_content or row < 3) {
                line_text[pos] = 0;
                // const line_str = line_text[0..pos]; // Unused since we're avoiding text rendering
                
                // Show line with cursor indicator if needed
                if (row == self.terminal.cursor_y) {
                    // Cursor line - show with green background
                    var cursor_line = try dvui.box(@src(), .horizontal, .{
                        .expand = .horizontal,
                        .background = true,
                        .color_fill = .{ .color = dvui.Color{ .r = 0, .g = 50, .b = 0 } },
                        .margin = .{ .x = 0, .y = 1, .w = 0, .h = 1 },
                    });
                    defer cursor_line.deinit();
                    
                    // TEMPORARILY DISABLED: Text rendering causes SDL crash
                    // try dvui.labelNoFmt(@src(), line_str, .{
                    //     .color_text = .{ .color = dvui.Color{ .r = 255, .g = 255, .b = 255 } },
                    //     .font_style = .heading,
                    // });
                    
                    // Show cursor position as colored box instead
                    var cursor_indicator = try dvui.box(@src(), .horizontal, .{
                        .min_size_content = .{ .w = 200, .h = 20 },
                        .background = true,
                        .color_fill = .{ .color = dvui.Color{ .r = 255, .g = 255, .b = 0 } }, // Yellow for cursor
                    });
                    defer cursor_indicator.deinit();
                } else {
                    // Normal line - show as colored box representing content
                    var line_indicator = try dvui.box(@src(), .horizontal, .{
                        .expand = .horizontal,
                        .min_size_content = .{ .h = 18 },
                        .background = true,
                        .color_fill = .{ .color = if (has_content) 
                            dvui.Color{ .r = 50, .g = 50, .b = 50 } // Gray for content
                        else 
                            dvui.Color{ .r = 20, .g = 20, .b = 20 } }, // Dark gray for empty
                    });
                    defer line_indicator.deinit();
                }
            } else if (row == 0) {
                // Always show first line even if empty - with a colored prompt indicator
                var prompt_box = try dvui.box(@src(), .horizontal, .{
                    .min_size_content = .{ .w = 50, .h = 18 },
                    .background = true,
                    .color_fill = .{ .color = dvui.Color{ .r = 0, .g = 255, .b = 0 } }, // Green prompt
                });
                defer prompt_box.deinit();
            }
        }        // Terminal status info - using colored boxes instead of text
        var status_box = try dvui.box(@src(), .horizontal, .{
            .expand = .horizontal,
            .min_size_content = .{ .h = 25 },
            .background = true,
            .color_fill = .{ .color = dvui.Color{ .r = 40, .g = 40, .b = 40 } }, // Gray status bar
        });
        defer status_box.deinit();
        
        // Status indicators using colored boxes
        const pty_alive = self.pty.isChildAlive();
        var pty_indicator = try dvui.box(@src(), .horizontal, .{
            .min_size_content = .{ .w = 30, .h = 20 },
            .background = true,
            .color_fill = .{ .color = if (pty_alive) 
                dvui.Color{ .r = 0, .g = 255, .b = 0 } // Green if PTY alive
            else 
                dvui.Color{ .r = 255, .g = 0, .b = 0 } }, // Red if dead
            .margin = .{ .x = 5, .y = 2, .w = 5, .h = 2 },
        });
        defer pty_indicator.deinit();

        // Frame counter indicator  
        var frame_indicator = try dvui.box(@src(), .horizontal, .{
            .min_size_content = .{ .w = 40, .h = 20 },
            .background = true,
            .color_fill = .{ .color = dvui.Color{ .r = 100, .g = 100, .b = 255 } }, // Blue
            .margin = .{ .x = 5, .y = 2, .w = 5, .h = 2 },
        });
        defer frame_indicator.deinit();
    }

    // ...existing code...
};
