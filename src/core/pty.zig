//! Pseudo-Terminal (PTY) functionality for spawning and managing shell processes.
//! Handles PTY creation, process spawning, and communication with child processes.

const std = @import("std");
const builtin = @import("builtin");
const os = std.os;
const posix = std.posix;
const Logger = @import("logger.zig");

// C function declarations for PTY operations
extern "c" fn grantpt(fd: c_int) c_int;
extern "c" fn unlockpt(fd: c_int) c_int;
extern "c" fn ptsname(fd: c_int) ?[*:0]u8;

/// Errors that can occur during PTY operations
pub const PTYError = error{
    OpenPTYFailed,
    SpawnProcessFailed,
    SetNonBlockingFailed,
    TerminalConfigFailed,
    ReadFailed,
    WriteFailed,
    WouldBlock,
    OutOfMemory,
};

/// PTY management structure
pub const PTY = struct {
    master_fd: posix.fd_t,
    slave_fd: posix.fd_t,
    child_pid: posix.pid_t,
    allocator: std.mem.Allocator,
    logger: *Logger.Logger,
    child_terminated: bool, // Track if child has already been terminated

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

        Logger.debug("PTY initialized successfully - master_fd: {d}, child_pid: {d}", .{ master_fd, child_pid });

        return PTY{
            .master_fd = master_fd,
            .slave_fd = slave_fd,
            .child_pid = child_pid,
            .allocator = allocator,
            .logger = Logger.getGlobal(),
            .child_terminated = false, // Initialize child as not terminated
        };
    }

    /// Safe close that handles BADF errors (already closed descriptors)
    fn safeClose(fd: posix.fd_t) void {
        // Use direct syscall to avoid Zig's unreachable for BADF
        const result = std.os.linux.close(fd);
        if (result != 0) {
            // Log the error but don't panic - file might already be closed
            Logger.debug("Close syscall returned error code: {d} for fd: {d}", .{ result, fd });
        }
    }

    /// Clean up PTY resources
    pub fn deinit(self: *PTY) void {
        Logger.info("Cleaning up PTY resources", .{});

        // First terminate the child process gracefully
        self.terminateChild();

        // Close file descriptors safely using direct syscall
        Logger.debug("Closing master_fd: {d}", .{self.master_fd});
        safeClose(self.master_fd);

        Logger.debug("Closing slave_fd: {d}", .{self.slave_fd});
        safeClose(self.slave_fd);

        Logger.info("PTY cleanup complete", .{});
    }

    /// Terminate child process gracefully
    pub fn terminateChild(self: *PTY) void {
        if (self.child_terminated) {
            Logger.info("Child process {d} already terminated", .{self.child_pid});
            return;
        }

        Logger.info("Terminating child process {d}", .{self.child_pid});

        // Check if child is still alive - handle race conditions properly
        const wait_result = posix.waitpid(self.child_pid, 1); // WNOHANG

        if (wait_result.pid == 0) {
            // Child is still running, send SIGTERM
            Logger.info("Child process still running, sending SIGTERM", .{});
            _ = posix.kill(self.child_pid, posix.SIG.TERM) catch |err| {
                Logger.warn("Failed to send SIGTERM to child process: {}", .{err});
            };

            // Wait briefly for graceful shutdown
            std.time.sleep(100_000_000); // 100ms

            // Check again
            const wait_result2 = posix.waitpid(self.child_pid, 1); // WNOHANG

            if (wait_result2.pid == 0) {
                // Still running, force kill
                Logger.warn("Child process did not respond to SIGTERM, sending SIGKILL", .{});
                _ = posix.kill(self.child_pid, posix.SIG.KILL) catch |err| {
                    Logger.err("Failed to send SIGKILL to child process: {}", .{err});
                };

                // Final wait without WNOHANG (but should be quick now)
                const final_result = posix.waitpid(self.child_pid, 0);
                Logger.debug("Final waitpid result: pid={d}, status={d}", .{ final_result.pid, final_result.status });
            } else {
                Logger.info("Child process terminated after SIGTERM", .{});
            }
        } else {
            // Child has already exited
            Logger.info("Child process {d} has already exited with status: {d}", .{ wait_result.pid, wait_result.status });
        }

        self.child_terminated = true;
        Logger.info("Child process termination complete", .{});
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
        Logger.debug("Resizing PTY to {d}x{d}", .{ cols, rows });

        // Set window size using TIOCSWINSZ ioctl
        if (builtin.os.tag == .linux) {
            const TIOCSWINSZ = 0x5414;
            const winsize = extern struct {
                ws_row: u16,
                ws_col: u16,
                ws_xpixel: u16,
                ws_ypixel: u16,
            };

            const ws = winsize{
                .ws_row = rows,
                .ws_col = cols,
                .ws_xpixel = 0,
                .ws_ypixel = 0,
            };

            const result = std.c.ioctl(self.master_fd, TIOCSWINSZ, &ws);
            if (result != 0) {
                Logger.warn("Failed to set PTY window size: ioctl returned {d}", .{result});
            } else {
                Logger.info("PTY window size set to {d}x{d} successfully", .{ cols, rows });
            }
        } else {
            Logger.warn("PTY resize not implemented for this platform", .{});
        }
    }

    /// Check if PTY has data available for reading
    pub fn hasData(self: *PTY) bool {
        // Use poll() to check for data availability without consuming data
        var poll_fd = [_]posix.pollfd{
            .{
                .fd = self.master_fd,
                .events = posix.POLL.IN,
                .revents = 0,
            },
        };

        // Poll with 0 timeout (non-blocking check)
        const poll_result = posix.poll(&poll_fd, 0) catch |err| {
            Logger.debug("Poll error in hasData(): {}", .{err});
            return false;
        };

        // Check if data is available for reading
        if (poll_result > 0 and (poll_fd[0].revents & posix.POLL.IN) != 0) {
            return true;
        }

        return false;
    }

    /// Check if the child shell process is still alive
    pub fn isChildAlive(self: *PTY) bool {
        // If we already know the child has terminated, return false immediately
        if (self.child_terminated) {
            return false;
        }

        // Use direct syscall to avoid Zig's unreachable for ECHILD
        var status: u32 = 0;
        const syscall_result = std.os.linux.wait4(self.child_pid, &status, 1, null); // 1 = WNOHANG

        if (syscall_result < 0) {
            // waitpid failed - likely ECHILD (no such child)
            Logger.debug("waitpid syscall failed with error: {d} for child {d}", .{ syscall_result, self.child_pid });
            self.child_terminated = true;
            return false;
        }

        if (syscall_result == 0) {
            // Child is still running
            return true;
        } else if (syscall_result == self.child_pid) {
            // Child has exited
            Logger.warn("Child process {d} has exited with status: {d}", .{ self.child_pid, status });
            self.child_terminated = true;
            return false;
        }

        return false;
    }
};

/// Open PTY master device
fn openPTYMaster() PTYError!posix.fd_t {
    const master_fd = posix.open("/dev/ptmx", .{ .ACCMODE = .RDWR, .NOCTTY = true }, 0) catch {
        Logger.err("Failed to open /dev/ptmx", .{});
        return PTYError.OpenPTYFailed;
    };

    // Grant access to slave PTY (macOS specific)
    // In a production system, you'd call grantpt() and unlockpt()
    // For now, we'll try to continue without these calls
    Logger.debug("Opened PTY master: {d}", .{master_fd});

    return master_fd;
}

/// Open corresponding PTY slave device
fn openPTYSlave(master_fd: posix.fd_t) PTYError!posix.fd_t {
    Logger.debug("Opening PTY slave for master fd: {d}", .{master_fd});

    // First, grant access to the slave PTY
    if (grantpt(@intCast(master_fd)) != 0) {
        Logger.err("grantpt() failed: {}", .{std.c._errno().*});
        return PTYError.OpenPTYFailed;
    }

    // Unlock the slave PTY
    if (unlockpt(@intCast(master_fd)) != 0) {
        Logger.err("unlockpt() failed: {}", .{std.c._errno().*});
        return PTYError.OpenPTYFailed;
    }

    // Get the slave device name
    const slave_name_ptr = ptsname(@intCast(master_fd));
    if (slave_name_ptr == null) {
        Logger.err("ptsname() failed: {}", .{std.c._errno().*});
        return PTYError.OpenPTYFailed;
    }

    // Convert C string to Zig string - handle the optional pointer properly
    const slave_name = std.mem.span(slave_name_ptr.?);
    Logger.debug("Slave PTY device name: {s}", .{slave_name});

    // Open the slave device
    const slave_fd = posix.open(slave_name, .{ .ACCMODE = .RDWR, .NOCTTY = true }, 0) catch |err| {
        Logger.err("Failed to open slave PTY device {s}: {any}", .{ slave_name, err });
        return PTYError.OpenPTYFailed;
    };

    Logger.debug("Opened PTY slave: {s} -> {d}", .{ slave_name, slave_fd });
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
        // Child process - set up new session and job control
        Logger.debug("Child process started, setting up PTY redirection", .{});

        // Create new session to establish proper job control
        // Use direct syscall for setsid since it might not be available in all Zig versions
        const setsid_result = std.os.linux.syscall1(.setsid, 0);
        if (setsid_result != 0) {
            Logger.debug("Created new session with SID: {d}", .{setsid_result});
        } else {
            Logger.warn("Failed to create new session, continuing without job control", .{});
        }

        // Make this PTY the controlling terminal using the standard Linux ioctl
        if (builtin.target.os.tag == .linux) {
            const TIOCSCTTY = 0x540E; // Linux ioctl number for TIOCSCTTY
            const ioctl_result = std.c.ioctl(slave_fd, TIOCSCTTY, @as(c_int, 0));
            if (ioctl_result == -1) {
                Logger.warn("Failed to set controlling terminal, job control may not work properly", .{});
            } else {
                Logger.debug("Successfully set PTY as controlling terminal", .{});
            }
        }

        // Redirect stdin/stdout/stderr to slave PTY
        _ = posix.dup2(slave_fd, posix.STDIN_FILENO) catch {
            Logger.err("Failed to redirect stdin", .{});
            posix.exit(1);
        };
        _ = posix.dup2(slave_fd, posix.STDOUT_FILENO) catch {
            Logger.err("Failed to redirect stdout", .{});
            posix.exit(1);
        };
        _ = posix.dup2(slave_fd, posix.STDERR_FILENO) catch {
            Logger.err("Failed to redirect stderr", .{});
            posix.exit(1);
        };

        // Close original slave fd
        posix.close(slave_fd);

        // Get shell from environment or use default
        const shell = posix.getenv("SHELL") orelse "/bin/bash";

        // Create argv with proper shell arguments
        // Use -i flag for interactive mode but avoid -l to prevent login shell errors
        const argv = [_:null]?[*:0]const u8{
            @constCast(shell.ptr),
            "-i", // Interactive mode
            null,
        };

        Logger.debug("Executing shell: {s} with interactive mode", .{shell});

        // Use execveZ with standard environment
        // The improved PTY setup should reduce error messages
        const result = posix.execveZ(@constCast(shell.ptr), &argv, std.c.environ);

        // If we reach here, exec failed
        Logger.err("Failed to exec shell {s}: {}", .{ shell, result });
        posix.exit(1);
    }

    // Parent process - close slave fd (child has its own copy)
    posix.close(slave_fd);

    // Return child PID        Logger.debug("Shell process spawned with PID: {d}", .{pid});
    return pid;
}
