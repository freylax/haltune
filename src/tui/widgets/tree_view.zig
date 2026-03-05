//! Tree navigation widget for browsing HAL component hierarchy
//!
//! This module provides TreeView, a widget that displays HAL components
//! in a hierarchical tree structure. Components appear as parent nodes
//! with their pins, signals, and parameters as children.
//!
//! Features:
//! - Collapsible component nodes (Enter key to expand/collapse)
//! - Checkbox selection for items (Space to toggle)
//! - Arrow key navigation
//! - Persistent state tracking (expanded nodes, checked items)

const std = @import("std");
const vxfw = @import("vaxis").vxfw;
const vaxis = @import("vaxis");
const cache = @import("../../state/cache.zig");
const StateStore = cache.StateStore;
const HalValue = cache.HalValue;
const NameKey = cache.NameKey;
const glob = @import("glob");
const HalBackend = @import("backend").HalBackend;
const PinType = @import("backend").PinType;
const BackendHalValue = @import("backend").HalValue;
const hal_value = @import("hal_value.zig");
const safe = @import("../../ffi/safe.zig"); // For read-only helpers (getPinDir, getParamDir)

/// Node type enumeration
pub const NodeType = enum {
    /// Parent node representing a HAL component
    component,
    /// Leaf node representing a HAL pin
    pin,
    /// Leaf node representing a HAL signal
    signal,
    /// Leaf node representing a HAL parameter
    param,
};

/// Visibility state for tree nodes
pub const VisibilityState = enum {
    /// Not visible (no asterisk)
    none,
    /// Partially visible - some children are visible (shows '+')
    partial,
    /// Fully visible - all children visible, or leaf is visible (shows '*')
    full,
};

/// Tree node representing a component or HAL item
pub const Node = struct {
    /// Node label (display name)
    name: []const u8,

    /// Node type
    item_type: NodeType,

    /// Full HAL item name for cache lookup (e.g., "motion.digital-in-00")
    full_name: []const u8,

    /// Child nodes (null if leaf node)
    children: ?std.ArrayList(*Node),

    /// Parent node (null for root components)
    parent: ?*Node,

    /// Create a new node
    pub fn init(
        allocator: std.mem.Allocator,
        name: []const u8,
        item_type: NodeType,
        full_name: []const u8,
        parent: ?*Node,
    ) !*Node {
        const node = try allocator.create(Node);
        node.* = .{
            .name = name,
            .item_type = item_type,
            .full_name = full_name,
            .children = if (item_type == .component) std.ArrayList(*Node).initCapacity(allocator, 0) catch return error.OutOfMemory else null,
            .parent = parent,
        };
        return node;
    }

    /// Check if this node is expandable (component nodes only)
    pub fn isExpandable(self: *const Node) bool {
        return self.item_type == .component;
    }

    /// Get depth of this node in the tree (0 for root components)
    pub fn getDepth(self: *const Node) usize {
        var depth: usize = 0;
        var current = self.parent;
        while (current != null) : (current = current.?.parent) {
            depth += 1;
        }
        return depth;
    }
};

/// Get pin/param direction as string (IN/OUT/IO/RO/RW/empty)
fn getDirectionString(self: *TreeView, node: *const Node) []const u8 {
    // Try to get direction from HAL
    const name_z = self.allocator.dupeZ(u8, node.full_name) catch return "";
    defer self.allocator.free(name_z);

    if (node.item_type == .pin) {
        if (safe.getPinDir(name_z)) |dir| {
            return switch (dir) {
                .in => " IN",
                .out => " OUT",
                .io => " IO",
                .unspecified => "",
            };
        } else |_| return "";
    } else if (node.item_type == .param) {
        if (safe.getParamDir(name_z)) |dir| {
            return switch (dir) {
                .ro => " RO",
                .rw => " RW",
            };
        } else |_| return "";
    }
    return "";
}

/// Tree navigation widget
pub const TreeView = struct {
    /// Memory allocator
    allocator: std.mem.Allocator,

    /// State store for reading HAL data
    store: *StateStore,

    /// HAL backend for writing values
    backend: *const HalBackend,

    /// Root level component nodes
    root: std.ArrayList(*Node),

    /// Set of expanded node names (for component nodes)
    expanded_nodes: std.StringHashMap(void),

    /// Visibility state for each node (none, partial, or full)
    checked_items: std.StringHashMap(VisibilityState),

    /// Current cursor position (index into visible nodes)
    cursor_index: usize,

    /// Scroll offset (index of first visible node)
    scroll_offset: usize = 0,

    /// Visible height (number of nodes that fit on screen)
    visible_height: usize = 20,

    /// List of visible nodes (built during draw, respecting expand/collapse)
    visible_nodes: std.ArrayList(*Node),

    /// Current search pattern (glob pattern for filtering)
    /// Owned slice allocated by allocator
    search_pattern: []const u8,

    /// Whether search input mode is active
    search_input: bool,

    /// Buffer for building search patterns
    search_buffer: std.ArrayList(u8),

    /// Edit mode state
    edit_mode: bool = false,
    edit_item: ?*Node = null,
    edit_buffer: std.ArrayList(u8),
    edit_cursor_pos: usize = 0, // Cursor position within edit_buffer

    /// Signal editing state (for Ctrl+S connect/create/disconnect)
    signal_edit_mode: bool = false,
    signal_edit_pin: ?*Node = null,
    signal_edit_buffer: std.ArrayList(u8),

    /// Signal deletion prompt state
    signal_delete_prompt: bool = false,
    pending_signal_delete: ?[]const u8 = null, // Owned memory, must free

    /// Helper: Convert cache.HalValue to backend.HalValue
    /// Both types have identical structure, so we convert field-by-field
    fn toBackendHalValue(v: HalValue) BackendHalValue {
        return switch (v) {
            .bit => |b| BackendHalValue{ .bit = b },
            .float => |f| BackendHalValue{ .float = f },
            .s32 => |s| BackendHalValue{ .s32 = s },
            .u32 => |u| BackendHalValue{ .u32 = u },
        };
    }

    /// Initialize a new TreeView
    pub fn init(allocator: std.mem.Allocator, store: *StateStore, backend: *const HalBackend) !TreeView {
        // Initialize ArrayLists using initCapacity
        // Note: initCapacity(allocator, 0) never fails in practice
        const root_list = std.ArrayList(*Node).initCapacity(allocator, 0) catch return error.OutOfMemory;
        const visible_nodes_list = std.ArrayList(*Node).initCapacity(allocator, 0) catch return error.OutOfMemory;
        const search_buffer_list = std.ArrayList(u8).initCapacity(allocator, 0) catch return error.OutOfMemory;
        const edit_buffer_list = std.ArrayList(u8).initCapacity(allocator, 0) catch return error.OutOfMemory;
        const signal_edit_buffer_list = std.ArrayList(u8).initCapacity(allocator, 0) catch return error.OutOfMemory;

        const tree_view = TreeView{
            .allocator = allocator,
            .store = store,
            .backend = backend,
            .root = root_list,
            .expanded_nodes = std.StringHashMap(void).init(allocator),
            .checked_items = std.StringHashMap(VisibilityState).init(allocator),
            .cursor_index = 0,
            .visible_nodes = visible_nodes_list,
            .search_pattern = "",
            .search_input = false,
            .search_buffer = search_buffer_list,
            .edit_buffer = edit_buffer_list,
            .signal_edit_buffer = signal_edit_buffer_list,
        };

        // Note: Don't call buildTree() here - let the caller call it after adding data
        // Model.init() calls buildTree() after adding test pins

        return tree_view;
    }

    /// Clean up TreeView resources
    pub fn deinit(self: *TreeView) void {
        // Free all nodes
        for (self.root.items) |node| {
            self.freeNode(node);
        }
        self.root.deinit(self.allocator);

        // Free HashMaps
        self.expanded_nodes.deinit();
        self.checked_items.deinit();
        self.visible_nodes.deinit(self.allocator);

        // Free search buffer
        self.search_buffer.deinit(self.allocator);

        // Free edit buffer
        self.edit_buffer.deinit(self.allocator);

        // Free signal edit buffer
        self.signal_edit_buffer.deinit(self.allocator);

        // Free pending signal deletion
        if (self.pending_signal_delete) |name| {
            self.allocator.free(name);
        }
    }

    /// Recursively free a node and its children
    fn freeNode(self: *TreeView, node: *Node) void {
        // Free the duplicated names
        self.allocator.free(node.name);
        // Only free full_name if it's a different allocation than name
        // (component nodes use the same pointer for both)
        if (node.full_name.ptr != node.name.ptr) {
            self.allocator.free(node.full_name);
        }

        if (node.children) |*children| {
            for (children.items) |child| {
                self.freeNode(child);
            }
            children.deinit(self.allocator);
        }
        self.allocator.destroy(node);
    }

    /// Build tree from HAL data in StateStore
    /// New structure: Components first (with pins/params as children),
    /// then a "Signals" pseudo-component containing all signals
    pub fn buildTree(self: *TreeView) !void {
        std.log.info("DEBUG: buildTree() called", .{});
        std.log.info("DEBUG: self.root.items.len = {d}", .{self.root.items.len});
        // Clean up existing tree before rebuilding
        for (self.root.items, 0..) |node, i| {
            std.log.info("DEBUG: Freeing node {d}: name={s}, type={}", .{i, node.name, node.item_type});
            self.freeNode(node);
        }
        self.root.clearRetainingCapacity();

        // Reset edit mode when tree rebuilds (node pointers become invalid)
        self.edit_mode = false;
        self.edit_item = null;
        self.edit_buffer.clearRetainingCapacity();

        // Reset signal edit mode when tree rebuilds
        self.signal_edit_mode = false;
        self.signal_edit_pin = null;
        self.signal_edit_buffer.clearRetainingCapacity();

        // Cancel deletion prompt if tree rebuilds
        if (self.signal_delete_prompt) {
            if (self.pending_signal_delete) |name| {
                self.allocator.free(name);
                self.pending_signal_delete = null;
            }
            self.signal_delete_prompt = false;
        }

        // Get all pins, signals, and params from StateStore
        std.log.info("DEBUG: About to call listPins", .{});
        const pins = try self.store.listPins(self.allocator);
        std.log.info("DEBUG: listPins returned {d} pins", .{pins.len});
        defer {
            for (pins) |p| self.allocator.free(p);
            self.allocator.free(pins);
        }

        std.log.info("DEBUG: About to call listSignals", .{});
        const signals = try self.store.listSignals(self.allocator);
        std.log.info("DEBUG: listSignals returned {d} signals", .{signals.len});
        defer {
            for (signals) |s| self.allocator.free(s);
            self.allocator.free(signals);
        }

        std.log.info("DEBUG: About to call listParams", .{});
        const params = try self.store.listParams(self.allocator);
        std.log.info("DEBUG: listParams returned {d} params", .{params.len});
        defer {
            for (params) |p| self.allocator.free(p);
            self.allocator.free(params);
        }

        // Track unique component names to avoid duplicates
        // Use ArrayList to avoid StringHashMap bug in Zig 0.15.2
        var component_list = try std.ArrayList([]const u8).initCapacity(self.allocator, 32);
        defer {
            for (component_list.items) |n| self.allocator.free(n);
            component_list.deinit(self.allocator);
        }

        // First pass: collect all unique component names from pins
        std.log.info("DEBUG: First pass: starting pins loop", .{});
        for (pins) |pin_name| {
            const component_name = try extractComponentName(self.allocator, pin_name);

            // Check if already in list
            var exists = false;
            for (component_list.items) |existing| {
                if (std.mem.eql(u8, existing, component_name)) {
                    exists = true;
                    self.allocator.free(component_name);
                    break;
                }
            }
            if (!exists) {
                try component_list.append(self.allocator, component_name);
            }
        }
        std.log.info("DEBUG: First pass complete, component_list.items.len = {d}", .{component_list.items.len});

        // Also collect component names from params
        for (params) |param_name| {
            const component_name = try extractComponentName(self.allocator, param_name);

            // Check if already in list
            var exists = false;
            for (component_list.items) |existing| {
                if (std.mem.eql(u8, existing, component_name)) {
                    exists = true;
                    self.allocator.free(component_name);
                    break;
                }
            }
            if (!exists) {
                try component_list.append(self.allocator, component_name);
            }
        }

        // Second pass: build component nodes with pins and params
        std.log.info("DEBUG: component_list.items.len = {d}", .{component_list.items.len});

        // Sort component names alphabetically
        std.log.info("DEBUG: About to sort component_list", .{});
        std.sort.insertion([]const u8, component_list.items, {}, struct {
            fn compare(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.order(u8, a, b) == .lt;
            }
        }.compare);
        std.log.info("DEBUG: Sort complete", .{});

        // Build component nodes
        for (component_list.items) |comp_name| {
            const comp_name_copy = try self.allocator.dupe(u8, comp_name);
            const component_node = try Node.init(
                self.allocator,
                comp_name_copy,
                .component,
                comp_name_copy,
                null,
            );

            var has_children = false;

            // Add pins for this component
            for (pins) |pin_name| {
                // Skip if search pattern is set and doesn't match
                if (self.search_pattern.len > 0) {
                    if (!glob.match(self.search_pattern, pin_name)) continue;
                }

                const pin_comp = try extractComponentName(self.allocator, pin_name);
                defer self.allocator.free(pin_comp);

                if (std.mem.eql(u8, pin_comp, comp_name)) {
                    const display_name = try extractItemName(self.allocator, pin_name);
                    const full_name_copy = try self.allocator.dupe(u8, pin_name);
                    const pin_node = try Node.init(
                        self.allocator,
                        display_name,
                        .pin,
                        full_name_copy,
                        component_node,
                    );
                    if (component_node.children) |*children| {
                        try children.append(self.allocator, pin_node);
                    }
                    has_children = true;
                }
            }

            // Add params for this component
            for (params) |param_name| {
                // Skip if search pattern is set and doesn't match
                if (self.search_pattern.len > 0) {
                    if (!glob.match(self.search_pattern, param_name)) continue;
                }

                const param_comp = try extractComponentName(self.allocator, param_name);
                defer self.allocator.free(param_comp);

                if (std.mem.eql(u8, param_comp, comp_name)) {
                    const display_name = try extractItemName(self.allocator, param_name);
                    const full_name_copy = try self.allocator.dupe(u8, param_name);
                    const param_node = try Node.init(
                        self.allocator,
                        display_name,
                        .param,
                        full_name_copy,
                        component_node,
                    );
                    if (component_node.children) |*children| {
                        try children.append(self.allocator, param_node);
                    }
                    has_children = true;
                }
            }

            // Only add component if it has children (pins or params)
            if (has_children) {
                try self.root.append(self.allocator, component_node);
            } else {
                // Free unused component node
                self.freeNode(component_node);
            }
        }

        // Build the "Signals" pseudo-component
        const signals_comp_name = try self.allocator.dupe(u8, "Signals");
        const signals_node = try Node.init(
            self.allocator,
            signals_comp_name,
            .component,
            signals_comp_name,
            null,
        );

        var has_signals = false;

        // Add all signals as children of the Signals pseudo-component
        for (signals) |signal_name| {
            // Skip if search pattern is set and doesn't match
            if (self.search_pattern.len > 0) {
                if (!glob.match(self.search_pattern, signal_name)) continue;
            }

            // For signals, show the full signal name (not stripped of prefix)
            // since they're all grouped under "Signals" pseudo-component
            const display_name = try self.allocator.dupe(u8, signal_name);
            const signal_node = try Node.init(
                self.allocator,
                display_name,
                .signal,
                display_name, // full_name same as display_name for signals
                signals_node,
            );
            if (signals_node.children) |*children| {
                try children.append(self.allocator, signal_node);
            }
            has_signals = true;
        }

        // Only add Signals pseudo-component if there are signals
        if (has_signals) {
            try self.root.append(self.allocator, signals_node);
        } else {
            // Free unused Signals node
            self.freeNode(signals_node);
        }
    }

    /// Extract component name from HAL item name
    /// Example: "motion.digital-in-00" -> "motion"
    fn extractComponentName(allocator: std.mem.Allocator, full_name: []const u8) ![]const u8 {
        // Find first dot in name
        const dot_index = std.mem.indexOfScalar(u8, full_name, '.') orelse {
            // No dot found - return full name as component
            return allocator.dupe(u8, full_name);
        };

        // Return substring before first dot
        return allocator.dupe(u8, full_name[0..dot_index]);
    }

    /// Extract item name without component prefix for display
    /// Example: "motion.digital-in-00" -> "digital-in-00"
    fn extractItemName(allocator: std.mem.Allocator, full_name: []const u8) ![]const u8 {
        // Find first dot in name
        const dot_index = std.mem.indexOfScalar(u8, full_name, '.') orelse {
            // No dot found - return full name as-is
            return allocator.dupe(u8, full_name);
        };

        // Return substring after first dot (skip the dot itself)
        return allocator.dupe(u8, full_name[dot_index + 1 ..]);
    }

    /// Return a vxfw.Widget for this TreeView
    pub fn widget(self: *TreeView) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = typeErasedEventHandler,
            .drawFn = typeErasedDrawFn,
        };
    }

    /// Rebuild tree if it's empty but StateStore has data
    /// This handles the case where refresh thread populates StateStore after initialization
    pub fn rebuildTreeIfNeeded(self: *TreeView) !void {
        // Only rebuild once when tree is empty
        if (self.root.items.len == 0) {
            // Check if StateStore has any data (using count to avoid allocations)
            const has_data = blk: {
                self.store.rwlock.lockShared();
                defer self.store.rwlock.unlockShared();
                break :blk self.store.pins.count() > 0 or
                          self.store.signals.count() > 0 or
                          self.store.params.count() > 0;
            };

            if (has_data) {
                std.log.warn("StateStore populated, rebuilding tree", .{});
                try self.buildTree();
            }
        }
    }

    /// Draw function - renders the tree with checkboxes and indicators
    fn typeErasedDrawFn(
        ptr: *anyopaque,
        ctx: vxfw.DrawContext,
    ) std.mem.Allocator.Error!vxfw.Surface {
        const self: *TreeView = @ptrCast(@alignCast(ptr));

        // Rebuild tree if StateStore was populated after initialization
        self.rebuildTreeIfNeeded() catch |err| {
            std.log.err("Failed to rebuild tree: {}", .{err});
        };

        // Clear and rebuild visible nodes list
        self.visible_nodes.clearRetainingCapacity();
        try self.buildVisibleNodes(&self.visible_nodes);

        // Update visible_height based on constrained context
        // Reserve 1 line for search input if active
        const search_lines: usize = if (self.search_input) 1 else 0;
        const available_height = ctx.max.size().height;
        self.visible_height = if (available_height > search_lines)
            @as(usize, @intCast(available_height -| search_lines))
        else
            1;

        // Ensure scroll_offset is valid
        if (self.visible_nodes.items.len > 0) {
            self.cursor_index = @min(self.cursor_index, self.visible_nodes.items.len - 1);
            // Adjust scroll_offset if cursor moved out of view or list shrank
            if (self.scroll_offset + self.visible_height > self.visible_nodes.items.len) {
                self.scroll_offset = if (self.visible_nodes.items.len > self.visible_height)
                    self.visible_nodes.items.len - self.visible_height
                else
                    0;
            }
        }

        // Calculate the slice of visible nodes to render (respecting scroll_offset)
        const render_start = self.scroll_offset;
        const render_end = @min(self.scroll_offset + self.visible_height, self.visible_nodes.items.len);
        const nodes_to_render = self.visible_nodes.items[render_start..render_end];

        // Count lines and find max width for surface sizing
        var line_count: usize = 0;
        var max_width: usize = 0;

        // Add search line if in search mode
        if (self.search_input) {
            line_count += 1;
            const search_width = 1 + self.search_pattern.len;
            max_width = @max(max_width, search_width);
        }

        // Count only rendered nodes
        for (nodes_to_render) |node| {
            line_count += 1;
            const depth = node.getDepth();
            const indent = depth * 2;
            const state = self.checked_items.get(node.full_name) orelse .none;
            const sym_len: usize = switch (state) {
                .none => 0,
                .partial => 2, // " +"
                .full => 2, // " *"
            };
            // Add 1 space + 8 char value column for non-component nodes
            const value_col_width: usize = if (node.item_type == .component) 0 else 9;
            const line_len = 1 + indent + sym_len + node.name.len + value_col_width;
            max_width = @max(max_width, line_len);

            std.log.info("  Line: name='{s}' depth={} indent={} line_len={} max_width={}", .{ node.name, depth, indent, line_len, max_width });
        }

        // Create surface with calculated size (use constrained height)
        const surface_height = @min(line_count, ctx.max.size().height);
        const surface_width = @min(@as(u16, @intCast(max_width)), ctx.max.size().width);
        const surface = try vxfw.Surface.init(
            ctx.arena,
            self.widget(),
            .{ .width = surface_width, .height = @intCast(surface_height) },
        );

        // Initialize buffer with default cells
        const base_cell: vaxis.Cell = .{ .default = true };
        @memset(surface.buffer, base_cell);

        // Write content to buffer
        var row: u16 = 0;

        // Write search input line if active
        if (self.search_input) {
            var col: u16 = 0;
            surface.writeCell(col, row, .{ .char = .{ .grapheme = "/", .width = 1 }, .style = .{} });
            col += 1;
            for (self.search_pattern) |c| {
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = &[_]u8{c}, .width = 1 },
                    .style = .{},
                });
                col += 1;
            }
            row += 1;
        }

        // Write each tree node (only rendered slice)
        for (nodes_to_render, 0..) |node, rel_idx| {
            const node_idx = render_start + rel_idx; // Actual index in visible_nodes
            const state = self.checked_items.get(node.full_name) orelse .none;
            const is_cursor = node_idx == self.cursor_index;
            const depth = node.getDepth();
            var col: u16 = 0;

            // Determine if this node is writable (for color coding)
            // Same logic as DataTable: green for writable, dim gray for read-only
            const is_writable = if (node.item_type != .component) blk: {
                const item_type = switch (node.item_type) {
                    .pin => hal_value.ItemType.pin,
                    .signal => hal_value.ItemType.signal,
                    .param => hal_value.ItemType.param,
                    .component => unreachable,
                };
                break :blk hal_value.isItemWritable(self.allocator, self.store, item_type, node.full_name);
            } else false;

            // Base style: green for writable, dim gray for read-only
            const base_style = if (is_writable)
                vaxis.Style{ .fg = .{ .index = 2 } } // Green for editable
            else
                vaxis.Style{ .fg = .{ .index = 8 } }; // Dim gray for read-only

            // Cursor indicator (▶ for current line, like DataTable)
            const cursor_char = if (is_cursor) "▶" else " ";
            const cursor_width = ctx.stringWidth(cursor_char);
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = cursor_char, .width = @intCast(cursor_width) },
                .style = .{},
            });
            col += @intCast(cursor_width);

            // Write indentation (2 spaces per depth level)
            const spaces = depth * 2;
            var i: usize = 0;
            while (i < spaces) : (i += 1) {
                surface.writeCell(col, row, .{ .char = .{ .grapheme = " ", .width = 1 }, .style = .{} });
                col += 1;
            }

            // Write node name with color
            var char_iter = ctx.graphemeIterator(node.name);
            while (char_iter.next()) |char| {
                const grapheme = char.bytes(node.name);
                const grapheme_width: u8 = @intCast(ctx.stringWidth(grapheme));
                if (col >= surface.size.width) break;
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = grapheme, .width = grapheme_width },
                    .style = if (node.item_type != .component) base_style else .{},
                });
                col += grapheme_width;
            }

            // Write visibility symbol after name
            switch (state) {
                .none => {}, // No symbol
                .partial => {
                    // Show " +" for partial visibility
                    surface.writeCell(col, row, .{ .char = .{ .grapheme = " +", .width = 2 }, .style = .{} });
                    col += 2;
                },
                .full => {
                    // Show " *" for full visibility
                    surface.writeCell(col, row, .{ .char = .{ .grapheme = " ", .width = 1 }, .style = .{} });
                    col += 1;
                    surface.writeCell(col, row, .{ .char = .{ .grapheme = "*", .width = 1 }, .style = .{} });
                    col += 1;
                },
            }

            // Fetch and display value for leaf nodes (pins/signals/params)
            if (node.item_type != .component) {
                // Add space before value column
                if (col < surface.size.width - 8) {
                    surface.writeCell(col, row, .{ .char = .{ .grapheme = " ", .width = 1 }, .style = .{} });
                    col += 1;
                }

                // Get display string: edit buffer if editing, otherwise current value
                const value_str = blk: {
                    if (self.edit_mode and self.edit_item == node) {
                        // Show edit buffer (empty string when buffer is empty, not placeholder)
                        break :blk self.edit_buffer.items;
                    } else {
                        // Show current value from store
                        const value = self.store.getPin(node.full_name) catch
                            self.store.getSignal(node.full_name) catch
                            self.store.getParam(node.full_name) catch null;
                        if (value) |v| {
                            break :blk hal_value.formatHalValue(v, ctx.arena) catch "ERR";
                        } else {
                            break :blk "";
                        }
                    }
                };

                // Check if we're editing this node
                const is_editing = self.edit_mode and self.edit_item == node;

                // Right-align value in 8-character column (also sets position for empty buffer)
                const value_width = if (value_str.len > 0) ctx.stringWidth(value_str) else 0;
                const value_col_start = @min(surface.size.width -| value_width, surface.size.width -| 8);
                if (col < value_col_start) {
                    col = value_col_start;
                }

                var char_idx: usize = 0;
                if (value_str.len > 0) {
                    // Write value string with grapheme iterator for proper Unicode width
                    // Show cursor at edit_cursor_pos position
                    var value_char_iter = ctx.graphemeIterator(value_str);
                    while (value_char_iter.next()) |char| {
                        const grapheme = char.bytes(value_str);
                        const grapheme_width: u8 = @intCast(ctx.stringWidth(grapheme));
                        if (col + grapheme_width <= surface.size.width) {
                            // When editing, show cursor at current cursor position
                            const char_style = if (is_editing and char_idx == self.edit_cursor_pos)
                                vaxis.Style{ .fg = base_style.fg, .reverse = true } // Cursor position
                            else if (is_editing)
                                base_style // Other chars use base color without reverse
                            else
                                base_style; // Not editing - use base color

                            surface.writeCell(col, row, .{
                                .char = .{ .grapheme = grapheme, .width = grapheme_width },
                                .style = char_style,
                            });
                            col += grapheme_width;
                        }
                        char_idx += 1;
                    }
                }

                // Show cursor marker when editing
                // Only show at end when cursor is past the last drawn character
                if (is_editing and self.edit_cursor_pos >= char_idx) {
                    // Cursor at or past end - show cursor marker
                    if (col < surface.size.width) {
                        // Use green background to match the reversed character cursor
                        surface.writeCell(col, row, .{
                            .char = .{ .grapheme = " ", .width = 1 },
                            .style = .{ .fg = .{ .index = 7 }, .bg = .{ .index = 2 } }, // White on green (matches reverse style)
                        });
                    }
                }
            }

            row += 1;
        }

        return surface;
    }

    /// Build list of visible nodes (respecting expand/collapse state)
    fn buildVisibleNodes(self: *TreeView, list: *std.ArrayList(*Node)) !void {
        for (self.root.items) |node| {
            try list.append(self.allocator, node);

            // If component is expanded, add its children
            if (node.isExpandable() and self.expanded_nodes.get(node.full_name) != null) {
                if (node.children) |*children| {
                    for (children.items) |child| {
                        try list.append(self.allocator, child);
                    }
                }
            }
        }
    }

    /// Event handler for keyboard navigation and interaction
    fn typeErasedEventHandler(
        ptr: *anyopaque,
        ctx: *vxfw.EventContext,
        event: vxfw.Event,
    ) anyerror!void {
        const self: *TreeView = @ptrCast(@alignCast(ptr));

        switch (event) {
            // Handle key presses
            .key_press => |key| {
                // Search input mode handling
                if (self.search_input) {
                    // Escape: exit search mode and clear pattern
                    if (key.matches(vaxis.Key.escape, .{})) {
                        self.search_input = false;
                        self.search_buffer.clearRetainingCapacity();
                        self.search_pattern = "";
                        try self.buildTree();
                        ctx.consumeAndRedraw();
                        return;
                    }

                    // Enter: apply search pattern and exit input mode
                    if (key.matches(vaxis.Key.enter, .{})) {
                        self.search_input = false;
                        // Keep search buffer as-is for pattern matching
                        try self.buildTree(); // Rebuild tree with filter applied
                        ctx.consumeAndRedraw();
                        return;
                    }

                    // Backspace: remove last character from pattern
                    if (key.codepoint == 127) { // ASCII DEL (backspace)
                        if (self.search_buffer.items.len > 0) {
                            // Find last UTF-8 code point start
                            var i = self.search_buffer.items.len;
                            while (i > 0) : (i -= 1) {
                                if (self.search_buffer.items[i - 1] >> 6 != 0b10) {
                                    // Found start of UTF-8 character
                                    break;
                                }
                            }
                            self.search_buffer.shrinkRetainingCapacity(i);
                            self.search_pattern = self.search_buffer.items;
                            try self.buildTree();
                            ctx.consumeAndRedraw();
                        }
                        return;
                    }

                    // Regular character: add to search pattern
                    if (key.codepoint >= 32 and key.codepoint < 127) {
                        // Only accept printable ASCII
                        const new_char = @as(u8, @intCast(key.codepoint));
                        try self.search_buffer.append(self.allocator, new_char);
                        self.search_pattern = self.search_buffer.items;
                        try self.buildTree();
                        ctx.consumeAndRedraw();
                        return;
                    }

                    return; // Ignore other keys in search mode
                }

                // Signal deletion prompt handling
                if (self.signal_delete_prompt) {
                    if (key.matches('y', .{})) {
                        // User confirmed deletion
                        if (self.pending_signal_delete) |sig_name| {
                            // Delete signal via backend (works for both native and remote)
                            self.backend.deleteSignal(sig_name) catch |err| {
                                std.log.err("Delete failed: {}", .{err});
                            };

                            try self.store.removeSignal(sig_name);
                            std.log.err("Deleted signal '{s}'", .{sig_name});

                            self.allocator.free(self.pending_signal_delete.?);
                            self.pending_signal_delete = null;
                        }

                        self.signal_delete_prompt = false;
                        ctx.consumeAndRedraw();
                        return;
                    }

                    if (key.matches('n', .{}) or key.matches(vaxis.Key.escape, .{})) {
                        // User cancelled - leave signal orphaned
                        const sig_name = self.pending_signal_delete orelse "";
                        std.log.err("Signal '{s}' left orphaned", .{sig_name});

                        if (self.pending_signal_delete) |name| {
                            self.allocator.free(name);
                            self.pending_signal_delete = null;
                        }

                        self.signal_delete_prompt = false;
                        ctx.consumeAndRedraw();
                        return;
                    }

                    // Ignore all other keys during prompt
                    return;
                }

                // Signal edit mode handling (Ctrl+S on pin)
                if (self.signal_edit_mode) {
                    // Escape: cancel
                    if (key.matches(vaxis.Key.escape, .{})) {
                        self.signal_edit_mode = false;
                        self.signal_edit_pin = null;
                        self.signal_edit_buffer.clearRetainingCapacity();
                        ctx.consumeAndRedraw();
                        return;
                    }

                    // Enter: connect to signal (empty = disconnect)
                    if (key.matches(vaxis.Key.enter, .{})) {
                        if (self.signal_edit_pin) |pin_node| {
                            const pin_name = pin_node.full_name;
                            const signal_name = self.signal_edit_buffer.items;

                            if (signal_name.len == 0) {
                                // Disconnect: Unlink pin from signal
                                const old_signal = self.store.pin_links.get(NameKey.fromStr(pin_name));

                                self.backend.unlinkPin(pin_name) catch |err| {
                                    std.log.err("Disconnect failed: {}", .{err});
                                    ctx.consumeAndRedraw();
                                    return;
                                };
                                try self.store.updatePinLink(pin_name, null);

                                // Check if this was the last pin connected to the signal
                                if (old_signal) |sig| {
                                    const sig_str = sig.slice();
                                    const remaining_pins = self.store.countPinsForSignal(sig_str);
                                    if (remaining_pins == 0) {
                                        // Prompt for signal deletion
                                        self.signal_delete_prompt = true;
                                        self.pending_signal_delete = try self.allocator.dupe(u8, sig_str);
                                        std.log.err("Delete orphaned signal '{s}'? (y/n)", .{sig_str});
                                    } else {
                                        std.log.err("Disconnected from signal ({d} pins remain)", .{remaining_pins});
                                    }
                                } else {
                                    std.log.err("Disconnected from signal", .{});
                                }

                                self.signal_edit_mode = false;
                                self.signal_edit_pin = null;
                                self.signal_edit_buffer.clearRetainingCapacity();
                                ctx.consumeAndRedraw();
                                return;
                            } else {
                                // Connect or create signal
                                // 1. Get current pin value to infer type
                                const pin_value = self.store.getPin(pin_name) catch {
                                    std.log.err("Failed to read pin value: {s}", .{pin_name});
                                    ctx.consumeAndRedraw();
                                    return;
                                };

                                // 2. Determine PinType from value
                                const pin_type: PinType = switch (pin_value) {
                                    .bit => .bit,
                                    .float => .float,
                                    .s32 => .s32,
                                    .u32 => .u32,
                                };

                                // 3. Check if signal exists
                                const signal_exists = self.store.getSignal(signal_name) catch null != null;

                                if (!signal_exists) {
                                    // Create new signal with inferred type (via backend)
                                    self.backend.createSignal(signal_name, pin_type) catch |err| {
                                        std.log.err("Signal creation failed: {}", .{err});
                                        ctx.consumeAndRedraw();
                                        return;
                                    };

                                    // Add to store with initial value
                                    try self.store.addSignal(signal_name, pin_value);
                                }

                                // 4. Link pin to signal (via backend)
                                self.backend.linkPin(pin_name, signal_name) catch |err| {
                                    std.log.err("Link failed: {}", .{err});
                                    ctx.consumeAndRedraw();
                                    return;
                                };

                                // Update store's pin link tracking
                                try self.store.updatePinLink(pin_name, signal_name);
                            }

                            self.signal_edit_mode = false;
                            self.signal_edit_pin = null;
                            self.signal_edit_buffer.clearRetainingCapacity();
                            ctx.consumeAndRedraw();
                            return;
                        }
                    }

                    // Backspace: remove last character
                    if (key.codepoint == 127) {
                        if (self.signal_edit_buffer.items.len > 0) {
                            _ = self.signal_edit_buffer.pop();
                            ctx.consumeAndRedraw();
                        }
                        return;
                    }

                    // Regular character: add to signal name buffer
                    if (key.codepoint >= 32 and key.codepoint < 127) {
                        const new_char = @as(u8, @intCast(key.codepoint));
                        // Signal names are alphanumeric with underscore and dash
                        const allowed = std.ascii.isAlphanumeric(new_char) or new_char == '_' or new_char == '-';
                        if (allowed) {
                            try self.signal_edit_buffer.append(self.allocator, new_char);
                            ctx.consumeAndRedraw();
                        }
                        return;
                    }

                    return; // Ignore other keys in signal edit mode
                }

                // Edit mode handling
                if (self.edit_mode) {
                    // Escape: cancel edit
                    if (key.matches(vaxis.Key.escape, .{})) {
                        self.edit_mode = false;
                        self.edit_item = null;
                        self.edit_buffer.clearRetainingCapacity();
                        self.edit_cursor_pos = 0;
                        ctx.consumeAndRedraw();
                        return;
                    }

                    // Left arrow: move cursor left
                    if (key.matches(vaxis.Key.left, .{})) {
                        if (self.edit_cursor_pos > 0) {
                            self.edit_cursor_pos -= 1;
                            ctx.consumeAndRedraw();
                        }
                        return;
                    }

                    // Right arrow: move cursor right
                    if (key.matches(vaxis.Key.right, .{})) {
                        if (self.edit_cursor_pos < self.edit_buffer.items.len) {
                            self.edit_cursor_pos += 1;
                            ctx.consumeAndRedraw();
                        }
                        return;
                    }

                    // Enter: confirm edit
                    if (key.matches(vaxis.Key.enter, .{})) {
                        if (self.edit_item) |node| {
                            const input = self.edit_buffer.items;

                            // Get original value to determine type
                            const orig_value = self.store.getPin(node.full_name) catch
                                self.store.getSignal(node.full_name) catch
                                self.store.getParam(node.full_name) catch null;

                            if (orig_value) |v| {
                                // Parse new value based on type
                                const new_value: HalValue = blk: {
                                    switch (v) {
                                        .bit => |b| break :blk HalValue{ .bit = b }, // BIT doesn't reach edit mode, but handle anyway
                                        .float => |_| {
                                            const parsed = std.fmt.parseFloat(f64, input) catch {
                                                // Invalid float - could show error but just stay in edit mode
                                                ctx.consumeAndRedraw();
                                                return;
                                            };
                                            break :blk HalValue{ .float = parsed };
                                        },
                                        .s32 => |_| {
                                            const parsed = std.fmt.parseInt(i32, input, 10) catch {
                                                // Invalid integer - just stay in edit mode
                                                ctx.consumeAndRedraw();
                                                return;
                                            };
                                            break :blk HalValue{ .s32 = parsed };
                                        },
                                        .u32 => |_| {
                                            const parsed = std.fmt.parseInt(u32, input, 10) catch {
                                                // Invalid unsigned - just stay in edit mode
                                                ctx.consumeAndRedraw();
                                                return;
                                            };
                                            break :blk HalValue{ .u32 = parsed };
                                        },
                                    }
                                };

                                // Write to HAL via backend (works for both native and remote)
                                // IMPORTANT: Backend write must happen BEFORE store.updatePin to ensure
                                // HAL value is written before cache update matches it
                                const hal_write_ok = blk: {
                                    if (node.item_type == .pin) {
                                        const backend_value = toBackendHalValue(new_value);
                                        self.backend.setPinValue(node.full_name, backend_value) catch |err| {
                                            std.debug.print("Backend write failed: setPinValue '{s}' error {}\n", .{ node.full_name, err });
                                            // Stay in edit mode on error so user can retry
                                            ctx.consumeAndRedraw();
                                            return;
                                        };
                                    } else if (node.item_type == .param) {
                                        const backend_value = toBackendHalValue(new_value);
                                        self.backend.setParamValue(node.full_name, backend_value) catch |err| {
                                            std.debug.print("Backend write failed: setParamValue '{s}' error {}\n", .{ node.full_name, err });
                                            ctx.consumeAndRedraw();
                                            return;
                                        };
                                    }
                                    break :blk true;
                                };
                                _ = hal_write_ok; // Use the value

                                // Update value in store
                                switch (node.item_type) {
                                    .pin => try self.store.updatePin(node.full_name, new_value),
                                    .signal => try self.store.updateSignal(node.full_name, new_value),
                                    .param => try self.store.updateParam(node.full_name, new_value),
                                    .component => unreachable,
                                }

                                self.edit_mode = false;
                                self.edit_item = null;
                                self.edit_buffer.clearRetainingCapacity();
                                ctx.consumeAndRedraw();
                                return;
                            }
                        }
                    }

                    // Backspace: remove character before cursor
                    if (key.codepoint == 127) {
                        if (self.edit_cursor_pos > 0) {
                            // Remove character at cursor_pos - 1
                            _ = self.edit_buffer.orderedRemove(self.edit_cursor_pos - 1);
                            self.edit_cursor_pos -= 1;
                            ctx.consumeAndRedraw();
                        }
                        return;
                    }

                    // Type-specific character validation
                    if (key.codepoint >= 32 and key.codepoint < 127) {
                        const new_char = @as(u8, @intCast(key.codepoint));

                        const orig_value = self.store.getPin(self.edit_item.?.full_name) catch
                            self.store.getSignal(self.edit_item.?.full_name) catch
                            self.store.getParam(self.edit_item.?.full_name) catch null;

                        const allowed = if (orig_value) |v| blk: {
                            const result = switch (v) {
                                .float => blk2: {
                                    // Allow: digits, minus (start only), decimal point (once)
                                    if (new_char == '-' and self.edit_buffer.items.len == 0) break :blk2 true else if (new_char == '.' and std.mem.indexOfScalar(u8, self.edit_buffer.items, '.') == null) break :blk2 true else break :blk2 new_char >= '0' and new_char <= '9';
                                },
                                .s32 => blk2: {
                                    // Allow: digits, minus (start only)
                                    if (new_char == '-') break :blk2 self.edit_buffer.items.len == 0 else break :blk2 new_char >= '0' and new_char <= '9';
                                },
                                .u32 => new_char >= '0' and new_char <= '9',
                                .bit => false, // BIT doesn't use text edit
                            };
                            break :blk result;
                        } else false;

                        if (allowed) {
                            // Insert character at cursor position
                            try self.edit_buffer.insert(self.allocator, self.edit_cursor_pos, new_char);
                            self.edit_cursor_pos += 1;
                            ctx.consumeAndRedraw();
                        }
                        return;
                    }

                    return; // Ignore other keys in edit mode
                }

                // Normal mode handling

                // "/": Enter search input mode
                if (key.matches('/', .{})) {
                    self.search_input = true;
                    self.search_buffer.clearRetainingCapacity();
                    self.search_pattern = "";
                    ctx.consumeAndRedraw();
                    return;
                }

                // Arrow Up: move cursor up
                if (key.matches(vaxis.Key.up, .{})) {
                    if (self.cursor_index > 0) {
                        self.cursor_index -= 1;
                        // Scroll up if cursor is above visible area
                        if (self.cursor_index < self.scroll_offset) {
                            self.scroll_offset = self.cursor_index;
                        }
                        ctx.consumeAndRedraw();
                    }
                    return;
                }

                // Page Down: move cursor down by visible_height
                if (key.matches(vaxis.Key.page_down, .{})) {
                    if (self.visible_nodes.items.len > 0) {
                        const page_size = @max(self.visible_height, 1);
                        const new_cursor = @min(self.cursor_index + page_size, self.visible_nodes.items.len - 1);
                        self.cursor_index = new_cursor;
                        // Adjust scroll_offset to keep cursor in view
                        const bottom_visible = self.scroll_offset + self.visible_height;
                        if (self.cursor_index >= bottom_visible) {
                            self.scroll_offset = self.cursor_index - self.visible_height + 1;
                        }
                        ctx.consumeAndRedraw();
                    }
                    return;
                }

                // Page Up: move cursor up by visible_height
                if (key.matches(vaxis.Key.page_up, .{})) {
                    if (self.visible_nodes.items.len > 0) {
                        const page_size = @max(self.visible_height, 1);
                        const new_cursor = if (page_size >= self.cursor_index) 0 else self.cursor_index - page_size;
                        self.cursor_index = new_cursor;
                        // Adjust scroll_offset to keep cursor in view
                        if (self.cursor_index < self.scroll_offset) {
                            self.scroll_offset = self.cursor_index;
                        }
                        ctx.consumeAndRedraw();
                    }
                    return;
                }

                // Arrow Down: move cursor down
                if (key.matches(vaxis.Key.down, .{})) {
                    if (self.visible_nodes.items.len > 0 and self.cursor_index < self.visible_nodes.items.len - 1) {
                        self.cursor_index += 1;
                        // Scroll down if cursor is below visible area
                        const bottom_visible = self.scroll_offset + self.visible_height;
                        if (self.visible_height > 0 and self.cursor_index >= bottom_visible) {
                            self.scroll_offset = self.cursor_index - self.visible_height + 1;
                        }
                        ctx.consumeAndRedraw();
                    }
                    return;
                }

                // Enter: Edit value or toggle BIT, or toggle expand/collapse for components
                if (key.matches(vaxis.Key.enter, .{})) {
                    if (self.visible_nodes.items.len == 0) return;

                    const node = self.visible_nodes.items[self.cursor_index];

                    // Expandable nodes (components): toggle expand/collapse
                    if (node.isExpandable()) {
                        const gop = try self.expanded_nodes.getOrPut(node.full_name);
                        if (gop.found_existing) {
                            // Collapse: remove from expanded set
                            _ = self.expanded_nodes.remove(node.full_name);
                        } else {
                            // Expand: add to expanded set
                            gop.value_ptr.* = {};
                        }
                        ctx.consumeAndRedraw();
                        return;
                    }

                    // Leaf nodes: check if value is writable
                    // Uses shared logic from hal_value module
                    const item_type = switch (node.item_type) {
                        .pin => hal_value.ItemType.pin,
                        .signal => hal_value.ItemType.signal,
                        .param => hal_value.ItemType.param,
                        .component => unreachable,
                    };
                    const is_writable = hal_value.isItemWritable(self.allocator, self.store, item_type, node.full_name);

                    if (!is_writable) {
                        // Skip editing - status message would be shown by caller if needed
                        ctx.consumeAndRedraw();
                        return;
                    }

                    // Get current value to determine type
                    const value = self.store.getPin(node.full_name) catch
                        self.store.getSignal(node.full_name) catch
                        self.store.getParam(node.full_name) catch null;

                    if (value) |v| {
                        switch (v) {
                            .bit => {
                                // BIT: Toggle value directly (no edit mode)
                                const new_value = !v.bit;

                                // Write to HAL for pins only (signals are read-only)
                                if (node.item_type == .pin) {
                                    const backend_value = BackendHalValue{ .bit = new_value };
                                    self.backend.setPinValue(node.full_name, backend_value) catch |err| {
                                        std.debug.print("Backend write failed: setPinValue '{s}' error {}\n", .{ node.full_name, err });
                                        // Even if HAL write fails, update cache and continue
                                    };
                                }

                                try self.store.updatePin(node.full_name, HalValue{ .bit = new_value });
                                ctx.consumeAndRedraw();
                                return;
                            },
                            .float, .s32, .u32 => {
                                // Numeric: Enter edit mode
                                self.edit_mode = true;
                                self.edit_item = node;
                                self.edit_buffer.clearRetainingCapacity();
                                self.edit_cursor_pos = 0;
                                // Pre-populate with current value
                                const current_str = hal_value.formatHalValue(v, self.allocator) catch "";
                                defer self.allocator.free(current_str);
                                try self.edit_buffer.appendSlice(self.allocator, current_str);
                                // Set cursor to end of initial value
                                self.edit_cursor_pos = self.edit_buffer.items.len;
                                ctx.consumeAndRedraw();
                                return;
                            },
                        }
                    }
                }

                // Space: toggle checkbox for current node
                if (key.matches(' ', .{})) {
                    if (self.visible_nodes.items.len > 0) {
                        const node = self.visible_nodes.items[self.cursor_index];
                        try self.toggleCheckbox(node.full_name);
                        ctx.consumeAndRedraw();
                        return;
                    }
                }

                // Backspace: collapse parent when on a child node
                if (key.matches(vaxis.Key.backspace, .{})) {
                    if (self.visible_nodes.items.len > 0) {
                        const node = self.visible_nodes.items[self.cursor_index];
                        // If this is a child node (has parent), collapse the parent
                        if (node.parent) |parent| {
                            _ = self.expanded_nodes.remove(parent.full_name);
                            ctx.consumeAndRedraw();
                        }
                        return;
                    }
                }

                // "Ctrl+S": Enter signal connection mode (for pins only)
                if (key.matches('s', .{ .ctrl = true })) {
                    if (self.visible_nodes.items.len == 0) return;

                    const node = self.visible_nodes.items[self.cursor_index];

                    // Only pins can connect to signals
                    if (node.item_type != .pin) {
                        // Silently ignore - user can only connect pins to signals
                        return;
                    }

                    // Enter signal name editing mode
                    self.signal_edit_mode = true;
                    self.signal_edit_pin = node;
                    self.signal_edit_buffer.clearRetainingCapacity();

                    // Pre-populate with current signal if connected
                    if (self.store.pin_links.get(NameKey.fromStr(node.full_name))) |current_signal| {
                        try self.signal_edit_buffer.appendSlice(self.allocator, current_signal.slice());
                    }

                    ctx.consumeAndRedraw();
                    return;
                }
            },

            else => {},
        }
    }

    /// Toggle visibility state for an item
    /// - Components: cycle none -> full -> none (propagates to children)
    /// - Leafs: cycle none -> full -> none (updates ancestors)
    fn toggleCheckbox(self: *TreeView, full_name: []const u8) !void {
        // Find the node in the tree
        const node = self.findNode(full_name) orelse return;
        const current_state = self.checked_items.get(full_name) orelse .none;

        // Determine new state based on current state and node type
        const new_state: VisibilityState = if (node.isExpandable())
            if (current_state == .full) .none else .full
        else if (current_state == .full) .none else .full;

        // Set the new state (will propagate)
        try self.setNodeState(node, new_state);
    }

    /// Find a node by full_name in the tree
    fn findNode(self: *const TreeView, full_name: []const u8) ?*Node {
        for (self.root.items) |node| {
            if (std.mem.eql(u8, node.full_name, full_name)) return node;
            if (node.children) |*children| {
                for (children.items) |child| {
                    if (std.mem.eql(u8, child.full_name, full_name)) return child;
                }
            }
        }
        return null;
    }

    /// Set a node's visibility state and propagate changes
    /// - For components: propagates to all descendants
    /// - Then updates all ancestors
    fn setNodeState(self: *TreeView, node: *Node, state: VisibilityState) !void {
        // Set this node's state
        try self.checked_items.put(node.full_name, state);

        // If this is a component, propagate state to all descendants
        if (node.isExpandable()) {
            if (node.children) |*children| {
                for (children.items) |child| {
                    try self.setNodeStateRecursive(child, state);
                }
            }
        }

        // Update all ancestor states based on their children
        var current = node.parent;
        while (current) |parent| {
            try self.updateParentState(parent);
            current = parent.parent;
        }
    }

    /// Recursively set state for a node and all its descendants
    fn setNodeStateRecursive(self: *TreeView, node: *Node, state: VisibilityState) !void {
        try self.checked_items.put(node.full_name, state);

        if (node.children) |*children| {
            for (children.items) |child| {
                try self.setNodeStateRecursive(child, state);
            }
        }
    }

    /// Update a parent node's state based on its children's states
    fn updateParentState(self: *TreeView, parent: *Node) !void {
        const children = parent.children orelse {
            // Leaf node - should not happen, but handle gracefully
            return;
        };

        if (children.items.len == 0) {
            // No children - remove state (equivalent to none)
            _ = self.checked_items.remove(parent.full_name);
            return;
        }

        // Check all children's states
        var has_full: bool = false;
        var has_none: bool = false;

        for (children.items) |child| {
            const child_state = self.checked_items.get(child.full_name) orelse .none;
            switch (child_state) {
                .full => has_full = true,
                .none => has_none = true,
                .partial => {
                    // If any child is partial, parent is partial
                    try self.checked_items.put(parent.full_name, .partial);
                    return;
                },
            }
        }

        // Determine parent state based on children
        if (has_full and !has_none) {
            // All children are full
            try self.checked_items.put(parent.full_name, .full);
        } else if (!has_full and has_none) {
            // All children are none
            _ = self.checked_items.remove(parent.full_name);
        } else {
            // Mixed - some full, some none
            try self.checked_items.put(parent.full_name, .partial);
        }
    }

    /// Get the currently focused (cursor) node
    pub fn getCursorNode(self: *const TreeView) ?*Node {
        if (self.visible_nodes.items.len == 0) return null;
        return self.visible_nodes.items[self.cursor_index];
    }

    /// Check if tree is in edit mode (value or signal editing)
    pub fn isEditMode(self: *const TreeView) bool {
        return self.edit_mode or self.signal_edit_mode or self.signal_delete_prompt;
    }

    /// Get list of visible pin names
    /// Returns pins that are currently visible in the tree (i.e., their parent component is expanded)
    /// This is used to optimize refresh to only query visible pins from the backend
    pub fn getVisiblePinNames(self: *const TreeView, allocator: std.mem.Allocator) ![][]const u8 {
        var visible_pins = std.ArrayList([]const u8).initCapacity(allocator, 0) catch return error.OutOfMemory;
        defer visible_pins.deinit(allocator);

        // Iterate through visible nodes and collect pin names
        for (self.visible_nodes.items) |node| {
            if (node.item_type == .pin) {
                const name_copy = try allocator.dupe(u8, node.full_name);
                try visible_pins.append(allocator, name_copy);
            }
        }

        return visible_pins.toOwnedSlice(allocator);
    }
};

/// Helper struct to group HAL items by component
/// IMPORTANT: ComponentGroup owns its name copy (not a reference to HashMap key)
/// because HashMap may reallocate keys during growth, which would invalidate references.
const ComponentGroup = struct {
    name: []const u8,
    pins: std.ArrayList([]const u8),
    signals: std.ArrayList([]const u8),
    params: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator, name: []const u8) !ComponentGroup {
        // Duplicate the name so we own it (HashMap may reallocate during growth)
        const name_copy = try allocator.dupe(u8, name);
        return .{
            .name = name_copy,
            .pins = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable,
            .signals = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable,
            .params = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable,
            .allocator = allocator,
        };
    }

    fn deinit(self: *ComponentGroup) void {
        // Free the name we own
        self.allocator.free(self.name);

        // Free duplicated pin/signal/param names
        for (self.pins.items) |pin| {
            self.allocator.free(pin);
        }
        self.pins.deinit(self.allocator);

        for (self.signals.items) |signal| {
            self.allocator.free(signal);
        }
        self.signals.deinit(self.allocator);

        for (self.params.items) |param| {
            self.allocator.free(param);
        }
        self.params.deinit(self.allocator);
    }
};

// Compile-time tests
comptime {
    _ = NodeType;
    _ = Node;
    _ = TreeView.init;
    _ = TreeView.deinit;
    _ = Node.isExpandable;
    _ = Node.getDepth;
}
