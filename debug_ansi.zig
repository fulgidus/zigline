const std = @import("std");
const AnsiParser = @import("src/terminal/ansi.zig").AnsiParser;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parser = AnsiParser.init(allocator);
    defer parser.deinit();

    // Test the failing case
    const input = "\x1B[10H";
    const sequences = try parser.parse(input);
    defer parser.freeSequences(sequences);

    std.debug.print("Input: {s}\n", .{input});
    std.debug.print("Sequences length: {d}\n", .{sequences.len});

    if (sequences.len > 0) {
        switch (sequences[0]) {
            .cursor_position => |pos| {
                std.debug.print("Cursor position: row={d}, col={d}\n", .{ pos.row, pos.col });
            },
            else => {
                std.debug.print("Not a cursor position sequence\n");
            },
        }
    }
}
