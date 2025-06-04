//! Simple logging functionality for Zigline terminal emulator.
//! Provides structured logging with different levels for debugging and monitoring.

const std = @import("std");

/// Log levels for categorizing messages
pub const LogLevel = enum {
    debug,
    info,
    warn,
    err,

    /// Convert log level to string representation
    pub fn toString(self: LogLevel) []const u8 {
        return switch (self) {
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
        };
    }
};

/// Simple logger for the terminal emulator
pub const Logger = struct {
    level: LogLevel,
    writer: std.fs.File.Writer,

    /// Initialize logger with specified minimum level
    pub fn init(level: LogLevel) Logger {
        return Logger{
            .level = level,
            .writer = std.io.getStdErr().writer(),
        };
    }

    /// Log a message at the specified level
    pub fn log(self: *Logger, level: LogLevel, comptime format: []const u8, args: anytype) void {
        if (@intFromEnum(level) >= @intFromEnum(self.level)) {
            const timestamp = std.time.timestamp();
            self.writer.print("[{d}] {s}: ", .{ timestamp, level.toString() }) catch return;
            self.writer.print(format, args) catch return;
            self.writer.print("\n", .{}) catch return;
        }
    }

    /// Log debug message
    pub fn debug(self: *Logger, comptime format: []const u8, args: anytype) void {
        self.log(.debug, format, args);
    }

    /// Log info message
    pub fn info(self: *Logger, comptime format: []const u8, args: anytype) void {
        self.log(.info, format, args);
    }

    /// Log warning message
    pub fn warn(self: *Logger, comptime format: []const u8, args: anytype) void {
        self.log(.warn, format, args);
    }

    /// Log error message
    pub fn err(self: *Logger, comptime format: []const u8, args: anytype) void {
        self.log(.err, format, args);
    }
};

/// Global logger instance
var global_logger: Logger = undefined;
var logger_initialized: bool = false;

/// Initialize global logger
pub fn initGlobal(level: LogLevel) void {
    global_logger = Logger.init(level);
    logger_initialized = true;
}

/// Get global logger instance
pub fn getGlobal() *Logger {
    if (!logger_initialized) {
        initGlobal(.info);
    }
    return &global_logger;
}

/// Convenience functions for global logging
pub fn debug(comptime format: []const u8, args: anytype) void {
    getGlobal().debug(format, args);
}

pub fn info(comptime format: []const u8, args: anytype) void {
    getGlobal().info(format, args);
}

pub fn warn(comptime format: []const u8, args: anytype) void {
    getGlobal().warn(format, args);
}

pub fn err(comptime format: []const u8, args: anytype) void {
    getGlobal().err(format, args);
}
