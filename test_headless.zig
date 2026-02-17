//! Headless test for haltune - tests core functionality without TUI

const std = @import("std");
const StateStore = @import("src/state/cache.zig").StateStore;
const RefreshThread = @import("src/state/refresh.zig").RefreshThread;
const hal_parser = @import("src/config/hal_parser.zig");
const ini_parser = @import("src/config/ini_parser.zig");
const ItemOrigin = @import("src/config/origin.zig").ItemOrigin;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("\n=== haltune Headless Test ===\n\n", .{});

    // Test 1: Initialize StateStore
    std.debug.print("Test 1: Initializing StateStore...\n", .{});
    var store = StateStore.init(allocator);
    defer store.deinit();
    std.debug.print("  StateStore initialized\n", .{});

    // Test 2: StateStore maps work
    std.debug.print("\nTest 2: Testing StateStore maps...\n", .{});
    const pin_count = store.pins.count();
    const sig_count = store.signals.count();
    const param_count = store.params.count();
    std.debug.print("  StateStore has {} pins, {} signals, {} params\n", .{ pin_count, sig_count, param_count });

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
    try std.fs.cwd().writeFile(.{
        .sub_path = test_hal_path,
        .data = test_hal_content,
    });

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
    try std.fs.cwd().writeFile(.{
        .sub_path = test_ini_path,
        .data = test_ini_content,
    });

    var ini_result = try ini_parser.parseIniFile(allocator, test_ini_path);
    defer ini_result.deinit();

    std.debug.print("  Parsed {} entries from test .ini file\n", .{ini_result.entries.items.len});

    // Count halfiles
    var halfiles = ini_result.listHalfiles();
    defer halfiles.deinit(allocator);
    // Note: halfiles.items are slices owned by ini_result, don't free them
    std.debug.print("  Found {} HALFILE entries\n", .{halfiles.items.len});

    // Test 5: Test origin tracking
    std.debug.print("\nTest 5: Testing origin tracking...\n", .{});

    // Test setp origin
    const test_origin = try ItemOrigin.fromHalFile(allocator, "/test/path.hal", 42);
    defer test_origin.deinit(allocator);

    std.debug.print("  Created test origin with path: {s}\n", .{test_origin.file_path orelse "null"});

    std.debug.print("\n=== All Tests Complete ===\n", .{});
}
