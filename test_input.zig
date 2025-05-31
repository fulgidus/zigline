const std = @import("std");
const posix = std.posix;
const print = std.debug.print;

pub fn main() !void {
    print("Testing basic input handling...\n");
    print("Type something and press Enter (or Ctrl+C to exit):\n");

    const stdin = std.io.getStdIn().reader();
    var buffer: [256]u8 = undefined;

    while (true) {
        print("> ");

        if (try stdin.readUntilDelimiterOrEof(buffer[0..], '\n')) |input| {
            print("You typed: '{s}'\n", .{std.mem.trim(u8, input, " \t\n\r")});

            if (std.mem.eql(u8, std.mem.trim(u8, input, " \t\n\r"), "exit")) {
                break;
            }
        } else {
            print("EOF received, exiting...\n");
            break;
        }
    }
}
