const std = @import("std");

pub fn main() void {
    // Test different file descriptor types
    const fd1: std.posix.fd_t = 0;
    const fd2: std.c.c_int = 0;
    _ = fd1;
    _ = fd2;
    std.debug.print("Testing fd types\n", .{});
}
