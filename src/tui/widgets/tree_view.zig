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
const StateStore = @import("../../state/cache.zig").StateStore;
const glob = @import("glob");

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

/// Tree navigation widget
pub const TreeView = struct {
    /// Memory allocator
    allocator: std.mem.Allocator,

    /// State store for reading HAL data
    store: *StateStore,

    /// Root level component nodes
    root: std.ArrayList(*Node),

    /// Set of expanded node names (for component nodes)
    expanded_nodes: std.StringHashMap(void),

    /// Visibility state for each node (none, partial, or full)
    checked_items: std.StringHashMap(VisibilityState),

    /// Current cursor position (index into visible nodes)
    cursor_index: usize,

    /// List of visible nodes (built during draw, respecting expand/collapse)
    visible_nodes: std.ArrayList(*Node),

    /// Current search pattern (glob pattern for filtering)
    /// Owned slice allocated by allocator
    search_pattern: []const u8,

    /// Whether search input mode is active
    search_input: bool,

    /// Buffer for building search patterns
    search_buffer: std.ArrayList(u8),

    /// Initialize a new TreeView
    pub fn init(allocator: std.mem.Allocator, store: *StateStore) !TreeView {
        // Initialize ArrayLists using initCapacity
        // Note: initCapacity(allocator, 0) never fails in practice
        const root_list = std.ArrayList(*Node).initCapacity(allocator, 0) catch return error.OutOfMemory;
        const visible_nodes_list = std.ArrayList(*Node).initCapacity(allocator, 0) catch return error.OutOfMemory;
        const search_buffer_list = std.ArrayList(u8).initCapacity(allocator, 0) catch return error.OutOfMemory;

        const tree_view = TreeView{
            .allocator = allocator,
            .store = store,
            .root = root_list,
            .expanded_nodes = std.StringHashMap(void).init(allocator),
            .checked_items = std.StringHashMap(VisibilityState).init(allocator),
            .cursor_index = 0,
            .visible_nodes = visible_nodes_list,
            .search_pattern = "",
            .search_input = false,
            .search_buffer = search_buffer_list,
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
    pub fn buildTree(self: *TreeView) !void {
        // Clean up existing tree before rebuilding
        for (self.root.items) |node| {
            self.freeNode(node);
        }
        self.root.clearRetainingCapacity();

        // Get all pins, signals, and params from StateStore
        const pins = try self.store.listPins(self.allocator);
        defer self.allocator.free(pins);

        const signals = try self.store.listSignals(self.allocator);
        defer self.allocator.free(signals);

        const params = try self.store.listParams(self.allocator);
        defer self.allocator.free(params);

        // HashMap to group items by component
        var component_map = std.StringHashMap(ComponentGroup).init(self.allocator);
        defer {
            var iter = component_map.iterator();
            while (iter.next()) |entry| {
                // Free the key (component name string owned by HashMap)
                self.allocator.free(entry.key_ptr.*);
                entry.value_ptr.*.deinit();
            }
            component_map.deinit();
        }

        // Group pins by component (filter by search pattern if set)
        for (pins) |pin_name| {
            // Skip if search pattern is set and doesn't match
            if (self.search_pattern.len > 0) {
                if (!glob.match(self.search_pattern, pin_name)) continue;
            }

            const component_name = try extractComponentName(self.allocator, pin_name);

            const gop = try component_map.getOrPut(component_name);
            if (!gop.found_existing) {
                gop.value_ptr.* = ComponentGroup.init(self.allocator, component_name);
                // HashMap owns component_name now - don't free it
            } else {
                // Entry already existed, free our temporary component_name
                self.allocator.free(component_name);
            }

            try gop.value_ptr.pins.append(gop.value_ptr.allocator, pin_name);
        }

        // Group signals by component (filter by search pattern if set)
        for (signals) |signal_name| {
            // Skip if search pattern is set and doesn't match
            if (self.search_pattern.len > 0) {
                if (!glob.match(self.search_pattern, signal_name)) continue;
            }

            const component_name = try extractComponentName(self.allocator, signal_name);

            const gop = try component_map.getOrPut(component_name);
            if (!gop.found_existing) {
                gop.value_ptr.* = ComponentGroup.init(self.allocator, component_name);
                // HashMap owns component_name now - don't free it
            } else {
                // Entry already existed, free our temporary component_name
                self.allocator.free(component_name);
            }

            try gop.value_ptr.signals.append(gop.value_ptr.allocator, signal_name);
        }

        // Group params by component (filter by search pattern if set)
        for (params) |param_name| {
            // Skip if search pattern is set and doesn't match
            if (self.search_pattern.len > 0) {
                if (!glob.match(self.search_pattern, param_name)) continue;
            }

            const component_name = try extractComponentName(self.allocator, param_name);

            const gop = try component_map.getOrPut(component_name);
            if (!gop.found_existing) {
                gop.value_ptr.* = ComponentGroup.init(self.allocator, component_name);
                // HashMap owns component_name now - don't free it
            } else {
                // Entry already existed, free our temporary component_name
                self.allocator.free(component_name);
            }

            try gop.value_ptr.params.append(gop.value_ptr.allocator, param_name);
        }

        // Build tree structure from component groups
        var iter = component_map.iterator();
        while (iter.next()) |entry| {
            // Component name is owned by HashMap (as key), duplicate for Node
            const comp_name = try self.allocator.dupe(u8, entry.value_ptr.name);
            const component_node = try Node.init(
                self.allocator,
                comp_name,
                .component,
                comp_name, // full_name same as name for components
                null, // no parent
            );
            try self.root.append(self.allocator, component_node);

            // Add pins as children
            for (entry.value_ptr.pins.items) |pin_name| {
                // Display name without component prefix, full name for lookups
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
            }

            // Add signals as children
            for (entry.value_ptr.signals.items) |signal_name| {
                // Display name without component prefix, full name for lookups
                const display_name = try extractItemName(self.allocator, signal_name);
                const full_name_copy = try self.allocator.dupe(u8, signal_name);
                const signal_node = try Node.init(
                    self.allocator,
                    display_name,
                    .signal,
                    full_name_copy,
                    component_node,
                );
                if (component_node.children) |*children| {
                    try children.append(self.allocator, signal_node);
                }
            }

            // Add params as children
            for (entry.value_ptr.params.items) |param_name| {
                // Display name without component prefix, full name for lookups
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
            }
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

    /// Draw function - renders the tree with checkboxes and indicators
    fn typeErasedDrawFn(
        ptr: *anyopaque,
        ctx: vxfw.DrawContext,
    ) std.mem.Allocator.Error!vxfw.Surface {
        const self: *TreeView = @ptrCast(@alignCast(ptr));

        // Clear and rebuild visible nodes list
        self.visible_nodes.clearRetainingCapacity();
        try self.buildVisibleNodes(&self.visible_nodes);

        // Count lines and find max width for surface sizing
        var line_count: usize = 0;
        var max_width: usize = 0;

        // Add search line if in search mode
        if (self.search_input) {
            line_count += 1;
            const search_width = 1 + self.search_pattern.len;
            max_width = @max(max_width, search_width);
        }

        // Count visible nodes
        for (self.visible_nodes.items) |node| {
            line_count += 1;
            const depth = node.getDepth();
            const indent = depth * 2;
            const state = self.checked_items.get(node.full_name) orelse .none;
            const sym_len: usize = switch (state) {
                .none => 0,
                .partial => 1, // "+"
                .full => 2,     // " *"
            };
            const line_len = 1 + indent + sym_len + node.name.len;
            max_width = @max(max_width, line_len);
        }

        // Ensure cursor is within bounds
        if (self.visible_nodes.items.len > 0) {
            self.cursor_index = @min(self.cursor_index, self.visible_nodes.items.len - 1);
        }

        // Create surface with calculated size
        const surface = try vxfw.Surface.init(
            ctx.arena,
            self.widget(),
            .{ .width = @intCast(max_width), .height = @intCast(line_count) },
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

        // Write each tree node
        for (self.visible_nodes.items, 0..) |node, node_idx| {
            const state = self.checked_items.get(node.full_name) orelse .none;
            const is_cursor = node_idx == self.cursor_index;
            const depth = node.getDepth();
            var col: u16 = 0;

            // Cursor indicator ('>' for current line)
            const cursor_char = if (is_cursor) ">" else " ";
            surface.writeCell(col, row, .{
                .char = .{ .grapheme = cursor_char, .width = 1 },
                .style = .{},
            });
            col += 1;

            // Write indentation (2 spaces per depth level)
            const spaces = depth * 2;
            var i: usize = 0;
            while (i < spaces) : (i += 1) {
                surface.writeCell(col, row, .{ .char = .{ .grapheme = " ", .width = 1 }, .style = .{} });
                col += 1;
            }

            // Write node name
            var char_iter = ctx.graphemeIterator(node.name);
            while (char_iter.next()) |char| {
                const grapheme = char.bytes(node.name);
                const grapheme_width: u8 = @intCast(ctx.stringWidth(grapheme));
                if (col >= surface.size.width) break;
                surface.writeCell(col, row, .{
                    .char = .{ .grapheme = grapheme, .width = grapheme_width },
                    .style = .{},
                });
                col += grapheme_width;
            }

            // Write visibility symbol after name
            switch (state) {
                .none => {}, // No symbol
                .partial => {
                    // Show "+" for partial visibility
                    surface.writeCell(col, row, .{ .char = .{ .grapheme = "+", .width = 1 }, .style = .{} });
                    col += 1;
                },
                .full => {
                    // Show " *" for full visibility
                    surface.writeCell(col, row, .{ .char = .{ .grapheme = " ", .width = 1 }, .style = .{} });
                    col += 1;
                    surface.writeCell(col, row, .{ .char = .{ .grapheme = "*", .width = 1 }, .style = .{} });
                    col += 1;
                },
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
                        ctx.consumeAndRedraw();
                    }
                    return;
                }

                // Arrow Down: move cursor down
                if (key.matches(vaxis.Key.down, .{})) {
                    if (self.cursor_index < self.visible_nodes.items.len - 1) {
                        self.cursor_index += 1;
                        ctx.consumeAndRedraw();
                    }
                    return;
                }

                // Enter: toggle expand/collapse for component nodes
                if (key.matches(vaxis.Key.enter, .{})) {
                    if (self.visible_nodes.items.len > 0) {
                        const node = self.visible_nodes.items[self.cursor_index];

                        // Only expandable nodes (components) respond to Enter
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
                        }
                        // TODO: For leaf nodes (pins), Enter could enter value editing mode
                        return;
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
        else
            if (current_state == .full) .none else .full;

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
};

/// Helper struct to group HAL items by component
const ComponentGroup = struct {
    name: []const u8,
    pins: std.ArrayList([]const u8),
    signals: std.ArrayList([]const u8),
    params: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator, name: []const u8) ComponentGroup {
        // Store reference to name - HashMap owns it
        return .{
            .name = name,
            .pins = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable,
            .signals = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable,
            .params = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable,
            .allocator = allocator,
        };
    }

    fn deinit(self: *ComponentGroup) void {
        // Don't free self.name - HashMap owns it
        self.pins.deinit(self.allocator);
        self.signals.deinit(self.allocator);
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
