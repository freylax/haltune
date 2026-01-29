const std = @import("std");
const vxfw = @import("vaxis").vxfw;
const StateStore = @import("../state/cache.zig").StateStore;
const SubscriptionManager = @import("../state/pubsub.zig").SubscriptionManager;
const TreeView = @import("widgets/tree_view.zig").TreeView;
const drawTwoPanelLayout = @import("layout.zig").drawTwoPanelLayout;

/// Model holds all application state for the TUI
pub const Model = struct {
    allocator: std.mem.Allocator,
    store: *StateStore,
    pubsub: *SubscriptionManager,
    tree_view: *TreeView,

    /// Initialize a new Model instance
    pub fn init(
        allocator: std.mem.Allocator,
        store: *StateStore,
        pubsub: *SubscriptionManager,
    ) !Model {
        // Create TreeView widget
        const tree_view = try allocator.create(TreeView);
        tree_view.* = try TreeView.init(allocator, store);

        return .{
            .allocator = allocator,
            .store = store,
            .pubsub = pubsub,
            .tree_view = tree_view,
        };
    }

    /// Clean up Model resources
    pub fn deinit(self: *Model) void {
        self.tree_view.deinit();
        self.allocator.destroy(self.tree_view);
    }

    /// Get list of checked item names
    /// Returns a snapshot of all items selected in the tree view
    pub fn getCheckedItems(self: *const Model, allocator: std.mem.Allocator) ![][]const u8 {
        var items = std.ArrayList([]const u8).init(allocator);

        var iter = self.tree_view.checked_items.iterator();
        while (iter.next()) |entry| {
            try items.append(entry.key_ptr.*);
        }

        return items.toOwnedSlice();
    }

    /// Return a vxfw.Widget for this Model
    pub fn widget(self: *Model) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = typeErasedEventHandler,
            .drawFn = typeErasedDrawFn,
        };
    }

    /// Event handler for key presses, mouse, focus changes
    fn typeErasedEventHandler(
        ptr: *anyopaque,
        ctx: *vxfw.EventContext,
        event: vxfw.Event,
    ) anyerror!void {
        const self: *Model = @ptrCast(@alignCast(ptr));

        switch (event) {
            // Initialize: request focus for our widget
            .init => {
                // No specific widget to focus yet - will add in future tasks
            },

            // Handle key presses
            .key_press => |key| {
                // Ctrl+C to quit
                if (key.matches('c', .{ .ctrl = true })) {
                    ctx.quit = true;
                    return;
                }
            },

            else => {},
        }
    }

    /// Draw function - renders the two-panel layout
    fn typeErasedDrawFn(
        ptr: *anyopaque,
        ctx: vxfw.DrawContext,
    ) std.mem.Allocator.Error!vxfw.Surface {
        // Delegate to layout module for two-panel split
        return drawTwoPanelLayout(ptr, ctx);
    }
};
