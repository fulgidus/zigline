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
        
        var gui = Self{
            .allocator = allocator,
            .backend = backend,
            .window = window,
            .terminal = terminal,
            .input_processor = input_processor,
            .pty = pty, // Store pty
        };
        
        // Load Fira Code font
        try gui.loadFont();
        
        return gui;
    }
    
    /// Clean up GUI resources
    pub fn deinit(self: *Self) void {
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
                return;
            },
            else => return err,
        };
        
        // Register the font with DVUI - note: font_bytes ownership transfers to DVUI
        dvui.addFont("FiraCode", font_bytes, self.allocator) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.freetypeError => {
                self.allocator.free(font_bytes);
                std.log.warn("Failed to load Fira Code font: freetype error, falling back to system font", .{});
                return;
            },
        };
        
        self.font_loaded = true;
        std.log.info("Loaded Fira Code font successfully", .{});
    }
    
    /// Main GUI render loop
    pub fn run(self: *Self) !void {
        main_loop: while (true) {
            // Begin frame timing for variable framerate
            const nstime = self.window.beginWait(self.backend.hasEvent());
            
            // Mark beginning of DVUI frame
            try self.window.begin(nstime);
            
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
                else => {},
            }
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
        _ = try self.pty.write(text_event.text); // Changed to use pty.write
    }

    /// Convert DVUI key events to terminal byte sequences
    fn dvuiKeyToBytes(self: *Self, key_event: dvui.Event.Key) ![]const u8 {
        _ = self; // Mark as used
        _ = key_event; // Mark as used for now
        
        // For now, let text events handle most input
        // We'll implement special key handling after fixing the struct access
        return "";
    }
    
    /// Render the terminal interface using DVUI
    fn renderTerminal(self: *Self) !void {
        // Create main window area with black background
        var scroll = try dvui.scrollArea(@src(), .{}, .{ 
            .expand = .both, 
            .color_fill = .{ .color = .{ .r = 0x00, .g = 0x00, .b = 0x00 } } 
        });
        defer scroll.deinit();
        
        // Render terminal buffer
        try self.renderTerminalBuffer();
    }
    
    /// Render the terminal buffer content
    fn renderTerminalBuffer(self: *Self) !void {
        const buffer = self.terminal.getBuffer();
        const cursor_pos = buffer.getCursorPosition();
        _ = cursor_pos; // Mark as used for future cursor rendering
        
        // Use Fira Code font if loaded, otherwise fallback to system monospace
        const font_name = if (self.font_loaded) "FiraCode" else "monospace";
        
        // Create a monospace layout for terminal text
        var layout = try dvui.textLayout(@src(), .{}, .{
            .expand = .horizontal,
            .font_style = .{ .name = font_name, .size = self.font_size },
        });
        defer layout.deinit();
        
        // Render each line of the terminal buffer
        var row: u32 = 0;
        while (row < buffer.height) : (row += 1) {
            var line_text = std.ArrayList(u8).init(self.allocator);
            defer line_text.deinit();
            
            // Build line text
            var col: u32 = 0;
            while (col < buffer.width) : (col += 1) {
                const cell = buffer.getCell(row, col);
                try line_text.append(cell.char);
            }
            
            // Add the line to the layout
            try layout.addText(line_text.items, .{});
            try layout.addText("\n", .{});
        }
        
        // TODO: Render cursor at current position
        // This will need additional DVUI widgets or custom drawing
    }
};
