const std = @import("std");
const TerminalBuffer = @import("buffer.zig").TerminalBuffer;

/// ANSI escape sequence parser for terminal emulation
pub const AnsiParser = struct {
    state: ParseState,
    params: std.ArrayList(u32),
    intermediate_chars: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    /// Parser state machine states
    pub const ParseState = enum {
        ground,
        escape,
        csi_entry,
        csi_param,
        csi_intermediate,
        csi_ignore,
        osc_string,
    };

    /// ANSI escape sequence types
    pub const EscapeSequence = union(enum) {
        /// Cursor movement commands
        cursor_up: u32,
        cursor_down: u32,
        cursor_forward: u32,
        cursor_backward: u32,
        cursor_position: struct { row: u32, col: u32 },

        /// Screen manipulation
        clear_screen: ClearType,
        clear_line: ClearType,

        /// Text attributes
        set_graphics_mode: []const u32,

        /// Colors
        set_foreground_color: u32,
        set_background_color: u32,

        /// Other sequences
        unknown: []const u8,

        pub const ClearType = enum {
            from_cursor_to_end,
            from_start_to_cursor,
            entire,
        };
    };

    /// Initialize the ANSI parser
    pub fn init(allocator: std.mem.Allocator) AnsiParser {
        return AnsiParser{
            .state = .ground,
            .params = std.ArrayList(u32).init(allocator),
            .intermediate_chars = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
    }

    /// Deinitialize the ANSI parser
    pub fn deinit(self: *AnsiParser) void {
        self.params.deinit();
        self.intermediate_chars.deinit();
    }

    /// Free an array of escape sequences and their owned memory
    pub fn freeSequences(self: *AnsiParser, sequences: []EscapeSequence) void {
        for (sequences) |sequence| {
            switch (sequence) {
                .set_graphics_mode => |params| {
                    self.allocator.free(params);
                },
                else => {}, // Other sequences don't have owned memory
            }
        }
        self.allocator.free(sequences);
    }

    /// Parse a sequence of bytes and return any complete escape sequences
    pub fn parse(self: *AnsiParser, input: []const u8) ![]EscapeSequence {
        var sequences = std.ArrayList(EscapeSequence).init(self.allocator);
        errdefer sequences.deinit();

        for (input) |byte| {
            if (try self.processByte(byte)) |sequence| {
                try sequences.append(sequence);
            }
        }

        return sequences.toOwnedSlice();
    }

    /// Process a single byte through the state machine
    fn processByte(self: *AnsiParser, byte: u8) !?EscapeSequence {
        switch (self.state) {
            .ground => {
                if (byte == 0x1B) { // ESC character
                    self.state = .escape;
                    self.resetParser();
                }
                return null;
            },

            .escape => {
                switch (byte) {
                    '[' => {
                        self.state = .csi_entry;
                        return null;
                    },
                    ']' => {
                        self.state = .osc_string;
                        return null;
                    },
                    else => {
                        // Unknown escape sequence, return to ground
                        self.state = .ground;
                        return EscapeSequence{ .unknown = &[_]u8{byte} };
                    },
                }
            },

            .csi_entry => {
                if (byte >= '0' and byte <= '9') {
                    self.state = .csi_param;
                    try self.addToCurrentParam(byte);
                } else if (byte >= '@' and byte <= '~') {
                    // Final byte
                    self.state = .ground;
                    return try self.buildCsiSequence(byte);
                } else if (byte >= ' ' and byte <= '/') {
                    self.state = .csi_intermediate;
                    try self.intermediate_chars.append(byte);
                } else {
                    // Invalid character, ignore
                    self.state = .csi_ignore;
                }
                return null;
            },

            .csi_param => {
                if (byte >= '0' and byte <= '9') {
                    try self.addToCurrentParam(byte);
                } else if (byte == ';') {
                    try self.finishCurrentParam();
                } else if (byte >= '@' and byte <= '~') {
                    // Final byte
                    try self.finishCurrentParam();
                    self.state = .ground;
                    return try self.buildCsiSequence(byte);
                } else if (byte >= ' ' and byte <= '/') {
                    self.state = .csi_intermediate;
                    try self.intermediate_chars.append(byte);
                } else {
                    // Invalid character, ignore
                    self.state = .csi_ignore;
                }
                return null;
            },

            .csi_intermediate => {
                if (byte >= '@' and byte <= '~') {
                    // Final byte
                    self.state = .ground;
                    return try self.buildCsiSequence(byte);
                } else if (byte >= ' ' and byte <= '/') {
                    try self.intermediate_chars.append(byte);
                } else {
                    // Invalid character, ignore
                    self.state = .csi_ignore;
                }
                return null;
            },

            .csi_ignore => {
                if (byte >= '@' and byte <= '~') {
                    // Final byte found, return to ground
                    self.state = .ground;
                }
                return null;
            },

            .osc_string => {
                // TODO: Implement OSC string parsing
                if (byte == 0x07 or byte == 0x1B) { // BEL or ESC
                    self.state = .ground;
                }
                return null;
            },
        }
    }

    /// Reset parser state for new sequence
    fn resetParser(self: *AnsiParser) void {
        self.params.clearRetainingCapacity();
        self.intermediate_chars.clearRetainingCapacity();
    }

    /// Add digit to current parameter
    fn addToCurrentParam(self: *AnsiParser, digit: u8) !void {
        const value = digit - '0';
        if (self.params.items.len == 0) {
            try self.params.append(value);
        } else {
            const last_index = self.params.items.len - 1;
            self.params.items[last_index] = self.params.items[last_index] * 10 + value;
        }
    }

    /// Finish current parameter and start new one
    fn finishCurrentParam(self: *AnsiParser) !void {
        if (self.params.items.len == 0) {
            try self.params.append(0);
        }
        try self.params.append(0);
    }

    /// Build CSI escape sequence from parsed components
    fn buildCsiSequence(self: *AnsiParser, final_byte: u8) !EscapeSequence {
        const params = self.params.items;

        return switch (final_byte) {
            'A' => EscapeSequence{ .cursor_up = if (params.len > 0) params[0] else 1 },
            'B' => EscapeSequence{ .cursor_down = if (params.len > 0) params[0] else 1 },
            'C' => EscapeSequence{ .cursor_forward = if (params.len > 0) params[0] else 1 },
            'D' => EscapeSequence{ .cursor_backward = if (params.len > 0) params[0] else 1 },
            'H', 'f' => {
                const row = if (params.len > 0) params[0] else 1;
                const col = if (params.len > 1) params[1] else 1;
                return EscapeSequence{ .cursor_position = .{ .row = row, .col = col } };
            },
            'J' => {
                const clear_type: EscapeSequence.ClearType = switch (if (params.len > 0) params[0] else 0) {
                    0 => .from_cursor_to_end,
                    1 => .from_start_to_cursor,
                    2 => .entire,
                    else => .entire,
                };
                return EscapeSequence{ .clear_screen = clear_type };
            },
            'K' => {
                const clear_type: EscapeSequence.ClearType = switch (if (params.len > 0) params[0] else 0) {
                    0 => .from_cursor_to_end,
                    1 => .from_start_to_cursor,
                    2 => .entire,
                    else => .entire,
                };
                return EscapeSequence{ .clear_line = clear_type };
            },
            'm' => {
                // Graphics mode - copy params to owned slice
                const owned_params = try self.allocator.dupe(u32, params);
                return EscapeSequence{ .set_graphics_mode = owned_params };
            },
            else => EscapeSequence{ .unknown = &[_]u8{final_byte} },
        };
    }
};

/// Enhanced ANSI sequence processor that integrates with terminal buffer
pub const AnsiProcessor = struct {
    parser: AnsiParser,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) AnsiProcessor {
        return AnsiProcessor{
            .parser = AnsiParser.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *AnsiProcessor) void {
        self.parser.deinit();
    }

    /// Process input text and apply ANSI sequences to terminal buffer
    pub fn processInput(self: *AnsiProcessor, input: []const u8, buffer: *TerminalBuffer, cursor_x: *u32, cursor_y: *u32) !void {
        var i: usize = 0;
        while (i < input.len) {
            if (input[i] == 0x1B and i + 1 < input.len and input[i + 1] == '[') {
                // Found CSI sequence
                const seq_end = self.findSequenceEnd(input[i..]) orelse {
                    // Incomplete sequence, skip for now
                    i += 1;
                    continue;
                };

                const sequence = input[i .. i + seq_end];
                try self.applyCsiSequence(sequence, buffer, cursor_x, cursor_y);
                i += seq_end;
            } else if (input[i] >= 32 and input[i] <= 126) {
                // Regular printable character
                try self.insertCharacter(input[i], buffer, cursor_x, cursor_y);
                i += 1;
            } else {
                // Control character - handle some basic ones
                switch (input[i]) {
                    '\n' => {
                        cursor_x.* = 0;
                        if (cursor_y.* < buffer.height - 1) {
                            cursor_y.* += 1;
                        } else {
                            buffer.scrollUp();
                        }
                    },
                    '\r' => cursor_x.* = 0,
                    '\t' => {
                        const tab_stop = ((cursor_x.* + 8) / 8) * 8;
                        cursor_x.* = @min(tab_stop, buffer.width - 1);
                    },
                    '\x08' => if (cursor_x.* > 0) {
                        cursor_x.* -= 1;
                    }, // Backspace
                    else => {}, // Ignore other control characters
                }
                i += 1;
            }
        }
    }

    /// Find the end of an ANSI escape sequence
    fn findSequenceEnd(self: *AnsiProcessor, input: []const u8) ?usize {
        _ = self;
        if (input.len < 2 or input[0] != 0x1B or input[1] != '[') return null;

        var i: usize = 2;
        while (i < input.len) {
            const c = input[i];
            if (c >= 0x40 and c <= 0x7E) { // Final byte
                return i + 1;
            }
            i += 1;
        }
        return null;
    }

    /// Apply a CSI (Control Sequence Introducer) sequence
    fn applyCsiSequence(self: *AnsiProcessor, sequence: []const u8, buffer: *TerminalBuffer, cursor_x: *u32, cursor_y: *u32) !void {
        _ = self;
        if (sequence.len < 3) return;

        const final_byte = sequence[sequence.len - 1];
        const params = sequence[2 .. sequence.len - 1];

        switch (final_byte) {
            'A' => { // Cursor Up
                const n = parseFirstParam(params) orelse 1;
                cursor_y.* = if (cursor_y.* >= n) cursor_y.* - n else 0;
            },
            'B' => { // Cursor Down
                const n = parseFirstParam(params) orelse 1;
                cursor_y.* = @min(cursor_y.* + n, buffer.height - 1);
            },
            'C' => { // Cursor Forward
                const n = parseFirstParam(params) orelse 1;
                cursor_x.* = @min(cursor_x.* + n, buffer.width - 1);
            },
            'D' => { // Cursor Backward
                const n = parseFirstParam(params) orelse 1;
                cursor_x.* = if (cursor_x.* >= n) cursor_x.* - n else 0;
            },
            'H', 'f' => { // Cursor Position
                const parts = splitParams(params);
                const row = if (parts.len > 0) parseNumber(parts[0]) orelse 1 else 1;
                const col = if (parts.len > 1) parseNumber(parts[1]) orelse 1 else 1;
                cursor_y.* = @min(@max(row, 1) - 1, buffer.height - 1);
                cursor_x.* = @min(@max(col, 1) - 1, buffer.width - 1);
            },
            'J' => { // Erase in Display
                const n = parseFirstParam(params) orelse 0;
                std.log.info("Processing clear display command (CSI {}J)", .{n});
                switch (n) {
                    0 => {
                        std.log.info("Clearing from cursor to end of screen", .{});
                        buffer.clearFromCursor(cursor_x.*, cursor_y.*);
                    },
                    1 => {
                        std.log.info("Clearing from start to screen to cursor", .{});
                        buffer.clearToCursor(cursor_x.*, cursor_y.*);
                    },
                    2 => {
                        std.log.info("Clearing entire screen", .{});
                        buffer.clearAll();
                    },
                    else => {
                        std.log.warn("Unknown clear display parameter: {}", .{n});
                    },
                }
            },
            'K' => { // Erase in Line
                const n = parseFirstParam(params) orelse 0;
                switch (n) {
                    0 => buffer.clearLineFromCursor(cursor_x.*, cursor_y.*),
                    1 => buffer.clearLineToCursor(cursor_x.*, cursor_y.*),
                    2 => buffer.clearLine(cursor_y.*),
                    else => {},
                }
            },
            'm' => { // Set Graphics Mode (colors, attributes)
                const parts = splitParams(params);
                for (parts) |part| {
                    const code = parseNumber(part) orelse 0;
                    buffer.applyGraphicsMode(code, cursor_x.*, cursor_y.*);
                }
            },
            else => {}, // Ignore unknown sequences
        }
    }

    /// Insert a character at the current cursor position
    fn insertCharacter(self: *AnsiProcessor, char: u8, buffer: *TerminalBuffer, cursor_x: *u32, cursor_y: *u32) !void {
        _ = self;
        buffer.setChar(cursor_x.*, cursor_y.*, char);
        cursor_x.* += 1;
        if (cursor_x.* >= buffer.width) {
            cursor_x.* = 0;
            if (cursor_y.* < buffer.height - 1) {
                cursor_y.* += 1;
            } else {
                buffer.scrollUp();
            }
        }
    }
};

/// Parse the first parameter from a parameter string
fn parseFirstParam(params: []const u8) ?u32 {
    if (params.len == 0) return null;
    var end: usize = 0;
    while (end < params.len and params[end] != ';') end += 1;
    return parseNumber(params[0..end]);
}

/// Split parameter string by semicolons
fn splitParams(params: []const u8) [][]const u8 {
    // Simple implementation - in a real implementation, you'd use an allocator
    _ = params;
    return &[_][]const u8{};
}

/// Parse a number from a string
fn parseNumber(str: []const u8) ?u32 {
    if (str.len == 0) return null;
    var result: u32 = 0;
    for (str) |c| {
        if (c < '0' or c > '9') return null;
        result = result * 10 + (c - '0');
    }
    return result;
}

// Tests
test "ansi parser basic cursor movement" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var parser = AnsiParser.init(allocator);
    defer parser.deinit();

    const input = "\x1B[5A"; // Move cursor up 5 lines
    const sequences = try parser.parse(input);
    defer allocator.free(sequences);

    try testing.expect(sequences.len == 1);
    try testing.expect(sequences[0] == .cursor_up);
    try testing.expect(sequences[0].cursor_up == 5);
}

test "ansi parser cursor position" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var parser = AnsiParser.init(allocator);
    defer parser.deinit();

    const input = "\x1B[10;20H"; // Position cursor at row 10, column 20
    const sequences = try parser.parse(input);
    defer allocator.free(sequences);

    try testing.expect(sequences.len == 1);
    try testing.expect(sequences[0] == .cursor_position);
    try testing.expect(sequences[0].cursor_position.row == 10);
    try testing.expect(sequences[0].cursor_position.col == 20);
}
