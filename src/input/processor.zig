// Input processing module for Zigline terminal emulator
// This module processes keyboard input and translates it to terminal commands

const std = @import("std");
const Logger = @import("../core/logger.zig");
const PTY = @import("../core/pty.zig").PTY;
const TerminalBuffer = @import("../terminal/buffer.zig").TerminalBuffer;
const keyboard = @import("keyboard.zig");
const KeyEvent = keyboard.KeyEvent;
const KeyCode = keyboard.KeyCode;

// Input processing state
pub const InputProcessor = struct {
    allocator: std.mem.Allocator,
    keyboard_handler: keyboard.KeyboardHandler,
    input_buffer: std.ArrayList(u8),
    cursor_position: u32,
    history: std.ArrayList([]const u8),
    history_index: usize,

    pub fn init(allocator: std.mem.Allocator) !InputProcessor {
        const keyboard_handler = try keyboard.KeyboardHandler.init(allocator);

        return InputProcessor{
            .allocator = allocator,
            .keyboard_handler = keyboard_handler,
            .input_buffer = std.ArrayList(u8).init(allocator),
            .cursor_position = 0,
            .history = std.ArrayList([]const u8).init(allocator),
            .history_index = 0,
        };
    }

    pub fn deinit(self: *InputProcessor) void {
        self.keyboard_handler.deinit();
        self.input_buffer.deinit();

        // Free history entries
        for (self.history.items) |entry| {
            self.allocator.free(entry);
        }
        self.history.deinit();
    }

    // Enable input processing
    pub fn enable(self: *InputProcessor) !void {
        try self.keyboard_handler.enableInput();
        Logger.info("Input processing enabled", .{});
    }

    // Disable input processing
    pub fn disable(self: *InputProcessor) !void {
        try self.keyboard_handler.disableInput();
        Logger.info("Input processing disabled", .{});
    }

    // Process input events and return commands to send to PTY (with timeout)
    pub fn processInput(self: *InputProcessor, pty: ?*PTY) !?[]const u8 {
        // Try to read a key event with timeout
        Logger.debug("Attempting to read key with timeout...", .{});
        const key_event = try self.keyboard_handler.readKeyWithTimeout(100) orelse {
            // No input available within timeout
            return null;
        };

        Logger.debug("Key pressed: {s} (char: {})", .{ keyboard.getKeyName(key_event), key_event.char });

        return try self.handleKeyEvent(key_event, pty);
    }

    // Handle individual key events
    fn handleKeyEvent(self: *InputProcessor, key_event: KeyEvent, pty: ?*PTY) !?[]const u8 {
        switch (key_event.code) {
            .ctrl_c => {
                Logger.info("Ctrl+C pressed - sending interrupt signal", .{});
                if (pty) |p| {
                    _ = p.write("\x03") catch {}; // Send Ctrl+C to shell
                }
                // Clear current input and start fresh
                self.input_buffer.clearRetainingCapacity();
                self.cursor_position = 0;
                return null;
            },

            .ctrl_d => {
                Logger.info("Ctrl+D pressed - sending EOF", .{});
                if (pty) |p| {
                    _ = p.write("\x04") catch {}; // Send EOF to shell
                }
                return null;
            },

            .ctrl_z => {
                Logger.info("Ctrl+Z pressed - sending suspend signal", .{});
                if (pty) |p| {
                    _ = p.write("\x1a") catch {}; // Send Ctrl+Z to shell
                }
                return null;
            },

            .enter => {
                Logger.debug("Enter pressed - executing command", .{});
                const command = try self.finishInput();
                if (command.len > 0) {
                    try self.addToHistory(command);
                }

                // Add newline to the command
                const command_with_newline = try std.fmt.allocPrint(self.allocator, "{s}\n", .{command});
                return command_with_newline;
            },

            .backspace => {
                try self.handleBackspace();
                return null;
            },

            .tab => {
                Logger.debug("Tab pressed - tab completion not implemented yet", .{});
                // TODO: Implement tab completion
                return null;
            },

            .arrow_up => {
                try self.handleHistoryUp(pty);
                return null;
            },

            .arrow_down => {
                try self.handleHistoryDown(pty);
                return null;
            },

            .arrow_left => {
                try self.handleCursorLeft();
                return null;
            },

            .arrow_right => {
                try self.handleCursorRight();
                return null;
            },

            .home => {
                self.cursor_position = 0;
                Logger.debug("Cursor moved to beginning of line", .{});
                return null;
            },

            .end => {
                self.cursor_position = @intCast(self.input_buffer.items.len);
                Logger.debug("Cursor moved to end of line", .{});
                return null;
            },

            .delete => {
                try self.handleDelete();
                return null;
            },

            .character => {
                try self.handleCharacterInput(key_event.char);
                return null;
            },

            else => {
                Logger.debug("Unhandled key: {s}", .{keyboard.getKeyName(key_event)});
                return null;
            },
        }
    }

    // Handle character input
    fn handleCharacterInput(self: *InputProcessor, char: u8) !void {
        // Insert character at cursor position
        try self.input_buffer.insert(self.cursor_position, char);
        self.cursor_position += 1;

        Logger.debug("Character '{c}' inserted at position {}", .{ char, self.cursor_position - 1 });
    }

    // Handle backspace
    fn handleBackspace(self: *InputProcessor) !void {
        if (self.cursor_position > 0) {
            _ = self.input_buffer.orderedRemove(self.cursor_position - 1);
            self.cursor_position -= 1;
            Logger.debug("Character deleted, cursor at position {}", .{self.cursor_position});
        }
    }

    // Handle delete key
    fn handleDelete(self: *InputProcessor) !void {
        if (self.cursor_position < self.input_buffer.items.len) {
            _ = self.input_buffer.orderedRemove(self.cursor_position);
            Logger.debug("Character deleted at position {}", .{self.cursor_position});
        }
    }

    // Handle cursor movement
    fn handleCursorLeft(self: *InputProcessor) !void {
        if (self.cursor_position > 0) {
            self.cursor_position -= 1;
            Logger.debug("Cursor moved left to position {}", .{self.cursor_position});
        }
    }

    fn handleCursorRight(self: *InputProcessor) !void {
        if (self.cursor_position < self.input_buffer.items.len) {
            self.cursor_position += 1;
            Logger.debug("Cursor moved right to position {}", .{self.cursor_position});
        }
    }

    // Handle history navigation
    fn handleHistoryUp(self: *InputProcessor, pty: ?*PTY) !void {
        if (self.history.items.len == 0) return;

        if (self.history_index > 0) {
            self.history_index -= 1;
        }

        try self.loadFromHistory(pty);
        Logger.debug("History up: loaded command {}", .{self.history_index});
    }

    fn handleHistoryDown(self: *InputProcessor, pty: ?*PTY) !void {
        if (self.history.items.len == 0) return;

        if (self.history_index < self.history.items.len - 1) {
            self.history_index += 1;
            try self.loadFromHistory(pty);
        } else {
            // Clear input buffer when going past last history entry
            self.input_buffer.clearRetainingCapacity();
            self.cursor_position = 0;
            // Send ANSI escape sequence to clear current line on display
            if (pty) |p| {
                _ = p.write("\x1b[2K\x1b[0G") catch {}; // Clear entire line and move cursor to column 0
            }
        }

        Logger.debug("History down: loaded command {}", .{self.history_index});
    }

    // Load command from history
    fn loadFromHistory(self: *InputProcessor, pty: ?*PTY) !void {
        if (self.history_index >= self.history.items.len) return;

        // Send ANSI escape sequence to clear current line on display
        // This prevents visual artifacts when switching between commands of different lengths
        if (pty) |p| {
            _ = p.write("\x1b[2K\x1b[0G") catch {}; // Clear entire line and move cursor to column 0
        }

        const command = self.history.items[self.history_index];
        self.input_buffer.clearRetainingCapacity();
        try self.input_buffer.appendSlice(command);
        self.cursor_position = @intCast(self.input_buffer.items.len);

        // Send the new command to display
        if (pty) |p| {
            _ = p.write(command) catch {}; // Display the new command
        }
    }

    // Finish input and return the command
    fn finishInput(self: *InputProcessor) ![]const u8 {
        const command = try self.allocator.dupe(u8, self.input_buffer.items);
        self.input_buffer.clearRetainingCapacity();
        self.cursor_position = 0;
        return command;
    }

    // Add command to history
    fn addToHistory(self: *InputProcessor, command: []const u8) !void {
        if (command.len == 0) return;

        // Don't add duplicate commands
        if (self.history.items.len > 0) {
            const last_command = self.history.items[self.history.items.len - 1];
            if (std.mem.eql(u8, command, last_command)) {
                self.history_index = self.history.items.len;
                return;
            }
        }

        const command_copy = try self.allocator.dupe(u8, command);
        try self.history.append(command_copy);
        self.history_index = self.history.items.len;

        Logger.debug("Added command to history: '{s}'", .{command});
    }

    // Get current input buffer content
    pub fn getCurrentInput(self: *InputProcessor) []const u8 {
        return self.input_buffer.items;
    }

    // Get cursor position
    pub fn getCursorPosition(self: *InputProcessor) u32 {
        return self.cursor_position;
    }

    // Clear input buffer
    pub fn clearInput(self: *InputProcessor) void {
        self.input_buffer.clearRetainingCapacity();
        self.cursor_position = 0;
    }

    // Check if there's input available
    pub fn hasInput(self: *InputProcessor) bool {
        return self.keyboard_handler.hasInput();
    }
};
