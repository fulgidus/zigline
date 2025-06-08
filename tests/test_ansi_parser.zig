// Unit tests for ANSI parser functionality
// Tests known escape sequences and parsing behavior

const std = @import("std");
const testing = std.testing;
const AnsiParser = @import("ansi").AnsiParser;
const EscapeSequence = @import("ansi").AnsiParser.EscapeSequence;

test "ANSI parser initialization and cleanup" {
    const allocator = testing.allocator;
    // Initialize the ANSI parser
    var parser = AnsiParser.init(allocator);
    defer parser.deinit();
    
    // Parser should be initialized in ground state
    try testing.expect(parser.state == .ground);
    try testing.expect(parser.params.items.len == 0);
    try testing.expect(parser.intermediate_chars.items.len == 0);
}

test "ANSI parser cursor movement sequences" {
    const allocator = testing.allocator;
    
    var parser = AnsiParser.init(allocator);
    defer parser.deinit();
    
    // Test cursor up
    {
        const input = "\x1B[5A";
        const sequences = try parser.parse(input);
        defer allocator.free(sequences);
        
        try testing.expect(sequences.len == 1);
        try testing.expect(sequences[0] == .cursor_up);
        try testing.expect(sequences[0].cursor_up == 5);
    }
    
    // Test cursor down
    {
        const input = "\x1B[10B";
        const sequences = try parser.parse(input);
        defer allocator.free(sequences);
        
        try testing.expect(sequences.len == 1);
        try testing.expect(sequences[0] == .cursor_down);
        try testing.expect(sequences[0].cursor_down == 10);
    }
    
    // Test cursor forward
    {
        const input = "\x1B[3C";
        const sequences = try parser.parse(input);
        defer allocator.free(sequences);
        
        try testing.expect(sequences.len == 1);
        try testing.expect(sequences[0] == .cursor_forward);
        try testing.expect(sequences[0].cursor_forward == 3);
    }
    
    // Test cursor backward
    {
        const input = "\x1B[7D";
        const sequences = try parser.parse(input);
        defer allocator.free(sequences);
        
        try testing.expect(sequences.len == 1);
        try testing.expect(sequences[0] == .cursor_backward);
        try testing.expect(sequences[0].cursor_backward == 7);
    }
}

test "ANSI parser cursor positioning" {
    const allocator = testing.allocator;
    
    var parser = AnsiParser.init(allocator);
    defer parser.deinit();
    
    // Test cursor position with both parameters
    {
        const input = "\x1B[15;25H";
        const sequences = try parser.parse(input);
        defer allocator.free(sequences);
        
        try testing.expect(sequences.len == 1);
        try testing.expect(sequences[0] == .cursor_position);
        try testing.expect(sequences[0].cursor_position.row == 15);
        try testing.expect(sequences[0].cursor_position.col == 25);
    }
    
    // Test cursor position with single parameter
    {
        const input = "\x1B[10H";
        const sequences = try parser.parse(input);
        defer allocator.free(sequences);
        
        try testing.expect(sequences.len == 1);
        try testing.expect(sequences[0] == .cursor_position);
        try testing.expect(sequences[0].cursor_position.row == 10);
        try testing.expect(sequences[0].cursor_position.col == 1);
    }
    
    // Test cursor position with no parameters (should default to 1,1)
    {
        const input = "\x1B[H";
        const sequences = try parser.parse(input);
        defer allocator.free(sequences);
        
        try testing.expect(sequences.len == 1);
        try testing.expect(sequences[0] == .cursor_position);
        try testing.expect(sequences[0].cursor_position.row == 1);
        try testing.expect(sequences[0].cursor_position.col == 1);
    }
}

test "ANSI parser clear screen sequences" {
    const allocator = testing.allocator;
    
    var parser = AnsiParser.init(allocator);
    defer parser.deinit();
    
    // Test clear from cursor to end of screen
    {
        const input = "\x1B[0J";
        const sequences = try parser.parse(input);
        defer allocator.free(sequences);
        
        try testing.expect(sequences.len == 1);
        try testing.expect(sequences[0] == .clear_screen);
        try testing.expect(sequences[0].clear_screen == .from_cursor_to_end);
    }
    
    // Test clear from start of screen to cursor
    {
        const input = "\x1B[1J";
        const sequences = try parser.parse(input);
        defer allocator.free(sequences);
        
        try testing.expect(sequences.len == 1);
        try testing.expect(sequences[0] == .clear_screen);
        try testing.expect(sequences[0].clear_screen == .from_start_to_cursor);
    }
    
    // Test clear entire screen
    {
        const input = "\x1B[2J";
        const sequences = try parser.parse(input);
        defer allocator.free(sequences);
        
        try testing.expect(sequences.len == 1);
        try testing.expect(sequences[0] == .clear_screen);
        try testing.expect(sequences[0].clear_screen == .entire);
    }
    
    // Test clear entire screen (default parameter)
    {
        const input = "\x1B[J";
        const sequences = try parser.parse(input);
        defer allocator.free(sequences);
        
        try testing.expect(sequences.len == 1);
        try testing.expect(sequences[0] == .clear_screen);
        try testing.expect(sequences[0].clear_screen == .from_cursor_to_end);
    }
}

test "ANSI parser clear line sequences" {
    const allocator = testing.allocator;
    
    var parser = AnsiParser.init(allocator);
    defer parser.deinit();
    
    // Test clear from cursor to end of line
    {
        const input = "\x1B[0K";
        const sequences = try parser.parse(input);
        defer allocator.free(sequences);
        
        try testing.expect(sequences.len == 1);
        try testing.expect(sequences[0] == .clear_line);
        try testing.expect(sequences[0].clear_line == .from_cursor_to_end);
    }
    
    // Test clear from start of line to cursor
    {
        const input = "\x1B[1K";
        const sequences = try parser.parse(input);
        defer allocator.free(sequences);
        
        try testing.expect(sequences.len == 1);
        try testing.expect(sequences[0] == .clear_line);
        try testing.expect(sequences[0].clear_line == .from_start_to_cursor);
    }
    
    // Test clear entire line
    {
        const input = "\x1B[2K";
        const sequences = try parser.parse(input);
        defer allocator.free(sequences);
        
        try testing.expect(sequences.len == 1);
        try testing.expect(sequences[0] == .clear_line);
        try testing.expect(sequences[0].clear_line == .entire);
    }
}

test "ANSI parser graphics mode sequences" {
    const allocator = testing.allocator;
    
    var parser = AnsiParser.init(allocator);
    defer parser.deinit();
    
    // Test single graphics mode parameter
    {
        const input = "\x1B[1m"; // Bold
        const sequences = try parser.parse(input);
        defer allocator.free(sequences);
        
        try testing.expect(sequences.len == 1);
        try testing.expect(sequences[0] == .set_graphics_mode);
        try testing.expect(sequences[0].set_graphics_mode.len == 1);
        try testing.expect(sequences[0].set_graphics_mode[0] == 1);
        
        // Free the owned slice
        allocator.free(sequences[0].set_graphics_mode);
    }
    
    // Test multiple graphics mode parameters
    {
        const input = "\x1B[1;31;42m"; // Bold, red foreground, green background
        const sequences = try parser.parse(input);
        defer allocator.free(sequences);
        
        try testing.expect(sequences.len == 1);
        try testing.expect(sequences[0] == .set_graphics_mode);
        try testing.expect(sequences[0].set_graphics_mode.len == 3);
        try testing.expect(sequences[0].set_graphics_mode[0] == 1);   // Bold
        try testing.expect(sequences[0].set_graphics_mode[1] == 31);  // Red foreground
        try testing.expect(sequences[0].set_graphics_mode[2] == 42);  // Green background
        
        // Free the owned slice
        allocator.free(sequences[0].set_graphics_mode);
    }
    
    // Test reset graphics mode
    {
        const input = "\x1B[0m";
        const sequences = try parser.parse(input);
        defer allocator.free(sequences);
        
        try testing.expect(sequences.len == 1);
        try testing.expect(sequences[0] == .set_graphics_mode);
        try testing.expect(sequences[0].set_graphics_mode.len == 1);
        try testing.expect(sequences[0].set_graphics_mode[0] == 0);
        
        // Free the owned slice
        allocator.free(sequences[0].set_graphics_mode);
    }
}

test "ANSI parser multiple sequences in one input" {
    const allocator = testing.allocator;
    
    var parser = AnsiParser.init(allocator);
    defer parser.deinit();
    
    const input = "\x1B[2J\x1B[1;1H\x1B[31m";
    const sequences = try parser.parse(input);
    defer allocator.free(sequences);
    
    try testing.expect(sequences.len == 3);
    
    // First sequence: clear screen
    try testing.expect(sequences[0] == .clear_screen);
    try testing.expect(sequences[0].clear_screen == .entire);
    
    // Second sequence: cursor position
    try testing.expect(sequences[1] == .cursor_position);
    try testing.expect(sequences[1].cursor_position.row == 1);
    try testing.expect(sequences[1].cursor_position.col == 1);
    
    // Third sequence: graphics mode
    try testing.expect(sequences[2] == .set_graphics_mode);
    try testing.expect(sequences[2].set_graphics_mode.len == 1);
    try testing.expect(sequences[2].set_graphics_mode[0] == 31);
    
    // Free the owned slice from graphics mode
    allocator.free(sequences[2].set_graphics_mode);
}

test "ANSI parser invalid and unknown sequences" {
    const allocator = testing.allocator;
    
    var parser = AnsiParser.init(allocator);
    defer parser.deinit();
    
    // Test unknown escape sequence
    {
        const input = "\x1B[99Z"; // Unknown final character
        const sequences = try parser.parse(input);
        defer allocator.free(sequences);
        
        try testing.expect(sequences.len == 1);
        try testing.expect(sequences[0] == .unknown);
        try testing.expect(sequences[0].unknown.len == 1);
        try testing.expect(sequences[0].unknown[0] == 'Z');
    }
    
    // Test incomplete sequence (should be ignored)
    {
        const input = "\x1B["; // Incomplete
        const sequences = try parser.parse(input);
        defer allocator.free(sequences);
        
        try testing.expect(sequences.len == 0);
    }
}

test "ANSI parser edge cases" {
    const allocator = testing.allocator;
    
    var parser = AnsiParser.init(allocator);
    defer parser.deinit();
    
    // Test empty input
    {
        const input = "";
        const sequences = try parser.parse(input);
        defer allocator.free(sequences);
        
        try testing.expect(sequences.len == 0);
    }
    
    // Test input with no escape sequences
    {
        const input = "Hello, World!";
        const sequences = try parser.parse(input);
        defer allocator.free(sequences);
        
        try testing.expect(sequences.len == 0);
    }
    
    // Test escape character without following sequence
    {
        const input = "\x1B";
        const sequences = try parser.parse(input);
        defer allocator.free(sequences);
        
        try testing.expect(sequences.len == 0);
    }
    
    // Test mixed content with escape sequences
    {
        const input = "Hello \x1B[31mWorld\x1B[0m!";
        const sequences = try parser.parse(input);
        defer allocator.free(sequences);
        
        try testing.expect(sequences.len == 2);
        try testing.expect(sequences[0] == .set_graphics_mode);
        try testing.expect(sequences[1] == .set_graphics_mode);
        
        // Free the owned slices
        allocator.free(sequences[0].set_graphics_mode);
        allocator.free(sequences[1].set_graphics_mode);
    }
}
