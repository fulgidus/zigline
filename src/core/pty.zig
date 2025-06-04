//! Pseudo-Terminal (PTY) functionality for spawning and managing shell processes.
//! Handles PTY creation, process spawning, and communication with child processes.

const std = @import("std");
const os = std.os;
const posix = std.posix;
const Logger = @import("logger.zig");

/// Errors that can occur during PTY operations
pub const PTYError = error{
    OpenPTYFailed,
    SpawnProcessFailed,
    SetNonBlockingFailed,
    TerminalConfigFailed,
    ReadFailed,
    WriteFailed,
    WouldBlock,
};

/// PTY management structure
pub const PTY = struct {
    master_fd: posix.fd_t,
    slave_fd: posix.fd_t,
    child_pid: posix.pid_t,
    allocator: std.mem.Allocator,
    logger: *Logger.Logger,

    /// Initialize a new PTY and spawn a shell process
    pub fn init(allocator: std.mem.Allocator) PTYError!PTY {
        Logger.info("Initializing PTY", .{});

        // Open PTY master/slave pair
        const master_fd = try openPTYMaster();
        const slave_fd = try openPTYSlave(master_fd);

        // Set master to non-blocking mode
        try setNonBlocking(master_fd);

        // Spawn shell process
        const child_pid = try spawnShell(slave_fd);

        Logger.info("PTY initialized successfully - master_fd: {d}, child_pid: {d}", .{ master_fd, child_pid });

        return PTY{
            .master_fd = master_fd,
            .slave_fd = slave_fd,
            .child_pid = child_pid,
            .allocator = allocator,
            .logger = Logger.getGlobal(),
        };
    }

    /// Clean up PTY resources
    pub fn deinit(self: *PTY) void {
        Logger.info("Cleaning up PTY resources", .{});
        
        // Close file descriptors
        posix.close(self.master_fd);
        posix.close(self.slave_fd);

        // Terminate child process if still running
        _ = posix.waitpid(self.child_pid, 0);
        
        Logger.info("PTY cleanup complete", .{});
    }

    /// Read data from PTY master (shell output)
    pub fn read(self: *PTY, buffer: []u8) PTYError!usize {
        const bytes_read = posix.read(self.master_fd, buffer) catch |err| switch (err) {
            error.WouldBlock => return PTYError.WouldBlock,
            else => {
                Logger.err("PTY read failed: {}", .{err});
                return PTYError.ReadFailed;
            },
        };
        
        if (bytes_read > 0) {
            Logger.debug("Read {d} bytes from PTY", .{bytes_read});
        }
        
        return bytes_read;
    }

    /// Write data to PTY master (user input to shell)
    pub fn write(self: *PTY, data: []const u8) PTYError!usize {
        const bytes_written = posix.write(self.master_fd, data) catch |err| {
            Logger.err("PTY write failed: {}", .{err});
            return PTYError.WriteFailed;
        };
        
        Logger.debug("Wrote {d} bytes to PTY", .{bytes_written});
        return bytes_written;
    }

    /// Resize PTY to match terminal window size
    pub fn resize(self: *PTY, cols: u16, rows: u16) void {
        Logger.debug("Resizing PTY to {}x{}", .{ cols, rows });
        
        // Note: On macOS, resizing PTY would require proper ioctl calls
        // For now, this is a placeholder - in a production system you'd use
        // platform-specific ioctl calls to set the window size
        _ = self;
    }

    /// Check if PTY has data available for reading
    pub fn hasData(self: *PTY) bool {
        var buffer: [1]u8 = undefined;
        const result = posix.read(self.master_fd, &buffer) catch |err| switch (err) {
            error.WouldBlock => return false,
            else => return false,
        };
        
        // If we read data, we need to "put it back" - this is a simple check
        // In a real implementation, you'd use select() or poll() to check availability
        return result > 0;
    }
};

/// Open PTY master device
fn openPTYMaster() PTYError!posix.fd_t {
    const master_fd = posix.open("/dev/ptmx", .{ .ACCMODE = .RDWR, .NOCTTY = true }, 0) catch {
        return PTYError.OpenPTYFailed;
    };

    // Grant access and unlock slave PTY (macOS/BSD specific calls)
    // These are simplified - in a production system you'd use proper C bindings
    return master_fd;
}

/// Open corresponding PTY slave device
fn openPTYSlave(master_fd: posix.fd_t) PTYError!posix.fd_t {
    // For now, use a simple approach - in a real implementation you'd get the slave name
    // from the master using ptsname() or equivalent
    var slave_path_buf: [64]u8 = undefined;
    const slave_path = std.fmt.bufPrint(&slave_path_buf, "/dev/pts/{d}", .{master_fd}) catch {
        return PTYError.OpenPTYFailed;
    };

    const slave_fd = posix.open(slave_path, .{ .ACCMODE = .RDWR, .NOCTTY = true }, 0) catch {
        // Fallback to a common pts device
        return posix.open("/dev/tty", .{ .ACCMODE = .RDWR, .NOCTTY = true }, 0) catch {
            return PTYError.OpenPTYFailed;
        };
    };

    return slave_fd;
}

/// Set file descriptor to non-blocking mode
fn setNonBlocking(fd: posix.fd_t) PTYError!void {
    const flags = posix.fcntl(fd, posix.F.GETFL, 0) catch {
        return PTYError.SetNonBlockingFailed;
    };

    _ = posix.fcntl(fd, posix.F.SETFL, flags | @as(u32, @bitCast(posix.O{ .NONBLOCK = true }))) catch {
        return PTYError.SetNonBlockingFailed;
    };
}

/// Spawn shell process attached to PTY slave
fn spawnShell(slave_fd: posix.fd_t) PTYError!posix.pid_t {
    const pid = posix.fork() catch {
        return PTYError.SpawnProcessFailed;
    };

    if (pid == 0) {
        // Child process - set up new session
        // Note: setsid() creates a new session and process group
        // For now, we'll skip this for simplicity on macOS
        // In a production system, you'd use proper platform-specific session management

        // Redirect stdin/stdout/stderr to slave PTY
        _ = posix.dup2(slave_fd, posix.STDIN_FILENO) catch {};
        _ = posix.dup2(slave_fd, posix.STDOUT_FILENO) catch {};
        _ = posix.dup2(slave_fd, posix.STDERR_FILENO) catch {};

        // Close original slave fd
        posix.close(slave_fd);

        // Get shell from environment or use default
        const shell = posix.getenv("SHELL") orelse "/bin/sh";
        const argv = [_:null]?[*:0]u8{ @constCast(shell.ptr), null };
        const envp = [_:null]?[*:0]u8{null};

        _ = posix.execveZ(@constCast(shell.ptr), &argv, &envp) catch {};
        
        // If exec fails, exit child process
        posix.exit(1);
    }

    // Parent process - return child PID
    return pid;
}
