// Test configuration file parsers
//
// This test verifies that:
// 1. hal_parser.zig correctly parses .hal files
// 2. ini_parser.zig correctly parses .ini files
// 3. origin.zig data structures work correctly

const std = @import("std");
const hal_parser = @import("../config/hal_parser.zig");
const ini_parser = @import("../config/ini_parser.zig");

test "Parse .hal file" {
    // Sample .hal file content
    const hal_content =
        \\# My HAL configuration
        \\# Load realtime threads
        loadrt threads name1=fast-thread period1=50000
        loadrt threads name2=slow-thread period2=1000000
        \\
        \\# Load siggen component
        loadrt siggen 0.00001
        \\
        \\# Connect signals to stepgens
        net X-vel siggen.0.cosine => stepgen.0.velocity-cmd
        net Y-vel siggen.0.sine => stepgen.1.velocity-cmd
        \\
        \\# Set stepgen scales
        setp stepgen.0.position-scale 10000
        setp stepgen.1.position-scale 10000
    ;

    // Test parsing
    const result = try hal_parser.parseHalFile(std.testing.allocator, "test.hal", hal_content);
    defer result.deinit();

    // Verify results
    var setp_count: usize = 0;
    var net_count: usize = 0;

    for (result.commands.items) |cmd| {
        switch (cmd) {
            .setp => setp_count += 1,
            .net => net_count += 1,
            else => {},
        }
    }

    // Should have 2 setp and 2 net commands
    try std.testing.expectEqual(setp_count, 2);
    try std.testing.expectEqual(net_count, 2);
}

test "Parse .ini file" {
    // Sample .ini file content
    const ini_content =
        \\# LinuxCNC configuration
        \\[EMC]
        \\VERSION = 1.1
        \\MACHINE = My Controller
        \\
        \\[DISPLAY]
        \\DISPLAY = axis
        \\
        \\[HAL]
        \\HALFILE = core_stepper.hal
        \\HALFILE = custom.hal
        \\
        \\[TRAJ]
        \\COORDINATES = X Y Z
        \\
        \\[JOINT_0]
        \\TYPE = LINEAR
        \\SCALE = 16000
    ;

    // Test parsing
    const result = try ini_parser.parseIniFile(std.testing.allocator, "test.ini", ini_content);
    defer result.deinit();

    // Verify we got the HALFILE entries
    var halfile_count: usize = 0;
    for (result.entries.items) |entry| {
        if (entry == .halfile) halfile_count += 1;
    }

    // Should have 2 HALFILE entries
    try std.testing.expectEqual(halfile_count, 2);
}

test "Origin data structures" {
    // Just verify origin.zig compiles
    const origin = @import("../config/origin.zig");

    // Test that Origin enum has correct values
    try std.testing.expectEqual(@intFromEnum(origin.Origin.hal_file), 1);
    try std.testing.expectEqual(@intFromEnum(origin.Origin.ini_file), 2);
    try std.testing.expectEqual(@intFromEnum(origin.Origin.none), 0);
    try std.testing.expectEqual(@intFromEnum(origin.Origin.default_value), 3);
    try std.testing.expectEqual(@intFromEnum(origin.Origin.runtime_modified), 4);
}

// Note: This is a standalone test that doesn't require HAL libraries
// It verifies config parsing logic without linking to linuxcnchal
