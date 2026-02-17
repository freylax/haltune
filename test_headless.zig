#!/usr/bin/env zig run
//! Headless test for haltune - tests core functionality without TUI

const std = @import("std");
const StateStore = @import("src/state/cache.zig").StateStore;
const RefreshThread = @import("src/state/refresh.zig").RefreshThread;
const hal_parser = @import("src/config/hal_parser.zig");
const ini_parser = @import("src/config/ini_parser.zig");
const ItemOrigin = @import("src/config/origin.zig").ItemOrigin;

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    std.debug.print("\n=== haltune Headless Test ===\n\n", .{});

    // Test 1: Initialize StateStore
    std.debug.print("Test 1: Initializing StateStore...\n", .{});
    var store = StateStore.init(allocator);
    defer store.deinit();
    std.debug.print("  StateStore initialized\n", .{});

    // Test 2: Start RefreshThread to discover HAL components
    std.debug.print("\nTest 2: Starting RefreshThread...\n", .{});
    var refresh_thread = try allocator.create(RefreshThread);
    defer allocator.destroy(refresh_thread);

    refresh_thread.* = RefreshThread.init(allocator, &store) catch |err| {
        std.debug.print("  Warning: Could not start RefreshThread: {}\n", .{err});
        std.debug.print("  (This is expected if LinuxCNC HAL is not running)\n", .{});
    } else {
        std.debug.print("  RefreshThread started\n", .{});

        // Wait a bit for discovery
        std.time.sleep(100 * std.time.ns_per_ms);

        // Check what we discovered
        const pin_count = store.pins.count();
        const sig_count = store.signals.count();
        const param_count = store.params.count();

        std.debug.print("  Discovered {} pins, {} signals, {} params\n", .{ pin_count, sig_count, param_count });

        refresh_thread.stop();
        std.debug.print("  RefreshThread stopped\n", .{});
    }

    // Test 3: Test .hal file parsing
    std.debug.print("\nTest 3: Testing .hal file parsing...\n", .{});

    // Create a test .hal file
    const test_hal_content =
        \\# Test HAL file
        \\loadusr -Wn halui halui
        \\setp halui.md5-01.0.input 1
        \\setp stepgen.00.position-scale 4000
        \\net X-pos stepgen.00.position-fb => motion.adaptive-feed
        \\
    ;

    const test_hal_path = "/tmp/test_haltune.hal";
    try std.fs.cwd().writeFile(.{ .sub_path = test_hal_path }, test_hal_content);

    var parse_result = try hal_parser.parseHalFile(allocator, test_hal_path, null);
    defer parse_result.deinit(allocator);

    std.debug.print("  Parsed {} commands from test .hal file\n", .{parse_result.commands.items.len});

    // Count setp commands
    var setp_count: usize = 0;
    for (parse_result.commands.items) |cmd| {
        if (cmd == .setp) setp_count += 1;
    }
    std.debug.print("  Found {} setp commands\n", .{setp_count});

    // Test 4: Test .ini file parsing
    std.debug.print("\nTest 4: Testing .ini file parsing...\n", .{});

    const test_ini_content =
        \\[EMC]
        \\MACHINE = PlasmaCutter
        \\DEBUG = 0
        \\
        \\[DISPLAY]
        \\DISPLAY = axis
        \\POSITION_OFFSET = RELATIVE
        \\
        \\[HAL]
        \\HALFILE = core_stepper.hal
        \\HALFILE = custom.hal
        \\POSTGUI_HALFILE = postgui.hal
        \\
        \\[TRAJ]
        \\AXES = 3
        \\COORDINATES = X Y Z
        \\MAX_VELOCITY = 30.0
        \\
    ;

    const test_ini_path = "/tmp/test_haltune.ini";
    try std.fs.cwd().writeFile(.{ .sub_path = test_ini_path }, test_ini_content);

    var ini_result = try ini_parser.parseIniFile(allocator, test_ini_path);
    defer ini_result.deinit();

    std.debug.print("  Parsed {} entries from test .ini file\n", .{ini_result.entries.items.len});

    // Count halfiles
    const halfiles = ini_result.listHalfiles(allocator);
    defer {
        for (halfiles.items) |f| allocator.free(f);
        halfiles.deinit(allocator);
    }
    std.debug.print("  Found {} HALFILE entries\n", .{halfiles.items.len});

    // Test 5: Test origin tracking
    std.debug.print("\nTest 5: Testing origin tracking...\n", .{});

    // Test setp origin
    const test_origin = try ItemOrigin.fromHalFile(allocator, "/test/path.hal", 42);
    defer test_origin.deinit(allocator);

    std.debug.print("  Created test origin: ", .{});
    try test_origin.format(std.io.getStdOut().writer());
    std.debug.print("\n", .{});

    std.debug.print("\n=== All Tests Complete ===\n", .{});
}
