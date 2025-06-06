const std = @import("std");
const print = std.debug.print;

// Import core components
const Terminal = @import("core/terminal.zig").Terminal;
const Logger = @import("core/logger.zig");
const PTY = @import("core/pty.zig").PTY;
const TerminalBuffer = @import("terminal/buffer.zig").TerminalBuffer;
const AnsiProcessor = @import("terminal/ansi.zig").AnsiProcessor;
const InputProcessor = @import("input/processor.zig").InputProcessor;
const Gui = @import("ui/gui.zig").Gui;

// Version constant following semantic versioning
const VERSION = "0.3.0";

// Main entry point for the Zigline terminal emulator
pub fn main() !void {
    print("Zigline Terminal Emulator v{s}\n", .{VERSION});
    print("An experimental terminal emulator written in Zig\n", .{});
    print("Phase 5: DVUI GUI Integration with Fira Code font\n", .{});
    print("Starting GUI mode...\n\n", .{});

    // Initialize general purpose allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize global logger
    Logger.initGlobal(.info);
    Logger.info("Zigline v{s} starting up with GUI", .{VERSION});

    // Initialize the terminal emulator with GUI
    try initializeTerminalWithGui(allocator);

    Logger.info("Zigline shutting down", .{});
}

// Initialize the terminal emulator components
fn initializeTerminal(allocator: std.mem.Allocator) !void {
    Logger.info("Initializing terminal emulator...", .{});

    // Create a basic terminal instance
    var terminal = Terminal.init(allocator, 80, 24) catch |err| {
        Logger.err("Failed to initialize terminal: {}", .{err});
        return err;
    };
    defer terminal.deinit();

    Logger.info("Terminal emulator initialized successfully", .{});
    Logger.info("Terminal size: {}x{}", .{ terminal.buffer.width, terminal.buffer.height });

    const cursor_pos = terminal.getCursorPosition();
    Logger.debug("Cursor position: {},{}", .{ cursor_pos.x, cursor_pos.y });

    // Initialize PTY for shell communication (Fase 2)
    var pty = PTY.init(allocator) catch |err| {
        Logger.warn("Failed to initialize PTY: {} (continuing without PTY)", .{err});
        // Continue without PTY for now
        try basicEventLoop(&terminal, null);
        return;
    };
    defer pty.deinit();

    Logger.info("PTY initialized successfully", .{});

    Logger.info("Shell spawned successfully", .{});

    // TODO: Implement core terminal emulation features:
    // - Advanced input handling and processing (Fase 4) ✓
    // - Text rendering and display (Fase 5)
    // - ANSI escape sequence processing (Fase 3) ✓
    // - Command execution and process management (Fase 2) ✓

    print("Ready to accept input with enhanced keyboard support\n", .{});

    // Enhanced event loop with keyboard input support
    try interactiveEventLoop(&terminal, &pty, allocator);

    // Test ANSI processing (Fase 3)
    try testAnsiProcessing(allocator);
}

// Initialize the terminal emulator with GUI (Phase 5)
fn initializeTerminalWithGui(allocator: std.mem.Allocator) !void {
    Logger.info("Initializing terminal emulator with DVUI GUI...", .{});

    // Create a basic terminal instance
    var terminal = Terminal.init(allocator, 80, 24) catch |err| {
        Logger.err("Failed to initialize terminal: {}", .{err});
        return err;
    };
    defer terminal.deinit();

    Logger.info("Terminal emulator initialized successfully", .{});
    Logger.info("Terminal size: {}x{}", .{ terminal.buffer.width, terminal.buffer.height });

    // Initialize PTY for shell communication
    var pty = PTY.init(allocator) catch |err| {
        Logger.warn("Failed to initialize PTY: {} (continuing without PTY)", .{err});
        return err;
    };
    // Defer PTY deinitialization until after GUI is done
    // defer pty.deinit(); // Moved down

    Logger.info("PTY initialized successfully", .{});

    Logger.info("Shell spawned successfully", .{});

    // Initialize input processor (optional for GUI mode)
    var input_processor_opt: ?InputProcessor = null;
    if (InputProcessor.init(allocator)) |input_proc| {
        input_processor_opt = input_proc;
        Logger.info("Input processor initialized successfully", .{});
    } else |err| {
        Logger.warn("Failed to initialize input processor (continuing without terminal keyboard handling): {}", .{err});
    }
    defer if (input_processor_opt) |*input_proc| input_proc.deinit();

    // Initialize GUI - pass PTY ownership to GUI
    var gui = Gui.init(allocator, &terminal, if (input_processor_opt) |*ip| ip else null, &pty) catch |err| {
        Logger.err("Failed to initialize GUI: {}", .{err});
        pty.deinit(); // Clean up PTY if GUI init fails
        return err;
    };
    defer gui.deinit();
    // Note: PTY will be cleaned up by GUI deinit, no need for separate defer

    Logger.info("GUI initialized successfully with DVUI", .{});

    // Run the GUI main loop
    try gui.run();

    Logger.info("GUI main loop completed, performing cleanup", .{});
    
    // Explicitly clean up PTY after GUI loop ends
    pty.deinit();
}

// Enhanced interactive event loop with keyboard input support (Fase 4)
fn interactiveEventLoop(terminal: *Terminal, pty: *PTY, allocator: std.mem.Allocator) !void {
    Logger.info("Entering interactive event loop with keyboard input support...", .{});

    // Initialize input processor
    var input_processor = InputProcessor.init(allocator) catch |err| {
        Logger.warn("Failed to initialize input processor: {} (falling back to basic event loop)", .{err});
        try basicEventLoop(terminal, pty);
        return;
    };
    defer input_processor.deinit();

    // Enable keyboard input capture
    input_processor.enable() catch |err| {
        Logger.warn("Failed to enable keyboard input: {} (falling back to basic event loop)", .{err});
        try basicEventLoop(terminal, pty);
        return;
    };
    defer input_processor.disable() catch |disable_err| {
        Logger.warn("Failed to disable keyboard input: {}", .{disable_err});
    };

    Logger.info("Interactive mode enabled. Type commands and press Enter. Ctrl+C to interrupt, Ctrl+D to exit.", .{});
    print("zigline $ ", .{});

    // Main interactive loop
    var should_exit = false;
    while (!should_exit) {
        // Process keyboard input (with timeout)
        const maybe_command = input_processor.processInput(pty) catch |err| {
            Logger.debug("Input processing error: {}", .{err});
            continue;
        };

        if (maybe_command) |command| {
            defer allocator.free(command);

            // Check for exit commands
            const trimmed_command = std.mem.trim(u8, command, " \t\n\r");
            if (std.mem.eql(u8, trimmed_command, "exit") or std.mem.eql(u8, trimmed_command, "quit")) {
                Logger.info("Exit command received", .{});
                should_exit = true;
                break;
            }

            // Send command to PTY
            if (trimmed_command.len > 0) {
                Logger.debug("Sending command to shell: {s}", .{trimmed_command});
                _ = pty.write(command) catch |err| {
                    Logger.warn("Failed to send command to PTY: {}", .{err});
                };
            }

            // Brief pause to allow shell to process
            std.time.sleep(50000000); // 50ms

            // Read and display shell output
            try readAndDisplayPTYOutput(pty, terminal);

            // Show prompt for next command
            print("zigline $ ", .{});
        }

        // Read any pending PTY output between input attempts
        try readAndDisplayPTYOutput(pty, terminal);
    }

    Logger.info("Interactive event loop completed", .{});
}

// Helper function to read and display PTY output
fn readAndDisplayPTYOutput(pty: *PTY, terminal: *Terminal) !void {
    var buffer: [1024]u8 = undefined;

    // Read all available output
    while (pty.hasData()) {
        const bytes_read = pty.readWithTimeout(buffer[0..], 50) catch |err| {
            if (err == error.WouldBlock or err == error.NoData) break;
            Logger.debug("PTY read error: {}", .{err});
            break;
        };

        if (bytes_read > 0) {
            const output = buffer[0..bytes_read];

            // Process the output to handle carriage returns properly for display
            var display_output = std.ArrayList(u8).init(terminal.allocator);
            defer display_output.deinit();

            for (output) |byte| {
                if (byte == '\r') {
                    // Convert bare carriage return to carriage return + newline for proper display
                    try display_output.append('\r');
                } else if (byte == '\n') {
                    // Ensure we have proper line ending
                    try display_output.append('\n');
                } else {
                    try display_output.append(byte);
                }
            }

            // Print processed output
            print("{s}", .{display_output.items});

            // Process through ANSI parser (demonstration)
            var ansi_processor = AnsiProcessor.init(terminal.allocator);
            defer ansi_processor.deinit();

            var cursor_x: u32 = 0;
            var cursor_y: u32 = 0;
            ansi_processor.processInput(output, &terminal.buffer, &cursor_x, &cursor_y) catch |err| {
                Logger.debug("ANSI processing error: {}", .{err});
            };
        }
    }
}

// Enhanced event loop for the terminal emulator
fn basicEventLoop(terminal: *Terminal, pty: ?*PTY) !void {
    Logger.info("Entering event loop...", .{});

    if (pty) |p| {
        Logger.info("Event loop running with PTY support", .{});

        // Test PTY communication
        try testPTYCommunication(p);

        // TODO: Implement proper event loop with:
        // - Asynchronous PTY reading/writing (Fase 2)
        // - Keyboard input handling (Fase 4)
        // - Terminal output processing (Fase 3)
        // - Window resize events (Fase 5)
        // - Signal handling

        // For now, just demonstrate basic PTY functionality
        const test_command = "echo 'Hello from Zigline PTY!'\n";
        _ = p.write(test_command) catch |err| {
            Logger.warn("Failed to write to PTY: {}", .{err});
        };

        // Read response
        var buffer: [1024]u8 = undefined;
        const bytes_read = p.read(buffer[0..]) catch |err| {
            Logger.warn("Failed to read from PTY: {}", .{err});
            std.time.sleep(1000000000); // Sleep for 1 second
            Logger.info("Event loop completed", .{});
            return;
        };

        if (bytes_read > 0) {
            Logger.info("PTY output: '{s}'", .{buffer[0..bytes_read]});
        }
    } else {
        Logger.info("Event loop running without PTY", .{});
    }

    _ = terminal; // Suppress unused parameter warning for now

    print("This is a placeholder implementation\n", .{});

    // For now, just wait for a brief moment to show the program is running
    std.time.sleep(2000000000); // Sleep for 2 seconds
    Logger.info("Event loop completed", .{});
}

// Test PTY communication with improved functionality
fn testPTYCommunication(pty: *PTY) !void {
    Logger.info("Testing improved PTY communication...", .{});

    // Send a simple command
    const test_commands = [_][]const u8{
        "echo 'PTY Test - Zigline v0.1.0'\n",
        "pwd\n",
        "date\n",
        "whoami\n",
    };

    for (test_commands) |cmd| {
        Logger.debug("Sending command: {s}", .{cmd});
        _ = pty.write(cmd) catch |err| {
            Logger.warn("Failed to send command '{s}': {}", .{ cmd, err });
            continue;
        };

        // Wait for response with improved timing
        std.time.sleep(300000000); // 300ms

        // Read all available output using new hasData method
        var buffer: [1024]u8 = undefined;
        while (pty.hasData()) {
            const bytes_read = pty.readWithTimeout(buffer[0..], 100) catch |err| {
                if (err == error.WouldBlock or err == error.NoData) break;
                Logger.debug("Read error for command '{s}': {}", .{ cmd, err });
                break;
            };

            if (bytes_read > 0) {
                Logger.info("Shell response: '{s}'", .{buffer[0..bytes_read]});
            }
        }
    }

    Logger.info("Enhanced PTY communication test completed", .{});
}

// Test ANSI sequence processing (Fase 3)
fn testAnsiProcessing(allocator: std.mem.Allocator) !void {
    Logger.info("Testing ANSI sequence processing (Fase 3)...", .{});

    // Create a terminal buffer for testing
    var buffer = try TerminalBuffer.init(allocator, 80, 24);
    defer buffer.deinit();

    // Create ANSI processor
    var ansi_processor = AnsiProcessor.init(allocator);
    defer ansi_processor.deinit();

    // Test cursor position
    var cursor_x: u32 = 0;
    var cursor_y: u32 = 0;

    // Test sequences from typical terminal output
    const test_sequences = [_][]const u8{
        "Hello, World!\n",
        "\x1B[2J", // Clear screen
        "\x1B[1;1H", // Move cursor to home position
        "Zigline Terminal Emulator\n",
        "\x1B[31mRed text\x1B[0m\n", // Red text with reset
        "\x1B[5A", // Move cursor up 5 lines
        "\x1B[10C", // Move cursor right 10 columns
        "Positioned text\n",
        "\x1B[K", // Clear line from cursor
        "Clean line\n",
    };

    for (test_sequences, 0..) |sequence, i| {
        Logger.debug("Processing ANSI sequence {}: '{s}'", .{ i + 1, sequence });

        try ansi_processor.processInput(sequence, &buffer, &cursor_x, &cursor_y);
        Logger.debug("Cursor position after sequence {}: {},{}", .{ i + 1, cursor_x, cursor_y });

        // Log the content of a few cells to show buffer state
        if (cursor_y < buffer.height) {
            if (buffer.getCell(0, cursor_y)) |cell| {
                Logger.debug("Cell at (0,{}): '{c}'", .{ cursor_y, @as(u8, @intCast(cell.char)) });
            }
        }
    }

    Logger.info("ANSI sequence processing test completed successfully", .{});
}

// Test function for unit testing
test "version constant" {
    const testing = std.testing;
    try testing.expect(std.mem.eql(u8, VERSION, "0.3.0"));
}

test "basic functionality" {
    // Basic test to ensure the program can initialize
    const allocator = std.testing.allocator;

    // Test that we can call initialize without crashing
    // Note: This is a minimal test for the early stage of the project
    _ = allocator;
}
