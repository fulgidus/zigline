# Changelog

All notable changes to the Zigline project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Fase 2 Complete**: PTY (Pseudo Terminal) management system
  - PTY initialization and shell spawning functionality
  - Shell process communication with pipe-based approach
  - Non-blocking data availability checking with `hasData()` method
  - Timeout-based reading with `readWithTimeout()` method
  - Proper process cleanup and PTY deinitialization
  - Enhanced PTY testing with multiple shell commands
- **Fase 3 Complete**: ANSI escape sequence parsing and terminal buffer management
  - Complete ANSI parser with state machine for escape sequence processing
  - Terminal buffer with cell-based character storage and attribute support
  - ANSI processor integration for real-time terminal output processing
  - Support for cursor movement commands (up, down, forward, backward, position)
  - Screen manipulation commands (clear screen, clear line variants)
  - Color and graphics mode support framework
  - Comprehensive terminal scrolling and line manipulation
  - Integration testing of ANSI processing with terminal buffer

### Fixed
- Compilation errors in Zig 0.14.0 compatibility
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
