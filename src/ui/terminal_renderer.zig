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

    /// Render a single line of the terminal buffer with color and style
    fn renderLine(self: *Self, src: std.builtin.SourceLocation, row: usize) !void {
        var line_box = try dvui.box(src, .horizontal, .{
            .expand = .horizontal,
            .min_size_content = .{ .h = self.font_size + self.line_spacing },
        });
        defer line_box.deinit();

        var col: usize = 0;
        while (col < self.buffer.width) {
            if (self.buffer.getCell(@intCast(col), @intCast(row))) |cell| {
                // Map terminal color to DVUI color
                const fg = colorToDvui(cell.fg_color);
                const bg = colorToDvui(cell.bg_color);

                // Render each character as a label with its style
                const char_byte = @as(u8, @intCast(@min(cell.char, 255)));
                const char_bytes = [_]u8{char_byte};
                try dvui.labelNoFmt(src, &char_bytes, .{
                    .font_style = .{ .size = self.font_size },
                    .color_text = .{ .color = fg },
                    .color_fill = .{ .color = bg },
                    .expand = .none,
                });
            }
            col += 1;
        }
    }

    /// Map terminal buffer color to DVUI color
    fn colorToDvui(color: terminal.TerminalBuffer.Color) dvui.Color {
        return switch (color) {
            .black => dvui.Color{ .r = 0, .g = 0, .b = 0 },
            .red => dvui.Color{ .r = 205, .g = 49, .b = 49 },
            .green => dvui.Color{ .r = 13, .g = 188, .b = 121 },
            .yellow => dvui.Color{ .r = 229, .g = 229, .b = 16 },
            .blue => dvui.Color{ .r = 36, .g = 114, .b = 200 },
            .magenta => dvui.Color{ .r = 188, .g = 63, .b = 188 },
            .cyan => dvui.Color{ .r = 17, .g = 168, .b = 205 },
            .white => dvui.Color{ .r = 229, .g = 229, .b = 229 },
            .bright_black => dvui.Color{ .r = 102, .g = 102, .b = 102 },
            .bright_red => dvui.Color{ .r = 241, .g = 76, .b = 76 },
            .bright_green => dvui.Color{ .r = 35, .g = 209, .b = 139 },
            .bright_yellow => dvui.Color{ .r = 245, .g = 245, .b = 67 },
            .bright_blue => dvui.Color{ .r = 59, .g = 142, .b = 234 },
            .bright_magenta => dvui.Color{ .r = 214, .g = 112, .b = 214 },
            .bright_cyan => dvui.Color{ .r = 41, .g = 184, .b = 219 },
            .bright_white => dvui.Color{ .r = 255, .g = 255, .b = 255 },
        };
    }

    /// Render the cursor at its current position
    fn renderCursor(self: *Self, src: std.builtin.SourceLocation) !void {
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
        _ = self; // Self not used in this simple implementation

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
