// Simple test for remote HAL client
const std = @import("std");

const RemoteBackend = @import("src/remote_hal/client.zig").RemoteBackend;

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    std.log.info("Connecting to remote HAL at 192.168.2.118:8765", .{});

    const backend = try RemoteBackend.create(allocator, "192.168.2.118", 8765);
    defer backend.deinit();

    // Initialize component
    const comp_id = try backend.initComponent("test_client");
    std.log.info("Initialized component: comp_id={d}", .{comp_id});

    // List pins
    std.log.info("Listing pins...", .{});
    const pins = try backend.listPins(allocator);
    defer {
        for (pins) |p| allocator.free(p.name);
        allocator.free(pins);
    }

    std.log.info("Got {} pins:", .{pins.len});
    for (pins, 0..) |pin, i| {
        if (i < 5) {
            std.log.info("  [{d}] {s}: {} dir={} value={}", .{ i, pin.name, pin.type, pin.dir, pin.value });
        }
    }
    if (pins.len > 5) {
        std.log.info("  ... and {} more pins", .{pins.len - 5});
    }

    // Ready component
    try backend.readyComponent(comp_id);
    std.log.info("Component ready", .{});

    // Exit component
    backend.exitComponent(comp_id);
    std.log.info("Done!", .{});
}
