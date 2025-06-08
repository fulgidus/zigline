// Unit tests for terminal buffer behavior
// Tests buffer operations, character storage, scrolling, and cell manipulation

const std = @import("std");
const testing = std.testing;
const TerminalBuffer = @import("buffer").TerminalBuffer;
const Cell = TerminalBuffer.Cell;
const Color = TerminalBuffer.Color;
const Attributes = TerminalBuffer.Attributes;

test "terminal buffer initialization and basic properties" {
    const allocator = testing.allocator;

    var buffer = try TerminalBuffer.init(allocator, 80, 24);
    defer buffer.deinit();

    try testing.expect(buffer.width == 80);
    try testing.expect(buffer.height == 24);
    try testing.expect(buffer.cells.len == 80 * 24);

    // All cells should be initialized with default values
    for (buffer.cells) |cell| {
        try testing.expect(cell.char == ' ');
        try testing.expect(cell.fg_color == Color.white);
        try testing.expect(cell.bg_color == Color.black);
        try testing.expect(cell.attributes.bold == false);
        try testing.expect(cell.attributes.italic == false);
    }
}

test "terminal buffer cell access and modification" {
    const allocator = testing.allocator;

    var buffer = try TerminalBuffer.init(allocator, 10, 10);
    defer buffer.deinit();

    // Test basic cell setting and getting
    const test_cell = Cell{
        .char = 'X',
        .fg_color = Color.red,
        .bg_color = Color.blue,
        .attributes = Attributes{ .bold = true, .underline = true },
    };

    buffer.setCell(5, 5, test_cell);

    if (buffer.getCell(5, 5)) |cell| {
        try testing.expect(cell.char == 'X');
        try testing.expect(cell.fg_color == Color.red);
        try testing.expect(cell.bg_color == Color.blue);
        try testing.expect(cell.attributes.bold == true);
        try testing.expect(cell.attributes.underline == true);
    } else {
        try testing.expect(false); // Should not happen
    }

    // Test setChar function
    buffer.setChar(3, 3, 'Y');
    if (buffer.getCell(3, 3)) |cell| {
        try testing.expect(cell.char == 'Y');
    } else {
        try testing.expect(false);
    }
}

test "terminal buffer bounds checking" {
    const allocator = testing.allocator;

    var buffer = try TerminalBuffer.init(allocator, 5, 5);
    defer buffer.deinit();

    // Test out-of-bounds access returns null
    try testing.expect(buffer.getCell(5, 0) == null); // x out of bounds
    try testing.expect(buffer.getCell(0, 5) == null); // y out of bounds
    try testing.expect(buffer.getCell(10, 10) == null); // both out of bounds

    // Test out-of-bounds setCell doesn't crash (should be ignored)
    buffer.setCell(10, 10, Cell{ .char = 'Z' });
    buffer.setChar(10, 10, 'A');

    // Verify buffer wasn't corrupted
    if (buffer.getCell(0, 0)) |cell| {
        try testing.expect(cell.char == ' '); // Should still be default
    }
}

test "terminal buffer scrolling up" {
    const allocator = testing.allocator;

    var buffer = try TerminalBuffer.init(allocator, 5, 5);
    defer buffer.deinit();

    // Fill buffer with identifiable pattern
    var y: u32 = 0;
    while (y < 5) : (y += 1) {
        var x: u32 = 0;
        while (x < 5) : (x += 1) {
            buffer.setChar(x, y, @as(u8, @intCast('0' + y)));
        }
    }

    // Verify initial state
    if (buffer.getCell(0, 0)) |cell| try testing.expect(cell.char == '0');
    if (buffer.getCell(0, 4)) |cell| try testing.expect(cell.char == '4');

    // Scroll up by one line
    buffer.scrollUp();

    // Verify that line 0 now contains what was line 1
    if (buffer.getCell(0, 0)) |cell| try testing.expect(cell.char == '1');
    if (buffer.getCell(0, 1)) |cell| try testing.expect(cell.char == '2');
    if (buffer.getCell(0, 2)) |cell| try testing.expect(cell.char == '3');
    if (buffer.getCell(0, 3)) |cell| try testing.expect(cell.char == '4');

    // Last line should be cleared (default space)
    if (buffer.getCell(0, 4)) |cell| try testing.expect(cell.char == ' ');
}

test "terminal buffer clear operations" {
    const allocator = testing.allocator;

    var buffer = try TerminalBuffer.init(allocator, 10, 10);
    defer buffer.deinit();

    // Fill buffer with test pattern
    var y: u32 = 0;
    while (y < 10) : (y += 1) {
        var x: u32 = 0;
        while (x < 10) : (x += 1) {
            buffer.setChar(x, y, 'A');
        }
    }

    // Test clearAll
    buffer.clearAll();
    for (buffer.cells) |cell| {
        try testing.expect(cell.char == ' ');
    }

    // Refill buffer
    y = 0;
    while (y < 10) : (y += 1) {
        var x: u32 = 0;
        while (x < 10) : (x += 1) {
            buffer.setChar(x, y, 'B');
        }
    }

    // Test clearLine
    buffer.clearLine(5);

    // Line 5 should be cleared
    var x: u32 = 0;
    while (x < 10) : (x += 1) {
        if (buffer.getCell(x, 5)) |cell| try testing.expect(cell.char == ' ');
    }

    // Other lines should be unchanged
    if (buffer.getCell(0, 4)) |cell| try testing.expect(cell.char == 'B');
    if (buffer.getCell(0, 6)) |cell| try testing.expect(cell.char == 'B');
}

test "terminal buffer partial clear operations" {
    const allocator = testing.allocator;

    var buffer = try TerminalBuffer.init(allocator, 10, 5);
    defer buffer.deinit();

    // Fill with test pattern
    var y: u32 = 0;
    while (y < 5) : (y += 1) {
        var x: u32 = 0;
        while (x < 10) : (x += 1) {
            buffer.setChar(x, y, 'X');
        }
    }

    // Test clearLineFromCursor (cursor at 5, 2)
    buffer.clearLineFromCursor(5, 2);

    // Characters from position 5 onwards on line 2 should be cleared
    var x: u32 = 0;
    while (x < 5) : (x += 1) {
        if (buffer.getCell(x, 2)) |cell| try testing.expect(cell.char == 'X');
    }
    x = 5;
    while (x < 10) : (x += 1) {
        if (buffer.getCell(x, 2)) |cell| try testing.expect(cell.char == ' ');
    }

    // Refill line 2
    x = 0;
    while (x < 10) : (x += 1) {
        buffer.setChar(x, 2, 'Y');
    }

    // Test clearLineToCursor (cursor at 5, 2)
    buffer.clearLineToCursor(5, 2);

    // Characters from position 0 to 5 on line 2 should be cleared
    x = 0;
    while (x <= 5) : (x += 1) {
        if (buffer.getCell(x, 2)) |cell| try testing.expect(cell.char == ' ');
    }
    x = 6;
    while (x < 10) : (x += 1) {
        if (buffer.getCell(x, 2)) |cell| try testing.expect(cell.char == 'Y');
    }
}

test "terminal buffer screen clear operations" {
    const allocator = testing.allocator;

    var buffer = try TerminalBuffer.init(allocator, 5, 5);
    defer buffer.deinit();

    // Fill with test pattern
    var y: u32 = 0;
    while (y < 5) : (y += 1) {
        var x: u32 = 0;
        while (x < 5) : (x += 1) {
            buffer.setChar(x, y, 'Z');
        }
    }

    // Test clearFromCursor (cursor at 2, 2)
    buffer.clearFromCursor(2, 2);

    // Lines above cursor should be unchanged
    if (buffer.getCell(0, 0)) |cell| try testing.expect(cell.char == 'Z');
    if (buffer.getCell(0, 1)) |cell| try testing.expect(cell.char == 'Z');

    // Current line from cursor onwards should be cleared
    if (buffer.getCell(0, 2)) |cell| try testing.expect(cell.char == 'Z');
    if (buffer.getCell(1, 2)) |cell| try testing.expect(cell.char == 'Z');
    if (buffer.getCell(2, 2)) |cell| try testing.expect(cell.char == ' ');
    if (buffer.getCell(3, 2)) |cell| try testing.expect(cell.char == ' ');

    // Lines below cursor should be cleared
    if (buffer.getCell(0, 3)) |cell| try testing.expect(cell.char == ' ');
    if (buffer.getCell(0, 4)) |cell| try testing.expect(cell.char == ' ');

    // Refill for next test
    y = 0;
    while (y < 5) : (y += 1) {
        var x: u32 = 0;
        while (x < 5) : (x += 1) {
            buffer.setChar(x, y, 'W');
        }
    }

    // Test clearToCursor (cursor at 2, 2)
    buffer.clearToCursor(2, 2);

    // Lines above cursor should be cleared
    if (buffer.getCell(0, 0)) |cell| try testing.expect(cell.char == ' ');
    if (buffer.getCell(0, 1)) |cell| try testing.expect(cell.char == ' ');

    // Current line up to cursor should be cleared
    if (buffer.getCell(0, 2)) |cell| try testing.expect(cell.char == ' ');
    if (buffer.getCell(1, 2)) |cell| try testing.expect(cell.char == ' ');
    if (buffer.getCell(2, 2)) |cell| try testing.expect(cell.char == ' ');

    // Rest of current line and lines below should be unchanged
    if (buffer.getCell(3, 2)) |cell| try testing.expect(cell.char == 'W');
    if (buffer.getCell(0, 3)) |cell| try testing.expect(cell.char == 'W');
    if (buffer.getCell(0, 4)) |cell| try testing.expect(cell.char == 'W');
}

test "terminal buffer resize operations" {
    const allocator = testing.allocator;

    var buffer = try TerminalBuffer.init(allocator, 5, 5);
    defer buffer.deinit();

    // Fill with test pattern
    var y: u32 = 0;
    while (y < 5) : (y += 1) {
        var x: u32 = 0;
        while (x < 5) : (x += 1) {
            buffer.setChar(x, y, @as(u8, @intCast('0' + x)));
        }
    }

    // Resize to larger
    try buffer.resize(8, 8);

    try testing.expect(buffer.width == 8);
    try testing.expect(buffer.height == 8);
    try testing.expect(buffer.cells.len == 64);

    // Original content should be preserved
    y = 0;
    while (y < 5) : (y += 1) {
        var x: u32 = 0;
        while (x < 5) : (x += 1) {
            if (buffer.getCell(x, y)) |cell| {
                try testing.expect(cell.char == @as(u8, @intCast('0' + x)));
            }
        }
    }

    // New areas should be initialized with defaults
    if (buffer.getCell(7, 7)) |cell| try testing.expect(cell.char == ' ');

    // Resize to smaller
    try buffer.resize(3, 3);

    try testing.expect(buffer.width == 3);
    try testing.expect(buffer.height == 3);
    try testing.expect(buffer.cells.len == 9);

    // Preserved content should still be there
    y = 0;
    while (y < 3) : (y += 1) {
        var x: u32 = 0;
        while (x < 3) : (x += 1) {
            if (buffer.getCell(x, y)) |cell| {
                try testing.expect(cell.char == @as(u8, @intCast('0' + x)));
            }
        }
    }
}

test "terminal buffer color and attribute operations" {
    const allocator = testing.allocator;

    var buffer = try TerminalBuffer.init(allocator, 5, 5);
    defer buffer.deinit();

    // Test color ANSI conversion
    try testing.expect(std.mem.eql(u8, Color.red.toAnsi(false), "\x1b[31m"));
    try testing.expect(std.mem.eql(u8, Color.red.toAnsi(true), "\x1b[41m"));
    try testing.expect(std.mem.eql(u8, Color.bright_green.toAnsi(false), "\x1b[92m"));
    try testing.expect(std.mem.eql(u8, Color.bright_green.toAnsi(true), "\x1b[102m"));

    // Test cell with attributes
    const styled_cell = Cell{
        .char = 'S',
        .fg_color = Color.yellow,
        .bg_color = Color.magenta,
        .attributes = Attributes{
            .bold = true,
            .italic = true,
            .underline = true,
        },
    };

    buffer.setCell(2, 2, styled_cell);

    if (buffer.getCell(2, 2)) |cell| {
        try testing.expect(cell.char == 'S');
        try testing.expect(cell.fg_color == Color.yellow);
        try testing.expect(cell.bg_color == Color.magenta);
        try testing.expect(cell.attributes.bold == true);
        try testing.expect(cell.attributes.italic == true);
        try testing.expect(cell.attributes.underline == true);
        try testing.expect(cell.attributes.strikethrough == false);
    }
}

test "terminal buffer edge cases and error conditions" {
    const allocator = testing.allocator;

    // Test with minimal buffer size
    var buffer = try TerminalBuffer.init(allocator, 1, 1);
    defer buffer.deinit();

    try testing.expect(buffer.width == 1);
    try testing.expect(buffer.height == 1);
    try testing.expect(buffer.cells.len == 1);

    // Test operations on minimal buffer
    buffer.setChar(0, 0, 'M');
    if (buffer.getCell(0, 0)) |cell| try testing.expect(cell.char == 'M');

    buffer.scrollUp();
    if (buffer.getCell(0, 0)) |cell| try testing.expect(cell.char == ' '); // Should be cleared

    buffer.clearAll();
    if (buffer.getCell(0, 0)) |cell| try testing.expect(cell.char == ' ');

    // Test clear operations at boundaries
    buffer.setChar(0, 0, 'B');
    buffer.clearLineFromCursor(0, 0);
    if (buffer.getCell(0, 0)) |cell| try testing.expect(cell.char == ' ');

    buffer.setChar(0, 0, 'C');
    buffer.clearLineToCursor(0, 0);
    if (buffer.getCell(0, 0)) |cell| try testing.expect(cell.char == ' ');

    // Test clear operations beyond boundaries (should not crash)
    buffer.clearLine(10); // y out of bounds
    buffer.clearLineFromCursor(10, 10); // both out of bounds
    buffer.clearLineToCursor(10, 10); // both out of bounds
    buffer.clearFromCursor(10, 10); // both out of bounds
    buffer.clearToCursor(10, 10); // both out of bounds
}
