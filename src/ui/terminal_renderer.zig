//! Terminal renderer using DVUI
//! Renders the terminal buffer content to a GUI window

const std = @import("std");
const dvui = @import("dvui");
const terminal = @import("../terminal/buffer.zig");
const ansi = @import("../terminal/ansi.zig");

/// Terminal renderer for DVUI
pub const TerminalRenderer = struct {
    /// Terminal buffer to render
    buffer: *terminal.TerminalBuffer,
    /// Font size for terminal text
    font_size: f32 = 16.0,
    /// Character spacing
    char_spacing: f32 = 1.0,
    /// Line spacing
    line_spacing: f32 = 1.0,

    const Self = @This();

    /// Initialize the terminal renderer
    pub fn init(buffer: *terminal.TerminalBuffer) Self {
        return Self{
            .buffer = buffer,
        };
    }

    /// Render the terminal buffer to the current DVUI context
    pub fn render(self: *Self, src: std.builtin.SourceLocation) !void {
        // Create a scroll area for the terminal content
        var scroll = try dvui.scrollArea(src, .{}, .{ 
            .expand = .both, 
            .color_fill = .{ .color = .{ .r = 0, .g = 0, .b = 0 } }, // Black background
        });
        defer scroll.deinit();

        // Create a box for the terminal content
        var terminal_box = try dvui.box(src, .vertical, .{ 
            .expand = .both,
            .padding = .{ .x = 4, .y = 4 },
        });
        defer terminal_box.deinit();

        // Render each line of the terminal buffer
        for (0..self.buffer.height) |row| {
            try self.renderLine(src, row);
        }

        // Render cursor if visible
        if (self.buffer.cursor_visible) {
            try self.renderCursor(src);
        }
    }

    /// Render a single line of the terminal buffer
    fn renderLine(self: *Self, src: std.builtin.SourceLocation, row: usize) !void {
        var line_box = try dvui.box(src, .horizontal, .{ 
            .expand = .horizontal,
            .min_size_content = .{ .h = self.font_size + self.line_spacing },
        });
        defer line_box.deinit();

        // Build the line text and collect style information
        var line_text = std.ArrayList(u8).init(std.heap.page_allocator);
        defer line_text.deinit();

        var col: usize = 0;
        while (col < self.buffer.width) {
            const cell = self.buffer.getCell(col, row);
            
            // Add character to line text
            const char_bytes = [_]u8{cell.char};
            try line_text.appendSlice(&char_bytes);
            
            col += 1;
        }

        // Render the line as a single text label for now
        // TODO: Implement proper color and style rendering per character
        const line_str = try line_text.toOwnedSlice();
        defer std.heap.page_allocator.free(line_str);

        try dvui.labelNoFmt(src, line_str, .{
            .font_style = .{ .size = self.font_size },
            .color_text = .{ .color = .{ .r = 255, .g = 255, .b = 255 } }, // White text
            .expand = .horizontal,
        });
    }

    /// Render the cursor at its current position
    fn renderCursor(self: *Self, src: std.builtin.SourceLocation) !void {
        // For now, we'll render the cursor as a simple overlay
        // This is a simplified implementation - in a full terminal emulator,
        // you'd want to position the cursor precisely over the character
        
        // Calculate cursor position (simplified)
        const cursor_x = @as(f32, @floatFromInt(self.buffer.cursor_x)) * self.font_size * 0.6; // Approximate char width
        const cursor_y = @as(f32, @floatFromInt(self.buffer.cursor_y)) * (self.font_size + self.line_spacing);

        // Create a cursor overlay (simplified implementation)
        var cursor_overlay = try dvui.overlay(src, .{
            .min_size_content = .{ .w = 2, .h = self.font_size },
        });
        defer cursor_overlay.deinit();

        // Draw cursor as a vertical line
        try dvui.box(src, .vertical, .{
            .background = true,
            .color_fill = .{ .color = .{ .r = 255, .g = 255, .b = 255 } }, // White cursor
            .min_size_content = .{ .w = 2, .h = self.font_size },
        });
    }

    /// Handle window resize events
    pub fn handleResize(self: *Self, new_width: u32, new_height: u32) !void {
        // Calculate new terminal dimensions based on character size
        const char_width = self.font_size * 0.6; // Approximate character width
        const char_height = self.font_size + self.line_spacing;
        
        const cols = @as(usize, @intFromFloat(@as(f32, @floatFromInt(new_width)) / char_width));
        const rows = @as(usize, @intFromFloat(@as(f32, @floatFromInt(new_height)) / char_height));
        
        // Resize the terminal buffer
        try self.buffer.resize(cols, rows);
    }

    /// Convert DVUI input events to terminal input
    pub fn handleInput(self: *Self, event: dvui.Event) ?[]const u8 {
        _ = self;
        
        switch (event.evt) {
            .key => |key_event| {
                if (key_event.action == .down or key_event.action == .repeat) {
                    return self.keyToTerminalInput(key_event);
                }
            },
            .text => |text_event| {
                return text_event.text;
            },
            else => {},
        }
        
        return null;
    }

    /// Convert DVUI key events to terminal input sequences
    fn keyToTerminalInput(self: *Self, key_event: dvui.Event.Key) ?[]const u8 {
        _ = self;
        
        // Convert common keys to ANSI escape sequences
        switch (key_event.key) {
            .up => return "\x1B[A",
            .down => return "\x1B[B",
            .right => return "\x1B[C",
            .left => return "\x1B[D",
            .home => return "\x1B[H",
            .end => return "\x1B[F",
            .page_up => return "\x1B[5~",
            .page_down => return "\x1B[6~",
            .delete => return "\x1B[3~",
            .backspace => return "\x08",
            .tab => return "\t",
            .enter => return "\r",
            .escape => return "\x1B",
            else => {
                // For other keys, we'll rely on the text event
                return null;
            },
        }
    }
};
