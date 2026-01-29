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
