// Test TOML write functionality - standalone test
//
// This test verifies that toml_write.zig can serialize TomlConfig
// back to TOML format.

const std = @import("std");
const toml = @import("toml");
const TomlConfig = @import("toml_config").TomlConfig;

test "Write TOML configuration file" {
    const toml_write = @import("toml_write");

    var config = TomlConfig{
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
        for (config.files.hal_files.?) |f| std.testing.allocator.free(f);
        std.testing.allocator.free(config.files.hal_files.?);
        for (config.files.ini_files.?) |f| std.testing.allocator.free(f);
        std.testing.allocator.free(config.files.ini_files.?);
        if (config.logging.file) |f| std.testing.allocator.free(f);
        for (config.plugins.enabled.?) |p| std.testing.allocator.free(p);
        std.testing.allocator.free(config.plugins.enabled.?);
    }

    config.files.hal_files.?[0] = try std.testing.allocator.dupe(u8, "test1.hal");
    config.files.hal_files.?[1] = try std.testing.allocator.dupe(u8, "test2.hal");
    config.files.ini_files.?[0] = try std.testing.allocator.dupe(u8, "config.ini");
    config.plugins.enabled.?[0] = try std.testing.allocator.dupe(u8, "velocity_control");
    config.plugins.enabled.?[1] = try std.testing.allocator.dupe(u8, "trapvel_control");

    var buffer = std.ArrayList(u8).initCapacity(std.testing.allocator, 1024) catch unreachable;
    defer buffer.deinit(std.testing.allocator);

    try toml_write.writeTomlConfig(buffer.writer(std.testing.allocator), &config);

    const output = buffer.items;

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
    const toml_write = @import("toml_write");

    var config = TomlConfig{
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

    var buffer = std.ArrayList(u8).initCapacity(std.testing.allocator, 256) catch unreachable;
    defer buffer.deinit(std.testing.allocator);

    try toml_write.writeTomlConfig(buffer.writer(std.testing.allocator), &config);

    const output = buffer.items;

    try std.testing.expect(std.mem.indexOf(u8, output, "[files]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[logging]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[plugins]") != null);
}

test "Write and read round-trip" {
    const toml_write = @import("toml_write");
    const toml_config_mod = @import("toml_config");

    var original = TomlConfig{
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

    var buffer = std.ArrayList(u8).initCapacity(std.testing.allocator, 256) catch unreachable;
    defer buffer.deinit(std.testing.allocator);

    try toml_write.writeTomlConfig(buffer.writer(std.testing.allocator), &original);

    var parsed = try toml_config_mod.parseTomlConfig(std.testing.allocator, buffer.items);
    defer toml_config_mod.deinit(&parsed, std.testing.allocator);

    try std.testing.expect(parsed.files.hal_files != null);
    try std.testing.expectEqual(@as(usize, 1), parsed.files.hal_files.?.len);
    try std.testing.expectEqualStrings("test.hal", parsed.files.hal_files.?[0]);
    try std.testing.expectEqualStrings("roundtrip.log", parsed.logging.file.?);
    try std.testing.expectEqualStrings("test_plugin", parsed.plugins.enabled.?[0]);
}
