const std = @import("std");
const cache = @import("state/cache.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = cache.StateStore.init(allocator);
    defer store.deinit();

    // Add a test pin
    try store.addPin("test-component.pin-0", .{ .bit = false });

    // List pins and verify the string is valid
    const pins = try store.listPins(allocator);
    defer {
        for (pins) |p| allocator.free(p);
        allocator.free(pins);
    }

    std.debug.print("Found {d} pins:\n", .{pins.len});
    for (pins) |pin| {
        std.debug.print("  pin: {s}\n", .{pin});
        // Verify we can read the string safely
        const dot_idx = std.mem.indexOfScalar(u8, pin, '.') orelse 0;
        std.debug.print("    dot index: {d}\n", .{dot_idx});
    }

    std.debug.print("TEST PASSED!\n", .{});
}
