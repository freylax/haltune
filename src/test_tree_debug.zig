const std = @import("std");
const StateStore = @import("state/cache.zig").StateStore;
const RefreshThread = @import("state/refresh.zig").RefreshThread;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = StateStore.init(allocator);
    defer store.deinit();

    std.debug.print("Testing refresh thread...\n", .{});
    var refresh = try allocator.create(RefreshThread);
    defer allocator.destroy(refresh);
    refresh.* = RefreshThread.init(allocator, &store);
    try refresh.start();

    std.debug.print("Waiting 2 seconds for refresh...\n", .{});
    std.Thread.sleep(2 * std.time.ns_per_s);

    std.debug.print("Stopping refresh...\n", .{});
    refresh.stop();

    std.debug.print("Pins: {d}, Signals: {d}, Params: {d}\n", .{
        store.pins.count(),
        store.signals.count(),
        store.params.count(),
    });

    const pin_names = try store.listPins(allocator);
    defer {
        for (pin_names) |p| allocator.free(p);
        allocator.free(pin_names);
    };

    std.debug.print("\nPins:\n", .{});
    for (pin_names) |pin| {
        std.debug.print("  {s}\n", .{pin});
    }
}
