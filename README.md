# Zigline

An experimental terminal emulator written in Zig.

## Overview

Zigline is an early-stage personal project aimed at exploring Zig's capabilities for building a lightweight terminal emulator. This project is **not production-ready** and serves as a learning exercise and exploration of Zig's systems programming features.

## Features (Current Status)

- [x] Basic project structure and build system
- [x] Pseudo-terminal (PTY) interface with shell integration
- [x] ANSI escape sequence processing
- [x] Terminal screen buffer management  
- [x] **Raylib GUI backend with FiraCode font support**
- [x] Real-time input handling and key processing
- [x] Character rendering with custom monospace fonts
- [x] Cross-platform X11/GLFW display support
- [ ] Advanced ANSI sequence support (colors, formatting)
- [ ] Window resizing and dynamic terminal dimensions
- [ ] Tab support and session management
- [ ] Configuration system and theming
- [ ] Copy/paste functionality
- [ ] Plugin system

## Key Achievements

### Phase 5: Successful Raylib GUI Integration
- **Stable Rendering**: Resolved the "ogni rerender cancella la ui" (UI clearing) issue by migrating from DVUI to Raylib
- **FiraCode Font Integration**: Successfully integrated FiraCode monospace font with programming ligatures
- **Real-time Communication**: Functional PTY integration with live shell interaction
- **Cross-platform Display**: Working X11/GLFW backend with OpenGL rendering

### Technical Highlights
- **Font Loading**: Custom font loading with fallback system
- **Character Metrics**: Precise monospace character dimensions (8x16 pixels)
- **Memory Management**: Proper font resource cleanup with defer statements
- **Error Handling**: Robust error handling throughout the rendering pipeline

## Requirements

- Zig 0.14.0 or later
- Linux/Unix-like system with X11 support
- OpenGL 3.3+ compatible graphics
- X11 development libraries (libgl1-mesa-dev, libglu1-mesa-dev, libx11-dev, etc.)

## Building

```bash
# Clone the repository
git clone <repository-url>
cd zigline

# Install X11 development dependencies (Ubuntu/Debian)
sudo apt install libgl1-mesa-dev libglu1-mesa-dev libxcursor-dev libxext-dev \
                 libxfixes-dev libxi-dev libxinerama-dev libxrandr-dev \
                 libxrender-dev libx11-dev

# Build the project
zig build

# Run the terminal emulator
./zig-out/bin/zigline

# Run tests
zig build test
```

## Font Support

Zigline includes FiraCode font integration for enhanced programming experience:

- **Automatic Font Loading**: Loads FiraCode-Regular.ttf from `assets/fonts/ttf/`
- **Programming Ligatures**: Supports code-specific ligatures like `->`, `=>`, `!=`, `>=`, etc.
- **Fallback System**: Gracefully falls back to system default if FiraCode is unavailable
- **Monospace Precision**: Exact character dimensions for terminal grid alignment

## Development Status

### Current Phase: Phase 5 Complete ✅
The terminal emulator now features:

- **Stable Raylib GUI**: Replaced problematic DVUI with reliable Raylib backend
- **Working PTY Integration**: Real-time shell communication and process management  
- **FiraCode Rendering**: Professional monospace font with programming ligatures
- **Input Processing**: Complete keyboard input handling with special key support
- **Cross-platform Display**: X11/GLFW backend with OpenGL rendering pipeline

### Project Structure

```
zigline/
├── src/
│   ├── main.zig              # Application entry point
│   ├── core/                 # Core terminal functionality
│   │   ├── terminal.zig      # Terminal buffer and state management
│   │   ├── pty.zig          # Pseudo-terminal interface
│   │   └── logger.zig       # Logging system
│   ├── terminal/            # Terminal-specific processing
│   │   ├── buffer.zig       # Screen buffer management
│   │   └── ansi.zig         # ANSI escape sequence parser
│   ├── input/               # Input handling
│   │   ├── keyboard.zig     # Keyboard input processing
│   │   └── processor.zig    # Input event processing
│   └── ui/                  # User interface
│       ├── raylib_gui.zig   # Main Raylib GUI implementation
│       └── terminal_renderer.zig  # Terminal rendering logic
├── assets/
│   └── fonts/               # Font resources
│       └── ttf/
│           └── FiraCode-*.ttf  # FiraCode font files
├── build.zig               # Zig build configuration
├── build.zig.zon          # Dependency management
└── README.md              # This documentation
```

## Contributing

This is primarily a personal learning project, but feedback and suggestions are welcome. Please note that this is experimental software and not intended for production use.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Disclaimer

**This software is experimental and not production-ready.** Use at your own risk. The project is primarily for educational purposes and exploring Zig's capabilities in systems programming.

## Resources

- [Zig Programming Language](https://ziglang.org/)
- [Terminal Emulator Implementation Guide](https://www.uninformativ.de/blog/postings/2018-02-24/0/POSTING-en.html)
- [ANSI Escape Sequences](https://en.wikipedia.org/wiki/ANSI_escape_code)
