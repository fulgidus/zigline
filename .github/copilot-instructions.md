# v4-DVUI

All comments and output for software must be in English, regardless of the user language used in the prompt. This includes:

-   Code comments
-   Console output
-   Documentation comments
-   Error messages
-   Log messages
-   Any other text output
    This ensures consistency and accessibility for all users, as English is the most widely understood language in the software development community.

# Pipelines

When making or editing pipelines for releases and builds, ensure that:

-   The ci pipeline is designed to be cross-platform, supporting Windows, Linux, and macOS.
-   The ci pipeline includes steps for building, testing, and packaging the software.
-   The ci pipeline is automated to run on every commit or pull request to ensure continuous integration (release excluded).
-   The release pipeline includes steps for generating release notes and updating the changelog.
-   The pipelines are all documented with clear instructions on how to run it locally and in the CI environment.
-   The pipelines are all version-controlled and follows best practices for maintainability and scalability.
-   The pipelines include security checks and vulnerability scans to ensure the software is secure.
-   Every pipeline is commented for clarity, explaining each step and its purpose.

# Changelog

When updating the changelog, follow these guidelines:

-   Use the format `## [version] - YYYY-MM-DD` for each version entry.
-   Include sections for `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, and `Security`.
-   Each section should list the changes made in that version, with a brief description of each change.
-   Ensure that the changelog is updated with every release, reflecting all changes made since the last version.
-   Use bullet points for clarity and readability.
-   Ensure that the changelog is written in English, with clear and concise descriptions of changes.
-   Avoid using jargon or abbreviations that may not be understood by all users.
-   Keep the changelog up-to-date with every commit that affects the software, not just major releases.
-   Ensure that the changelog is accessible in the repository, typically in a file named `CHANGELOG.md`.
-   Use consistent formatting and style throughout the changelog to maintain readability.
-   Ensure that the changelog is linked in the README or documentation for easy access by users.
-   Use semantic versioning for version numbers, following the format `MAJOR.MINOR.PATCH`.

# Release Notes

When creating release notes, ensure that:

-   The release notes are clear, concise, and informative.
-   Each release note includes a summary of the changes made in that version.
-   The release notes are written in English and are accessible to all users.
-   The release notes are linked in the changelog and README for easy access.
-   The release notes include any important information about breaking changes, new features, or bug fixes.
-   The release notes are formatted consistently with the changelog for easy navigation.
-   The release notes are versioned and follow the same versioning scheme as the changelog.
-   The release notes include links to relevant issues or pull requests for further context.
-   The release notes are stored in a file named `RELEASE_NOTES.md` or similar, in the root of the repository.
-   The release notes are updated with every release, reflecting all changes made since the last version.

# Versioning

When versioning the software, follow these guidelines:

-   Use semantic versioning (MAJOR.MINOR.PATCH) to indicate the nature of changes:
    -   **MAJOR**: Incompatible API changes
    -   **MINOR**: Backward-compatible functionality
    -   **PATCH**: Backward-compatible bug fixes
-   Ensure that the version number is updated in the codebase, documentation, and changelog with every release.
-   Use a consistent versioning scheme across all components of the software.
-   Ensure that the version number is clearly displayed in the software, such as in the help command or about section.
-   Use tags in the version control system (e.g., Git) to mark each release with the corresponding version number.
-   The tags should follow the format `vMAJOR.MINOR.PATCH` for clarity.
-   Ensure that the version number is included in the release notes and changelog for easy reference.

# Zig specific guidelines

When writing Zig code, follow these additional guidelines:

-   Use `const` and `var` appropriately to define variables, with `const` for immutable values and `var` for mutable ones.
-   Use `comptime` for compile-time evaluation where applicable, to improve performance and reduce runtime overhead.
-   Use `error` for error handling, and ensure that errors are handled gracefully.
-   Use `defer` for cleanup operations, ensuring that resources are released properly.
-   All Zig code must be formatted using `zig fmt` to ensure consistent style and readability.
    -   This should be integrated into the CI pipeline to automatically format code on every commit or pull request.
-   Prefer stdout and stderr for output, using `std.io.getStdOut().print()` and `std.io.getStdErr().print()` for printing messages.
-   Zig Documentation Comments
    Use standard Zig documentation comments: `//!` for file/module-level comments and `///` for public items like functions, structs, enums, etc.
    The goal is to generate useful documentation and keep the code self-explanatory.
    These comments are parsed by the Zig compiler and can be accessed via `std.meta.declDocs` and `std.meta.modDocs`.
-   Zig Error Handling
    Strictly adhere to Zig's error handling model, using error sets and `try` for propagation.
    Avoid `unreachable` or `panic` unless for unrecoverable logical errors or critical invariant assertions.
-   Zig Naming Conventions
    Follow commonly accepted Zig community naming conventions:
    -   `PascalCase` for types (structs, enums, unions).
    -   `camelCase` for functions and methods.
    -   `snake_case` for variables, struct/union members, and source file names (`.zig`).
-   Always refer to the most recent Zig documentation for best practices and language features, as Zig is actively developed and may introduce new features or changes that can improve code quality and performance.
-   Always refer to DVUI documentation for GUI-related tasks, as it provides a comprehensive guide on how to use the library effectively.

# Testing

When writing tests, ensure that:

-   Tests are written in a clear and concise manner, with descriptive names for test functions.
-   Tests cover a wide range of scenarios, including edge cases and error conditions.
-   Use the `std.testing` module for writing tests, ensuring that tests are run using `zig test`.
-   Ensure that tests are automated and run as part of the CI pipeline to catch issues early.
-   Use assertions to verify expected behavior, and ensure that tests fail when the expected conditions are not met.
-   Ensure that tests are isolated and do not depend on external state or resources.
-   Ensure that tests don't write to stdout or debug output, as this can interfere with test results.
-   Ensure that tests don't write to disk or modify the filesystem, as this can lead to flaky tests.
-   Test Naming and Scope (especially for `src/tests.zig`)
    Tests, particularly those in `src/tests.zig`, must be descriptively named (e.g., `test "descriptive test name" { ... }`).
    Each test should ideally verify a single logical unit or functionality.
    Include tests for edge cases, invalid inputs, and success scenarios.
    Ensure all tests are executable via `zig build test`.

# Build System (`build.zig`)

## applyTo: 'build.zig'

-   The `build.zig` file is central to the compilation process. It must be kept clean, well-commented, and organized.
-   Any complex build logic, option definitions (e.g., `-Doptimize`, `-Dtarget`), custom test steps, or dependency management must be clearly documented within it.

# Automation Scripts

## applyTo: 'scripts/\*\*'

-   Scripts in the `scripts/` directory (e.g., `build-all.sh`, `create-release.ps1`) must be well-commented, explaining their purpose, any parameters they accept, and any external dependencies.
-   If multiple versions exist for different operating systems (e.g., `.sh` and `.ps1`), ensure they maintain functional parity or clearly document the differences.
-   All comments and output within scripts must be in English.

# Version Control

-   Commit Messages
    Adopt the Conventional Commits standard for commit messages (e.g., `feat: add new feature`, `fix: correct bug X`, `docs: update Y documentation`, `style: code formatting`, `refactor: Z refactoring`, `test: add tests for W`, `chore: update build script`).
    This facilitates automatic changelog generation and improves the readability of the change history.

# Project Documentation

## applyTo: 'README.md'

-   The main `README.md` file must always be kept up-to-date and considered the primary entry point for understanding the project.
-   It must include:
    -   A clear description of the project.
    -   Detailed instructions for building (`zig build`) and running on different platforms.
    -   How to run tests (`zig build test`).
    -   Direct links to `CHANGELOG.md` and `RELEASE_NOTES.md`.
    -   Any specific system dependencies or requirements.
-   All content must be in English.

# Dependency Management

-   If the project starts using external dependencies managed via Zig's package manager (e.g., through a `build.zig.zon` file):
    -   Ensure this file is always committed.
    -   Ensure dependency versions are pinned to guarantee reproducible and stable builds.

# Performance Guidelines

When optimizing code, follow these principles:

-   Profile before optimizing - use `zig build -Doptimize=ReleaseFast` for performance testing
-   Prefer algorithmic improvements over micro-optimizations
-   Use `comptime` for compile-time calculations to reduce runtime overhead
-   Minimize memory allocations in hot paths
-   Document performance-critical sections with comments explaining why specific approaches were chosen
-   Include performance benchmarks in commit messages when making optimization changes
-   Always test both debug and release builds before commits
-   Use `-Doptimize=ReleaseFast` for production builds
-   Include cross-compilation testing in CI for all target platforms
-   Ensure builds are reproducible - avoid system-dependent paths or timestamps

# Memory Management

When working with memory in Zig:

-   Use arena allocators for temporary allocations that can be freed together
-   Always pair allocator.alloc() with allocator.free()
-   Use `defer` for automatic cleanup in error paths
-   Prefer stack allocation over heap when data size is known and reasonable
-   Document memory ownership in function signatures
-   Avoid memory leaks by ensuring all allocated memory is properly freed

# Multithreading Guidelines

For concurrent code:

-   Use Zig's thread-safe primitives (`std.Thread.Mutex`, `std.atomic`)
-   Avoid shared mutable state when possible - prefer message passing
-   Document thread safety guarantees in function comments
-   Use `std.Thread.Pool` for work distribution patterns
-   Always handle thread creation/joining errors gracefully
-   Test multithreaded code with different thread counts and under high load
-   Ensure proper synchronization to avoid race conditions

# Error Handling Specifics

For robust error handling:

-   Define custom error sets for different subsystems (e.g., `GridError`, `WorkerError`)
-   Always handle or explicitly propagate errors - never ignore them
-   Use descriptive error names that indicate the failure cause
-   Log errors with sufficient context for debugging
-   Prefer returning errors over printing and continuing
-   Include relevant context in error messages (thread ID, operation state)

# Logging and Debugging

When adding logging and debug information:

-   Use structured logging with consistent format
-   Include relevant context in log messages (thread ID, operation state)
-   Use different log levels appropriately (debug, info, warn, error)
-   Never log sensitive information
-   Ensure logging doesn't significantly impact performance in release builds
-   Use `std.log` for consistent logging across the application

# Project fases

## Project Overview

You are developing **Zigline**, a lightweight and modular terminal emulator written entirely in **Zig**. This is a personal, experimental, and early-stage project — not intended for production — aimed at learning, exploring Zig's systems capabilities, and building a basic but extensible terminal.

You will implement core terminal emulator functionality (PTY, ANSI parsing, rendering, input), integrate a Zig-native GUI (DVUI), and layer in advanced features like tabbed sessions, session persistence, and user configuration.

Each phase must be implemented and tested in isolation before proceeding to the next.

---

## Phase 1: Project Setup

-   Initialize a Zig project using `zig init-exe`.
-   Create a modular directory structure:
    -   `src/` for core application code
    -   `tests/` for test files
    -   `assets/` or `config/` if needed
-   Configure `build.zig` to:
    -   Support debug and release modes
    -   Easily add or exclude GUI or PTY backends
-   Set up basic error logging with `std.log` or a custom wrapper
-   Verify the build works with a simple `main.zig` that logs “Zigline initialized”

---

## Phase 2: PTY & Shell Process Integration

-   Create a pseudo-terminal (PTY) using direct syscalls or a Zig wrapper for system APIs
-   Launch a subprocess (`/bin/sh` or `$SHELL`) attached to the PTY slave
-   Set the PTY master to non-blocking mode
-   Continuously read from the PTY master:
    -   Buffer output from the shell process
    -   Pass data to the renderer or debug print it
-   Write to the PTY from user input
-   Build a basic loop that echoes shell output and accepts keyboard input

---

## Phase 3: ANSI Parsing & Screen Buffer Management

-   Define an internal screen buffer:
    -   2D array of character cells
    -   Each cell includes character, foreground/background color, and style (bold, underline, etc.)
-   Parse basic ANSI escape sequences:
    -   Cursor movement (`CSI n A/B/C/D`)
    -   Color attributes (`CSI 30–37`, `CSI 40–47`)
    -   Clear screen (`CSI 2J`)
-   Update the buffer as new data is received
-   Create a debug output renderer to print buffer state to stdout or a string

---

## Phase 4: Input Handling

-   Capture user keyboard input:
    -   Use terminal raw mode (on Unix) or DVUI events
    -   Read key events asynchronously or via polling
-   Normalize special keys into ANSI sequences:
    -   Arrows, backspace, delete, enter, tab, etc.
-   Forward user input to the PTY input stream
-   Test the full loop: keypress → PTY write → shell response → ANSI → buffer update

---

## Phase 5: Graphical Rendering via DVUI

-   Add the DVUI dependency and integrate it into your `build.zig`
-   Create a basic DVUI application window
-   Render the buffer from Phase 3 inside a text grid:
    -   Map ANSI colors and styles to DVUI primitives
    -   Implement cursor drawing and blinking
-   Handle window resize events:
    -   Resize internal buffer and notify the PTY of new terminal size (`TIOCSWINSZ`)
-   Forward key and mouse input from DVUI to your input handler

---

## Phase 6: Advanced Features

-   **Tabbed sessions:**

    -   Maintain multiple PTYs and buffers
    -   Switch between them using hotkeys
    -   Update DVUI UI to support tab headers or selectors

-   **Session persistence:**

    -   Save buffer state, cursor, and configuration to disk
    -   Load session on startup if a restore flag is passed

-   **Configuration:**

    -   Parse a simple config file (TOML or JSON) for:
        -   Color themes
        -   Fonts
        -   Default shell
        -   Keybindings
    -   Hot-reload config if file changes (optional)

-   **Input enhancements:**

    -   Support Ctrl/Alt/Shift modifiers
    -   Mouse click support (for copy/paste or future apps)

-   **Rendering improvements:**
    -   Consider using a font engine for better Unicode and font rendering
    -   Support font fallback or emoji rendering in future

---

## Phase 7: Testing & Documentation

-   Unit test:

    -   ANSI parser (known escape sequences)
    -   Buffer behavior under input/output
    -   Key normalization and escape generation

-   Manual tests:

    -   Run interactive shells
    -   Resize window and verify PTY behavior
    -   Open multiple tabs and switch reliably

-   Write a complete `README.md`:

    -   Project description and goals
    -   Build instructions
    -   Usage instructions and known issues
    -   Contribution guide (if open source)

-   Inline documentation:
    -   Add Zig-style doc comments for each major function and module
    -   Maintain modular and readable code for future refactoring

---

## Final Notes

-   Prioritize simplicity and readability over completeness.
-   Avoid premature optimization — focus on correctness and clarity.
-   Build incrementally: always validate output before moving forward.
-   Keep the codebase clean and modular to enable future experimentation.
