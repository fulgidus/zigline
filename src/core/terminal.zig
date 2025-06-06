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
    buffer: TerminalBuffer,
    ansi_processor: AnsiProcessor,
    allocator: std.mem.Allocator,
    logger: *Logger.Logger,
    running: bool,
    cursor_x: u32,
    cursor_y: u32,

    /// Initialize terminal with specified dimensions (no PTY)
    pub fn init(allocator: std.mem.Allocator, cols: u16, rows: u16) TerminalError!Terminal {
        Logger.info("Initializing terminal with size {d}x{d}", .{ cols, rows });

        // Initialize terminal buffer
        const buffer = TerminalBuffer.init(allocator, cols, rows) catch |err| {
            Logger.err("Failed to initialize terminal buffer: {}", .{err});
            return TerminalError.InitializationFailed;
        };

        // Initialize ANSI processor
        const ansi_processor = AnsiProcessor.init(allocator);

        Logger.info("Terminal initialized successfully", .{});

        return Terminal{
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
        self.buffer.deinit();
        Logger.info("Terminal cleanup complete", .{});
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

    /// Get current cursor position
    pub fn getCursorPosition(self: *const Terminal) struct { x: u32, y: u32 } {
        return .{ .x = self.cursor_x, .y = self.cursor_y };
    }

    /// Resize terminal buffer
    pub fn resize(self: *Terminal, cols: u16, rows: u16) TerminalError!void {
        Logger.info("Resizing terminal to {d}x{d}", .{ cols, rows });

        // Resize the buffer
        self.buffer.resize(cols, rows) catch |err| {
            Logger.err("Failed to resize buffer: {}", .{err});
            return TerminalError.ProcessingError;
        };

        Logger.info("Terminal buffer resized successfully", .{});
    }

    /// Get current terminal buffer for rendering
    pub fn getBuffer(self: *Terminal) *TerminalBuffer {
        return &self.buffer;
    }

    /// Check if terminal is still running
    pub fn isRunning(self: *Terminal) bool {
        return self.running;
    }

    /// Stop the terminal
    pub fn stop(self: *Terminal) void {
        Logger.info("Stopping terminal", .{});
        self.running = false;
    }
};
