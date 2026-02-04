// Simple test to verify tree building works
const std = @import("std");
const StateStore = @import("src/state/cache.zig").StateStore;
const TreeView = @import("src/tui/widgets/tree_view.zig").TreeView;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize StateStore
    var store = StateStore.init(allocator);
    defer store.deinit();

    // Add test pins
    try store.addPin("test.pin-1", .{ .bit = true });
    try store.addPin("test.pin-2", .{ .bit = false });
    try store.addPin("motion.analog-in-00", .{ .float = 3.14159 });
    try store.addPin("motion.digital-in-00", .{ .s32 = 42 });

    std.debug.print("Added 4 test pins\n", .{});

    // Build tree
    var tree_view = try TreeView.init(allocator, &store);
    defer tree_view.deinit();

    std.debug.print("TreeView created successfully\n", .{});
    std.debug.print("Tree has {d} root components\n", .{tree_view.root.items.len});

    // List components
    for (tree_view.root.items) |node| {
        std.debug.print("  Component: {s}\n", .{node.name});
        if (node.children) |*children| {
            std.debug.print("    Children: {d}\n", .{children.items.len});
            for (children.items) |child| {
                std.debug.print("      - {s}\n", .{child.name});
            }
        }
    }

    std.debug.print("\nTest completed successfully!\n", .{});
}
