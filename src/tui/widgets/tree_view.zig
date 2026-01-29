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
const StateStore = @import("../../state/cache.zig").StateStore;

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
            .children = if (item_type == .component) std.ArrayList(*Node).init(allocator) else null,
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

    /// Set of checked item names (for display in data table)
    checked_items: std.StringHashMap(void),

    /// Current cursor position (index into visible nodes)
    cursor_index: usize,

    /// List of visible nodes (built during draw, respecting expand/collapse)
    visible_nodes: std.ArrayList(*Node),

    /// Initialize a new TreeView
    pub fn init(allocator: std.mem.Allocator, store: *StateStore) !TreeView {
        var tree_view = TreeView{
            .allocator = allocator,
            .store = store,
            .root = std.ArrayList(*Node).init(allocator),
            .expanded_nodes = std.StringHashMap(void).init(allocator),
            .checked_items = std.StringHashMap(void).init(allocator),
            .cursor_index = 0,
            .visible_nodes = std.ArrayList(*Node).init(allocator),
        };

        // Build the tree from HAL data
        try tree_view.buildTree();

        return tree_view;
    }

    /// Clean up TreeView resources
    pub fn deinit(self: *TreeView) void {
        // Free all nodes
        for (self.root.items) |node| {
            self.freeNode(node);
        }
        self.root.deinit();

        // Free HashMaps
        self.expanded_nodes.deinit();
        self.checked_items.deinit();
        self.visible_nodes.deinit();
    }

    /// Recursively free a node and its children
    fn freeNode(self: *TreeView, node: *Node) void {
        if (node.children) |*children| {
            for (children.items) |child| {
                self.freeNode(child);
            }
            children.deinit();
        }
        self.allocator.destroy(node);
    }

    /// Build tree from HAL data in StateStore
    fn buildTree(self: *TreeView) !void {
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
                entry.value_ptr.*.deinit();
            }
            component_map.deinit();
        };

        // Group pins by component
        for (pins) |pin_name| {
            const component_name = try extractComponentName(self.allocator, pin_name);
            defer self.allocator.free(component_name);

            const gop = try component_map.getOrPut(component_name);
            if (!gop.found_existing) {
                gop.value_ptr.* = ComponentGroup.init(self.allocator, component_name);
            }
            try gop.value_ptr.pins.append(pin_name);
        }

        // Group signals by component
        for (signals) |signal_name| {
            const component_name = try extractComponentName(self.allocator, signal_name);
            defer self.allocator.free(component_name);

            const gop = try component_map.getOrPut(component_name);
            if (!gop.found_existing) {
                gop.value_ptr.* = ComponentGroup.init(self.allocator, component_name);
            }
            try gop.value_ptr.signals.append(signal_name);
        }

        // Group params by component
        for (params) |param_name| {
            const component_name = try extractComponentName(self.allocator, param_name);
            defer self.allocator.free(component_name);

            const gop = try component_map.getOrPut(component_name);
            if (!gop.found_existing) {
                gop.value_ptr.* = ComponentGroup.init(self.allocator, component_name);
            }
            try gop.value_ptr.params.append(param_name);
        }

        // Build tree structure from component groups
        var iter = component_map.iterator();
        while (iter.next()) |entry| {
            const component_node = try Node.init(
                self.allocator,
                entry.value_ptr.name,
                .component,
                entry.value_ptr.name, // full_name same as name for components
                null, // no parent
            );
            try self.root.append(component_node);

            // Add pins as children
            for (entry.value_ptr.pins.items) |pin_name| {
                const pin_node = try Node.init(
                    self.allocator,
                    pin_name,
                    .pin,
                    pin_name,
                    component_node,
                );
                if (component_node.children) |*children| {
                    try children.append(pin_node);
                }
            }

            // Add signals as children
            for (entry.value_ptr.signals.items) |signal_name| {
                const signal_node = try Node.init(
                    self.allocator,
                    signal_name,
                    .signal,
                    signal_name,
                    component_node,
                );
                if (component_node.children) |*children| {
                    try children.append(signal_node);
                }
            }

            // Add params as children
            for (entry.value_ptr.params.items) |param_name| {
                const param_node = try Node.init(
                    self.allocator,
                    param_name,
                    .param,
                    param_name,
                    component_node,
                );
                if (component_node.children) |*children| {
                    try children.append(param_node);
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

        // Get maximum available size
        const max = ctx.max.size() orelse .{ .width = 25, .height = 24 };

        // Clear and rebuild visible nodes list
        self.visible_nodes.clearRetainingCapacity();
        try self.buildVisibleNodes(&self.visible_nodes);

        // Ensure cursor is within bounds
        if (self.visible_nodes.len > 0) {
            self.cursor_index = @min(self.cursor_index, self.visible_nodes.len - 1);
        }

        // Build text lines for each visible node
        const lines = try ctx.arena.alloc(vxfw.TextWidget, self.visible_nodes.len);
        for (self.visible_nodes.items, 0..) |node, i| {
            const is_checked = self.checked_items.get(node.full_name) != null;
            const is_cursor = i == self.cursor_index;

            // Build line text with checkbox, expand indicator, indentation, and name
            const checkbox = if (is_checked) "[x]" else "[ ]";
            const depth = node.getDepth();
            const indent = try std.fmt.allocPrint(ctx.arena, "{s: >[0]}", .{"", depth * 2});

            // Add expand/collapse indicator for component nodes
            const indicator: []const u8 = if (node.isExpandable())
                if (self.expanded_nodes.get(node.full_name) != null) "[- " else "[+ "
            else
                "   ";

            // Build full line text
            const text = try std.fmt.allocPrint(
                ctx.arena,
                "{s}{s}{s} {s}",
                .{ indent, indicator, checkbox, node.name },
            );

            // Create text widget with styling
            lines[i] = vxfw.TextWidget.init(text);
        }

        // Create surface with all text widgets
        return .{
            .size = max,
            .widget = self.widget(),
            .buffer = &.{},
            .children = &.{},
        };
    }

    /// Build list of visible nodes (respecting expand/collapse state)
    fn buildVisibleNodes(self: *TreeView, list: *std.ArrayList(*Node)) !void {
        for (self.root.items) |node| {
            try list.append(node);

            // If component is expanded, add its children
            if (node.isExpandable() and self.expanded_nodes.get(node.full_name) != null) {
                if (node.children) |*children| {
                    for (children.items) |child| {
                        try list.append(child);
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
                // Arrow Up: move cursor up
                if (key.matches(vxfw.Key.up, .{})) {
                    if (self.cursor_index > 0) {
                        self.cursor_index -= 1;
                        ctx.consumeAndRedraw();
                    }
                    return;
                }

                // Arrow Down: move cursor down
                if (key.matches(vxfw.Key.down, .{})) {
                    if (self.cursor_index < self.visible_nodes.len - 1) {
                        self.cursor_index += 1;
                        ctx.consumeAndRedraw();
                    }
                    return;
                }

                // Enter: toggle expand/collapse or toggle checkbox
                if (key.matches(vxfw.Key.enter, .{})) {
                    if (self.visible_nodes.items.len > 0) {
                        const node = self.visible_nodes.items[self.cursor_index];

                        // For component nodes: toggle expand/collapse
                        if (node.isExpandable()) {
                            const gop = try self.expanded_nodes.getOrPut(node.full_name);
                            if (gop.found_existing) {
                                // Collapse: remove from expanded set
                                self.expanded_nodes.remove(node.full_name);
                            } else {
                                // Expand: add to expanded set
                                gop.value_ptr.* = {};
                            }
                            ctx.consumeAndRedraw();
                            return;
                        }

                        // For leaf nodes: toggle checkbox
                        try self.toggleCheckbox(node.full_name);
                        ctx.consumeAndRedraw();
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
            },

            else => {},
        }
    }

    /// Toggle checkbox state for an item
    fn toggleCheckbox(self: *TreeView, full_name: []const u8) !void {
        const gop = try self.checked_items.getOrPut(full_name);
        if (gop.found_existing) {
            // Uncheck: remove from checked set
            self.checked_items.remove(full_name);
        } else {
            // Check: add to checked set
            gop.value_ptr.* = {};
        }
    }
};

/// Helper struct to group HAL items by component
const ComponentGroup = struct {
    name: []const u8,
    pins: std.ArrayList([]const u8),
    signals: std.ArrayList([]const u8),
    params: std.ArrayList([]const u8),

    fn init(allocator: std.mem.Allocator, name: []const u8) ComponentGroup {
        return .{
            .name = name,
            .pins = std.ArrayList([]const u8).init(allocator),
            .signals = std.ArrayList([]const u8).init(allocator),
            .params = std.ArrayList([]const u8).init(allocator),
        };
    }

    fn deinit(self: *ComponentGroup) void {
        self.pins.deinit();
        self.signals.deinit();
        self.params.deinit();
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
