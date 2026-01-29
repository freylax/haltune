const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            // Target aarch64-linux for Raspberry Pi 5 compatibility
            .cpu_arch = .aarch64,
            .os_tag = .linux,
            // Use musl - requires: apt install musl on target
            // Note: This conflicts with liblinuxcnchal.so which is glibc-based
            // To fix: either build LinuxCNC from source with musl, or use glibc build
        },
    });

    const optimize = b.standardOptimizeOption(.{});

    // LinuxCNC include path - system option for dev vs production environments
    const linuxcnc_include = b.option([]const u8, "linuxcnc-include", "Path to LinuxCNC headers (default: /usr/include/linuxcnc)") orelse "/usr/include/linuxcnc";

    // Option to skip HAL library linking for development on machines without LinuxCNC
    const skip_hal_link = b.option(bool, "skip-hal-link", "Skip linking against libhal (for development on machines without LinuxCNC)") orelse false;

    // Create root module
    const root_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add LinuxCNC HAL include path for @cImport
    root_module.addIncludePath(.{ .cwd_relative = linuxcnc_include });

    // Create the haltune executable
    const exe = b.addExecutable(.{
        .name = "haltune",
        .root_module = root_module,
    });

    // Link against LinuxCNC HAL library (system library search path)
    // Skip if building on dev machine without LinuxCNC installed
    if (!skip_hal_link) {
        exe.addLibraryPath(.{ .cwd_relative = "/usr/lib" }); // Search /usr/lib for liblinuxcnchal.so

        // Link libc first to provide GLIBC symbols needed by liblinuxcnchal.so
        exe.linkSystemLibrary("c");
        exe.linkSystemLibrary("linuxcnchal"); // Library is liblinuxcnchal.so on Debian/Ubuntu
        exe.linkSystemLibrary("rt"); // LinuxCNC HAL requires librt

        // Allow undefined symbols in shared libraries to work around GLIBC version mismatch
        // LLD is stricter than system linker about symbol versions
        exe.linker_allow_shlib_undefined = true;

        // Add RPATH so runtime linker can find liblinuxcnchal.so
        exe.rpath = "/usr/lib";
    }

    // Install the executable
    b.installArtifact(exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // ===== Test Configuration =====

    // Create test module
    const test_module = b.createModule(.{
        .root_source_file = b.path("tests/ffi/pin_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add LinuxCNC HAL include path for @cImport
    test_module.addIncludePath(.{ .cwd_relative = linuxcnc_include });

    // Create test executable
    const test_exe = b.addTest(.{
        .root_module = test_module,
    });

    // Link test against LinuxCNC HAL library
    if (!skip_hal_link) {
        test_exe.addLibraryPath(.{ .cwd_relative = "/usr/lib" }); // Search /usr/lib for liblinuxcnchal.so

        // Link libc first to provide GLIBC symbols
        test_exe.linkSystemLibrary("c");
        test_exe.linkSystemLibrary("linuxcnchal"); // Library is liblinuxcnchal.so on Debian/Ubuntu
        test_exe.linkSystemLibrary("rt");

        // Allow undefined symbols in shared libraries
        test_exe.linker_allow_shlib_undefined = true;

        // Add RPATH so runtime linker can find liblinuxcnchal.so
        test_exe.rpath = "/usr/lib";
    }

    // Create test step
    const run_test = b.addRunArtifact(test_exe);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_test.step);
}
