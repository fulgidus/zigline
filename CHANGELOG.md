# Changelog

All notable changes to the Zigline project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Phase 5 Complete**: Raylib GUI Integration with FiraCode Font Support
  - Stable Raylib-based GUI backend replacing problematic DVUI implementation
  - FiraCode monospace font integration with automatic loading and fallback system
  - Custom font rendering with precise character metrics (8x16 pixels)
  - Programming ligatures support for enhanced code readability
  - Cross-platform X11/GLFW display backend with OpenGL rendering
  - Real-time terminal content rendering with custom font support
  - Proper resource management with automatic font cleanup
  - Enhanced status display showing PTY status, cursor position, and frame counter
- **Phase 2 Complete**: PTY (Pseudo Terminal) management system
  - PTY initialization and shell spawning functionality
  - Shell process communication with pipe-based approach
  - Non-blocking data availability checking with `hasData()` method
  - Timeout-based reading with `readWithTimeout()` method
  - Proper process cleanup and PTY deinitialization
  - Enhanced PTY testing with multiple shell commands
- **Phase 3 Complete**: ANSI escape sequence parsing and terminal buffer management
  - Complete ANSI parser with state machine for escape sequence processing
  - Terminal buffer with cell-based character storage and attribute support
  - ANSI processor integration for real-time terminal output processing
  - Support for cursor movement commands (up, down, forward, backward, position)
  - Screen manipulation commands (clear screen, clear line variants)
  - Color and graphics mode support framework
  - Comprehensive terminal scrolling and line manipulation
  - Integration testing of ANSI processing with terminal buffer

### Fixed
- **UI Stability**: Completely resolved "ogni rerender cancella la ui" (UI clearing on every render) issue
  - Migrated from unstable DVUI backend to stable Raylib implementation
  - Fixed string type mismatches in font loading functions ([:0]const u8 vs [*:0]const u8)
  - Corrected raylib function calls to use proper raylib-zig binding syntax
  - Fixed loadFontEx function call parameters (removed incorrect fourth parameter)
  - Resolved all logging format string requirements for Zig 0.14.0
- **Build System**: Fixed all compilation errors for Zig 0.14.0 compatibility
  - Resolved X11 development dependencies for raylib compilation
  - Fixed PTY module file descriptor type issues (os.fd_t → posix.fd_t)
  - Updated all os.* calls to posix.* equivalents
  - Fixed ChildProcess reference (std.process.Child)
  - Added libc linking to build.zig for proper system calls
  - Fixed format string slice errors ({} → {s} for strings, {any} for complex types)
  - Resolved unused variable warnings in logger and buffer modules
  - Fixed ANSI parser cursor pointer assignment syntax
  - Fixed terminal buffer optional binding syntax (if (const x = ...) → if (...) |x|)

### Changed
- Enhanced PTY communication from basic pipe to improved pipe-based approach
- Improved event loop with better command testing and response handling
- Enhanced logging with more detailed debug information for PTY and ANSI operations

## [0.1.0] - 2025-05-31

### Added
- Initial project setup for Zigline terminal emulator
- Basic Zig build configuration with executable and test targets
- Main application entry point with version display
- Project documentation including README and changelog
- Development environment setup with GitHub Copilot instructions
- Foundation for terminal emulation features (placeholders)
- MIT License placeholder
- Git repository initialization

### Security
- No security features implemented yet (early development stage)
