// Test configuration file parsers
//
// This test verifies that:
// 1. hal_parser.zig correctly parses .hal files
// 2. ini_parser.zig correctly parses .ini files
// 3. toml_config.zig correctly parses TOML config files
// 4. origin.zig data structures work correctly

const std = @import("std");
const hal_parser = @import("../config/hal_parser.zig");
const ini_parser = @import("../config/ini_parser.zig");
const toml_config = @import("../config/toml_config.zig");

test "Parse .hal file" {
    // Sample .hal file content
    const hal_content =
        \\# My HAL configuration
        \\# Load realtime threads
        \\loadrt threads name1=fast-thread period1=50000
        \\loadrt threads name2=slow-thread period2=1000000
        \\# Load siggen component
        \\loadrt siggen 0.00001
        \\# Connect signals to stepgens
        \\net X-vel siggen.0.cosine => stepgen.0.velocity-cmd
        \\net Y-vel siggen.0.sine => stepgen.1.velocity-cmd
        \\# Set stepgen scales
        \\setp stepgen.0.position-scale 10000
        \\setp stepgen.1.position-scale 10000
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
        \\[DISPLAY]
        \\DISPLAY = axis
        \\[HAL]
        \\HALFILE = core_stepper.hal
        \\HALFILE = custom.hal
        \\[TRAJ]
        \\COORDINATES = X Y Z
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

test "Parse TOML configuration file" {
    const toml_content =
        \\[files]
        \\hal_files = ["test.hal", "custom.hal"]
        \\ini_files = ["myconfig.ini"]
        \\
        \\[logging]
        \\file = "debug.log"
        \\
        \\[plugins]
        \\enabled = ["plugin1"]
    ;

    var config = try toml_config.parseTomlConfig(std.testing.allocator, toml_content);
    defer toml_config.deinit(&config, std.testing.allocator);

    // Check hal_files
    try std.testing.expect(config.files.hal_files != null);
    try std.testing.expectEqual(@as(usize, 2), config.files.hal_files.?.len);
    try std.testing.expectEqualStrings("test.hal", config.files.hal_files.?[0]);
    try std.testing.expectEqualStrings("custom.hal", config.files.hal_files.?[1]);

    // Check ini_files
    try std.testing.expect(config.files.ini_files != null);
    try std.testing.expectEqual(@as(usize, 1), config.files.ini_files.?.len);
    try std.testing.expectEqualStrings("myconfig.ini", config.files.ini_files.?[0]);

    // Check log file
    try std.testing.expect(config.logging.file != null);
    try std.testing.expectEqualStrings("debug.log", config.logging.file.?);

    // Check plugins
    try std.testing.expect(config.plugins.enabled != null);
    try std.testing.expectEqual(@as(usize, 1), config.plugins.enabled.?.len);
    try std.testing.expectEqualStrings("plugin1", config.plugins.enabled.?[0]);
}

test "Parse TOML with empty sections" {
    const toml_content =
        \\[files]
        \\
        \\[logging]
        \\
        \\[plugins]
        \\
    ;

    var config = try toml_config.parseTomlConfig(std.testing.allocator, toml_content);
    defer toml_config.deinit(&config, std.testing.allocator);

    // All should be null
    try std.testing.expect(config.files.hal_files == null);
    try std.testing.expect(config.files.ini_files == null);
    try std.testing.expect(config.logging.file == null);
    try std.testing.expect(config.plugins.enabled == null);
}

test "Generate default TOML configuration" {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    try toml_config.generateDefaultConfig(std.testing.allocator, buffer.writer());

    const output = buffer.items;

    // Check for expected sections
    try std.testing.expect(std.mem.indexOf(u8, output, "[files]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[logging]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[plugins]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "hal_files") != null);
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

test "Write TOML configuration file" {
    const toml_write = @import("../config/toml_write.zig");

    var config = toml_config.TomlConfig{
        .files = .{
            .hal_files = try std.testing.allocator.alloc([]const u8, 2),
            .ini_files = try std.testing.allocator.alloc([]const u8, 1),
        },
        .logging = .{
            .file = try std.testing.allocator.dupe(u8, "test.log"),
        },
        .plugins = .{
            .enabled = try std.testing.allocator.alloc([]const u8, 2),
            .settings = null,
        },
    };
    defer {
        // Clean up hal_files
        for (config.files.hal_files.?) |f| std.testing.allocator.free(f);
        std.testing.allocator.free(config.files.hal_files.?);
        // Clean up ini_files
        for (config.files.ini_files.?) |f| std.testing.allocator.free(f);
        std.testing.allocator.free(config.files.ini_files.?);
        // Clean up logging
        if (config.logging.file) |f| std.testing.allocator.free(f);
        // Clean up plugins
        for (config.plugins.enabled.?) |p| std.testing.allocator.free(p);
        std.testing.allocator.free(config.plugins.enabled.?);
    }

    config.files.hal_files.?[0] = try std.testing.allocator.dupe(u8, "test1.hal");
    config.files.hal_files.?[1] = try std.testing.allocator.dupe(u8, "test2.hal");
    config.files.ini_files.?[0] = try std.testing.allocator.dupe(u8, "config.ini");
    config.plugins.enabled.?[0] = try std.testing.allocator.dupe(u8, "velocity_control");
    config.plugins.enabled.?[1] = try std.testing.allocator.dupe(u8, "trapvel_control");

    // Write to buffer
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    try toml_write.writeTomlConfig(buffer.writer(), &config);

    const output = buffer.items;

    // Verify output contains expected sections and values
    try std.testing.expect(std.mem.indexOf(u8, output, "[files]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[logging]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[plugins]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "test1.hal") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "test2.hal") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "config.ini") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "test.log") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "velocity_control") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "trapvel_control") != null);
}

test "Write empty TOML configuration" {
    const toml_write = @import("../config/toml_write.zig");

    var config = toml_config.TomlConfig{
        .files = .{
            .hal_files = null,
            .ini_files = null,
        },
        .logging = .{
            .file = null,
        },
        .plugins = .{
            .enabled = null,
            .settings = null,
        },
    };

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    try toml_write.writeTomlConfig(buffer.writer(), &config);

    const output = buffer.items;

    // Should still have sections but no values
    try std.testing.expect(std.mem.indexOf(u8, output, "[files]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[logging]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[plugins]") != null);
}

test "Write and read round-trip" {
    const toml_write = @import("../config/toml_write.zig");

    var original = toml_config.TomlConfig{
        .files = .{
            .hal_files = try std.testing.allocator.alloc([]const u8, 1),
            .ini_files = null,
        },
        .logging = .{
            .file = try std.testing.allocator.dupe(u8, "roundtrip.log"),
        },
        .plugins = .{
            .enabled = try std.testing.allocator.alloc([]const u8, 1),
            .settings = null,
        },
    };
    defer {
        if (original.files.hal_files) |files| {
            for (files) |f| std.testing.allocator.free(f);
            std.testing.allocator.free(files);
        }
        if (original.logging.file) |f| std.testing.allocator.free(f);
        if (original.plugins.enabled) |plugins| {
            for (plugins) |p| std.testing.allocator.free(p);
            std.testing.allocator.free(plugins);
        }
    }

    original.files.hal_files.?[0] = try std.testing.allocator.dupe(u8, "test.hal");
    original.plugins.enabled.?[0] = try std.testing.allocator.dupe(u8, "test_plugin");

    // Write to buffer
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    try toml_write.writeTomlConfig(buffer.writer(), &original);

    // Parse it back
    var parsed = try toml_config.parseTomlConfig(std.testing.allocator, buffer.items);
    defer toml_config.deinit(&parsed, std.testing.allocator);

    // Verify round-trip
    try std.testing.expect(parsed.files.hal_files != null);
    try std.testing.expectEqual(@as(usize, 1), parsed.files.hal_files.?.len);
    try std.testing.expectEqualStrings("test.hal", parsed.files.hal_files.?[0]);
    try std.testing.expectEqualStrings("roundtrip.log", parsed.logging.file.?);
    try std.testing.expectEqualStrings("test_plugin", parsed.plugins.enabled.?[0]);
}

// Note: This is a standalone test that doesn't require HAL libraries
// It verifies config parsing logic without linking to linuxcnchal
