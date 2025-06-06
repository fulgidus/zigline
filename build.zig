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

    // Create a test step that can be invoked with `zig build test`
    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&run_main_unit_tests.step);
    test_step.dependOn(&run_phase_tests.step);

    // Create individual test steps for specific phases
    const test_main_step = b.step("test-main", "Run main module tests");
    test_main_step.dependOn(&run_main_unit_tests.step);

    const test_phases_step = b.step("test-phases", "Run phase-specific tests");
    test_phases_step.dependOn(&run_phase_tests.step);
}
