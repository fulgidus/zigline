const std = @import("std");

/// Terminal buffer for managing the screen content
pub const TerminalBuffer = struct {
    width: u32,
    height: u32,
    cells: []Cell,
    allocator: std.mem.Allocator,

    /// A single cell in the terminal buffer
    pub const Cell = struct {
        char: u21 = ' ',
        fg_color: Color = Color.white,
        bg_color: Color = Color.black,
        attributes: Attributes = Attributes{},
    };

    /// Color representation for terminal cells
    pub const Color = enum {
        black,
        red,
        green,
        yellow,
        blue,
        magenta,
        cyan,
        white,
        bright_black,
        bright_red,
        bright_green,
        bright_yellow,
        bright_blue,
        bright_magenta,
        bright_cyan,
        bright_white,

        /// Convert color to ANSI escape sequence
        pub fn toAnsi(self: Color, background: bool) []const u8 {
            return switch (self) {
                .black => if (background) "\x1b[40m" else "\x1b[30m",
                .red => if (background) "\x1b[41m" else "\x1b[31m",
                .green => if (background) "\x1b[42m" else "\x1b[32m",
                .yellow => if (background) "\x1b[43m" else "\x1b[33m",
                .blue => if (background) "\x1b[44m" else "\x1b[34m",
                .magenta => if (background) "\x1b[45m" else "\x1b[35m",
                .cyan => if (background) "\x1b[46m" else "\x1b[36m",
                .white => if (background) "\x1b[47m" else "\x1b[37m",
                .bright_black => if (background) "\x1b[100m" else "\x1b[90m",
                .bright_red => if (background) "\x1b[101m" else "\x1b[91m",
                .bright_green => if (background) "\x1b[102m" else "\x1b[92m",
                .bright_yellow => if (background) "\x1b[103m" else "\x1b[93m",
                .bright_blue => if (background) "\x1b[104m" else "\x1b[94m",
                .bright_magenta => if (background) "\x1b[105m" else "\x1b[95m",
                .bright_cyan => if (background) "\x1b[106m" else "\x1b[96m",
                .bright_white => if (background) "\x1b[107m" else "\x1b[97m",
            };
        }
    };

    /// Text attributes for terminal cells
    pub const Attributes = struct {
        bold: bool = false,
        italic: bool = false,
        underline: bool = false,
        strikethrough: bool = false,
        reverse: bool = false,

        /// Convert attributes to ANSI escape sequence
        pub fn toAnsi(self: Attributes) []const u8 {
            // TODO: Implement proper attribute combination
            _ = self;
            return "";
        }
    };

    /// Initialize a new terminal buffer
    pub fn init(allocator: std.mem.Allocator, width: u32, height: u32) !TerminalBuffer {
        const total_cells = width * height;
        const cells = try allocator.alloc(Cell, total_cells);

        // Initialize all cells with default values
        for (cells) |*cell| {
            cell.* = Cell{};
        }

        return TerminalBuffer{
            .width = width,
            .height = height,
            .cells = cells,
            .allocator = allocator,
        };
    }

    /// Deinitialize the terminal buffer
    pub fn deinit(self: *TerminalBuffer) void {
        self.allocator.free(self.cells);
    }

    /// Get a cell at the specified position
    pub fn getCell(self: *const TerminalBuffer, x: u32, y: u32) ?*const Cell {
        if (x >= self.width or y >= self.height) return null;
        const index = y * self.width + x;
        return &self.cells[index];
    }

    /// Set a cell at the specified position
    pub fn setCell(self: *TerminalBuffer, x: u32, y: u32, cell: Cell) void {
        if (x >= self.width or y >= self.height) return;
        const index = y * self.width + x;
        self.cells[index] = cell;
    }

    /// Set a character at the specified position
    pub fn setChar(self: *TerminalBuffer, x: u32, y: u32, char: u8) void {
        if (self.getCellMut(x, y)) |cell| {
            cell.char = char;
        }
    }

    /// Get a mutable cell at the specified position
    pub fn getCellMut(self: *TerminalBuffer, x: u32, y: u32) ?*Cell {
        if (x >= self.width or y >= self.height) return null;
        const index = y * self.width + x;
        return &self.cells[index];
    }

    /// Clear the entire buffer
    pub fn clear(self: *TerminalBuffer) void {
        for (self.cells) |*cell| {
            cell.* = Cell{};
        }
    }

    /// Resize the terminal buffer
    pub fn resize(self: *TerminalBuffer, new_width: u32, new_height: u32) !void {
        const new_total_cells = new_width * new_height;
        const new_cells = try self.allocator.alloc(Cell, new_total_cells);

        // Initialize new cells
        for (new_cells) |*cell| {
            cell.* = Cell{};
        }

        // Copy existing content if possible
        const copy_width = @min(self.width, new_width);
        const copy_height = @min(self.height, new_height);

        for (0..copy_height) |y| {
            for (0..copy_width) |x| {
                const old_index = y * self.width + x;
                const new_index = y * new_width + x;
                new_cells[new_index] = self.cells[old_index];
            }
        }

        // Replace old buffer
        self.allocator.free(self.cells);
        self.cells = new_cells;
        self.width = new_width;
        self.height = new_height;
    }

    /// Scroll the buffer up by one line
    pub fn scrollUp(self: *TerminalBuffer) void {
        // Move all lines up by one
        const line_size = self.width;
        var y: u32 = 1;
        while (y < self.height) : (y += 1) {
            const src_start = y * line_size;
            const dst_start = (y - 1) * line_size;
            @memcpy(self.cells[dst_start .. dst_start + line_size], self.cells[src_start .. src_start + line_size]);
        }

        // Clear the last line
        const last_line_start = (self.height - 1) * line_size;
        for (self.cells[last_line_start .. last_line_start + line_size]) |*cell| {
            cell.* = Cell{};
        }
    }

    /// Clear from cursor to end of screen
    pub fn clearFromCursor(self: *TerminalBuffer, cursor_x: u32, cursor_y: u32) void {
        // Clear from cursor to end of current line
        self.clearLineFromCursor(cursor_x, cursor_y);

        // Clear all lines below current line
        var y = cursor_y + 1;
        while (y < self.height) : (y += 1) {
            self.clearLine(y);
        }
    }

    /// Clear from start of screen to cursor
    pub fn clearToCursor(self: *TerminalBuffer, cursor_x: u32, cursor_y: u32) void {
        // Clear all lines above current line
        var y: u32 = 0;
        while (y < cursor_y) : (y += 1) {
            self.clearLine(y);
        }

        // Clear from start of current line to cursor
        self.clearLineToCursor(cursor_x, cursor_y);
    }

    /// Clear entire screen
    pub fn clearAll(self: *TerminalBuffer) void {
        for (self.cells) |*cell| {
            cell.* = Cell{};
        }
    }

    /// Clear from cursor to end of line
    pub fn clearLineFromCursor(self: *TerminalBuffer, cursor_x: u32, cursor_y: u32) void {
        if (cursor_y >= self.height) return;
        var x = cursor_x;
        while (x < self.width) : (x += 1) {
            if (self.getCellMut(x, cursor_y)) |cell| {
                cell.* = Cell{};
            }
        }
    }

    /// Clear from start of line to cursor
    pub fn clearLineToCursor(self: *TerminalBuffer, cursor_x: u32, cursor_y: u32) void {
        if (cursor_y >= self.height) return;
        var x: u32 = 0;
        while (x <= cursor_x and x < self.width) : (x += 1) {
            if (self.getCellMut(x, cursor_y)) |cell| {
                cell.* = Cell{};
            }
        }
    }

    /// Clear entire line
    pub fn clearLine(self: *TerminalBuffer, y: u32) void {
        if (y >= self.height) return;
        var x: u32 = 0;
        while (x < self.width) : (x += 1) {
            if (self.getCellMut(x, y)) |cell| {
                cell.* = Cell{};
            }
        }
    }

    /// Apply graphics mode (colors and attributes)
    pub fn applyGraphicsMode(self: *TerminalBuffer, code: u32, cursor_x: u32, cursor_y: u32) void {
        _ = self;
        _ = code;
        _ = cursor_x;
        _ = cursor_y;
        // TODO: Implement graphics mode application
        // This would set colors and attributes for future text
    }
};

// Tests
test "terminal buffer initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var buffer = try TerminalBuffer.init(allocator, 80, 24);
    defer buffer.deinit();

    try testing.expect(buffer.width == 80);
    try testing.expect(buffer.height == 24);
    try testing.expect(buffer.cells.len == 80 * 24);
}

test "terminal buffer cell access" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var buffer = try TerminalBuffer.init(allocator, 10, 10);
    defer buffer.deinit();

    const test_cell = TerminalBuffer.Cell{
        .char = 'A',
        .fg_color = TerminalBuffer.Color.red,
    };

    buffer.setCell(5, 5, test_cell);

    if (buffer.getCell(5, 5)) |cell| {
        try testing.expect(cell.char == 'A');
        try testing.expect(cell.fg_color == TerminalBuffer.Color.red);
    } else {
        try testing.expect(false); // Should not happen
    }
}
