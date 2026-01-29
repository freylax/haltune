const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            // Target aarch64-linux-gnu for Raspberry Pi 5 compatibility
            // Must use glibc (GNU ABI) to link with liblinuxcnchal.so
            // liblinuxcnchal.so is built against glibc 2.41
            .cpu_arch = .aarch64,
            .os_tag = .linux,
            .abi = .gnu, // Use glibc, not musl
        },
    });

    const optimize = b.standardOptimizeOption(.{});

    // LinuxCNC include path - system option for dev vs production environments
    const linuxcnc_include = b.option([]const u8, "linuxcnc-include", "Path to LinuxCNC headers (default: /usr/include/linuxcnc)") orelse "/usr/include/linuxcnc";

    // Option to skip HAL library linking for development on machines without LinuxCNC
    const skip_hal_link = b.option(bool, "skip-hal-link", "Skip linking against libhal (for development on machines without LinuxCNC)") orelse false;

    // Create FFI modules for imports
    const ffi_c = b.createModule(.{
        .root_source_file = b.path("src/ffi/c.zig"),
        .target = target,
        .optimize = optimize,
    });
    ffi_c.addIncludePath(.{ .cwd_relative = linuxcnc_include });

    const ffi_errors = b.createModule(.{
        .root_source_file = b.path("src/ffi/errors.zig"),
        .target = target,
        .optimize = optimize,
    });

    const ffi_types = b.createModule(.{
        .root_source_file = b.path("src/ffi/types.zig"),
        .target = target,
        .optimize = optimize,
    });
    ffi_types.addImport("c.zig", ffi_c);

    const state_cache = b.createModule(.{
        .root_source_file = b.path("src/state/cache.zig"),
        .target = target,
        .optimize = optimize,
    });
    state_cache.addImport("ffi-errors", ffi_errors);
    state_cache.addImport("ffi-types", ffi_types);

    const ffi_safe = b.createModule(.{
        .root_source_file = b.path("src/ffi/safe.zig"),
        .target = target,
        .optimize = optimize,
    });
    ffi_safe.addImport("c.zig", ffi_c);
    ffi_safe.addImport("errors.zig", ffi_errors);
    ffi_safe.addImport("types.zig", ffi_types);
    ffi_safe.addImport("../state/cache.zig", state_cache);

    // Create root module
    const root_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add FFI modules to root module
    root_module.addImport("ffi/c.zig", ffi_c);
    root_module.addImport("ffi/errors.zig", ffi_errors);
    root_module.addImport("ffi/types.zig", ffi_types);
    root_module.addImport("ffi/safe.zig", ffi_safe);

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

        // Note: Runtime library path must be set via LD_LIBRARY_PATH=/usr/lib
        // or configure /etc/ld.so.conf.d/ to find liblinuxcnchal.so at runtime
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

    // Create FFI modules for tests to import
    const ffi_c = b.createModule(.{
        .root_source_file = b.path("src/ffi/c.zig"),
        .target = target,
        .optimize = optimize,
    });
    ffi_c.addIncludePath(.{ .cwd_relative = linuxcnc_include });

    const ffi_errors = b.createModule(.{
        .root_source_file = b.path("src/ffi/errors.zig"),
        .target = target,
        .optimize = optimize,
    });

    const ffi_types = b.createModule(.{
        .root_source_file = b.path("src/ffi/types.zig"),
        .target = target,
        .optimize = optimize,
    });
    // types.zig depends on c.zig
    ffi_types.addImport("c.zig", ffi_c);

    // Create state module (needed by safe.zig for getSignalValue/getParamValue)
    const state_cache = b.createModule(.{
        .root_source_file = b.path("src/state/cache.zig"),
        .target = target,
        .optimize = optimize,
    });
    // state/cache.zig imports ../ffi/errors.zig, so we alias it
    state_cache.addImport("ffi-errors", ffi_errors);
    state_cache.addImport("ffi-types", ffi_types);

    const ffi_safe = b.createModule(.{
        .root_source_file = b.path("src/ffi/safe.zig"),
        .target = target,
        .optimize = optimize,
    });
    // safe.zig depends on c.zig, errors.zig, types.zig, and ../state/cache.zig
    ffi_safe.addImport("c.zig", ffi_c);
    ffi_safe.addImport("errors.zig", ffi_errors);
    ffi_safe.addImport("types.zig", ffi_types);
    ffi_safe.addImport("state-cache", state_cache);

    // Create test module
    const test_module = b.createModule(.{
        .root_source_file = b.path("tests/ffi/pin_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add FFI modules as imports so tests can access them
    test_module.addImport("ffi/c.zig", ffi_c);
    test_module.addImport("ffi/errors.zig", ffi_errors);
    test_module.addImport("ffi/safe.zig", ffi_safe);

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

        // Note: Runtime library path must be set via LD_LIBRARY_PATH=/usr/lib
    }

    // Create test step
    const run_test = b.addRunArtifact(test_exe);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_test.step);
}
