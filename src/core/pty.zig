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

        Logger.info("PTY initialized successfully - master_fd: {d}, child_pid: {d}", .{ master_fd, child_pid });

        return PTY{
            .master_fd = master_fd,
            .slave_fd = slave_fd,
            .child_pid = child_pid,
            .allocator = allocator,
            .logger = Logger.getGlobal(),
            .child_terminated = false, // Initialize child as not terminated
        };
    }

    /// Clean up PTY resources
    pub fn deinit(self: *PTY) void {
        Logger.info("Cleaning up PTY resources", .{});

        // First terminate the child process gracefully
        self.terminateChild();

        // Close file descriptors
        posix.close(self.master_fd);
        posix.close(self.slave_fd);

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
                Logger.debug("Final waitpid result: pid={}, status={}", .{ final_result.pid, final_result.status });
            } else {
                Logger.info("Child process terminated after SIGTERM", .{});
            }
        } else {
            // Child has already exited
            Logger.info("Child process {d} has already exited with status: {d}", .{ wait_result.pid, wait_result.status });
        }
        
        self.child_terminated = true;
        }

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
        const result = posix.waitpid(self.child_pid, 1); // 1 = WNOHANG on most systems

        if (result.pid == 0) {
            // Child is still running
            return true;
        } else if (result.pid == self.child_pid) {
            // Child has exited
            Logger.warn("Child process {d} has exited with status: {d}", .{ self.child_pid, result.status });
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
        // Child process - set up new session
        // Use direct system call for setsid (simplified approach)
        // For now, skip setsid to avoid compilation issues
        Logger.debug("Child process started, setting up PTY redirection", .{});

        // Make this PTY the controlling terminal
        // On macOS, we need to do this properly (simplified for now)
        // _ = posix.ioctl(slave_fd, std.os.linux.T.IOCSCTTY, @as(u32, 0)) catch {
        //     Logger.warn("Failed to set controlling terminal, continuing...", .{});
        // };

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
        const shell = posix.getenv("SHELL") orelse "/bin/zsh";

        // Set up proper environment for shell
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();

        // Create argv with proper shell arguments
        const argv = [_:null]?[*:0]u8{
            @constCast(shell.ptr),
            @constCast("-l"), // Login shell
            null,
        };

        // Set up environment with TERM variable and other essential variables
        const allocator = arena.allocator();
        var env_list = std.ArrayList([*:0]const u8).init(allocator);

        // Essential environment variables for terminal operation
        try env_list.append(try allocator.dupeZ(u8, "TERM=xterm-256color"));
        try env_list.append(try allocator.dupeZ(u8, "COLORTERM=truecolor"));

        // Copy some existing environment variables if they exist
        const important_vars = [_][]const u8{ "PATH", "HOME", "USER", "SHELL", "LANG", "LC_ALL" };
        for (important_vars) |var_name| {
            if (posix.getenv(var_name)) |value| {
                const env_string = try std.fmt.allocPrintZ(allocator, "{s}={s}", .{ var_name, value });
                try env_list.append(env_string);
            }
        }

        // Add null terminator
        try env_list.append(@as([*:0]const u8, @ptrCast(@as([*:0]const u8, ""))));

        const envp: [*:null]const ?[*:0]const u8 = @ptrCast(env_list.items.ptr);

        Logger.info("Executing shell: {s} with args: {s}", .{ shell, "-l" });
        const exec_result = posix.execveZ(@constCast(shell.ptr), &argv, envp);

        // If we reach here, exec failed
        Logger.err("Failed to exec shell {s}: {}", .{ shell, exec_result });
        posix.exit(1);

        // If exec fails, exit child process
        posix.exit(1);
    }

    // Parent process - close slave fd (child has its own copy)
    posix.close(slave_fd);

    // Return child PID
    Logger.info("Shell process spawned with PID: {d}", .{pid});
    return pid;
}
