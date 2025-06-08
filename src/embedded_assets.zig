//! Embedded assets for Zigline terminal emulator
//! This module embeds font files directly into the executable for self-contained distribution

const std = @import("std");

/// Embedded FiraCode Regular font data
pub const firacode_regular_ttf = @embedFile("assets/fonts/FiraCode-Regular.ttf");

/// Embedded FiraCode Bold font data
pub const firacode_bold_ttf = @embedFile("assets/fonts/FiraCode-Bold.ttf");

/// Embedded FiraCode Light font data
pub const firacode_light_ttf = @embedFile("assets/fonts/FiraCode-Light.ttf");

/// Embedded FiraCode Medium font data
pub const firacode_medium_ttf = @embedFile("assets/fonts/FiraCode-Medium.ttf");

/// Get embedded font data by name
pub fn getFontData(font_name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, font_name, "FiraCode-Regular")) {
        return firacode_regular_ttf;
    } else if (std.mem.eql(u8, font_name, "FiraCode-Bold")) {
        return firacode_bold_ttf;
    } else if (std.mem.eql(u8, font_name, "FiraCode-Light")) {
        return firacode_light_ttf;
    } else if (std.mem.eql(u8, font_name, "FiraCode-Medium")) {
        return firacode_medium_ttf;
    }
    return null;
}

/// Check if a font name is available as embedded asset
pub fn isFontEmbedded(font_name: []const u8) bool {
    return getFontData(font_name) != null;
}

/// Get all available embedded font names
pub fn getAvailableFonts() []const []const u8 {
    return &[_][]const u8{
        "FiraCode-Regular",
        "FiraCode-Bold",
        "FiraCode-Light",
        "FiraCode-Medium",
    };
}
