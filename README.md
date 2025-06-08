# Zigline

A lightweight and modular terminal emulator written entirely in Zig.

## Overview

Zigline is a feature-rich terminal emulator designed as a learning project to explore Zig's systems programming capabilities. While still experimental, it now includes advanced features like tabbed sessions, configuration management, and session persistence. This project demonstrates modern terminal emulator functionality with clean, modular Zig code.

## Features (Current Status)

- [x] **Core Terminal Functionality**
  - [x] Pseudo-terminal (PTY) interface with shell integration
  - [x] ANSI escape sequence processing and color support
  - [x] Terminal screen buffer management with cursor handling
  - [x] Real-time input handling and special key processing
  
- [x] **Advanced GUI Features (Phase 6 Complete)**
  - [x] **Raylib GUI backend with enhanced rendering**
  - [x] **Window resizing support with dynamic terminal dimensions**
  - [x] **Mouse support for tab interaction and UI navigation**
  - [x] **Tab bar with hover effects and visual feedback**
  - [x] **FiraCode font integration with fallback system**

- [x] **Session Management**
  - [x] **Multi-tab session support with keyboard shortcuts**
  - [x] **Session persistence (save/restore across restarts)**
  - [x] **Dynamic session creation and deletion**
  - [x] **Mouse-based tab switching and closing**

- [x] **Configuration System**
  - [x] **JSON-based configuration with hot-reload support**
  - [x] **Theme and color customization**
  - [x] **Font configuration with multiple fallbacks**
  - [x] **Keybinding customization**
  - [x] **Window and display settings**

- [ ] **Future Enhancements**
  - [ ] Copy/paste functionality with text selection
  - [ ] Terminal scrollback history
  - [ ] Plugin system and extensibility
  - [ ] Search functionality within terminal content

## Key Achievements

### Phase 6: Advanced Session Management and UI Enhancements ✅
- **Window Resizing**: Full support for window resizing with automatic terminal dimension updates
- **Mouse Integration**: Complete mouse support for tab switching, closing, and UI interaction
- **Session Management**: Multi-tab sessions with persistence across application restarts
- **Configuration System**: Comprehensive JSON-based configuration with theme support
- **Enhanced UI**: Tab bar with hover effects, window title updates, and visual feedback

### Phase 5: Successful Raylib GUI Integration ✅
- **Stable Rendering**: Resolved UI clearing issues by migrating from DVUI to Raylib
- **FiraCode Font Integration**: Successfully integrated FiraCode monospace font with programming ligatures
- **Real-time Communication**: Functional PTY integration with live shell interaction
- **Cross-platform Display**: Working X11/GLFW backend with OpenGL rendering

### Technical Highlights
- **Memory Management**: Proper resource cleanup with defer statements and arena allocators
- **Error Handling**: Robust error handling throughout the rendering and PTY pipelines
- **Font System**: Custom font loading with automatic fallback to system defaults
- **Session Persistence**: JSON-based session saving with terminal state restoration
- **Configuration Hot-reload**: Dynamic configuration updates without application restart

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

## Usage

### Basic Operation
```bash
# Run the terminal emulator
./zig-out/bin/zigline

# The application will load with your configured settings
# Default configuration creates a 1200x800 window with FiraCode font
```

### Keyboard Shortcuts
- **Ctrl+T**: Create new terminal session (new tab)
- **Ctrl+W**: Close current session
- **Ctrl+Tab**: Switch to next session
- **Shift+Ctrl+Tab**: Switch to previous session
- **Ctrl+PageUp/PageDown**: Alternative session navigation

### Mouse Controls
- **Click Tab**: Switch to that session
- **Click × Button**: Close the session
- **Mouse Wheel over Tab Bar**: Scroll through sessions
- **Window Dragging**: Resize window (terminal automatically adjusts)

### Configuration

Zigline uses a JSON configuration file (`zigline_config.json`) for customization:

```json
{
  "theme": "dark",
  "font_path": "assets/fonts/ttf/FiraCode-Regular.ttf",
  "font_size": 26,
  "window_width": 1200,
  "window_height": 800,
  "auto_save_sessions": true,
  "auto_save_interval": 30,
  "keybindings": {
    "new_session": "Ctrl+T",
    "close_session": "Ctrl+W", 
    "next_session": "Ctrl+Tab",
    "prev_session": "Shift+Ctrl+Tab"
  },
  "colors": {
    "background": { "r": 40, "g": 42, "b": 54, "a": 255 },
    "foreground": { "r": 248, "g": 248, "b": 242, "a": 255 },
    "cursor": { "r": 139, "g": 233, "b": 253, "a": 255 }
  }
}
```

### Session Persistence

Sessions are automatically saved to `zigline_sessions.json` and restored on startup:
- Terminal dimensions and cursor position
- Session names and active session
- PTY state and working directories
- Auto-save occurs every 30 seconds (configurable)

## Development Status

### Current Phase: Phase 6 Complete ✅
The terminal emulator now features a complete advanced session management system:

- **Window Management**: Full resizing support with minimum size constraints
- **Mouse Integration**: Complete mouse support for all UI interactions
- **Multi-Session Support**: Tabbed interface with visual feedback and easy navigation
- **Configuration System**: Comprehensive JSON-based settings with hot-reload
- **Session Persistence**: Automatic save/restore of terminal sessions across restarts
- **Enhanced UI**: Professional tab bar with hover effects and window title updates

### Architecture Overview
Zigline follows a modular architecture with clear separation of concerns:

- **Core Layer**: PTY management, terminal buffer, and ANSI processing
- **UI Layer**: Raylib rendering, session management, and input handling
- **Configuration Layer**: JSON-based settings with runtime updates
- **Persistence Layer**: Session state saving and restoration

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
│   ├── ui/                  # User interface layer
│   │   ├── raylib_gui.zig   # Main Raylib GUI with mouse/window support
│   │   └── session_manager.zig  # Multi-session management
│   ├── config/              # Configuration management
│   │   └── config.zig       # JSON config loading and validation
│   └── persistence/         # Session persistence
│       └── session_persistence.zig  # Save/restore session state
├── assets/
│   └── fonts/               # Font resources
│       └── ttf/
│           └── FiraCode-*.ttf  # FiraCode font files
├── zigline_config.json     # User configuration file
├── zigline_sessions.json   # Saved session state
├── build.zig               # Zig build configuration
├── build.zig.zon          # Dependency management
├── CHANGELOG.md           # Version history
├── RELEASE_NOTES.md       # Release documentation
└── README.md              # This documentation
```

## Contributing

This project welcomes contributions! While originally a personal learning project, it has evolved into a functional terminal emulator. Areas where contributions are especially welcome:

- **Terminal Features**: Copy/paste, scrollback history, search functionality
- **UI Enhancements**: More themes, font options, accessibility features  
- **Platform Support**: Windows and macOS compatibility
- **Performance**: Rendering optimizations and memory usage improvements
- **Testing**: Unit tests and integration tests for better reliability

Please ensure all code follows the Zig style guidelines and includes appropriate documentation.

## Version History

- **v0.4.0** (Current): Phase 6 - Advanced session management, window resizing, mouse support
- **v0.3.0**: Phase 5 - Raylib GUI integration with stable rendering
- **v0.2.0**: Phase 4 - Input handling and keyboard processing
- **v0.1.0**: Phase 3 - Basic ANSI parsing and screen buffer

See [CHANGELOG.md](CHANGELOG.md) for detailed version history and [RELEASE_NOTES.md](RELEASE_NOTES.md) for release information.

## Disclaimer

While Zigline is now quite functional and includes advanced features, it remains primarily an educational and experimental project. The codebase demonstrates modern terminal emulator techniques and serves as a reference for Zig systems programming. Use in production environments should be carefully evaluated.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Resources

- [Zig Programming Language](https://ziglang.org/)
- [Raylib Graphics Library](https://www.raylib.com/)
- [Terminal Emulator Implementation Guide](https://www.uninformativ.de/blog/postings/2018-02-24/0/POSTING-en.html)
- [ANSI Escape Sequences Reference](https://en.wikipedia.org/wiki/ANSI_escape_code)
- [FiraCode Programming Font](https://github.com/tonsky/FiraCode)
