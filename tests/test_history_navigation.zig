// Unit test for command history navigation fix
// Tests that proper ANSI escape sequences are sent when navigating command history

const std = @import("std");
const testing = std.testing;
const InputProcessor = @import("../src/input/processor.zig").InputProcessor;
const PTY = @import("../src/core/pty.zig").PTY;

// Mock PTY that captures written data for testing
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

    // Mock write function that captures data
    pub fn write(self: *Self, data: []const u8) !usize {
        try self.written_data.appendSlice(data);
        return data.len;
    }

    // Get all written data as a string for testing
    pub fn getWrittenData(self: *Self) []const u8 {
        return self.written_data.items;
    }

    // Clear written data for next test
    pub fn clearWrittenData(self: *Self) void {
        self.written_data.clearRetainingCapacity();
    }
};

test "command history navigation sends clear sequence" {
    var allocator = testing.allocator;

    // Create input processor
    var input_processor = try InputProcessor.init(allocator);
    defer input_processor.deinit();

    // Create mock PTY
    var mock_pty = MockPTY.init(allocator);
    defer mock_pty.deinit();

    // Add some test commands to history
    try input_processor.addToHistory("ls");
    try input_processor.addToHistory("echo 'This is a very long command that should test clearing'");
    try input_processor.addToHistory("pwd");

    // Test navigation up (should send clear sequence + command)
    try input_processor.handleHistoryUp(@ptrCast(&mock_pty));

    const written_data = mock_pty.getWrittenData();

    // Verify that clear sequence is sent
    try testing.expect(std.mem.indexOf(u8, written_data, "\x1b[2K\x1b[0G") != null);

    // Verify that the command is sent after clear sequence
    try testing.expect(std.mem.indexOf(u8, written_data, "pwd") != null);

    // Clear for next test
    mock_pty.clearWrittenData();

    // Test navigation down
    try input_processor.handleHistoryDown(@ptrCast(&mock_pty));

    const written_data_down = mock_pty.getWrittenData();

    // Should contain clear sequence
    try testing.expect(std.mem.indexOf(u8, written_data_down, "\x1b[2K\x1b[0G") != null);
}

test "navigating past last history entry clears line" {
    var allocator = testing.allocator;

    // Create input processor
    var input_processor = try InputProcessor.init(allocator);
    defer input_processor.deinit();

    // Create mock PTY
    var mock_pty = MockPTY.init(allocator);
    defer mock_pty.deinit();

    // Add one command to history
    try input_processor.addToHistory("test command");

    // Navigate to the command
    try input_processor.handleHistoryUp(@ptrCast(&mock_pty));
    mock_pty.clearWrittenData();

    // Navigate past the last entry (should clear the line)
    try input_processor.handleHistoryDown(@ptrCast(&mock_pty));

    const written_data = mock_pty.getWrittenData();

    // Should contain clear sequence when going past last entry
    try testing.expect(std.mem.indexOf(u8, written_data, "\x1b[2K\x1b[0G") != null);
}
