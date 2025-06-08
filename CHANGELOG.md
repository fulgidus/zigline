# Changelog

All notable changes to the Zigline project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.7.1] - 2025-06-08

### Added
- CI/CD pipeline improvements with updated GitHub Actions
- Cross-platform build support for Linux x86_64 and ARM64
- Enhanced project structure validation

### Changed
- Updated GitHub Actions from deprecated versions to latest stable releases
- Streamlined system dependencies for better compatibility

## [0.7.0] - 2025-06-07

This major release represents the completion of **Phases 1-5** of the Zigline terminal emulator development roadmap, establishing a fully functional terminal emulator with graphical rendering capabilities.

### Added

#### **Phase 1 Complete**: Project Setup and Foundation
- Initialized Zig project using `zig init-exe` with modular directory structure
- Created organized project structure: `src/`, `tests/`, `assets/`, `config/`
- Configured `build.zig` with debug and release modes supporting cross-compilation
- Implemented basic error logging with `std.log` wrapper for structured debugging
- Established core application entry point with version management system
- Set up development environment with GitHub Actions CI/CD pipeline
- Created comprehensive project documentation and licensing structure
- Added automated testing framework with `zig build test` integration

#### **Phase 2 Complete**: PTY & Shell Process Integration
- PTY (Pseudo Terminal) initialization and management system using direct syscalls
- Shell process spawning and communication for `/bin/sh` or `$SHELL` environments
- PTY master configuration with non-blocking mode for efficient I/O operations
- Subprocess management with PTY slave attachment for proper terminal behavior
- Pipe-based shell process communication with bidirectional data flow
- Non-blocking data availability checking with `hasData()` method implementation
- Timeout-based reading with `readWithTimeout()` method for robust I/O handling
- Continuous PTY master reading with output buffering and overflow protection
- User input forwarding to PTY for interactive shell session management
- Proper process cleanup and PTY deinitialization with resource management
- Comprehensive PTY testing with multiple shell commands and echo verification

#### **Phase 3 Complete**: ANSI Parsing & Screen Buffer Management
- Complete ANSI escape sequence parser with finite state machine architecture
- 2D terminal screen buffer with character cell data structure
- Character cells containing: character, foreground/background color, and style attributes
- ANSI processor integration for real-time terminal output processing
- Cursor movement commands support (CSI n A/B/C/D - up, down, forward, backward)
- Absolute cursor positioning implementation (CSI row;col H)
- Screen manipulation commands (CSI 2J - clear screen, CSI K - clear line)
- Color attribute parsing (CSI 30-37 foreground, CSI 40-47 background colors)
- Text style support framework (bold, underline, italic rendering foundation)
- Comprehensive terminal scrolling and line manipulation algorithms
- Buffer state debugging with string representation output for development
- Integration testing of ANSI processing with terminal buffer updates

#### **Phase 4 Complete**: Input Handling System
- Comprehensive keyboard input capture system with event queue management
- Terminal raw mode implementation for Unix systems with proper state restoration
- Raylib input event integration for cross-platform input handling support
- Asynchronous key event reading with polling mechanism for responsive UI
- Special key normalization into ANSI escape sequences for shell compatibility
- Support for arrow keys, backspace, delete, enter, tab, and function keys
- Modifier key handling (Ctrl, Alt, Shift) with proper escape sequence generation
- User input forwarding to PTY input stream with input validation and buffering
- Complete input/output loop: keypress → PTY write → shell response → ANSI → buffer update
- Input validation and sanitization for shell safety and security

#### **Phase 5 Complete**: Graphical Rendering via Raylib
- Stable Raylib-based GUI backend replacing experimental DVUI implementation
- Raylib dependency integration with proper `build.zig` configuration and linking
- FiraCode monospace font integration with automatic loading and fallback system
- Custom font rendering with precise character metrics (8x16 pixels) for terminal display
- Programming ligatures support for enhanced code readability in terminal sessions
- Cross-platform X11/GLFW display backend with OpenGL hardware-accelerated rendering
- Real-time terminal content rendering with efficient buffer-to-screen mapping
- ANSI color mapping to Raylib Color structs with full 256-color palette support
- Text rendering using `DrawText()` and `DrawTextEx()` with advanced font management
- Cursor drawing and blinking implementation using rectangle primitives with timing
- Window resize event handling with dynamic terminal dimension calculation
- PTY window size notification using `TIOCSWINSZ` for proper shell environment behavior
- Raylib input forwarding with `IsKeyPressed()`, `GetKeyPressed()`, `GetCharPressed()` integration
- Special key handling for arrows, function keys, and modifier key combinations
- Mouse input capture foundation for future copy/paste and selection functionality
- Proper resource management with automatic font cleanup and memory leak prevention
- Enhanced status display showing PTY status, cursor position, and performance metrics

#### **Phase 6 (Foundation)**: Advanced Features Development Planning
- Tabbed sessions framework architecture design for multiple PTY management
- Session persistence system foundation for buffer state and configuration saving
- Configuration file parsing preparation (TOML/JSON support framework)
- Color theme system architecture planning for user customization
- Font customization system design for multiple font family support
- Keybinding customization framework foundation for user-defined shortcuts
- Hot-reload configuration monitoring system planning for dynamic updates

#### **Phase 7 (Planning)**: Testing & Documentation Framework
- Unit testing framework design for ANSI parser validation
- Buffer behavior testing under various input/output scenarios
- Key normalization and escape generation testing suite
- Manual testing procedures for interactive shell sessions
- Window resize and PTY behavior validation testing
- Multi-tab functionality and session switching reliability testing
- Comprehensive documentation system planning with inline Zig doc comments
- Performance profiling and optimization framework preparation

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
- **CI/CD Pipeline**: Updated deprecated GitHub Actions to latest versions
  - Updated actions/upload-artifact from v3 to v4
  - Updated actions/cache from v3 to v4
  - Replaced deprecated actions/create-release@v1 with GitHub CLI approach
  - Fixed release job condition from impossible logic to proper tag-based triggering
  - Updated Ubuntu test matrix to remove EOL Ubuntu 18.04 and add Ubuntu 20.04

### Changed
- Enhanced PTY communication from basic pipe to improved pipe-based approach
- Improved event loop with better command testing and response handling
- Enhanced logging with more detailed debug information for PTY and ANSI operations
- Streamlined CI system dependencies to match README.md specifications
- Enhanced build process with executable verification and system dependency checks
- Updated release job to support Linux x86_64/ARM64 builds (Linux X11 only per README)

### Security
- Input validation and sanitization for shell safety in PTY communication
- Proper resource management to prevent memory leaks and handle cleanup
- Non-blocking I/O operations to prevent system deadlocks

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
