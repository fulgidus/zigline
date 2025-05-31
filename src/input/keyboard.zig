// Keyboard input handling module for Zigline terminal emulator
// This module handles keyboard events, special key combinations, and input processing

const std = @import("std");
const posix = std.posix;
const Logger = @import("../core/logger.zig");

// Special key codes and sequences
pub const KeyCode = enum(u16) {
    // Control characters
    ctrl_c = 3,
    ctrl_d = 4,
    ctrl_z = 26,
    escape = 27,
    backspace = 127,
    enter = 13,
    tab = 9,

    // Special keys (will be detected as escape sequences) - using high values to avoid conflicts
    arrow_up = 256,
    arrow_down,
    arrow_left,
    arrow_right,
    home,
    end,
    page_up,
    page_down,
    delete,
    insert,

    // Function keys
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,

    // Regular character
    character = 1000,

    // Unknown/invalid key
    unknown,
};

// Key event structure
pub const KeyEvent = struct {
    code: KeyCode,
    char: u8, // The actual character for printable keys
    modifiers: KeyModifiers,

    pub fn init(code: KeyCode, char: u8) KeyEvent {
        return KeyEvent{
            .code = code,
            .char = char,
            .modifiers = KeyModifiers{},
        };
    }
};

// Key modifiers (Ctrl, Alt, Shift)
pub const KeyModifiers = struct {
    ctrl: bool = false,
    alt: bool = false,
    shift: bool = false,
};

// Terminal state management for raw mode
pub const TerminalState = struct {
    original_termios: posix.termios,
    raw_mode: bool = false,

    pub fn init() !TerminalState {
        const stdin_fd = posix.STDIN_FILENO;
        const original_termios = try posix.tcgetattr(stdin_fd);

        return TerminalState{
            .original_termios = original_termios,
            .raw_mode = false,
        };
    }

    // Enable raw mode for direct keyboard input
    pub fn enterRawMode(self: *TerminalState) !void {
        if (self.raw_mode) return; // Already in raw mode

        const stdin_fd = posix.STDIN_FILENO;

        // Check if stdin is a terminal
        if (!posix.isatty(stdin_fd)) {
            Logger.warn("stdin is not a terminal, raw mode may not work properly", .{});
        }

        var raw_termios = self.original_termios;

        // Disable canonical mode and echo
        raw_termios.lflag.ICANON = false;
        raw_termios.lflag.ECHO = false;
        raw_termios.lflag.ISIG = false; // Disable signal generation for Ctrl+C, etc.
        raw_termios.lflag.IEXTEN = false; // Disable extended input processing

        // Disable input processing
        raw_termios.iflag.IXON = false; // Disable Ctrl+S/Ctrl+Q flow control
        raw_termios.iflag.ICRNL = false; // Disable CR to NL translation
        raw_termios.iflag.BRKINT = false;
        raw_termios.iflag.INPCK = false;
        raw_termios.iflag.ISTRIP = false;

        // Disable output processing
        raw_termios.oflag.OPOST = false; // Disable output processing

        // Set character size to 8 bits
        raw_termios.cflag.CSIZE = posix.CSIZE.CS8;

        // Set minimum characters to read and timeout
        raw_termios.cc[@intFromEnum(posix.V.MIN)] = 1; // Wait for at least 1 character
        raw_termios.cc[@intFromEnum(posix.V.TIME)] = 0; // No timeout (blocking read)

        try posix.tcsetattr(stdin_fd, .FLUSH, raw_termios);
        self.raw_mode = true;

        Logger.debug("Terminal entered raw mode for keyboard input (isatty: {})", .{posix.isatty(stdin_fd)});
    }

    // Restore normal terminal mode
    pub fn exitRawMode(self: *TerminalState) !void {
        if (!self.raw_mode) return; // Not in raw mode

        const stdin_fd = posix.STDIN_FILENO;
        try posix.tcsetattr(stdin_fd, .FLUSH, self.original_termios);
        self.raw_mode = false;

        Logger.debug("Terminal exited raw mode", .{});
    }

    // Cleanup on deinit
    pub fn deinit(self: *TerminalState) void {
        self.exitRawMode() catch |err| {
            Logger.warn("Failed to restore terminal mode: {}", .{err});
        };
    }
};

// Keyboard input handler
pub const KeyboardHandler = struct {
    allocator: std.mem.Allocator,
    terminal_state: TerminalState,
    escape_sequence_buffer: [16]u8,
    escape_sequence_length: usize,

    pub fn init(allocator: std.mem.Allocator) !KeyboardHandler {
        const terminal_state = try TerminalState.init();

        return KeyboardHandler{
            .allocator = allocator,
            .terminal_state = terminal_state,
            .escape_sequence_buffer = undefined,
            .escape_sequence_length = 0,
        };
    }

    pub fn deinit(self: *KeyboardHandler) void {
        self.terminal_state.deinit();
    }

    // Enable keyboard input capture
    pub fn enableInput(self: *KeyboardHandler) !void {
        try self.terminal_state.enterRawMode();
        Logger.info("Keyboard input enabled", .{});
    }

    // Disable keyboard input capture
    pub fn disableInput(self: *KeyboardHandler) !void {
        try self.terminal_state.exitRawMode();
        Logger.info("Keyboard input disabled", .{});
    }

    // Read a single key event (blocking)
    pub fn readKey(self: *KeyboardHandler) !?KeyEvent {
        const stdin_fd = posix.STDIN_FILENO;
        var buffer: [1]u8 = undefined;

        // Read one character (blocking, since we've already checked input availability)
        const bytes_read = posix.read(stdin_fd, buffer[0..]) catch |err| {
            Logger.debug("Read error in readKey: {}", .{err});
            return null;
        };

        if (bytes_read == 0) return null; // EOF

        const char = buffer[0];

        // Handle escape sequences
        if (char == @intFromEnum(KeyCode.escape)) {
            return try self.handleEscapeSequence();
        }

        // Handle control characters
        if (char < 32) {
            return KeyEvent.init(self.getControlKeyCode(char), char);
        }

        // Handle delete character
        if (char == 127) {
            return KeyEvent.init(KeyCode.backspace, char);
        }

        // Regular printable character
        return KeyEvent.init(KeyCode.character, char);
    }

    // Handle escape sequences for special keys
    fn handleEscapeSequence(self: *KeyboardHandler) !?KeyEvent {
        self.escape_sequence_buffer[0] = @intFromEnum(KeyCode.escape);
        self.escape_sequence_length = 1;

        const stdin_fd = posix.STDIN_FILENO;

        // Temporarily set non-blocking mode for escape sequence reading
        var termios = try posix.tcgetattr(stdin_fd);
        termios.cc[@intFromEnum(posix.V.MIN)] = 0; // Non-blocking
        termios.cc[@intFromEnum(posix.V.TIME)] = 1; // 100ms timeout
        try posix.tcsetattr(stdin_fd, .NOW, termios);

        // Read additional characters for the escape sequence
        // Most escape sequences are 2-4 characters long
        while (self.escape_sequence_length < self.escape_sequence_buffer.len - 1) {
            var buffer: [1]u8 = undefined;

            const bytes_read = posix.read(stdin_fd, buffer[0..]) catch |err| {
                Logger.debug("Escape sequence read error: {}", .{err});
                break;
            };

            if (bytes_read == 0) break; // Timeout or no more data

            self.escape_sequence_buffer[self.escape_sequence_length] = buffer[0];
            self.escape_sequence_length += 1;

            // Check if we have a complete sequence
            if (try self.parseEscapeSequence()) |key_event| {
                // Restore blocking mode
                termios.cc[@intFromEnum(posix.V.MIN)] = 1;
                termios.cc[@intFromEnum(posix.V.TIME)] = 0;
                try posix.tcsetattr(stdin_fd, .NOW, termios);
                return key_event;
            }
        }

        // Restore blocking mode
        termios.cc[@intFromEnum(posix.V.MIN)] = 1;
        termios.cc[@intFromEnum(posix.V.TIME)] = 0;
        try posix.tcsetattr(stdin_fd, .NOW, termios);

        // If we couldn't parse the sequence, treat it as a plain escape
        return KeyEvent.init(KeyCode.escape, @intFromEnum(KeyCode.escape));
    }

    // Parse accumulated escape sequence
    fn parseEscapeSequence(self: *KeyboardHandler) !?KeyEvent {
        const sequence = self.escape_sequence_buffer[0..self.escape_sequence_length];

        // Common ANSI escape sequences
        if (std.mem.eql(u8, sequence, "\x1B[A")) {
            return KeyEvent.init(KeyCode.arrow_up, 0);
        } else if (std.mem.eql(u8, sequence, "\x1B[B")) {
            return KeyEvent.init(KeyCode.arrow_down, 0);
        } else if (std.mem.eql(u8, sequence, "\x1B[C")) {
            return KeyEvent.init(KeyCode.arrow_right, 0);
        } else if (std.mem.eql(u8, sequence, "\x1B[D")) {
            return KeyEvent.init(KeyCode.arrow_left, 0);
        } else if (std.mem.eql(u8, sequence, "\x1B[H")) {
            return KeyEvent.init(KeyCode.home, 0);
        } else if (std.mem.eql(u8, sequence, "\x1B[F")) {
            return KeyEvent.init(KeyCode.end, 0);
        } else if (std.mem.eql(u8, sequence, "\x1B[3~")) {
            return KeyEvent.init(KeyCode.delete, 0);
        } else if (std.mem.eql(u8, sequence, "\x1B[2~")) {
            return KeyEvent.init(KeyCode.insert, 0);
        } else if (std.mem.eql(u8, sequence, "\x1B[5~")) {
            return KeyEvent.init(KeyCode.page_up, 0);
        } else if (std.mem.eql(u8, sequence, "\x1B[6~")) {
            return KeyEvent.init(KeyCode.page_down, 0);
        }

        // Function keys
        if (std.mem.eql(u8, sequence, "\x1BOP")) {
            return KeyEvent.init(KeyCode.f1, 0);
        } else if (std.mem.eql(u8, sequence, "\x1BOQ")) {
            return KeyEvent.init(KeyCode.f2, 0);
        } else if (std.mem.eql(u8, sequence, "\x1BOR")) {
            return KeyEvent.init(KeyCode.f3, 0);
        } else if (std.mem.eql(u8, sequence, "\x1BOS")) {
            return KeyEvent.init(KeyCode.f4, 0);
        }

        // If sequence is not complete, return null to continue reading
        return null;
    }

    // Convert control character to KeyCode
    fn getControlKeyCode(self: *KeyboardHandler, char: u8) KeyCode {
        _ = self; // Suppress unused parameter warning

        return switch (char) {
            3 => KeyCode.ctrl_c,
            4 => KeyCode.ctrl_d,
            26 => KeyCode.ctrl_z,
            13 => KeyCode.enter,
            9 => KeyCode.tab,
            else => KeyCode.unknown,
        };
    }

    // Check if input is available (non-blocking)
    pub fn hasInput(self: *KeyboardHandler) bool {
        _ = self; // Suppress unused parameter warning

        const stdin_fd = posix.STDIN_FILENO;
        var poll_fd = [_]posix.pollfd{
            posix.pollfd{
                .fd = stdin_fd,
                .events = posix.POLL.IN,
                .revents = 0,
            },
        };

        const result = posix.poll(&poll_fd, 0) catch return false;
        return result > 0 and (poll_fd[0].revents & posix.POLL.IN) != 0;
    }

    // Read a single key event with timeout (in milliseconds)
    pub fn readKeyWithTimeout(self: *KeyboardHandler, timeout_ms: u32) !?KeyEvent {
        const stdin_fd = posix.STDIN_FILENO;

        // Use poll to wait for input with timeout
        var poll_fd = [_]posix.pollfd{
            posix.pollfd{
                .fd = stdin_fd,
                .events = posix.POLL.IN,
                .revents = 0,
            },
        };

        const poll_result = posix.poll(&poll_fd, @intCast(timeout_ms)) catch |err| {
            Logger.debug("Poll error in readKeyWithTimeout: {}", .{err});
            return null;
        };

        if (poll_result == 0) {
            // Timeout - no input available
            return null;
        }

        if ((poll_fd[0].revents & posix.POLL.IN) == 0) {
            // No input available despite poll success
            Logger.debug("Poll succeeded but no input flag set", .{});
            return null;
        }

        // Input is available, read it
        Logger.debug("Input detected, attempting to read key", .{});
        return try self.readKey();
    }
};

// Helper function to get key name for debugging
pub fn getKeyName(key_event: KeyEvent) []const u8 {
    return switch (key_event.code) {
        .ctrl_c => "Ctrl+C",
        .ctrl_d => "Ctrl+D",
        .ctrl_z => "Ctrl+Z",
        .escape => "Escape",
        .backspace => "Backspace",
        .enter => "Enter",
        .tab => "Tab",
        .arrow_up => "Arrow Up",
        .arrow_down => "Arrow Down",
        .arrow_left => "Arrow Left",
        .arrow_right => "Arrow Right",
        .home => "Home",
        .end => "End",
        .page_up => "Page Up",
        .page_down => "Page Down",
        .delete => "Delete",
        .insert => "Insert",
        .f1 => "F1",
        .f2 => "F2",
        .f3 => "F3",
        .f4 => "F4",
        .f5 => "F5",
        .f6 => "F6",
        .f7 => "F7",
        .f8 => "F8",
        .f9 => "F9",
        .f10 => "F10",
        .f11 => "F11",
        .f12 => "F12",
        .character => "Character",
        .unknown => "Unknown",
    };
}
