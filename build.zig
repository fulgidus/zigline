const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // Add Raylib dependency for simple GUI rendering
    const raylib_dep = b.dependency("raylib-zig", .{
        .target = target,
        .optimize = optimize,
        .linux_display_backend = .X11, // Force X11 backend to avoid wayland-scanner dependency
    });

    // Create the main executable for Zigline terminal emulator
    const exe = b.addExecutable(.{
        .name = "zigline",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link with libc for PTY functionality
    exe.linkLibC();

    // Add Raylib module for GUI functionality
    exe.root_module.addImport("raylib", raylib_dep.module("raylib"));
    exe.linkLibrary(raylib_dep.artifact("raylib"));

    // Install the executable artifact to the prefix path
    b.installArtifact(exe);

    // Create a run step that will execute the built binary
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application has no side effects.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Create a run step that can be invoked with `zig build run`
    const run_step = b.step("run", "Run the Zigline terminal emulator");
    run_step.dependOn(&run_cmd.step);

    // Create unit tests for main module
    const main_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    main_unit_tests.linkLibC();

    const run_main_unit_tests = b.addRunArtifact(main_unit_tests);

    // Create unit tests for all phases
    const phase_tests = b.addTest(.{
        .root_source_file = b.path("tests/test_all_phases.zig"),
        .target = target,
        .optimize = optimize,
    });
    phase_tests.linkLibC();

    const run_phase_tests = b.addRunArtifact(phase_tests);

    // Phase 7: Comprehensive unit tests
    // Note: Creating separate raylib dependency for tests to ensure X11 backend
    const test_raylib_dep = b.dependency("raylib-zig", .{
        .target = target,
        .optimize = optimize,
        .linux_display_backend = .X11, // Force X11 backend to avoid wayland-scanner dependency
    });

    const ansi_parser_tests = b.addTest(.{
        .root_source_file = b.path("tests/test_ansi_parser.zig"),
        .target = target,
        .optimize = optimize,
    });
    ansi_parser_tests.linkLibC();
    ansi_parser_tests.root_module.addImport("raylib", test_raylib_dep.module("raylib"));
    ansi_parser_tests.linkLibrary(test_raylib_dep.artifact("raylib"));
    ansi_parser_tests.root_module.addImport("ansi", b.createModule(.{ .root_source_file = b.path("src/terminal/ansi.zig") }));

    const buffer_behavior_tests = b.addTest(.{
        .root_source_file = b.path("tests/test_buffer_behavior.zig"),
        .target = target,
        .optimize = optimize,
    });
    buffer_behavior_tests.linkLibC();
    buffer_behavior_tests.root_module.addImport("raylib", test_raylib_dep.module("raylib"));
    buffer_behavior_tests.linkLibrary(test_raylib_dep.artifact("raylib"));
    buffer_behavior_tests.root_module.addImport("buffer", b.createModule(.{ .root_source_file = b.path("src/terminal/buffer.zig") }));

    const key_normalization_tests = b.addTest(.{
        .root_source_file = b.path("tests/test_key_normalization.zig"),
        .target = target,
        .optimize = optimize,
    });
    key_normalization_tests.linkLibC();
    key_normalization_tests.root_module.addImport("raylib", test_raylib_dep.module("raylib"));
    key_normalization_tests.linkLibrary(test_raylib_dep.artifact("raylib"));
    key_normalization_tests.root_module.addImport("processor", b.createModule(.{ .root_source_file = b.path("src/input/processor.zig") }));
    key_normalization_tests.root_module.addImport("keyboard", b.createModule(.{ .root_source_file = b.path("src/input/keyboard.zig") }));

    const history_navigation_tests = b.addTest(.{
        .root_source_file = b.path("tests/test_history_navigation.zig"),
        .target = target,
        .optimize = optimize,
    });
    history_navigation_tests.linkLibC();
    history_navigation_tests.root_module.addImport("raylib", test_raylib_dep.module("raylib"));
    history_navigation_tests.linkLibrary(test_raylib_dep.artifact("raylib"));
    history_navigation_tests.root_module.addImport("processor", b.createModule(.{ .root_source_file = b.path("src/input/processor.zig") }));
    history_navigation_tests.root_module.addImport("pty", b.createModule(.{ .root_source_file = b.path("src/core/pty.zig") }));

    const run_ansi_parser_tests = b.addRunArtifact(ansi_parser_tests);
    const run_buffer_behavior_tests = b.addRunArtifact(buffer_behavior_tests);
    const run_key_normalization_tests = b.addRunArtifact(key_normalization_tests);
    const run_history_navigation_tests = b.addRunArtifact(history_navigation_tests);

    // Create a test step that can be invoked with `zig build test`
    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&run_main_unit_tests.step);
    test_step.dependOn(&run_phase_tests.step);
    test_step.dependOn(&run_ansi_parser_tests.step);
    test_step.dependOn(&run_buffer_behavior_tests.step);
    test_step.dependOn(&run_key_normalization_tests.step);
    test_step.dependOn(&run_history_navigation_tests.step);

    // Create individual test steps for specific phases
    const test_main_step = b.step("test-main", "Run main module tests");
    test_main_step.dependOn(&run_main_unit_tests.step);

    const test_phases_step = b.step("test-phases", "Run phase-specific tests");
    test_phases_step.dependOn(&run_phase_tests.step);

    // Phase 7: Individual test steps
    const test_ansi_step = b.step("test-ansi", "Run ANSI parser tests");
    test_ansi_step.dependOn(&run_ansi_parser_tests.step);

    const test_buffer_step = b.step("test-buffer", "Run buffer behavior tests");
    test_buffer_step.dependOn(&run_buffer_behavior_tests.step);

    const test_keys_step = b.step("test-keys", "Run key normalization tests");
    test_keys_step.dependOn(&run_key_normalization_tests.step);

    const test_history_step = b.step("test-history", "Run history navigation tests");
    test_history_step.dependOn(&run_history_navigation_tests.step);
}
