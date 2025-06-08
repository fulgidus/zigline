//! Configuration test module
const std = @import("std");
const ConfigManager = @import("src/config/config.zig").ConfigManager;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("Testing configuration loading...", .{});

    var config_manager = ConfigManager.init(allocator, "zigline_config.json") catch |err| {
        std.log.err("Failed to init config manager: {any}", .{err});
        return;
    };
    defer config_manager.deinit();

    const config = config_manager.getConfig();

    // Test all parsed values
    std.log.info("✅ Configuration test results:", .{});
    std.log.info("  📄 Font path: {s}", .{config.font.path});
    std.log.info("  🔠 Font size: {d}", .{config.font.size});
    std.log.info("  📐 Window: {d}x{d}", .{ config.window.width, config.window.height });
    std.log.info("  💾 Auto save interval: {d}s", .{config.persistence.auto_save_interval});
    std.log.info("  💾 Auto save enabled: {}", .{config.persistence.enabled});
    std.log.info("  🎨 Background color: RGB({d}, {d}, {d})", .{ config.theme.background[0], config.theme.background[1], config.theme.background[2] });
    std.log.info("  🐚 Shell: {s}", .{config.shell});

    std.log.info("✅ Configuration loading test completed successfully!", .{});
}
