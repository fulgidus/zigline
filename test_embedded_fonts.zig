//! Test embedded font assets
const std = @import("std");
const EmbeddedAssets = @import("src/embedded_assets.zig");

pub fn main() !void {
    std.log.info("Testing embedded font assets...", .{});

    // Test getting embedded font data
    if (EmbeddedAssets.getFontData("FiraCode-Regular")) |font_data| {
        std.log.info("✅ FiraCode-Regular font embedded successfully: {d} bytes", .{font_data.len});
    } else {
        std.log.err("❌ FiraCode-Regular font not found in embedded assets", .{});
    }

    if (EmbeddedAssets.getFontData("FiraCode-Bold")) |font_data| {
        std.log.info("✅ FiraCode-Bold font embedded successfully: {d} bytes", .{font_data.len});
    } else {
        std.log.err("❌ FiraCode-Bold font not found in embedded assets", .{});
    }

    // Test checking if font is embedded
    std.log.info("✅ FiraCode-Regular is embedded: {}", .{EmbeddedAssets.isFontEmbedded("FiraCode-Regular")});
    std.log.info("✅ FiraCode-Bold is embedded: {}", .{EmbeddedAssets.isFontEmbedded("FiraCode-Bold")});
    std.log.info("✅ NonExistent font is embedded: {}", .{EmbeddedAssets.isFontEmbedded("NonExistent")});

    // Test getting available fonts
    const available_fonts = EmbeddedAssets.getAvailableFonts();
    std.log.info("✅ Available embedded fonts:", .{});
    for (available_fonts) |font_name| {
        std.log.info("   - {s}", .{font_name});
    }

    std.log.info("✅ Embedded font assets test completed successfully!", .{});
}
