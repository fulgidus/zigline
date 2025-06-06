const std = @import("std");
const posix = std.posix;

pub fn main() !void {
    // This will help us understand the correct waitpid signature
    std.debug.print("waitpid function type: {}\n", .{@TypeOf(posix.waitpid)});

    // Let's see what WaitPidResult contains
    const WaitPidResult = posix.WaitPidResult;
    std.debug.print("WaitPidResult type: {}\n", .{WaitPidResult});
}
