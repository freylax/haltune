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
        };
    }

    /// Clean up DataTable resources
    pub fn deinit(self: *DataTable) void {
        self.items.deinit();
        self.* = undefined;
    }

    /// Set the items to display in the table
    ///
    /// This function parses HAL item names to determine their type and
    /// editability, then populates the items list.
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

        // Parse each item name and add to table
        for (item_names) |name| {
            const item = try self.parseItem(name);
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

    /// Event handler (no-op for now - editing handled in plan 03-04)
    fn typeErasedEventHandler(
        ptr: *anyopaque,
        ctx: *vxfw.EventContext,
        event: vxfw.Event,
    ) anyerror!void {
        _ = ptr;
        _ = ctx;
        _ = event;
        // No event handling for now - will add in plan 03-04
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
