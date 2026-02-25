const std = @import("std");
const vxfw = @import("vaxis").vxfw;
const vaxis = @import("vaxis");
const StateStore = @import("../state/cache.zig").StateStore;
const HalValue = @import("../state/cache.zig").HalValue;
const ItemOrigin = @import("../config/origin.zig").ItemOrigin;
const SubscriptionManager = @import("../state/pubsub.zig").SubscriptionManager;
const RefreshThread = @import("../state/refresh.zig").RefreshThread;
const TreeView = @import("widgets/tree_view.zig").TreeView;
const TreeNode = @import("widgets/tree_view.zig").Node;
const VisibilityState = @import("widgets/tree_view.zig").VisibilityState;
const DataTable = @import("widgets/data_table.zig").DataTable;
const ItemType = @import("widgets/data_table.zig").ItemType;
const SignalDialog = @import("widgets/signal_dialog.zig").SignalDialog;
const PluginDialog = @import("widgets/plugin_dialog.zig").PluginDialog;
const safe = @import("../ffi/safe.zig");

// Import C HAL functions directly for checkHalAvailable
const hal_c = @cImport({
    @cDefine("ULAPI", "");
    @cInclude("hal.h");
});

/// Configuration for haltune from root.zig
const Config = @import("../root.zig").Config;

/// Configuration file parsers for origin tracking
const hal_parser = @import("../config/hal_parser.zig");
const ini_parser = @import("../config/ini_parser.zig");

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

// Remote backend imports
const HalBackend = @import("../hal/backend.zig").HalBackend;
const RemoteBackend = @import("../hal/remote/client.zig").RemoteBackend;

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
    plugin_dialog: PluginDialog,
    refresh_thread: ?*RefreshThread,
    hal_comp_id: c_int,

    /// Remote HAL backend (null when using local HAL)
    remote_backend: ?*HalBackend,

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

    /// Application configuration (file paths, etc)
    config: Config,

    /// Initialize a new Model instance
    pub fn init(
        allocator: std.mem.Allocator,
        store: *StateStore,
        pubsub: *SubscriptionManager,
        config: Config,
    ) !Model {
        // Determine if we should use remote HAL
        const use_remote = config.remote.enabled and config.remote.host != null;

        // Initialize HAL component (native or remote)
        const comp_id: c_int = if (use_remote) blk: {
            // Remote HAL: create fake comp_id, actual connection handled by refresh thread
            std.log.info("Using remote HAL server at {s}:{}",
                .{ config.remote.host.?, config.remote.port });
            break :blk -1; // No real component for remote HAL
        } else blk: {
            // Native HAL: Check if HAL is available before attempting to initialize
            // This prevents EINTR crashes when LinuxCNC is not running
            try @import("../ffi/errors.zig").checkHalAvailable(hal_c.hal_init, hal_c.hal_exit);

            // Initialize HAL component
            // halInit will try "haltune", "haltune1", "haltune2", etc. if there are conflicts
            const id = try ffi.halInit("haltune");
            errdefer ffi.halExit(id);

            // Mark HAL component as ready
            try ffi.halReady(id);
            break :blk id;
        };

        // Create TreeView widget
        const tree_view = try allocator.create(TreeView);
        errdefer allocator.destroy(tree_view);
        tree_view.* = try TreeView.init(allocator, store);

        // Build initial tree (may be empty if StateStore not yet populated)
        try tree_view.buildTree();
        std.log.info("Tree initialized with {d} components", .{tree_view.root.items.len});

        // Create DataTable widget
        const data_table = try allocator.create(DataTable);
        errdefer allocator.destroy(data_table);
        data_table.* = DataTable.init(allocator, store);

        // Create SignalDialog widget
        const signal_dialog = SignalDialog.init(allocator, store);

        // Create PluginDialog widget
        const registry = @import("../plugin/registry.zig").getGlobalRegistry() orelse {
            return error.PluginRegistryNotAvailable;
        };
        const plugin_dialog = PluginDialog.init(allocator, registry);

        // Initialize redraw flag
        const redraw_flag = std.atomic.Value(bool).init(false);

        // Create remote backend if configured
        const remote_backend: ?*HalBackend = if (use_remote) blk: {
            const host = config.remote.host.?;
            const port = config.remote.port;
            std.log.info("Creating remote HAL backend for {s}:{}", .{ host, port });
            const backend = try allocator.create(HalBackend);
            backend.* = try RemoteBackend.create(allocator, host, port);
            break :blk backend;
        } else null;

        // Create temporary Model instance to parse config files
        var temp_model = Model{
            .allocator = allocator,
            .store = store,
            .pubsub = pubsub,
            .tree_view = tree_view,
            .data_table = data_table,
            .signal_dialog = signal_dialog,
            .plugin_dialog = plugin_dialog,
            .refresh_thread = null,
            .hal_comp_id = comp_id,
            .remote_backend = remote_backend,
            .redraw_flag = redraw_flag,
            .error_message = null,
            .error_message_owner = null,
            .error_timeout = 0,
            .save_filename = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable,
            .config = config,
        };

        // Parse configuration files for origin tracking
        if (config.hal_files.items.len > 0 or config.ini_files.items.len > 0) {
            temp_model.parseConfigFiles() catch |err| {
                std.log.err("Failed to parse configuration files: {}", .{err});
            };
        }

        return temp_model;
    }

    /// Parse configuration files and populate origin tracker
    fn parseConfigFiles(self: *Model) !void {
        const allocator = self.allocator;

        // Parse .hal files
        for (self.config.hal_files.items) |file_path| {
            std.log.info("Parsing .hal file: {s}", .{file_path});
            var parse_result = try hal_parser.parseHalFile(allocator, file_path, null);
            defer parse_result.deinit(allocator);

            // Process commands and populate origin tracker
            for (parse_result.commands.items) |cmd| {
                switch (cmd) {
                    .setp => |setp_cmd| {
                        try self.store.origin_tracker.setParamOrigin(
                            setp_cmd.name,
                            try ItemOrigin.fromHalFile(allocator, file_path, setp_cmd.line),
                        );
                    },
                    .net => |net_cmd| {
                        // Track signal origin from net command
                        try self.store.origin_tracker.setSignalOrigin(
                            net_cmd.signal_name,
                            try ItemOrigin.fromHalFile(allocator, file_path, net_cmd.line),
                        );
                    },
                    else => {}, // Other commands don't need origin tracking yet
                }
            }
        }

        // Parse .ini files
        for (self.config.ini_files.items) |file_path| {
            std.log.info("Parsing .ini file: {s}", .{file_path});
            var parse_result = try ini_parser.parseIniFile(allocator, file_path);
            defer parse_result.deinit();

            // Process entries and populate origin tracker
            for (parse_result.entries.items) |entry| {
                switch (entry) {
                    .key_value => |kv| {
                        // Check if this is a HAL parameter reference
                        if (std.mem.startsWith(u8, kv.key, "HAL_") or
                            std.mem.startsWith(u8, kv.key, "PARAM_")) {
                            // Map [SECTION]VARIABLE to param name
                            const param_name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ kv.section, kv.key });
                            try self.store.origin_tracker.setParamOrigin(
                                param_name,
                                try ItemOrigin.fromIniFile(allocator, file_path, kv.section, kv.key, kv.line),
                            );
                        }
                    },
                    else => {},
                }
            }
        }
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

        // Clean up remote backend if present
        if (self.remote_backend) |backend| {
            std.log.info("Cleaning up remote HAL backend", .{});
            backend.deinit();
            self.allocator.destroy(backend);
        }

        // Clean up TreeView
        self.tree_view.deinit();
        self.allocator.destroy(self.tree_view);

        // Clean up DataTable
        self.data_table.deinit();
        self.allocator.destroy(self.data_table);

        // Clean up SignalDialog
        self.signal_dialog.deinit();

        // Clean up PluginDialog
        self.plugin_dialog.deinit();

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
    /// Items are returned in tree order (the order they appear in the tree view)
    pub fn getCheckedItems(self: *const Model, allocator: std.mem.Allocator) ![][]const u8 {
        var items = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable;

        std.log.debug("getCheckedItems: collecting in tree order", .{});

        // Track which leaf nodes have been added (to avoid duplicates)
        var added_leaves = std.StringHashMap(void).init(allocator);
        defer added_leaves.deinit();

        // Iterate through tree in order (root components first, then their children)
        for (self.tree_view.root.items) |component| {
            const component_state = self.tree_view.checked_items.get(component.full_name) orelse VisibilityState.none;

            if (component_state == VisibilityState.full and component.isExpandable()) {
                // Component fully checked - add all its checked children
                if (component.children) |*children| {
                    for (children.items) |child| {
                        const child_state = self.tree_view.checked_items.get(child.full_name) orelse VisibilityState.none;
                        if (child_state == VisibilityState.full) {
                            try items.append(self.allocator, child.full_name);
                            try added_leaves.put(child.full_name, {});
                        }
                    }
                }
            } else if (component_state == VisibilityState.full and !component.isExpandable()) {
                // This shouldn't happen (components should be expandable), but handle it
                try items.append(self.allocator, component.full_name);
                try added_leaves.put(component.full_name, {});
            } else if (component_state == VisibilityState.partial) {
                // Partial - check individual children
                if (component.children) |*children| {
                    for (children.items) |child| {
                        const child_state = self.tree_view.checked_items.get(child.full_name) orelse VisibilityState.none;
                        if (child_state == VisibilityState.full and added_leaves.get(child.full_name) == null) {
                            try items.append(self.allocator, child.full_name);
                            try added_leaves.put(child.full_name, {});
                        }
                    }
                }
            }
            // If component is .none, skip it entirely
        }

        std.log.debug("getCheckedItems: returning {} items in tree order", .{items.items.len});
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
    /// Returns a formatted string showing the item's name, type, direction (for pins), and full
    /// precision value. Unlike the compact format used in tree view (6 chars),
    /// this uses full precision for floats and word-format for bits.
    ///
    /// Example output:
    ///   - "motion.digital-in-00: BIT IN FALSE"
    ///   - "motion.analog-in-00: FLOAT IN 3.14159265358979"
    ///   - "pid.enable: BIT OUT TRUE"
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

            // Get direction for pins and params
            const dir_str = if (item_type == .pin) dir: {
                const name_z = try allocator.dupeZ(u8, item_name);
                defer allocator.free(name_z);
                if (safe.getPinDir(name_z)) |dir| {
                    break :dir switch (dir) {
                        .in => " IN",
                        .out => " OUT",
                        .io => " IO",
                        .unspecified => "",
                    };
                } else |_| {
                    break :dir "";
                }
            } else if (item_type == .param) dir: {
                const name_z = try allocator.dupeZ(u8, item_name);
                defer allocator.free(name_z);
                if (safe.getParamDir(name_z)) |dir| {
                    break :dir switch (dir) {
                        .ro => " RO",
                        .rw => " RW",
                    };
                } else |_| {
                    break :dir "";
                }
            } else "";

            return std.fmt.allocPrint(allocator, "{s}: {s}{s} {s}", .{ item_name, type_str, dir_str, value_str });
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

    /// Open plugin dialog
    pub fn openPluginDialog(self: *Model) !void {
        std.log.err("openPluginDialog called", .{});
        // Set up plugin manager reference if not already set
        if (self.plugin_dialog.manager == null) {
            const manager = @import("../plugin/manager.zig").getGlobalPluginManager() orelse {
                try self.setError("Plugin manager not available");
                return;
            };
            self.plugin_dialog.setManager(manager);
        }
        self.plugin_dialog.open();
        std.log.err("openPluginDialog done: visible={}", .{self.plugin_dialog.visible});
    }

    /// Close plugin dialog
    pub fn closePluginDialog(self: *Model) void {
        self.plugin_dialog.close();
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

                // Forward ALL keys to TreeView when in edit mode, or specific navigation keys otherwise
                // Forward to DataTable when in table view
                if (!self.signal_dialog.visible and !self.save_dialog_visible) {
                    const tree_widget = self.tree_view.widget();
                    const table_widget = self.data_table.widget();
                    const in_edit_mode = self.tree_view.edit_mode;
                    const in_table_edit = self.data_table.edit_mode or self.data_table.table_edit_mode;

                    // Table view: forward ALL keys when in edit mode, or navigation/edit keys otherwise
                    if (self.current_view == .table_only) {
                        if (in_table_edit or
                            key.matches(vaxis.Key.up, .{}) or
                            key.matches(vaxis.Key.down, .{}) or
                            key.matches(vaxis.Key.enter, .{}) or
                            key.matches(vaxis.Key.page_up, .{}) or
                            key.matches(vaxis.Key.page_down, .{}) or
                            key.matches(' ', .{}) or
                            key.matches(vaxis.Key.escape, .{}) or
                            key.matches(vaxis.Key.backspace, .{}))
                        {
                            // Forward to DataTable's event handler
                            if (table_widget.eventHandler) |handler| {
                                const table_event: vxfw.Event = .{ .key_press = key };
                                handler(table_widget.userdata, ctx, table_event) catch |err| {
                                    std.log.err("DataTable event handler error: {}", .{err});
                                };
                            }
                            return;
                        }
                    }

                    // Tree view: forward keys to TreeView
                    if (in_edit_mode or
                        key.matches(vaxis.Key.up, .{}) or
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

                // Ctrl+Q to quit
                if (key.matches('q', .{ .ctrl = true })) {
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

                // Ctrl+O to open plugin dialog
                if (key.matches('o', .{ .ctrl = true })) {
                    std.log.err("Ctrl+O pressed: plugin_dialog.visible={}", .{self.plugin_dialog.visible});
                    if (!self.plugin_dialog.visible) {
                        self.openPluginDialog() catch |err| {
                            std.log.err("Failed to open plugin dialog: {}", .{err});
                        };
                        std.log.err("After open: plugin_dialog.visible={}", .{self.plugin_dialog.visible});
                    } else {
                        self.closePluginDialog();
                    }
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

                // Pass key to plugin dialog if visible
                if (self.plugin_dialog.visible) {
                    const handled = self.plugin_dialog.handleKey(key) catch |err| {
                        std.log.err("Plugin dialog key error: {}", .{err});
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

            else => {
                // For any other event, also check the redraw flag
                // This handles the case where the refresh thread populates StateStore
                if (self.redraw_flag.load(.acquire)) {
                    ctx.consumeAndRedraw();
                    self.redraw_flag.store(false, .release);
                }
            },
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
