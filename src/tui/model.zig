const std = @import("std");
const vxfw = @import("vaxis").vxfw;
const StateStore = @import("../state/cache.zig").StateStore;
const SubscriptionManager = @import("../state/pubsub.zig").SubscriptionManager;
const RefreshThread = @import("../state/refresh.zig").RefreshThread;
const TreeView = @import("widgets/tree_view.zig").TreeView;
const DataTable = @import("widgets/data_table.zig").DataTable;
const drawTwoPanelLayout = @import("layout.zig").drawTwoPanelLayout;

/// Global redraw flag pointer for pubsub callbacks
/// This is set by the Model during initialization and used by callbacks
var GLOBAL_REDRAW_FLAG: ?*std.atomic.Value(bool) = null;

/// Callback function for value change notifications
/// This function is called by SubscriptionManager when any subscribed item changes
fn valueChangedCallback(
    name: []const u8,
    old_value: ?StateStore.HalValue,
    new_value: StateStore.HalValue,
) void {
    _ = name;
    _ = old_value;
    _ = new_value;

    // Set redraw flag to trigger UI update
    if (GLOBAL_REDRAW_FLAG) |flag| {
        flag.store(true, .release);
    }
}

/// Model holds all application state for the TUI
pub const Model = struct {
    allocator: std.mem.Allocator,
    store: *StateStore,
    pubsub: *SubscriptionManager,
    tree_view: *TreeView,
    data_table: *DataTable,
    refresh_thread: ?RefreshThread,

    /// Redraw flag for pubsub callbacks
    /// Set to true when any subscribed value changes, triggering a redraw
    redraw_flag: std.atomic.Value(bool),

    /// Error message to display (null = no error)
    error_message: ?[]const u8,

    /// Error message owner (allocated memory)
    error_message_owner: ?[]const u8,

    /// Error timeout timestamp (0 = no timeout set)
    error_timeout: u64,

    /// Initialize a new Model instance
    pub fn init(
        allocator: std.mem.Allocator,
        store: *StateStore,
        pubsub: *SubscriptionManager,
    ) !Model {
        // Create TreeView widget
        const tree_view = try allocator.create(TreeView);
        tree_view.* = try TreeView.init(allocator, store);

        // Create DataTable widget
        const data_table = try allocator.create(DataTable);
        data_table.* = DataTable.init(allocator, store);

        // Initialize redraw flag
        const redraw_flag = std.atomic.Value(bool).init(false);

        return .{
            .allocator = allocator,
            .store = store,
            .pubsub = pubsub,
            .tree_view = tree_view,
            .data_table = data_table,
            .refresh_thread = null,
            .redraw_flag = redraw_flag,
            .error_message = null,
            .error_message_owner = null,
            .error_timeout = 0,
        };
    }

    /// Clean up Model resources
    pub fn deinit(self: *Model) void {
        self.tree_view.deinit();
        self.allocator.destroy(self.tree_view);
        self.data_table.deinit();
        self.allocator.destroy(self.data_table);

        // Free error message if allocated
        if (self.error_message_owner) |msg| {
            self.allocator.free(msg);
        }
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

    /// Update data table with currently checked items
    ///
    /// This function should be called when tree selection changes to update
    /// the data table with the new set of checked items.
    ///
    /// Thread safety:
    ///   - Not thread-safe (call from TUI thread only)
    pub fn updateTable(self: *Model) !void {
        const checked_items = try self.getCheckedItems(self.allocator);
        defer self.allocator.free(checked_items);

        try self.data_table.setItems(checked_items);
    }

    /// Set an error message to display
    /// Error message will auto-clear after 5 seconds
    pub fn setError(self: *Model, msg: []const u8) !void {
        // Free old error message if exists
        if (self.error_message_owner) |old_msg| {
            self.allocator.free(old_msg);
        }

        // Allocate and store new error message
        const msg_copy = try self.allocator.dupe(u8, msg);
        self.error_message_owner = msg_copy;
        self.error_message = msg_copy;

        // Set timeout (5 seconds from now)
        const now = std.time.milliTimestamp();
        self.error_timeout = @intCast(now + 5000);
    }

    /// Clear the current error message
    pub fn clearError(self: *Model) void {
        if (self.error_message_owner) |msg| {
            self.allocator.free(msg);
        }
        self.error_message_owner = null;
        self.error_message = null;
        self.error_timeout = 0;
    }

    /// Check if error timeout has expired and clear if so
    pub fn checkErrorTimeout(self: *Model) bool {
        if (self.error_timeout == 0) return false;

        const now = std.time.milliTimestamp();
        if (now >= self.error_timeout) {
            self.clearError();
            return true;
        }
        return false;
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
            // Initialize: start RefreshThread and subscribe to checked items
            .init => {
                // Set global redraw flag pointer for callbacks
                GLOBAL_REDRAW_FLAG = &self.redraw_flag;

                // Start RefreshThread if not already started
                if (self.refresh_thread == null) {
                    var refresh = try self.allocator.create(RefreshThread);
                    refresh.* = RefreshThread.init(self.allocator, self.store);
                    try refresh.start();
                    self.refresh_thread = refresh;
                }

                // Subscribe to all currently checked items
                // (empty initially, will be updated when tree selection changes)
                self.updateSubscriptions() catch |err| {
                    std.log.err("Failed to update subscriptions: {}", .{err});
                };
            },

            // Handle key presses
            .key_press => |key| {
                // Check error timeout before handling key press
                if (self.checkErrorTimeout()) {
                    ctx.consumeAndRedraw();
                }

                // Ctrl+C to quit
                if (key.matches('c', .{ .ctrl = true })) {
                    ctx.quit = true;
                    return;
                }

                // Check if redraw flag is set (value changed via pubsub)
                if (self.redraw_flag.load(.acquire)) {
                    ctx.consumeAndRedraw();
                    self.redraw_flag.store(false, .release);
                }
            },

            else => {},
        }
    }

    /// Update subscriptions to match currently checked tree items
    ///
    /// This function subscribes to all currently checked items.
    /// Call this when tree selection changes.
    ///
    /// Thread safety:
    ///   - Not thread-safe (call from TUI thread only)
    pub fn updateSubscriptions(self: *Model) !void {
        // Get currently checked items
        const checked_items = try self.getCheckedItems(self.allocator);
        defer self.allocator.free(checked_items);

        // Subscribe to all checked items
        for (checked_items) |item_name| {
            // Subscribe to item changes with global callback
            self.pubsub.subscribe(item_name, valueChangedCallback) catch |err| {
                std.log.err("Failed to subscribe to '{s}': {}", .{item_name, err});
            };
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
