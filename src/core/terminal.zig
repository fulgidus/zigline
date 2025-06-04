//! Core terminal management functionality.
//! Coordinates PTY, buffer, and ANSI processing for the terminal emulator.

const std = @import("std");
const PTY = @import("pty.zig").PTY;
const PTYError = @import("pty.zig").PTYError;
const TerminalBuffer = @import("../terminal/buffer.zig").TerminalBuffer;
const AnsiProcessor = @import("../terminal/ansi.zig").AnsiProcessor;
const Logger = @import("logger.zig");

/// Errors that can occur during terminal operations
pub const TerminalError = error{
    InitializationFailed,
    PTYError,
    ProcessingError,
} || PTYError;

/// Main terminal management structure
pub const Terminal = struct {
    pty: PTY,
    buffer: TerminalBuffer,
    ansi_processor: AnsiProcessor,
    allocator: std.mem.Allocator,
    logger: *Logger.Logger,
    running: bool,
    cursor_x: u32,
    cursor_y: u32,

    /// Initialize terminal with specified dimensions
    pub fn init(allocator: std.mem.Allocator, cols: u16, rows: u16) TerminalError!Terminal {
        Logger.info("Initializing terminal with size {}x{}", .{ cols, rows });

        // Initialize PTY
        const pty = PTY.init(allocator) catch |err| {
            Logger.err("Failed to initialize PTY: {}", .{err});
            return TerminalError.InitializationFailed;
        };

        // Initialize terminal buffer
        const buffer = TerminalBuffer.init(allocator, cols, rows) catch |err| {
            Logger.err("Failed to initialize terminal buffer: {}", .{err});
            return TerminalError.InitializationFailed;
        };

        // Initialize ANSI processor
        const ansi_processor = AnsiProcessor.init(allocator);

        Logger.info("Terminal initialized successfully", .{});

        return Terminal{
            .pty = pty,
            .buffer = buffer,
            .ansi_processor = ansi_processor,
            .allocator = allocator,
            .logger = Logger.getGlobal(),
            .running = true,
            .cursor_x = 0,
            .cursor_y = 0,
        };
    }

    /// Clean up terminal resources
    pub fn deinit(self: *Terminal) void {
        Logger.info("Cleaning up terminal resources", .{});
        self.running = false;
        self.pty.deinit();
        self.buffer.deinit();
        Logger.info("Terminal cleanup complete", .{});
    }

    /// Process incoming data from PTY and update buffer
    pub fn processInput(self: *Terminal) TerminalError!bool {
        var read_buffer: [4096]u8 = undefined;

        const bytes_read = self.pty.read(&read_buffer) catch |err| {
            Logger.err("Error reading from PTY: {}", .{err});
            return TerminalError.PTYError;
        };

        if (bytes_read == 0) {
            return false; // No data available
        }

        // Process the data through ANSI processor
        const data = read_buffer[0..bytes_read];
        try self.processData(data);

        Logger.debug("Processed {d} bytes of PTY output", .{bytes_read});
        return true;
    }

    /// Process pre-read data and update buffer
    pub fn processData(self: *Terminal, data: []const u8) TerminalError!void {
        if (data.len == 0) {
            return; // No data to process
        }

        // Process the data through ANSI processor
        self.ansi_processor.processInput(data, &self.buffer, &self.cursor_x, &self.cursor_y) catch |err| {
            Logger.err("Error processing ANSI data: {}", .{err});
            return TerminalError.ProcessingError;
        };

        Logger.debug("Processed {d} bytes of data", .{data.len});
    }

    /// Send user input to the shell via PTY
    pub fn sendInput(self: *Terminal, data: []const u8) TerminalError!void {
        _ = self.pty.write(data) catch |err| {
            Logger.err("Error writing to PTY: {}", .{err});
            return TerminalError.PTYError;
        };

        Logger.debug("Sent {d} bytes to shell", .{data.len});
    }

    /// Get current cursor position
    pub fn getCursorPosition(self: *const Terminal) struct { x: u32, y: u32 } {
        return .{ .x = self.cursor_x, .y = self.cursor_y };
    }

    /// Resize terminal and notify PTY
    pub fn resize(self: *Terminal, cols: u16, rows: u16) TerminalError!void {
        Logger.info("Resizing terminal to {}x{}", .{ cols, rows });

        // Resize the buffer
        self.buffer.resize(cols, rows) catch |err| {
            Logger.err("Failed to resize buffer: {}", .{err});
            return TerminalError.ProcessingError;
        };

        // Notify PTY of size change
        self.pty.resize(cols, rows);

        Logger.info("Terminal resize complete", .{});
    }

    /// Get current terminal buffer for rendering
    pub fn getBuffer(self: *Terminal) *TerminalBuffer {
        return &self.buffer;
    }

    /// Check if terminal is still running
    pub fn isRunning(self: *Terminal) bool {
        return self.running;
    }

    /// Shutdown the terminal
    pub fn shutdown(self: *Terminal) void {
        Logger.info("Shutting down terminal", .{});
        self.running = false;
    }
};
