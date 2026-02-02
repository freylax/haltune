const std = @import("std");
const vxfw = @import("vaxis").vxfw;
const vaxis = @import("vaxis");
const StateStore = @import("../state/cache.zig").StateStore;
const HalValue = @import("../state/cache.zig").HalValue;
const SubscriptionManager = @import("../state/pubsub.zig").SubscriptionManager;
const RefreshThread = @import("../state/refresh.zig").RefreshThread;
const TreeView = @import("widgets/tree_view.zig").TreeView;
const DataTable = @import("widgets/data_table.zig").DataTable;
const SignalDialog = @import("widgets/signal_dialog.zig").SignalDialog;
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
        ffi.halExit(self.hal_comp_id);
    }

    /// Get list of checked item names
    /// Returns a snapshot of all items selected in the tree view
    pub fn getCheckedItems(self: *const Model, allocator: std.mem.Allocator) ![][]const u8 {
        var items = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable;

        var iter = self.tree_view.checked_items.iterator();
        while (iter.next()) |entry| {
            try items.append(allocator, entry.key_ptr.*);
        }

        return items.toOwnedSlice(allocator);
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

                // Start RefreshThread if not already started
                if (self.refresh_thread == null) {
                    std.log.info("Starting RefreshThread...", .{});
                    var refresh = try self.allocator.create(RefreshThread);
                    refresh.* = RefreshThread.init(self.allocator, self.store);
                    try refresh.start();
                    self.refresh_thread = refresh;
                    std.log.info("RefreshThread started successfully", .{});
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
