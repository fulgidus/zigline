//! Configuration management for Zigline terminal emulator
//! Supports themes, keybindings, and session persistence settings

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

/// Color configuration for the terminal
pub const ColorTheme = struct {
    /// Background color (R, G, B)
    background: [3]u8,
    /// Foreground color (R, G, B)
    foreground: [3]u8,
    /// Cursor color (R, G, B)
    cursor: [3]u8,
    /// ANSI color palette (16 colors: black, red, green, yellow, blue, magenta, cyan, white, bright variants)
    ansi_colors: [16][3]u8,
    /// Tab bar background color
    tab_background: [3]u8,
    /// Active tab color
    tab_active: [3]u8,
    /// Inactive tab color
    tab_inactive: [3]u8,
    /// Status bar background color
    status_background: [3]u8,
    /// Status bar text color
    status_text: [3]u8,

    /// Default dark theme
    pub fn defaultDark() ColorTheme {
        return ColorTheme{
            .background = [3]u8{ 40, 44, 52 },
            .foreground = [3]u8{ 171, 178, 191 },
            .cursor = [3]u8{ 97, 175, 239 },
            .ansi_colors = [16][3]u8{
                // Normal colors
                [3]u8{ 40, 44, 52 }, // Black
                [3]u8{ 224, 108, 117 }, // Red
                [3]u8{ 152, 195, 121 }, // Green
                [3]u8{ 229, 192, 123 }, // Yellow
                [3]u8{ 97, 175, 239 }, // Blue
                [3]u8{ 198, 120, 221 }, // Magenta
                [3]u8{ 86, 182, 194 }, // Cyan
                [3]u8{ 171, 178, 191 }, // White
                // Bright colors
                [3]u8{ 92, 99, 112 }, // Bright Black
                [3]u8{ 224, 108, 117 }, // Bright Red
                [3]u8{ 152, 195, 121 }, // Bright Green
                [3]u8{ 229, 192, 123 }, // Bright Yellow
                [3]u8{ 97, 175, 239 }, // Bright Blue
                [3]u8{ 198, 120, 221 }, // Bright Magenta
                [3]u8{ 86, 182, 194 }, // Bright Cyan
                [3]u8{ 200, 204, 212 }, // Bright White
            },
            .tab_background = [3]u8{ 33, 37, 43 },
            .tab_active = [3]u8{ 97, 175, 239 },
            .tab_inactive = [3]u8{ 92, 99, 112 },
            .status_background = [3]u8{ 33, 37, 43 },
            .status_text = [3]u8{ 171, 178, 191 },
        };
    }

    /// Default light theme
    pub fn defaultLight() ColorTheme {
        return ColorTheme{
            .background = [3]u8{ 250, 250, 250 },
            .foreground = [3]u8{ 56, 58, 66 },
            .cursor = [3]u8{ 64, 120, 242 },
            .ansi_colors = [16][3]u8{
                // Normal colors
                [3]u8{ 56, 58, 66 }, // Black
                [3]u8{ 202, 18, 67 }, // Red
                [3]u8{ 80, 161, 79 }, // Green
                [3]u8{ 152, 104, 1 }, // Yellow
                [3]u8{ 64, 120, 242 }, // Blue
                [3]u8{ 166, 38, 164 }, // Magenta
                [3]u8{ 9, 151, 179 }, // Cyan
                [3]u8{ 250, 250, 250 }, // White
                // Bright colors
                [3]u8{ 130, 137, 151 }, // Bright Black
                [3]u8{ 202, 18, 67 }, // Bright Red
                [3]u8{ 80, 161, 79 }, // Bright Green
                [3]u8{ 152, 104, 1 }, // Bright Yellow
                [3]u8{ 64, 120, 242 }, // Bright Blue
                [3]u8{ 166, 38, 164 }, // Bright Magenta
                [3]u8{ 9, 151, 179 }, // Bright Cyan
                [3]u8{ 56, 58, 66 }, // Bright White
            },
            .tab_background = [3]u8{ 240, 240, 240 },
            .tab_active = [3]u8{ 64, 120, 242 },
            .tab_inactive = [3]u8{ 130, 137, 151 },
            .status_background = [3]u8{ 240, 240, 240 },
            .status_text = [3]u8{ 56, 58, 66 },
        };
    }
};

/// Keybinding configuration
pub const KeyBindings = struct {
    /// Create new session (default: Ctrl+T)
    new_session: KeyBinding,
    /// Close current session (default: Ctrl+W)
    close_session: KeyBinding,
    /// Next session (default: Ctrl+Tab)
    next_session: KeyBinding,
    /// Previous session (default: Ctrl+Shift+Tab)
    previous_session: KeyBinding,
    /// Copy selection (default: Ctrl+C)
    copy: KeyBinding,
    /// Paste (default: Ctrl+V)
    paste: KeyBinding,
    /// Toggle fullscreen (default: F11)
    toggle_fullscreen: KeyBinding,

    /// Default keybindings
    pub fn default() KeyBindings {
        return KeyBindings{
            .new_session = KeyBinding{ .key = 't', .ctrl = true, .shift = false, .alt = false },
            .close_session = KeyBinding{ .key = 'w', .ctrl = true, .shift = false, .alt = false },
            .next_session = KeyBinding{ .key = '\t', .ctrl = true, .shift = false, .alt = false },
            .previous_session = KeyBinding{ .key = '\t', .ctrl = true, .shift = true, .alt = false },
            .copy = KeyBinding{ .key = 'c', .ctrl = true, .shift = false, .alt = false },
            .paste = KeyBinding{ .key = 'v', .ctrl = true, .shift = false, .alt = false },
            .toggle_fullscreen = KeyBinding{ .key = 290, .ctrl = false, .shift = false, .alt = false }, // F11
        };
    }
};

/// Individual keybinding
pub const KeyBinding = struct {
    /// Key code (ASCII for letters, Raylib key codes for special keys)
    key: u32,
    /// Ctrl modifier required
    ctrl: bool,
    /// Shift modifier required
    shift: bool,
    /// Alt modifier required
    alt: bool,
};

/// Font configuration
pub const FontConfig = struct {
    /// Font file path
    path: []const u8,
    /// Font size in pixels
    size: u32,
    /// Fallback fonts for missing glyphs
    fallbacks: []const []const u8,

    /// Default font configuration
    pub fn default() FontConfig {
        return FontConfig{
            .path = "assets/fonts/ttf/FiraCode-Regular.ttf",
            .size = 16,
            .fallbacks = &[_][]const u8{
                "assets/fonts/ttf/DejaVuSansMono.ttf",
                "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
                "/System/Library/Fonts/Monaco.ttf",
            },
        };
    }
};

/// Session persistence configuration
pub const PersistenceConfig = struct {
    /// Enable session persistence
    enabled: bool,
    /// Sessions save file path
    sessions_file: []const u8,
    /// Auto-save interval in seconds (0 = save on exit only)
    auto_save_interval: u32,
    /// Maximum number of sessions to persist
    max_sessions: u32,
    /// Restore sessions on startup
    restore_on_startup: bool,

    /// Default persistence configuration
    pub fn default() PersistenceConfig {
        return PersistenceConfig{
            .enabled = true,
            .sessions_file = "zigline_sessions.json",
            .auto_save_interval = 30, // 30 seconds
            .max_sessions = 10,
            .restore_on_startup = true,
        };
    }
};

/// Window configuration
pub const WindowConfig = struct {
    /// Initial window width
    width: u32,
    /// Initial window height
    height: u32,
    /// Window title
    title: []const u8,
    /// Start maximized
    maximized: bool,
    /// Enable window resizing
    resizable: bool,
    /// Window opacity (0.0 - 1.0)
    opacity: f32,

    /// Default window configuration
    pub fn default() WindowConfig {
        return WindowConfig{
            .width = 1200,
            .height = 800,
            .title = "Zigline Terminal",
            .maximized = false,
            .resizable = true,
            .opacity = 1.0,
        };
    }
};

/// Complete configuration structure
pub const Config = struct {
    /// Color theme
    theme: ColorTheme,
    /// Keybindings
    keybindings: KeyBindings,
    /// Font configuration
    font: FontConfig,
    /// Session persistence settings
    persistence: PersistenceConfig,
    /// Window settings
    window: WindowConfig,
    /// Shell command to execute
    shell: []const u8,

    /// Allocator used for dynamic strings
    allocator: Allocator,

    /// Track whether shell was dynamically allocated
    shell_allocated: bool = false,
    /// Track whether font path was dynamically allocated
    font_path_allocated: bool = false,

    /// Create default configuration
    pub fn default(allocator: Allocator) Config {
        return Config{
            .theme = ColorTheme.defaultDark(),
            .keybindings = KeyBindings.default(),
            .font = FontConfig.default(),
            .persistence = PersistenceConfig.default(),
            .window = WindowConfig.default(),
            .shell = "/bin/bash",
            .allocator = allocator,
            .shell_allocated = false,
            .font_path_allocated = false,
        };
    }

    /// Load configuration from file
    pub fn loadFromFile(allocator: Allocator, file_path: []const u8) !Config {
        const file = std.fs.cwd().openFile(file_path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                std.log.info("Config file not found: {s}, using defaults", .{file_path});
                return Config.default(allocator);
            },
            else => return err,
        };
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
        defer allocator.free(content);

        return parseConfigJson(allocator, content) catch |err| {
            std.log.warn("Failed to parse config file: {}, using defaults", .{err});
            return Config.default(allocator);
        };
    }

    /// Save configuration to file
    pub fn saveToFile(self: *const Config, file_path: []const u8) !void {
        const file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();

        const json_string = try self.toJsonString();
        defer self.allocator.free(json_string);

        try file.writeAll(json_string);
        std.log.info("Configuration saved to: {s}", .{file_path});
    }

    /// Convert configuration to JSON string
    fn toJsonString(self: *const Config) ![]u8 {
        var string = ArrayList(u8).init(self.allocator);
        defer string.deinit();

        try string.appendSlice("{\n");
        try string.appendSlice("  \"theme\": \"dark\",\n");
        try string.appendSlice("  \"shell\": \"");
        try string.appendSlice(self.shell);
        try string.appendSlice("\",\n");

        // Font configuration
        try string.appendSlice("  \"font\": {\n");
        try string.appendSlice("    \"path\": \"");
        try string.appendSlice(self.font.path);
        try string.appendSlice("\",\n");
        try string.appendSlice("    \"size\": ");
        try string.writer().print("{d}", .{self.font.size});
        try string.appendSlice("\n  },\n");

        // Window configuration
        try string.appendSlice("  \"window\": {\n");
        try string.appendSlice("    \"width\": ");
        try string.writer().print("{d}", .{self.window.width});
        try string.appendSlice(",\n    \"height\": ");
        try string.writer().print("{d}", .{self.window.height});
        try string.appendSlice(",\n    \"title\": \"");
        try string.appendSlice(self.window.title);
        try string.appendSlice("\",\n    \"resizable\": ");
        try string.appendSlice(if (self.window.resizable) "true" else "false");
        try string.appendSlice("\n  },\n");

        // Persistence configuration
        try string.appendSlice("  \"persistence\": {\n");
        try string.appendSlice("    \"enabled\": ");
        try string.appendSlice(if (self.persistence.enabled) "true" else "false");
        try string.appendSlice(",\n    \"sessions_file\": \"");
        try string.appendSlice(self.persistence.sessions_file);
        try string.appendSlice("\",\n    \"auto_save_interval\": ");
        try string.writer().print("{d}", .{self.persistence.auto_save_interval});
        try string.appendSlice(",\n    \"restore_on_startup\": ");
        try string.appendSlice(if (self.persistence.restore_on_startup) "true" else "false");
        try string.appendSlice("\n  }\n");

        try string.appendSlice("}\n");

        return string.toOwnedSlice();
    }

    /// Parse configuration from JSON string
    fn parseConfigJson(allocator: Allocator, json_content: []const u8) !Config {
        var config = Config.default(allocator);

        // Parse theme
        if (std.mem.indexOf(u8, json_content, "\"theme\": \"light\"") != null) {
            config.theme = ColorTheme.defaultLight();
        }

        // Parse shell if specified
        if (std.mem.indexOf(u8, json_content, "\"shell\": \"")) |start| {
            const shell_start = start + 10; // length of "\"shell\": \""
            if (std.mem.indexOf(u8, json_content[shell_start..], "\"")) |end| {
                const shell_str = json_content[shell_start .. shell_start + end];
                config.shell = try allocator.dupe(u8, shell_str);
                config.shell_allocated = true;
            }
        }

        // Parse font_path
        if (std.mem.indexOf(u8, json_content, "\"font_path\": \"")) |start| {
            const path_start = start + 14; // length of "\"font_path\": \""
            if (std.mem.indexOf(u8, json_content[path_start..], "\"")) |end| {
                const path_str = json_content[path_start .. path_start + end];
                config.font.path = try allocator.dupe(u8, path_str);
                config.font_path_allocated = true;
            }
        }

        // Parse font_size
        if (std.mem.indexOf(u8, json_content, "\"font_size\": ")) |start| {
            const size_start = start + 13; // length of "\"font_size\": "
            var end_pos: usize = size_start;
            while (end_pos < json_content.len and (json_content[end_pos] >= '0' and json_content[end_pos] <= '9')) {
                end_pos += 1;
            }
            if (end_pos > size_start) {
                const size_str = json_content[size_start..end_pos];
                config.font.size = std.fmt.parseInt(u32, size_str, 10) catch config.font.size;
            }
        }

        // Parse window_width
        if (std.mem.indexOf(u8, json_content, "\"window_width\": ")) |start| {
            const width_start = start + 16; // length of "\"window_width\": "
            var end_pos: usize = width_start;
            while (end_pos < json_content.len and (json_content[end_pos] >= '0' and json_content[end_pos] <= '9')) {
                end_pos += 1;
            }
            if (end_pos > width_start) {
                const width_str = json_content[width_start..end_pos];
                config.window.width = std.fmt.parseInt(u32, width_str, 10) catch config.window.width;
            }
        }

        // Parse window_height
        if (std.mem.indexOf(u8, json_content, "\"window_height\": ")) |start| {
            const height_start = start + 17; // length of "\"window_height\": "
            var end_pos: usize = height_start;
            while (end_pos < json_content.len and (json_content[end_pos] >= '0' and json_content[end_pos] <= '9')) {
                end_pos += 1;
            }
            if (end_pos > height_start) {
                const height_str = json_content[height_start..end_pos];
                config.window.height = std.fmt.parseInt(u32, height_str, 10) catch config.window.height;
            }
        }

        // Parse auto_save_interval
        if (std.mem.indexOf(u8, json_content, "\"auto_save_interval\": ")) |start| {
            const interval_start = start + 22; // length of "\"auto_save_interval\": "
            var end_pos: usize = interval_start;
            while (end_pos < json_content.len and (json_content[end_pos] >= '0' and json_content[end_pos] <= '9')) {
                end_pos += 1;
            }
            if (end_pos > interval_start) {
                const interval_str = json_content[interval_start..end_pos];
                config.persistence.auto_save_interval = std.fmt.parseInt(u32, interval_str, 10) catch config.persistence.auto_save_interval;
            }
        }

        // Parse auto_save_sessions
        if (std.mem.indexOf(u8, json_content, "\"auto_save_sessions\": true") != null) {
            config.persistence.enabled = true;
        } else if (std.mem.indexOf(u8, json_content, "\"auto_save_sessions\": false") != null) {
            config.persistence.enabled = false;
        }

        std.log.info("Configuration parsed - font_path: {s}, font_size: {d}, window: {d}x{d}", .{ config.font.path, config.font.size, config.window.width, config.window.height });

        return config;
    }

    /// Check if a key combination matches a keybinding
    pub fn matchesKeybinding(_: *const Config, binding: KeyBinding, key: u32, ctrl: bool, shift: bool, alt: bool) bool {
        return binding.key == key and binding.ctrl == ctrl and binding.shift == shift and binding.alt == alt;
    }

    /// Cleanup allocated resources
    pub fn deinit(self: *Config) void {
        // Free dynamically allocated strings if they were allocated
        if (self.shell_allocated) {
            self.allocator.free(self.shell);
            self.shell_allocated = false;
        }

        // Free font path if it was dynamically allocated
        if (self.font_path_allocated) {
            self.allocator.free(self.font.path);
            self.font_path_allocated = false;
        }
    }
};

/// Configuration manager
pub const ConfigManager = struct {
    config: Config,
    config_file_path: []const u8,
    allocator: Allocator,

    /// Initialize configuration manager
    pub fn init(allocator: Allocator, config_file_path: []const u8) !ConfigManager {
        const config = try Config.loadFromFile(allocator, config_file_path);

        return ConfigManager{
            .config = config,
            .config_file_path = config_file_path,
            .allocator = allocator,
        };
    }

    /// Get current configuration
    pub fn getConfig(self: *const ConfigManager) *const Config {
        return &self.config;
    }

    /// Get mutable configuration
    pub fn getConfigMut(self: *ConfigManager) *Config {
        return &self.config;
    }

    /// Save current configuration to file
    pub fn save(self: *const ConfigManager) !void {
        try self.config.saveToFile(self.config_file_path);
    }

    /// Reload configuration from file
    pub fn reload(self: *ConfigManager) !void {
        self.config.deinit();
        self.config = try Config.loadFromFile(self.allocator, self.config_file_path);
    }

    /// Cleanup resources
    pub fn deinit(self: *ConfigManager) void {
        self.config.deinit();
    }
};
