// Test remote HAL client directly (no TUI)
const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    std.log.info("=== Remote HAL Client Test ===", .{});
    std.log.info("Connecting to 192.168.2.118:8765", .{});

    // Import RemoteBackend
    const RemoteBackend = @import("remote_hal/client").RemoteBackend;

    const backend = try RemoteBackend.create(allocator, "192.168.2.118", 8765);
    defer backend.deinit();

    const comp_id = try backend.initComponent("test_client");
    std.log.info("✓ Component initialized: comp_id={d}", .{comp_id});

    try backend.readyComponent(comp_id);
    std.log.info("✓ Component ready", .{});

    // Test listPins
    std.log.info("Testing listPins...", .{});
    const pins = try backend.listPins(allocator);
    defer {
        for (pins) |p| allocator.free(p.name);
        allocator.free(pins);
    }

    std.log.info("✓ Got {} pins", .{pins.len});

    // Show first 5 pins
    for (pins, 0..) |pin, i| {
        if (i >= 5) break;
        std.log.info("  [{d}] {s}: type={} dir={} value={}", .{ i, pin.name, pin.type, pin.dir, pin.value });
    }

    // Test listSignals
    std.log.info("Testing listSignals...", .{});
    const signals = try backend.listSignals(allocator);
    defer {
        for (signals) |s| {
            allocator.free(s.name);
            allocator.free(s.writers);
            allocator.free(s.readers);
        }
        allocator.free(signals);
    }
    std.log.info("✓ Got {} signals", .{signals.len});

    // Test listParams
    std.log.info("Testing listParams...", .{});
    const params = try backend.listParams(allocator);
    defer {
        for (params) |p| allocator.free(p.name);
        allocator.free(params);
    }
    std.log.info("✓ Got {} params", .{params.len});

    backend.exitComponent(comp_id);
    std.log.info("✓ Test completed successfully!", .{});
}
