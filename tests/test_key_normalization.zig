// Unit tests for key normalization and input processing
// Tests keyboard input processing and special key handling

const std = @import("std");
const testing = std.testing;
const keyboard = @import("keyboard");
const KeyEvent = keyboard.KeyEvent;
const KeyCode = keyboard.KeyCode;
const KeyModifiers = keyboard.KeyModifiers;
const InputProcessor = @import("processor").InputProcessor;

test "key event initialization and structure" {
    // Test basic key event creation
    const key_event = KeyEvent.init(KeyCode.enter, '\n');

    try testing.expect(key_event.code == KeyCode.enter);
    try testing.expect(key_event.char == '\n');
    try testing.expect(key_event.modifiers.ctrl == false);
    try testing.expect(key_event.modifiers.alt == false);
    try testing.expect(key_event.modifiers.shift == false);

    // Test character key event
    const char_event = KeyEvent.init(KeyCode.character, 'a');
    try testing.expect(char_event.code == KeyCode.character);
    try testing.expect(char_event.char == 'a');
}

test "key code enumeration and values" {
    // Test control character codes match ASCII values
    try testing.expect(@intFromEnum(KeyCode.ctrl_c) == 3);
    try testing.expect(@intFromEnum(KeyCode.ctrl_d) == 4);
    try testing.expect(@intFromEnum(KeyCode.ctrl_z) == 26);
    try testing.expect(@intFromEnum(KeyCode.escape) == 27);
    try testing.expect(@intFromEnum(KeyCode.backspace) == 127);
    try testing.expect(@intFromEnum(KeyCode.enter) == 13);
    try testing.expect(@intFromEnum(KeyCode.tab) == 9);

    // Test special keys have high values to avoid conflicts
    try testing.expect(@intFromEnum(KeyCode.arrow_up) >= 256);
    try testing.expect(@intFromEnum(KeyCode.arrow_down) >= 256);
    try testing.expect(@intFromEnum(KeyCode.arrow_left) >= 256);
    try testing.expect(@intFromEnum(KeyCode.arrow_right) >= 256);
    try testing.expect(@intFromEnum(KeyCode.home) >= 256);
    try testing.expect(@intFromEnum(KeyCode.end) >= 256);
    try testing.expect(@intFromEnum(KeyCode.delete) >= 256);

    // Test function keys
    try testing.expect(@intFromEnum(KeyCode.f1) >= 256);
    try testing.expect(@intFromEnum(KeyCode.f12) >= 256);

    // Test character key has high value
    try testing.expect(@intFromEnum(KeyCode.character) == 1000);
}

test "key modifiers structure and behavior" {
    var modifiers = KeyModifiers{};

    // Test default initialization
    try testing.expect(modifiers.ctrl == false);
    try testing.expect(modifiers.alt == false);
    try testing.expect(modifiers.shift == false);

    // Test modifier setting
    modifiers.ctrl = true;
    modifiers.shift = true;

    try testing.expect(modifiers.ctrl == true);
    try testing.expect(modifiers.alt == false);
    try testing.expect(modifiers.shift == true);
}

test "input processor initialization and cleanup" {
    const allocator = testing.allocator;

    var processor = try InputProcessor.init(allocator);
    defer processor.deinit();

    try testing.expect(processor.cursor_position == 0);
    try testing.expect(processor.input_buffer.items.len == 0);
    try testing.expect(processor.history.items.len == 0);
    try testing.expect(processor.history_index == 0);
}

// Mock PTY for testing input processing without real PTY
const MockPTY = struct {
    allocator: std.mem.Allocator,
    written_data: std.ArrayList(u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .written_data = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.written_data.deinit();
    }

    pub fn write(self: *Self, data: []const u8) !usize {
        try self.written_data.appendSlice(data);
        return data.len;
    }

    pub fn getWrittenData(self: *const Self) []const u8 {
        return self.written_data.items;
    }

    pub fn clearWrittenData(self: *Self) void {
        self.written_data.clearRetainingCapacity();
    }
};

test "input processor character input handling" {
    const allocator = testing.allocator;

    var processor = try InputProcessor.init(allocator);
    defer processor.deinit();

    var mock_pty = MockPTY.init(allocator);
    defer mock_pty.deinit();

    // Test basic character input
    const char_event = KeyEvent.init(KeyCode.character, 'h');
    const result = try processor.handleKeyEvent(char_event, @ptrCast(&mock_pty));

    // Should return null (no command to execute yet)
    try testing.expect(result == null);

    // Input buffer should contain the character
    try testing.expect(processor.input_buffer.items.len == 1);
    try testing.expect(processor.input_buffer.items[0] == 'h');
    try testing.expect(processor.cursor_position == 1);

    // Add more characters
    const char_e = KeyEvent.init(KeyCode.character, 'e');
    const char_l = KeyEvent.init(KeyCode.character, 'l');
    const char_l2 = KeyEvent.init(KeyCode.character, 'l');
    const char_o = KeyEvent.init(KeyCode.character, 'o');

    _ = try processor.handleKeyEvent(char_e, @ptrCast(&mock_pty));
    _ = try processor.handleKeyEvent(char_l, @ptrCast(&mock_pty));
    _ = try processor.handleKeyEvent(char_l2, @ptrCast(&mock_pty));
    _ = try processor.handleKeyEvent(char_o, @ptrCast(&mock_pty));

    try testing.expect(processor.input_buffer.items.len == 5);
    try testing.expect(std.mem.eql(u8, processor.input_buffer.items, "hello"));
    try testing.expect(processor.cursor_position == 5);
}

test "input processor control character handling" {
    const allocator = testing.allocator;

    var processor = try InputProcessor.init(allocator);
    defer processor.deinit();

    var mock_pty = MockPTY.init(allocator);
    defer mock_pty.deinit();

    // Test Ctrl+C
    const ctrl_c = KeyEvent.init(KeyCode.ctrl_c, 3);
    _ = try processor.handleKeyEvent(ctrl_c, @ptrCast(&mock_pty));

    const written = mock_pty.getWrittenData();
    try testing.expect(std.mem.eql(u8, written, "\x03"));

    // Input buffer should be cleared
    try testing.expect(processor.input_buffer.items.len == 0);
    try testing.expect(processor.cursor_position == 0);

    mock_pty.clearWrittenData();

    // Test Ctrl+D
    const ctrl_d = KeyEvent.init(KeyCode.ctrl_d, 4);
    _ = try processor.handleKeyEvent(ctrl_d, @ptrCast(&mock_pty));

    const written_d = mock_pty.getWrittenData();
    try testing.expect(std.mem.eql(u8, written_d, "\x04"));

    mock_pty.clearWrittenData();

    // Test Ctrl+Z
    const ctrl_z = KeyEvent.init(KeyCode.ctrl_z, 26);
    _ = try processor.handleKeyEvent(ctrl_z, @ptrCast(&mock_pty));

    const written_z = mock_pty.getWrittenData();
    try testing.expect(std.mem.eql(u8, written_z, "\x1a"));
}

test "input processor enter key and command execution" {
    const allocator = testing.allocator;

    var processor = try InputProcessor.init(allocator);
    defer processor.deinit();

    var mock_pty = MockPTY.init(allocator);
    defer mock_pty.deinit();

    // Type a command
    const chars = "ls -la";
    for (chars) |c| {
        const char_event = KeyEvent.init(KeyCode.character, c);
        _ = try processor.handleKeyEvent(char_event, @ptrCast(&mock_pty));
    }

    try testing.expect(std.mem.eql(u8, processor.input_buffer.items, "ls -la"));

    // Press enter
    const enter_event = KeyEvent.init(KeyCode.enter, '\n');
    const result = try processor.handleKeyEvent(enter_event, @ptrCast(&mock_pty));

    // Should return command with newline
    try testing.expect(result != null);
    try testing.expect(std.mem.eql(u8, result.?, "ls -la\n"));

    // Command should be added to history
    try testing.expect(processor.history.items.len == 1);
    try testing.expect(std.mem.eql(u8, processor.history.items[0], "ls -la"));

    // Input buffer should be cleared
    try testing.expect(processor.input_buffer.items.len == 0);
    try testing.expect(processor.cursor_position == 0);

    // Free the returned command
    allocator.free(result.?);
}

test "input processor backspace and delete handling" {
    const allocator = testing.allocator;

    var processor = try InputProcessor.init(allocator);
    defer processor.deinit();

    var mock_pty = MockPTY.init(allocator);
    defer mock_pty.deinit();

    // Type some text
    const text = "hello world";
    for (text) |c| {
        const char_event = KeyEvent.init(KeyCode.character, c);
        _ = try processor.handleKeyEvent(char_event, @ptrCast(&mock_pty));
    }

    try testing.expect(std.mem.eql(u8, processor.input_buffer.items, "hello world"));
    try testing.expect(processor.cursor_position == 11);

    // Test backspace
    const backspace = KeyEvent.init(KeyCode.backspace, 127);
    _ = try processor.handleKeyEvent(backspace, @ptrCast(&mock_pty));

    try testing.expect(std.mem.eql(u8, processor.input_buffer.items, "hello worl"));
    try testing.expect(processor.cursor_position == 10);

    // Move cursor to middle and test delete
    processor.cursor_position = 5; // After "hello"

    const delete = KeyEvent.init(KeyCode.delete, 0);
    _ = try processor.handleKeyEvent(delete, @ptrCast(&mock_pty));

    try testing.expect(std.mem.eql(u8, processor.input_buffer.items, "helloworl"));
    try testing.expect(processor.cursor_position == 5);

    // Test backspace at beginning (should do nothing)
    processor.cursor_position = 0;
    _ = try processor.handleKeyEvent(backspace, @ptrCast(&mock_pty));
    try testing.expect(std.mem.eql(u8, processor.input_buffer.items, "helloworl"));
    try testing.expect(processor.cursor_position == 0);

    // Test delete at end (should do nothing)
    processor.cursor_position = @intCast(processor.input_buffer.items.len);
    _ = try processor.handleKeyEvent(delete, @ptrCast(&mock_pty));
    try testing.expect(std.mem.eql(u8, processor.input_buffer.items, "helloworl"));
}

test "input processor cursor movement" {
    const allocator = testing.allocator;

    var processor = try InputProcessor.init(allocator);
    defer processor.deinit();

    var mock_pty = MockPTY.init(allocator);
    defer mock_pty.deinit();

    // Type some text
    const text = "hello";
    for (text) |c| {
        const char_event = KeyEvent.init(KeyCode.character, c);
        _ = try processor.handleKeyEvent(char_event, @ptrCast(&mock_pty));
    }

    try testing.expect(processor.cursor_position == 5);

    // Test arrow left
    const left = KeyEvent.init(KeyCode.arrow_left, 0);
    _ = try processor.handleKeyEvent(left, @ptrCast(&mock_pty));
    try testing.expect(processor.cursor_position == 4);

    _ = try processor.handleKeyEvent(left, @ptrCast(&mock_pty));
    try testing.expect(processor.cursor_position == 3);

    // Test arrow right
    const right = KeyEvent.init(KeyCode.arrow_right, 0);
    _ = try processor.handleKeyEvent(right, @ptrCast(&mock_pty));
    try testing.expect(processor.cursor_position == 4);

    // Test home key
    const home = KeyEvent.init(KeyCode.home, 0);
    _ = try processor.handleKeyEvent(home, @ptrCast(&mock_pty));
    try testing.expect(processor.cursor_position == 0);

    // Test end key
    const end = KeyEvent.init(KeyCode.end, 0);
    _ = try processor.handleKeyEvent(end, @ptrCast(&mock_pty));
    try testing.expect(processor.cursor_position == 5);

    // Test boundary conditions
    // Left at beginning should do nothing
    processor.cursor_position = 0;
    _ = try processor.handleKeyEvent(left, @ptrCast(&mock_pty));
    try testing.expect(processor.cursor_position == 0);

    // Right at end should do nothing
    processor.cursor_position = @intCast(processor.input_buffer.items.len);
    _ = try processor.handleKeyEvent(right, @ptrCast(&mock_pty));
    try testing.expect(processor.cursor_position == 5);
}

test "input processor character insertion at cursor position" {
    const allocator = testing.allocator;

    var processor = try InputProcessor.init(allocator);
    defer processor.deinit();

    var mock_pty = MockPTY.init(allocator);
    defer mock_pty.deinit();

    // Type initial text
    const text = "hello world";
    for (text) |c| {
        const char_event = KeyEvent.init(KeyCode.character, c);
        _ = try processor.handleKeyEvent(char_event, @ptrCast(&mock_pty));
    }

    // Move cursor to middle (after "hello")
    processor.cursor_position = 5;

    // Insert a character
    const insert_char = KeyEvent.init(KeyCode.character, ',');
    _ = try processor.handleKeyEvent(insert_char, @ptrCast(&mock_pty));

    try testing.expect(std.mem.eql(u8, processor.input_buffer.items, "hello, world"));
    try testing.expect(processor.cursor_position == 6);

    // Insert at beginning
    processor.cursor_position = 0;
    const prefix_char = KeyEvent.init(KeyCode.character, '>');
    _ = try processor.handleKeyEvent(prefix_char, @ptrCast(&mock_pty));

    try testing.expect(std.mem.eql(u8, processor.input_buffer.items, ">hello, world"));
    try testing.expect(processor.cursor_position == 1);
}

test "input processor history navigation" {
    const allocator = testing.allocator;

    var processor = try InputProcessor.init(allocator);
    defer processor.deinit();

    var mock_pty = MockPTY.init(allocator);
    defer mock_pty.deinit();

    // Add some commands to history by executing them
    const commands = [_][]const u8{ "ls", "pwd", "echo hello" };

    for (commands) |cmd| {
        // Clear input buffer first
        processor.input_buffer.clearRetainingCapacity();
        processor.cursor_position = 0;

        // Type command
        for (cmd) |c| {
            const char_event = KeyEvent.init(KeyCode.character, c);
            _ = try processor.handleKeyEvent(char_event, @ptrCast(&mock_pty));
        }

        // Execute with enter
        const enter = KeyEvent.init(KeyCode.enter, '\n');
        const result = try processor.handleKeyEvent(enter, @ptrCast(&mock_pty));
        allocator.free(result.?); // Free the returned command
    }

    try testing.expect(processor.history.items.len == 3);

    // Test history navigation up
    const up = KeyEvent.init(KeyCode.arrow_up, 0);
    _ = try processor.handleKeyEvent(up, @ptrCast(&mock_pty));

    // Should show last command
    try testing.expect(std.mem.eql(u8, processor.input_buffer.items, "echo hello"));

    // Navigate up again
    _ = try processor.handleKeyEvent(up, @ptrCast(&mock_pty));
    try testing.expect(std.mem.eql(u8, processor.input_buffer.items, "pwd"));

    // Navigate down
    const down = KeyEvent.init(KeyCode.arrow_down, 0);
    _ = try processor.handleKeyEvent(down, @ptrCast(&mock_pty));
    try testing.expect(std.mem.eql(u8, processor.input_buffer.items, "echo hello"));

    // Navigate down past last entry should clear
    _ = try processor.handleKeyEvent(down, @ptrCast(&mock_pty));
    try testing.expect(processor.input_buffer.items.len == 0);
}

test "input processor special key handling" {
    const allocator = testing.allocator;

    var processor = try InputProcessor.init(allocator);
    defer processor.deinit();

    var mock_pty = MockPTY.init(allocator);
    defer mock_pty.deinit();

    // Test tab key (should not do anything currently)
    const tab = KeyEvent.init(KeyCode.tab, '\t');
    const result_tab = try processor.handleKeyEvent(tab, @ptrCast(&mock_pty));
    try testing.expect(result_tab == null);

    // Test unknown key
    const unknown = KeyEvent.init(KeyCode.unknown, 0);
    const result_unknown = try processor.handleKeyEvent(unknown, @ptrCast(&mock_pty));
    try testing.expect(result_unknown == null);

    // Test function keys
    const f1 = KeyEvent.init(KeyCode.f1, 0);
    const result_f1 = try processor.handleKeyEvent(f1, @ptrCast(&mock_pty));
    try testing.expect(result_f1 == null);
}

test "input processor edge cases and error conditions" {
    const allocator = testing.allocator;

    var processor = try InputProcessor.init(allocator);
    defer processor.deinit();

    // Test with null PTY
    const char_event = KeyEvent.init(KeyCode.character, 'a');
    const result = try processor.handleKeyEvent(char_event, null);
    try testing.expect(result == null);

    // Character should still be added to buffer
    try testing.expect(processor.input_buffer.items.len == 1);
    try testing.expect(processor.input_buffer.items[0] == 'a');

    // Test control characters with null PTY
    const ctrl_c = KeyEvent.init(KeyCode.ctrl_c, 3);
    _ = try processor.handleKeyEvent(ctrl_c, null);

    // Buffer should be cleared even without PTY
    try testing.expect(processor.input_buffer.items.len == 0);
    try testing.expect(processor.cursor_position == 0);

    // Test empty command execution
    const enter = KeyEvent.init(KeyCode.enter, '\n');
    const empty_result = try processor.handleKeyEvent(enter, null);

    try testing.expect(empty_result != null);
    try testing.expect(std.mem.eql(u8, empty_result.?, "\n"));

    // Empty command should not be added to history
    try testing.expect(processor.history.items.len == 0);

    allocator.free(empty_result.?);
}
