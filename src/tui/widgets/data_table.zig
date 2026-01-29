// Data table widget for displaying HAL item values
//
// This module provides DataTable, a table widget that displays selected HAL items
// (pins, signals, parameters) with their current values. The table updates in
// real-time via pubsub notifications from the RefreshThread.
//
// Design principles:
// - Display Name, Type, Direction, and Current Value columns
// - Show only checked items from tree view
// - Read values from StateStore cache (fast, lock-free reads)
// - Use color to distinguish editable from read-only items

const std = @import("std");
const vxfw = @import("vaxis").vxfw;
const StateStore = @import("../../state/cache.zig").StateStore;
const HalValue = StateStore.HalValue;

/// HAL item type (pin, signal, or parameter)
pub const ItemType = enum {
    /// Pin (IN/OUT/IO)
    pin,
    /// Signal (wire connecting pins)
    signal,
    /// Parameter (configurable value)
    param,
};

/// HAL data type (bit, float, s32, u32)
pub const HalType = enum {
    /// Boolean/bit value
    bit,
    /// Floating-point value
    float,
    /// Signed 32-bit integer
    s32,
    /// Unsigned 32-bit integer
    u32,

    /// String representation
    pub fn toString(self: HalType) []const u8 {
        return switch (self) {
            .bit => "BIT",
            .float => "FLOAT",
            .s32 => "S32",
            .u32 => "U32",
        };
    }
};

/// Type filter for table items
pub const TypeFilter = enum {
    /// Show all types
    all,
    /// Show only bit items
    bit,
    /// Show only float items
    float,
    /// Show only s32 items
    s32,
    /// Show only u32 items
    u32,

    /// Get next filter in cycle
    pub fn next(self: TypeFilter) TypeFilter {
        return switch (self) {
            .all => .bit,
            .bit => .float,
            .float => .s32,
            .s32 => .u32,
            .u32 => .all,
        };
    }

    /// String representation
    pub fn toString(self: TypeFilter) []const u8 {
        return switch (self) {
            .all => "ALL",
            .bit => "BIT",
            .float => "FLOAT",
            .s32 => "S32",
            .u32 => "U32",
        };
    }
};

/// Pin direction (for pins only)
pub const PinDirection = enum {
    /// Input pin (read-only)
    @"in",
    /// Output pin (writable)
    out,
    /// Bidirectional pin (writable)
    io,
    /// Not a pin (for signals/params)
    none,
};

/// Table row representing a single HAL item
pub const TableItem = struct {
    /// HAL item name (e.g., "motion.digital-in-00")
    name: []const u8,

    /// Item type (pin, signal, or param)
    item_type: ItemType,

    /// HAL data type (bit, float, s32, u32)
    hal_type: HalType,

    /// Pin direction (for pins only)
    direction: PinDirection,

    /// Whether this item is writable (OUT/I/O pins, writable params)
    is_writable: bool,
};

/// Data table widget
///
/// Displays selected HAL items in a tabular format with columns:
/// - Name: HAL item name
/// - Type: Data type (BIT, FLOAT, S32, U32)
/// - Direction: Pin direction (IN, OUT, IO) or empty for signals/params
/// - Value: Current value from StateStore
///
/// The table uses color coding:
/// - Green: Editable items (writable params, OUT/I/O pins)
/// - Dim gray: Read-only items (IN pins, read-only params)
///
/// Filters:
/// - Type filter: Show only items of specific HAL type
/// - Component filter: Show only items from specific component
pub const DataTable = struct {
    /// Memory allocator for table data
    allocator: std.mem.Allocator,

    /// StateStore for reading current values
    store: *StateStore,

    /// Table rows (checked items from tree view)
    items: std.ArrayList(TableItem),

    /// Column widths (as percentages of total width)
    /// [Name, Type, Direction, Value]
    column_widths: [4]u16,

    /// Type filter (null = show all types)
    filter_type: TypeFilter,

    /// Component filter (empty = show all components)
    filter_component: []const u8,

    /// Component filter buffer
    component_buffer: std.ArrayList(u8),

    /// Whether component filter input mode is active
    component_filter_input: bool,

    /// Initialize a new DataTable
    ///
    /// Parameters:
    ///   - allocator: Memory allocator
    ///   - store: StateStore for reading values
    ///
    /// Returns:
    ///   - Initialized DataTable with empty item list
    pub fn init(allocator: std.mem.Allocator, store: *StateStore) DataTable {
        return .{
            .allocator = allocator,
            .store = store,
            .items = std.ArrayList(TableItem).init(allocator),
            // Column widths: Name 40%, Type 10%, Direction 10%, Value 30%
            // Remaining 10% for spacing/padding
            .column_widths = .{ 40, 10, 10, 30 },
            .filter_type = .all,
            .filter_component = "",
            .component_buffer = std.ArrayList(u8).init(allocator),
            .component_filter_input = false,
        };
    }

    /// Clean up DataTable resources
    pub fn deinit(self: *DataTable) void {
        self.items.deinit();
        self.component_buffer.deinit();
        self.* = undefined;
    }

    /// Set the items to display in the table
    ///
    /// This function parses HAL item names to determine their type and
    /// editability, then populates the items list. Items are filtered
    /// by type and component if filters are active.
    ///
    /// Parameters:
    ///   - item_names: Slice of HAL item names to display
    ///
    /// Returns:
    ///   - error.OutOfMemory if allocation fails
    ///
    /// Thread safety:
    ///   - Not thread-safe (call from TUI thread only)
    pub fn setItems(self: *DataTable, item_names: [][]const u8) !void {
        // Clear existing items
        self.items.clearRetainingCapacity();

        // Parse each item name and add to table (with filtering)
        for (item_names) |name| {
            const item = try self.parseItem(name);

            // Apply type filter
            if (self.filter_type != .all) {
                const filter_hal_type: HalType = switch (self.filter_type) {
                    .all => unreachable, // handled above
                    .bit => .bit,
                    .float => .float,
                    .s32 => .s32,
                    .u32 => .u32,
                };
                if (item.hal_type != filter_hal_type) continue;
            }

            // Apply component filter (prefix match)
            if (self.filter_component.len > 0) {
                if (!std.mem.startsWith(u8, item.name, self.filter_component)) continue;
            }

            try self.items.append(item);
        }
    }

    /// Parse a HAL item name to determine its properties
    ///
    /// This function uses heuristics based on naming patterns to determine
    /// item type and editability. For now, we assume:
    /// - All params are writable (will refine in future)
    /// - Pins with ".out" or ".io" in name are OUT/I/O
    /// - All other pins are IN (read-only)
    /// - Signals are read-only
    ///
    /// Parameters:
    ///   - name: HAL item name (e.g., "motion.digital-in-00")
    ///
    /// Returns:
    ///   - TableItem with parsed properties
    fn parseItem(self: *DataTable, name: []const u8) !TableItem {
        _ = self;

        // Default values
        var item_type: ItemType = .pin;
        var hal_type: HalType = .bit;
        var direction: PinDirection = .none;
        var is_writable: bool = false;

        // Try to get the item from StateStore to determine its type
        // Try pin first
        if (self.store.getPin(name)) |value| {
            item_type = .pin;
            hal_type = halTypeFromHalValue(value);
            // TODO: Determine direction from HAL (not available in cache yet)
            // For now, assume IN based on naming pattern
            direction = if (std.mem.indexOf(u8, name, "-out") != null or
                std.mem.indexOf(u8, name, "-io") != null)
                .out
            else if (std.mem.indexOf(u8, name, "-in") != null)
                .@"in"
            else
                .none;
            is_writable = (direction == .out or direction == .io);
        } else |_| {
            // Try signal
            if (self.store.getSignal(name)) |value| {
                item_type = .signal;
                hal_type = halTypeFromHalValue(value);
                direction = .none;
                is_writable = false; // Signals are read-only
            } else |_| {
                // Try param
                if (self.store.getParam(name)) |value| {
                    item_type = .param;
                    hal_type = halTypeFromHalValue(value);
                    direction = .none;
                    // TODO: Check if param is writable (not in cache yet)
                    // For now, assume all params are writable
                    is_writable = true;
                } else |err| {
                    // Item not found in any cache
                    std.log.warn("Item '{s}' not found in cache: {}", .{name, err});
                    // Return a placeholder item
                    return TableItem{
                        .name = name,
                        .item_type = .pin,
                        .hal_type = .bit,
                        .direction = .none,
                        .is_writable = false,
                    };
                }
            }
        }

        return TableItem{
            .name = name,
            .item_type = item_type,
            .hal_type = hal_type,
            .direction = direction,
            .is_writable = is_writable,
        };
    }

    /// Convert HalValue union to HalType enum
    fn halTypeFromHalValue(value: HalValue) HalType {
        return switch (value) {
            .bit => .bit,
            .float => .float,
            .s32 => .s32,
            .u32 => .u32,
        };
    }

    /// Return a vxfw.Widget for this DataTable
    pub fn widget(self: *DataTable) vxfw.Widget {
        return .{
            .userdata = self,
            .eventHandler = typeErasedEventHandler,
            .drawFn = typeErasedDrawFn,
        };
    }

    /// Event handler for keyboard input
    fn typeErasedEventHandler(
        ptr: *anyopaque,
        ctx: *vxfw.EventContext,
        event: vxfw.Event,
    ) anyerror!void {
        const self: *DataTable = @ptrCast(@alignCast(ptr));

        switch (event) {
            .key_press => |key| {
                // Component filter input mode handling
                if (self.component_filter_input) {
                    // Escape: exit component filter mode and clear
                    if (key.matches(vxfw.Key.escape, .{})) {
                        self.component_filter_input = false;
                        self.component_buffer.clearRetainingCapacity();
                        self.filter_component = "";
                        ctx.consumeAndRedraw();
                        return;
                    }

                    // Enter: apply component filter and exit input mode
                    if (key.matches(vxfw.Key.enter, .{})) {
                        self.component_filter_input = false;
                        self.filter_component = self.component_buffer.items;
                        ctx.consumeAndRedraw();
                        return;
                    }

                    // Backspace: remove last character
                    if (key.codepoint == 127) { // ASCII DEL (backspace)
                        if (self.component_buffer.items.len > 0) {
                            _ = self.component_buffer.pop();
                            self.filter_component = self.component_buffer.items;
                            ctx.consumeAndRedraw();
                        }
                        return;
                    }

                    // Regular character: add to component filter
                    if (key.codepoint >= 32 and key.codepoint < 127) {
                        const new_char = @as(u8, @intCast(key.codepoint));
                        try self.component_buffer.append(new_char);
                        self.filter_component = self.component_buffer.items;
                        ctx.consumeAndRedraw();
                        return;
                    }

                    return; // Ignore other keys in component filter mode
                }

                // Normal mode handling

                // "t": Cycle type filter
                if (key.matches('t', .{})) {
                    self.filter_type = self.filter_type.next();
                    ctx.consumeAndRedraw();
                    return;
                }

                // "c": Enter component filter mode
                if (key.matches('c', .{})) {
                    self.component_filter_input = true;
                    self.component_buffer.clearRetainingCapacity();
                    self.filter_component = "";
                    ctx.consumeAndRedraw();
                    return;
                }

                // Escape: Clear all filters
                if (key.matches(vxfw.Key.escape, .{})) {
                    self.filter_type = .all;
                    self.component_buffer.clearRetainingCapacity();
                    self.filter_component = "";
                    ctx.consumeAndRedraw();
                    return;
                }
            },
            else => {},
        }
    }

    /// Draw function - renders the data table
    fn typeErasedDrawFn(
        ptr: *anyopaque,
        ctx: vxfw.DrawContext,
    ) std.mem.Allocator.Error!vxfw.Surface {
        const self: *DataTable = @ptrCast(@alignCast(ptr));

        // Get available size
        const max = ctx.max.size() orelse .{ .width = 80, .height = 24 };

        // Calculate column widths in characters
        const name_width = (max.width * self.column_widths[0]) / 100;
        const type_width = (max.width * self.column_widths[1]) / 100;
        const dir_width = (max.width * self.column_widths[2]) / 100;
        const value_width = (max.width * self.column_widths[3]) / 100;

        // Build list of text widgets for table content
        var widgets = std.ArrayList(vxfw.Widget).init(ctx.arena);
        defer widgets.deinit();

        // Show filter indicators if filters are active
        if (self.filter_type != .all or self.filter_component.len > 0 or self.component_filter_input) {
            var filter_text = std.ArrayList(u8).init(ctx.arena);
            try filter_text.append('[');

            // Type filter
            try filter_text.appendSlice("Type: ");
            try filter_text.appendSlice(self.filter_type.toString());

            // Component filter
            if (self.filter_component.len > 0) {
                try filter_text.appendSlice(", Comp: ");
                try filter_text.appendSlice(self.filter_component);
            } else if (self.component_filter_input) {
                try filter_text.appendSlice(", Comp: ");
                try filter_text.appendSlice(self.component_buffer.items);
            }

            try filter_text.append(']');

            const filter_style = vxfw.Style{ .bold = true, .fg = .{ .index = 3 } }; // Yellow
            try widgets.append(vxfw.Text.asWidget(filter_text.items, .{ .style = filter_style }));
        }

        // Row 1: Header
        const header_style = vxfw.Style{ .bold = true };
        try widgets.append(vxfw.Text.asWidget(
            try std.fmt.allocPrint(ctx.arena, "{s:<{d}}{s:<{d}}{s:<{d}}{s:<{d}}", .{
                "Name", name_width,
                "Type", type_width,
                "Dir", dir_width,
                "Value", value_width,
            }),
            .{ .style = header_style },
        ));

        // Row 2: Separator
        const separator = try std.fmt.allocPrint(ctx.arena, "{s:<{d}}", .{
            "-" ** (name_width + type_width + dir_width + value_width),
            max.width,
        });
        try widgets.append(vxfw.Text.asWidget(separator, .{}));

        // Data rows
        for (self.items.items) |item| {
            // Determine row color
            const row_style = if (item.is_writable)
                vxfw.Style{ .fg = .{ .index = 2 } } // Green for editable
            else
                vxfw.Style{ .fg = .{ .index = 8 } }; // Dim gray for read-only

            // Format item type
            const type_str = switch (item.hal_type) {
                .bit => "BIT",
                .float => "FLOAT",
                .s32 => "S32",
                .u32 => "U32",
            };

            // Format direction
            const dir_str = switch (item.direction) {
                .@"in" => "IN",
                .out => "OUT",
                .io => "IO",
                .none => "",
            };

            // Get current value from StateStore
            const value_str = blk: {
                const value = self.getItemValue(item) catch |err| {
                    std.log.warn("Failed to get value for '{s}': {}", .{item.name, err});
                    break :blk "ERR";
                };
                break :blk formatHalValue(value, ctx.arena);
            };

            // Format row
            const row_text = try std.fmt.allocPrint(ctx.arena, "{s:<{d}}{s:<{d}}{s:<{d}}{s:<{d}}", .{
                item.name, name_width,
                type_str, type_width,
                dir_str, dir_width,
                value_str, value_width,
            });

            try widgets.append(vxfw.Text.asWidget(row_text, .{ .style = row_style }));
        }

        // Create surface with widgets as children
        const children = try ctx.arena.alloc(vxfw.SubSurface, widgets.items.len);
        for (widgets.items, 0..) |widget, i| {
            children[i] = .{
                .origin = .{ .row = @intCast(i), .col = 0 },
                .surface = try widget.draw(ctx),
            };
        }

        return .{
            .size = .{ .width = max.width, .height = @intCast(widgets.items.len) },
            .widget = self.widget(),
            .buffer = &.{},
            .children = children,
        };
    }

    /// Get current value for an item from StateStore
    fn getItemValue(self: *DataTable, item: TableItem) !HalValue {
        return switch (item.item_type) {
            .pin => self.store.getPin(item.name),
            .signal => self.store.getSignal(item.name),
            .param => self.store.getParam(item.name),
        };
    }

    /// Format a HalValue as a string
    fn formatHalValue(value: HalValue, allocator: std.mem.Allocator) []const u8 {
        return switch (value) {
            .bit => |v| if (v) "TRUE" else "FALSE",
            .float => |v| std.fmt.allocPrint(allocator, "{d:.2}", .{v}) catch "ERR",
            .s32 => |v| std.fmt.allocPrint(allocator, "{d}", .{v}) catch "ERR",
            .u32 => |v| std.fmt.allocPrint(allocator, "{d}", .{v}) catch "ERR",
        };
    }
};

// Compile-time tests to verify API surface
comptime {
    _ = DataTable.init;
    _ = DataTable.deinit;
    _ = DataTable.setItems;
    _ = ItemType;
    _ = HalType;
    _ = PinDirection;
    _ = TableItem;
}
