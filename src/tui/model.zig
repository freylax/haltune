const std = @import("std");
const vxfw = @import("vaxis").vxfw;
const vaxis = @import("vaxis");
const StateStore = @import("../state/cache.zig").StateStore;
const HalValue = @import("../state/cache.zig").HalValue;
const SubscriptionManager = @import("../state/pubsub.zig").SubscriptionManager;
const RefreshThread = @import("../state/refresh.zig").RefreshThread;
const TreeView = @import("widgets/tree_view.zig").TreeView;
const TreeNode = @import("widgets/tree_view.zig").Node;
const VisibilityState = @import("widgets/tree_view.zig").VisibilityState;
const DataTable = @import("widgets/data_table.zig").DataTable;
const ItemType = @import("widgets/data_table.zig").ItemType;
const SignalDialog = @import("widgets/signal_dialog.zig").SignalDialog;

/// View mode enumeration for single-panel layout switching
pub const ViewMode = enum {
    /// Tree view only: full width
    tree_only,
    /// Table view only: full width
    table_only,

    /// Cycle to next view mode: tree_only -> table_only -> tree_only
    pub fn next(self: ViewMode) ViewMode {
        return switch (self) {
            .tree_only => .table_only,
            .table_only => .tree_only,
        };
    }
};

const drawTwoPanelLayout = @import("layout.zig").drawTwoPanelLayout;
const exportHal = @import("../hal/export.zig");
const ffi = @import("../ffi/safe.zig");
const HalError = @import("../ffi/errors.zig").HalError;

/// Global redraw flag pointer for pubsub callbacks
/// This is set by the Model during initialization and used by callbacks
var GLOBAL_REDRAW_FLAG: ?*std.atomic.Value(bool) = null;

/// Callback function for value change notifications
/// This function is called by SubscriptionManager when any subscribed item changes
fn valueChangedCallback(
    name: []const u8,
    old_value: ?HalValue,
    new_value: HalValue,
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
    signal_dialog: SignalDialog,
    refresh_thread: ?*RefreshThread,
    hal_comp_id: c_int,

    /// Redraw flag for pubsub callbacks
    /// Set to true when any subscribed value changes, triggering a redraw
    redraw_flag: std.atomic.Value(bool),

    /// Error message to display (null = no error)
    error_message: ?[]const u8,

    /// Error message owner (allocated memory)
    error_message_owner: ?[]const u8,

    /// Error timeout timestamp (0 = no timeout set)
    error_timeout: u64,

    /// Save dialog state
    save_dialog_visible: bool = false,
    save_filename: std.ArrayList(u8),

    /// Current view mode for single-panel layout
    current_view: ViewMode = .tree_only,

    /// Initialize a new Model instance
    pub fn init(
        allocator: std.mem.Allocator,
        store: *StateStore,
        pubsub: *SubscriptionManager,
    ) !Model {
        // Check if HAL is available before attempting to initialize
        // This prevents EINTR crashes when LinuxCNC is not running
        try @import("../ffi/errors.zig").checkHalAvailable();

        // Initialize HAL component
        const comp_id = try ffi.halInit("haltune");
        errdefer ffi.halExit(comp_id);

        // Mark HAL component as ready
        try ffi.halReady(comp_id);

        // Create TreeView widget
        const tree_view = try allocator.create(TreeView);
        errdefer allocator.destroy(tree_view);
        tree_view.* = try TreeView.init(allocator, store);

        // Build initial tree (will be populated by refresh thread)
        try tree_view.buildTree();
        std.log.info("Tree initialized with {d} components (will populate from HAL)", .{tree_view.root.items.len});

        // Create DataTable widget
        const data_table = try allocator.create(DataTable);
        errdefer allocator.destroy(data_table);
        data_table.* = DataTable.init(allocator, store);

        // Create SignalDialog widget
        const signal_dialog = SignalDialog.init(allocator, store);

        // Initialize redraw flag
        const redraw_flag = std.atomic.Value(bool).init(false);

        return .{
            .allocator = allocator,
            .store = store,
            .pubsub = pubsub,
            .tree_view = tree_view,
            .data_table = data_table,
            .signal_dialog = signal_dialog,
            .refresh_thread = null,
            .hal_comp_id = comp_id,
            .redraw_flag = redraw_flag,
            .error_message = null,
            .error_message_owner = null,
            .error_timeout = 0,
            .save_filename = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable,
        };
    }

    /// Clean up Model resources
    pub fn deinit(self: *Model) void {
        // Stop RefreshThread FIRST
        // This must be done before cleaning up other resources
        if (self.refresh_thread) |refresh| {
            std.log.info("Stopping RefreshThread...", .{});
            refresh.stop();
            std.log.info("RefreshThread stopped", .{});
            self.allocator.destroy(refresh);
        }

        // Clean up TreeView
        self.tree_view.deinit();
        self.allocator.destroy(self.tree_view);

        // Clean up DataTable
        self.data_table.deinit();
        self.allocator.destroy(self.data_table);

        // Clean up SignalDialog
        self.signal_dialog.deinit();

        // Free error message if allocated
        if (self.error_message_owner) |msg| {
            self.allocator.free(msg);
        }

        // Free save filename buffer
        self.save_filename.deinit(self.allocator);

        // Exit HAL component
        std.log.info("Exiting HAL component {d}...", .{self.hal_comp_id});
        ffi.halExit(self.hal_comp_id);
        std.log.info("HAL component exited", .{});
    }

    /// Get list of checked item names
    /// Returns only fully-visible leaf items (pins, signals, params)
    /// Components with .partial or .full state are expanded to their visible children
    pub fn getCheckedItems(self: *const Model, allocator: std.mem.Allocator) ![][]const u8 {
        var items = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable;

        std.log.debug("getCheckedItems: checked_items count = {}", .{self.tree_view.checked_items.count()});

        // Track which leaf nodes have been added (to avoid duplicates when both parent component and child are marked as full)
        var added_leaves = std.StringHashMap(void).init(allocator);
        defer added_leaves.deinit();

        var iter = self.tree_view.checked_items.iterator();
        while (iter.next()) |entry| {
            const state = entry.value_ptr.*;
            const full_name = entry.key_ptr.*;

            std.log.debug("  checking: '{s}' state={}", .{ full_name, state });

            // Skip partial states (component with some children visible)
            if (state == VisibilityState.partial) continue;

            // For full state, check if it's a leaf or component
            if (state == VisibilityState.full) {
                // Find the node to check its type
                const node = self.findNodeByName(full_name);
                if (node) |n| {
                    std.log.debug("    node found: '{s}' expandable={}", .{ n.full_name, n.isExpandable() });
                    if (n.isExpandable()) {
                        // Component - add its visible children instead
                        if (n.children) |*children| {
                            for (children.items) |child| {
                                const child_state = self.tree_view.checked_items.get(child.full_name) orelse VisibilityState.none;
                                if (child_state == VisibilityState.full) {
                                    std.log.debug("      adding child: '{s}'", .{child.full_name});
                                    try items.append(self.allocator, child.full_name);
                                    try added_leaves.put(child.full_name, {});
                                }
                            }
                        }
                    } else {
                        // Leaf node - add directly, but only if not already added via parent component
                        if (added_leaves.get(full_name) == null) {
                            std.log.debug("      adding leaf: '{s}'", .{full_name});
                            try items.append(self.allocator, full_name);
                            try added_leaves.put(full_name, {});
                        } else {
                            std.log.debug("      skipping leaf (already added via parent): '{s}'", .{full_name});
                        }
                    }
                } else {
                    // Node not found - add as fallback (if not already added)
                    if (added_leaves.get(full_name) == null) {
                        std.log.debug("      node not found, adding fallback: '{s}'", .{full_name});
                        try items.append(self.allocator, full_name);
                        try added_leaves.put(full_name, {});
                    } else {
                        std.log.debug("      skipping fallback (already added): '{s}'", .{full_name});
                    }
                }
            }
        }

        std.log.debug("getCheckedItems: returning {} items", .{items.items.len});
        for (items.items, 0..) |item, i| {
            std.log.debug("  [{}] '{s}'", .{ i, item });
        }

        return items.toOwnedSlice(self.allocator);
    }

    /// Find a node by full_name (helper for getCheckedItems)
    fn findNodeByName(self: *const Model, full_name: []const u8) ?*const TreeNode {
        for (self.tree_view.root.items) |node| {
            if (std.mem.eql(u8, node.full_name, full_name)) return node;
            if (node.children) |*children| {
                for (children.items) |child| {
                    if (std.mem.eql(u8, child.full_name, full_name)) return child;
                }
            }
        }
        return null;
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

    /// Get full precision value string for a HAL item
    ///
    /// Returns a formatted string showing the item's name, type, and full
    /// precision value. Unlike the compact format used in tree view (6 chars),
    /// this uses full precision for floats and word-format for bits.
    ///
    /// Example output:
    ///   - "motion.digital-in-00: BIT TRUE"
    ///   - "motion.analog-in-00: FLOAT 3.14159265358979"
    pub fn getFullValueString(self: *const Model, allocator: std.mem.Allocator, item_name: []const u8, item_type: ItemType) ![]const u8 {
        const value = switch (item_type) {
            .pin => self.store.getPin(item_name) catch null,
            .signal => self.store.getSignal(item_name) catch null,
            .param => self.store.getParam(item_name) catch null,
        };

        if (value) |v| {
            const type_str = switch (v) {
                .bit => "BIT",
                .float => "FLOAT",
                .s32 => "S32",
                .u32 => "U32",
            };

            const value_str = switch (v) {
                .bit => |b| if (b) "TRUE" else "FALSE",
                .float => |f| try std.fmt.allocPrint(allocator, "{d}", .{f}),
                .s32 => |s| try std.fmt.allocPrint(allocator, "{d}", .{s}),
                .u32 => |u| try std.fmt.allocPrint(allocator, "{d}", .{u}),
            };

            return std.fmt.allocPrint(allocator, "{s}: {s} {s}", .{ item_name, type_str, value_str });
        } else {
            return std.fmt.allocPrint(allocator, "{s}: (no value)", .{item_name});
        }
    }

    /// Open signal creation dialog
    pub fn openSignalDialog(self: *Model) !void {
        try self.signal_dialog.open();
    }

    /// Close signal creation dialog
    pub fn closeSignalDialog(self: *Model) void {
        self.signal_dialog.close();
    }

    /// Open save configuration dialog
    pub fn openSaveDialog(self: *Model) !void {
        self.save_dialog_visible = true;
        self.save_filename.clearRetainingCapacity();
        // Default filename
        try self.save_filename.appendSlice(self.allocator, "haltune-config.hal");
    }

    /// Close save configuration dialog
    pub fn closeSaveDialog(self: *Model) void {
        self.save_dialog_visible = false;
        self.save_filename.clearRetainingCapacity();
    }

    /// Save HAL configuration to file
    pub fn saveConfiguration(self: *Model, filename: []const u8) !void {
        const file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();

        // Use buffered writer with fixed-size buffer
        var buffer: [4096]u8 = undefined;
        var buf_stream = std.io.fixedBufferStream(&buffer);
        const writer = buf_stream.writer();
        try exportHal.exportHalConfiguration(self.allocator, self.store, writer);
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
            // Initialize: subscribe to checked items
            .init => {
                // Set global redraw flag pointer for callbacks
                GLOBAL_REDRAW_FLAG = &self.redraw_flag;

                // Test pins already added in Model.init(), just log here
                std.log.info(".init event: tree has {d} components", .{self.tree_view.root.items.len});

                // Trigger redraw to show the tree
                ctx.consumeAndRedraw();
            },

            // Handle key presses
            .key_press => |key| {
                // Check error timeout before handling key press
                if (self.checkErrorTimeout()) {
                    ctx.consumeAndRedraw();
                }

                // Forward navigation keys to TreeView if no modal dialogs are visible
                if (!self.signal_dialog.visible and !self.save_dialog_visible) {
                    // TreeView handles: arrow keys, Enter (expand/collapse), Space (checkbox), '/' (search), Backspace (collapse)
                    const tree_widget = self.tree_view.widget();
                    if (key.matches(vaxis.Key.up, .{}) or
                        key.matches(vaxis.Key.down, .{}) or
                        key.matches(vaxis.Key.enter, .{}) or
                        key.matches(' ', .{}) or
                        key.matches('/', .{}) or
                        key.matches(vaxis.Key.backspace, .{}))
                    {
                        // Forward to TreeView's event handler
                        if (tree_widget.eventHandler) |handler| {
                            const tree_event: vxfw.Event = .{ .key_press = key };
                            handler(tree_widget.userdata, ctx, tree_event) catch |err| {
                                std.log.err("TreeView event handler error: {}", .{err});
                            };
                        }
                        return;
                    }
                }

                // Ctrl+C to quit
                if (key.matches('c', .{ .ctrl = true })) {
                    ctx.quit = true;
                    return;
                }

                // 'n' to open signal creation dialog
                if (key.matches('n', .{}) and !self.signal_dialog.visible and !self.save_dialog_visible) {
                    self.openSignalDialog() catch |err| {
                        std.log.err("Failed to open signal dialog: {}", .{err});
                    };
                    ctx.consumeAndRedraw();
                    return;
                }

                // 's' to open save configuration dialog
                if (key.matches('s', .{}) and !self.save_dialog_visible and !self.signal_dialog.visible) {
                    self.openSaveDialog() catch |err| {
                        self.setError("Failed to open save dialog") catch {};
                        std.log.err("Failed to open save dialog: {}", .{err});
                    };
                    ctx.consumeAndRedraw();
                    return;
                }

                // Ctrl+T to cycle view mode
                if (key.matches('t', .{ .ctrl = true })) {
                    // Block view switching when dialogs are open
                    if (self.signal_dialog.visible or self.save_dialog_visible) {
                        return;
                    }
                    self.current_view = self.current_view.next();

                    // Update table with checked items when switching to table view
                    if (self.current_view == .table_only) {
                        self.updateTable() catch |err| {
                            std.log.err("Failed to update table: {}", .{err});
                        };
                    }

                    ctx.consumeAndRedraw();
                    return;
                }

                // Handle save dialog input
                if (self.save_dialog_visible) {
                    const handled = self.handleSaveDialogKey(key) catch |err| {
                        self.setError("Save dialog error") catch {};
                        std.log.err("Save dialog error: {}", .{err});
                        return;
                    };
                    if (handled) {
                        ctx.consumeAndRedraw();
                        return;
                    }
                }

                // Pass key to signal dialog if visible
                if (self.signal_dialog.visible) {
                    const handled = self.signal_dialog.handleKey(key) catch |err| {
                        std.log.err("Signal dialog key error: {}", .{err});
                        return;
                    };
                    if (handled) {
                        ctx.consumeAndRedraw();
                        return;
                    }
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
                std.log.err("Failed to subscribe to '{s}': {}", .{ item_name, err });
            };
        }
    }

    /// Handle key press in save dialog
    fn handleSaveDialogKey(self: *Model, key: vaxis.Key) !bool {
        // Alphanumeric input for filename
        if (key.codepoint >= 32 and key.codepoint < 127) {
            const c = @as(u8, @intCast(key.codepoint));
            if (std.ascii.isPrint(c) and c != '/') {
                try self.save_filename.append(self.allocator, c);
            }
            return true;
        }

        // Backspace
        if (key.matches(vaxis.Key.backspace, .{})) {
            if (self.save_filename.items.len > 0) {
                _ = self.save_filename.pop();
            }
            return true;
        }

        // Enter to save
        if (key.matches(vaxis.Key.enter, .{})) {
            if (self.save_filename.items.len == 0) {
                try self.setError("Filename cannot be empty");
                return true;
            }

            // Null-terminate for file API
            const filename_terminated = try self.allocator.dupeZ(u8, self.save_filename.items);
            defer self.allocator.free(filename_terminated);

            // Save configuration
            self.saveConfiguration(filename_terminated) catch |err| {
                try self.setError("Save failed");
                std.log.err("Failed to save configuration: {}", .{err});
                return true;
            };

            // Success
            try self.setError("Configuration saved successfully");
            self.closeSaveDialog();
            return true;
        }

        // Escape to cancel
        if (key.matches(vaxis.Key.escape, .{})) {
            self.closeSaveDialog();
            return true;
        }

        return true;
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
