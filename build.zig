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

    // Option to skip HAL library linking for development on machines without LinuxCNC
    const skip_hal_link = b.option(bool, "skip-hal-link", "Skip linking against libhal (for development on machines without LinuxCNC)") orelse false;

    // LinuxCNC include path - system option for dev vs production environments
    const linuxcnc_include = b.option([]const u8, "linuxcnc-include", "Path to LinuxCNC headers (default: /usr/include/linuxcnc)") orelse
        if (skip_hal_link) "include" else "/usr/include/linuxcnc";

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

    const state_pubsub = b.createModule(.{
        .root_source_file = b.path("src/state/pubsub.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Pin module (depends on errors.zig)
    const ffi_pin = b.createModule(.{
        .root_source_file = b.path("src/ffi/pin.zig"),
        .target = target,
        .optimize = optimize,
    });
    ffi_pin.addIncludePath(.{ .cwd_relative = linuxcnc_include });
    ffi_pin.addImport("errors", ffi_errors);

    // Component module (depends on errors.zig and pin.zig)
    const ffi_component = b.createModule(.{
        .root_source_file = b.path("src/ffi/component.zig"),
        .target = target,
        .optimize = optimize,
    });
    ffi_component.addIncludePath(.{ .cwd_relative = linuxcnc_include });
    ffi_component.addImport("errors", ffi_errors);
    ffi_component.addImport("pin", ffi_pin);

    // Wiring module (depends on errors.zig)
    const ffi_wiring = b.createModule(.{
        .root_source_file = b.path("src/ffi/wiring.zig"),
        .target = target,
        .optimize = optimize,
    });
    ffi_wiring.addIncludePath(.{ .cwd_relative = linuxcnc_include });
    ffi_wiring.addImport("errors", ffi_errors);

    const ffi_safe = b.createModule(.{
        .root_source_file = b.path("src/ffi/safe.zig"),
        .target = target,
        .optimize = optimize,
    });
    ffi_safe.addImport("c.zig", ffi_c);
    ffi_safe.addImport("errors.zig", ffi_errors);
    ffi_safe.addImport("types.zig", ffi_types);
    ffi_safe.addImport("../state/cache.zig", state_cache);

    // Vaxis dependency for TUI framework
    const vaxis = b.dependency("vaxis", .{
        .target = target,
        .optimize = optimize,
    });

    // Glob dependency for pattern matching
    const glob = b.dependency("glob", .{
        .target = target,
        .optimize = optimize,
    });

    // TOML dependency for configuration files
    const toml = b.dependency("toml", .{
        .target = target,
        .optimize = optimize,
    });

    // TOML config module (for reading TOML configs)
    const toml_config = b.createModule(.{
        .root_source_file = b.path("src/config/toml_config.zig"),
        .target = target,
        .optimize = optimize,
    });
    toml_config.addImport("toml", toml.module("toml"));

    // TOML write module (for writing TOML configs)
    const toml_write = b.createModule(.{
        .root_source_file = b.path("src/config/toml_write.zig"),
        .target = target,
        .optimize = optimize,
    });
    toml_write.addImport("toml", toml.module("toml"));
    toml_write.addImport("toml_config", toml_config);

    // Plugin interface module (NO FFI imports - clean separation)
    const plugin_interface = b.createModule(.{
        .root_source_file = b.path("src/plugin/interface.zig"),
        .target = target,
        .optimize = optimize,
    });
    plugin_interface.addImport("vaxis", vaxis.module("vaxis"));

    // Plugin registry module
    const plugin_registry = b.createModule(.{
        .root_source_file = b.path("src/plugin/registry.zig"),
        .target = target,
        .optimize = optimize,
    });
    plugin_registry.addImport("plugin/interface", plugin_interface);

    // Plugin manager module (minimal - no FFI imports)
    const plugin_manager = b.createModule(.{
        .root_source_file = b.path("src/plugin/manager.zig"),
        .target = target,
        .optimize = optimize,
    });
    plugin_manager.addImport("plugin/interface", plugin_interface);
    plugin_manager.addImport("plugin/registry", plugin_registry);

    // Velocity control plugin
    const velocity_control_plugin = b.createModule(.{
        .root_source_file = b.path("src/plugins/velocity_control.zig"),
        .target = target,
        .optimize = optimize,
    });
    velocity_control_plugin.addImport("vaxis", vaxis.module("vaxis"));

    // TrapVel control plugin
    const trapvel_control_plugin = b.createModule(.{
        .root_source_file = b.path("src/plugins/trapvel_control.zig"),
        .target = target,
        .optimize = optimize,
    });
    trapvel_control_plugin.addImport("vaxis", vaxis.module("vaxis"));

    // Plugins registry (registers all plugins)
    const plugins = b.createModule(.{
        .root_source_file = b.path("src/plugins/plugins.zig"),
        .target = target,
        .optimize = optimize,
    });
    plugins.addImport("plugin/registry", plugin_registry);
    plugins.addImport("velocity_control", velocity_control_plugin);
    plugins.addImport("trapvel_control", trapvel_control_plugin);

    // Create HAL backend module for haltune (needed for protocol module)
    // Must be created before tui_module which depends on it
    const hal_backend_module = b.createModule(.{
        .root_source_file = b.path("src/hal/backend.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create TUI module
    const tui_module = b.createModule(.{
        .root_source_file = b.path("src/tui/app.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Import existing modules into TUI
    tui_module.addImport("ffi-errors", ffi_errors);
    tui_module.addImport("ffi-types", ffi_types);
    tui_module.addImport("state-cache", state_cache);
    tui_module.addImport("state-pubsub", state_pubsub);

    // Add Vaxis to TUI module
    tui_module.addImport("vaxis", vaxis.module("vaxis"));

    // Add Glob to TUI module
    tui_module.addImport("glob", glob.module("glob"));

    // Add TOML to TUI module
    tui_module.addImport("toml", toml.module("toml"));
    tui_module.addImport("toml_config", toml_config);
    tui_module.addImport("toml_write", toml_write);

    // Add plugin modules to TUI
    tui_module.addImport("plugin/interface", plugin_interface);
    tui_module.addImport("plugin/registry", plugin_registry);
    tui_module.addImport("plugin/manager", plugin_manager);
    tui_module.addImport("plugins", plugins);
    tui_module.addImport("backend", hal_backend_module); // For protocol access

    // Create root module

    // Create root module
    const root_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add backend module to root for protocol access
    root_module.addImport("backend", hal_backend_module);

    // Add FFI modules to root module
    root_module.addImport("ffi/c.zig", ffi_c);
    root_module.addImport("ffi/errors.zig", ffi_errors);
    root_module.addImport("ffi/types.zig", ffi_types);
    root_module.addImport("ffi/safe.zig", ffi_safe);
    root_module.addImport("ffi/pin.zig", ffi_pin);
    root_module.addImport("ffi/component.zig", ffi_component);
    root_module.addImport("ffi/wiring.zig", ffi_wiring);
    root_module.addImport("ffi", ffi_component); // Add convenience import
    root_module.addImport("vaxis", vaxis.module("vaxis"));
    root_module.addImport("glob", glob.module("glob"));
    root_module.addImport("toml", toml.module("toml"));
    root_module.addImport("toml_config", toml_config);
    root_module.addImport("toml_write", toml_write);

    // Add plugin modules to root
    root_module.addImport("plugin/interface", plugin_interface);
    root_module.addImport("plugin/registry", plugin_registry);
    root_module.addImport("plugin/manager", plugin_manager);
    root_module.addImport("plugins", plugins);

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
        // Add multiple library paths for cross-compilation support
        exe.addLibraryPath(.{ .cwd_relative = "/usr/lib" });
        exe.addLibraryPath(.{ .cwd_relative = "/home/robert/zig-sdk/aarch64-linux-gnu/lib" });

        // Link libc first to provide GLIBC symbols needed by liblinuxcnchal.so
        exe.linkSystemLibrary("c");
        exe.linkSystemLibrary("linuxcnchal"); // Library is liblinuxcnchal.so on Debian/Ubuntu
        exe.linkSystemLibrary("rt"); // LinuxCNC HAL requires librt

        // Allow undefined symbols in shared libraries to work around GLIBC version mismatch
        // LLD is stricter than system linker about symbol versions
        exe.linker_allow_shlib_undefined = true;

        // Note: Runtime library path must be set via LD_LIBRARY_PATH=/usr/lib
        // or configure /etc/ld.so.conf.d/ to find liblinuxcnchal.so at runtime
    } else {
        // Even when skipping HAL link, we still need libc for std.heap.c_allocator
        exe.linkSystemLibrary("c");
        // Add HAL stub C file for linking without LinuxCNC
        exe.addCSourceFile(.{
            .file = b.path("src/ffi/hal_stubs.c"),
        });
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

    // Note: FFI modules (ffi_c, ffi_errors, ffi_types, ffi_safe, state_cache)
    // are already created above for the main executable. We reuse them here.

    // Create test module
    const test_module = b.createModule(.{
        .root_source_file = b.path("tests/ffi/pin_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add include path to test module (for @cImport in imported modules)
    test_module.addIncludePath(.{ .cwd_relative = linuxcnc_include });

    // Add FFI modules as imports so tests can access them
    test_module.addImport("ffi/c.zig", ffi_c);
    test_module.addImport("errors", ffi_errors);
    test_module.addImport("ffi/types.zig", ffi_types);
    test_module.addImport("ffi/safe.zig", ffi_safe);
    test_module.addImport("ffi/pin.zig", ffi_pin);
    test_module.addImport("ffi/component.zig", ffi_component);
    test_module.addImport("ffi/wiring.zig", ffi_wiring);

    // Create test executable
    const test_exe = b.addTest(.{
        .root_module = test_module,
    });

    // Add include path for C headers
    test_exe.addIncludePath(.{ .cwd_relative = linuxcnc_include });

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
    } else {
        // Even when skipping HAL link, we still need libc
        test_exe.linkSystemLibrary("c");
    }

    // Create test step
    const run_test = b.addRunArtifact(test_exe);

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_test.step);

    // ===== Discovery Test =====

    // Create discovery test module
    const discovery_module = b.createModule(.{
        .root_source_file = b.path("tests/discovery_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add FFI modules to discovery test module
    discovery_module.addImport("ffi/c.zig", ffi_c);
    discovery_module.addImport("ffi/errors.zig", ffi_errors);
    discovery_module.addImport("ffi/types.zig", ffi_types);
    discovery_module.addImport("ffi/safe.zig", ffi_safe);

    // Create discovery test executable
    const discovery_exe = b.addExecutable(.{
        .name = "discovery-test",
        .root_module = discovery_module,
    });

    // Link discovery test against LinuxCNC HAL library
    if (!skip_hal_link) {
        discovery_exe.addLibraryPath(.{ .cwd_relative = "/usr/lib" });
        discovery_exe.linkSystemLibrary("c");
        discovery_exe.linkSystemLibrary("linuxcnchal");
        discovery_exe.linkSystemLibrary("rt");
        discovery_exe.linker_allow_shlib_undefined = true;
    }

    // Create discovery test run step
    const run_discovery = b.addRunArtifact(discovery_exe);
    run_discovery.step.dependOn(b.getInstallStep());

    const discovery_step = b.step("discovery", "Run HAL discovery test");
    discovery_step.dependOn(&run_discovery.step);

    // ===== Full Discovery Test (with created objects) =====

    // Create full discovery test module
    const discovery_full_module = b.createModule(.{
        .root_source_file = b.path("tests/discovery_full_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add FFI modules to full discovery test module
    discovery_full_module.addImport("ffi/c.zig", ffi_c);
    discovery_full_module.addImport("ffi/errors.zig", ffi_errors);
    discovery_full_module.addImport("ffi/types.zig", ffi_types);
    discovery_full_module.addImport("ffi/safe.zig", ffi_safe);

    // Create full discovery test executable
    const discovery_full_exe = b.addExecutable(.{
        .name = "discovery-full-test",
        .root_module = discovery_full_module,
    });

    // Link full discovery test against LinuxCNC HAL library
    if (!skip_hal_link) {
        discovery_full_exe.addLibraryPath(.{ .cwd_relative = "/usr/lib" });
        discovery_full_exe.linkSystemLibrary("c");
        discovery_full_exe.linkSystemLibrary("linuxcnchal");
        discovery_full_exe.linkSystemLibrary("rt");
        discovery_full_exe.linker_allow_shlib_undefined = true;
    }

    // Create full discovery test run step
    const run_discovery_full = b.addRunArtifact(discovery_full_exe);
    run_discovery_full.step.dependOn(b.getInstallStep());

    const discovery_full_step = b.step("discovery-full", "Run HAL discovery test with created objects");
    discovery_full_step.dependOn(&run_discovery_full.step);

    // ===== Tree Debug Test =====

    const tree_debug_module = b.createModule(.{
        .root_source_file = b.path("src/test_tree_debug.zig"),
        .target = target,
        .optimize = optimize,
    });

    tree_debug_module.addImport("ffi/c.zig", ffi_c);
    tree_debug_module.addImport("ffi/errors.zig", ffi_errors);
    tree_debug_module.addImport("ffi/types.zig", ffi_types);
    tree_debug_module.addImport("ffi/safe.zig", ffi_safe);
    tree_debug_module.addImport("../state/cache.zig", state_cache);
    tree_debug_module.addImport("../state/refresh.zig", b.createModule(.{
        .root_source_file = b.path("src/state/refresh.zig"),
        .target = target,
        .optimize = optimize,
    }));

    const tree_debug_exe = b.addExecutable(.{
        .name = "tree-debug",
        .root_module = tree_debug_module,
    });

    if (!skip_hal_link) {
        tree_debug_exe.addLibraryPath(.{ .cwd_relative = "/usr/lib" });
        tree_debug_exe.linkSystemLibrary("c");
        tree_debug_exe.linkSystemLibrary("linuxcnchal");
        tree_debug_exe.linkSystemLibrary("rt");
        tree_debug_exe.linker_allow_shlib_undefined = true;
    }

    // ===== TOML Write Test =====

    // Create toml write test module (no FFI dependencies needed)
    const toml_write_module = b.createModule(.{
        .root_source_file = b.path("tests/toml_write_test_standalone.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add TOML dependency
    toml_write_module.addImport("toml", toml.module("toml"));
    toml_write_module.addImport("toml_write", toml_write);
    toml_write_module.addImport("toml_config", toml_config);

    // Create toml write test executable
    const toml_write_exe = b.addTest(.{
        .root_module = toml_write_module,
    });

    // Create toml write test run step
    const run_toml_write = b.addRunArtifact(toml_write_exe);

    const toml_write_step = b.step("toml-write-test", "Run TOML write test");
    toml_write_step.dependOn(&run_toml_write.step);

    // ===== HAL Bridge Server =====
    // Skip bridge server build when skip_hal_link is set (development without LinuxCNC)

    if (!skip_hal_link) {
        const hal_native_module = b.createModule(.{
            .root_source_file = b.path("src/hal/native.zig"),
            .target = target,
            .optimize = optimize,
        });
        hal_native_module.addImport("backend", hal_backend_module);
        hal_native_module.addImport("ffi-c", ffi_c);

        // Create protocol module for bridge server
        // IMPORTANT: protocol imports backend as a MODULE to avoid circular deps
        const hal_protocol_module = b.createModule(.{
            .root_source_file = b.path("src/hal/remote/protocol.zig"),
            .target = target,
            .optimize = optimize,
        });
        hal_protocol_module.addImport("backend", hal_backend_module);

        // Create bridge server module
        const bridge_server_module = b.createModule(.{
            .root_source_file = b.path("src/hal/bridge_server/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        bridge_server_module.addImport("backend", hal_backend_module);
        bridge_server_module.addImport("native", hal_native_module);
        bridge_server_module.addImport("protocol", hal_protocol_module);
        bridge_server_module.addIncludePath(.{ .cwd_relative = linuxcnc_include });

        // Create bridge server executable
        const bridge_server_exe = b.addExecutable(.{
            .name = "hal_bridge_server",
            .root_module = bridge_server_module,
        });

        // Link bridge server against LinuxCNC HAL library
        bridge_server_exe.addLibraryPath(.{ .cwd_relative = "/usr/lib" });
        bridge_server_exe.addLibraryPath(.{ .cwd_relative = "/home/robert/zig-sdk/aarch64-linux-gnu/lib" });
        bridge_server_exe.linkSystemLibrary("c");
        bridge_server_exe.linkSystemLibrary("linuxcnchal");
        bridge_server_exe.linkSystemLibrary("rt");
        bridge_server_exe.linker_allow_shlib_undefined = true;

        // Install bridge server
        b.installArtifact(bridge_server_exe);

        // Bridge server tests
        const bridge_server_test_module = b.createModule(.{
            .root_source_file = b.path("src/hal/bridge_server/test.zig"),
            .target = target,
            .optimize = optimize,
        });
        bridge_server_test_module.addImport("backend", hal_backend_module);
        bridge_server_test_module.addImport("protocol", hal_protocol_module);

        const bridge_server_tests = b.addTest(.{
            .root_module = bridge_server_test_module,
            .name = "bridge-server-test",
        });

        const run_bridge_server_tests = b.addRunArtifact(bridge_server_tests);
        run_bridge_server_tests.step.dependOn(b.getInstallStep());

        const bridge_server_test_step = b.step("bridge-server-test", "Run HAL bridge server tests");
        bridge_server_test_step.dependOn(&run_bridge_server_tests.step);

        // Bridge server run step
        const run_bridge_server = b.addRunArtifact(bridge_server_exe);
        run_bridge_server.step.dependOn(b.getInstallStep());

        const bridge_server_step = b.step("bridge-server", "Run HAL bridge server");
        bridge_server_step.dependOn(&run_bridge_server.step);
    }
}
