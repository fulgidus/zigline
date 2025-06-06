//! Simple Raylib-based GUI for Zigline terminal emulator
//! This replaces the complex DVUI implementation with a simple, working solution

const std = @import("std");
const rl = @import("raylib");
const Terminal = @import("../core/terminal.zig").Terminal;
const PTY = @import("../core/pty.zig").PTY;

pub const RaylibGui = struct {
    allocator: std.mem.Allocator,
    terminal: *Terminal,
    pty: *PTY,

    // Window settings
    width: i32 = 1200,
    height: i32 = 800,

    // Font settings
    font_size: i32 = 16,
    char_width: f32 = 9.0,
    char_height: f32 = 16.0,

    // Terminal display settings
    cols: u32 = 120,
    rows: u32 = 40,

    // State
    should_exit: bool = false,
    frame_count: u64 = 0,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, terminal: *Terminal, pty: *PTY) Self {
        return Self{
            .allocator = allocator,
            .terminal = terminal,
            .pty = pty,
        };
    }

    pub fn run(self: *Self) !void {
        // Initialize Raylib window
        rl.initWindow(self.width, self.height, "Zigline Terminal");
        defer rl.closeWindow();

        rl.setTargetFPS(60);
        std.log.info("Raylib window initialized successfully", .{});

        // Main loop
        while (!rl.windowShouldClose() and !self.should_exit) {
            self.frame_count += 1;

            // Handle input
            try self.handleInput();

            // Read PTY output
            try self.readPtyOutput();

            // Render
            self.render();

            // Check if child process died
            if (!self.pty.isChildAlive()) {
                std.log.warn("Child process died, exiting", .{});
                self.should_exit = true;
            }
        }

        std.log.info("Raylib GUI exiting gracefully", .{});
    }

    fn handleInput(self: *Self) !void {
        // Handle keyboard input
        const key = rl.getKeyPressed();
        if (key != .null) {
            const key_data = try self.convertKeyToBytes(key);
            if (key_data.len > 0) {
                _ = try self.pty.write(key_data);
                std.log.debug("Sent key to PTY: '{s}'", .{key_data});
            }
        }

        // Handle text input
        const char = rl.getCharPressed();
        if (char != 0) {
            var char_buffer: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(@intCast(char), &char_buffer) catch 1;
            _ = try self.pty.write(char_buffer[0..len]);
            std.log.debug("Sent char to PTY: '{c}'", .{@as(u8, @intCast(char))});
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
        if (!self.pty.hasData()) return;

        var buffer: [4096]u8 = undefined;
        const bytes_read = self.pty.read(buffer[0..]) catch |err| switch (err) {
            error.WouldBlock => return,
            else => {
                std.log.warn("PTY read error: {any}", .{err});
                return;
            },
        };

        if (bytes_read > 0) {
            std.log.debug("Read {} bytes from PTY", .{bytes_read});
            try self.terminal.processData(buffer[0..bytes_read]);
        }
    }

    fn render(self: *Self) void {
        rl.beginDrawing();
        defer rl.endDrawing();

        // Clear with black background
        rl.clearBackground(rl.Color.black);

        // Render terminal content
        self.renderTerminalContent();

        // Render cursor
        self.renderCursor();

        // Render status info
        self.renderStatus();
    }

    fn renderTerminalContent(self: *Self) void {
        const buffer = &self.terminal.buffer;

        // Render each character in the terminal buffer
        for (0..@min(buffer.height, self.rows)) |row| {
            for (0..@min(buffer.width, self.cols)) |col| {
                if (buffer.getCell(@intCast(col), @intCast(row))) |cell| {
                    if (cell.char > 0 and cell.char != ' ') {
                        const x = @as(f32, @floatFromInt(col)) * self.char_width + 10;
                        const y = @as(f32, @floatFromInt(row)) * self.char_height + 10;

                        // Convert cell.char (u21) to a string for drawing
                        var char_buffer: [4]u8 = undefined;
                        const len = std.unicode.utf8Encode(cell.char, &char_buffer) catch 1;
                        char_buffer[len] = 0; // Null terminate

                        // Convert color
                        const color = self.convertColor(cell.fg_color);

                        rl.drawText(@ptrCast(&char_buffer), @intFromFloat(x), @intFromFloat(y), self.font_size, color);
                    }
                }
            }
        }
    }

    fn renderCursor(self: *Self) void {
        // Blinking cursor
        if ((self.frame_count / 30) % 2 == 0) {
            const x = @as(f32, @floatFromInt(self.terminal.cursor_x)) * self.char_width + 10;
            const y = @as(f32, @floatFromInt(self.terminal.cursor_y)) * self.char_height + 10;

            rl.drawRectangle(@intFromFloat(x), @intFromFloat(y), @intFromFloat(self.char_width), @intFromFloat(self.char_height), rl.Color.yellow);
        }
    }

    fn renderStatus(self: *Self) void {
        // Status line at bottom
        const status_y = self.height - 25;

        // PTY status
        const pty_color = if (self.pty.isChildAlive()) rl.Color.green else rl.Color.red;
        rl.drawText("PTY", 10, status_y, 12, pty_color);

        // Cursor position
        var pos_buffer: [32]u8 = undefined;
        const pos_text = std.fmt.bufPrintZ(&pos_buffer, "Cursor: {d},{d}", .{ self.terminal.cursor_x, self.terminal.cursor_y }) catch "Cursor: ?";
        rl.drawText(@ptrCast(pos_text), 60, status_y, 12, rl.Color.white);

        // Frame counter
        var frame_buffer: [32]u8 = undefined;
        const frame_text = std.fmt.bufPrintZ(&frame_buffer, "Frame: {d}", .{self.frame_count}) catch "Frame: ?";
        rl.drawText(@ptrCast(frame_text), 200, status_y, 12, rl.Color.gray);
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
            else => rl.Color.white,
        };
    }
};
