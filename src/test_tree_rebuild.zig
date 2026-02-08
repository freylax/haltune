// Test tree rebuild with refresh thread (no TUI)
const std = @import("std");
const glob = @import("glob");
const StateStore = @import("state/cache.zig").StateStore;
const RefreshThread = @import("state/refresh.zig").RefreshThread;
const TreeView = @import("tui/widgets/tree_view.zig").TreeView;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected!\n", .{});
        }
    }
    const allocator = gpa.allocator();

    std.debug.print("=== Tree Rebuild Test ===\n", .{});

    // Initialize StateStore
    var store = StateStore.init(allocator);
    defer store.deinit();

    // Initialize TreeView (empty initially)
    const tree_view = try allocator.create(TreeView);
    defer {
        tree_view.deinit();
        allocator.destroy(tree_view);
    }
    tree_view.* = try TreeView.init(allocator, &store);
    try tree_view.buildTree();

    std.debug.print("Initial tree: {d} components\n", .{tree_view.root.items.len});

    // Start refresh thread
    var refresh_thread = try allocator.create(RefreshThread);
    defer allocator.destroy(refresh_thread);
    refresh_thread.* = RefreshThread.init(allocator, &store);
    try refresh_thread.start();
    defer refresh_thread.stop();

    // Wait for refresh thread to discover pins
    std.debug.print("Waiting for refresh thread...\n", .{});
    std.Thread.sleep(500 * std.time.ns_per_ms);

    // Rebuild tree with new data
    try tree_view.buildTree();

    std.debug.print("After refresh: {d} components\n", .{tree_view.root.items.len});

    // Print tree structure
    for (tree_view.root.items, 0..) |node, i| {
        std.debug.print("  [{d}] Component: {s}\n", .{ i, node.full_name });
        if (node.children) |*children| {
            for (children.items) |child| {
                std.debug.print("      - {s} ({s})\n", .{ child.full_name, @tagName(child.item_type) });
            }
        }
    }

    std.debug.print("\n=== Test Complete ===\n", .{});
}
