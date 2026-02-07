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
const HalValue = @import("../../state/cache.zig").HalValue;
const safe = @import("../../ffi/safe.zig");
const vaxis = @import("vaxis");

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
    in,
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

    /// Owned copy of the name (kept for cleanup)
    /// null if name points to borrowed memory
    name_owner: ?[]const u8,

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

    /// Edit mode flag
    edit_mode: bool,

    /// Index of item being edited
    edit_item: ?usize,

    /// Edit buffer for in-place editing
    edit_buffer: std.ArrayList(u8),

    /// Pending edit items (waiting for refresh)
    pending_edits: std.StringHashMap(void),

    /// Error message to display at bottom of table
    error_message: ?[]const u8,

    /// Error message owner (allocated memory)
    error_message_owner: ?[]const u8,

    /// Error timeout timestamp (0 = no timeout set)
    error_timeout: u64,

    /// Cursor for selecting rows (for value editing)
    cursor_row: usize = 0,

    /// Table edit mode for in-place value editing
    table_edit_mode: bool = false,
    table_edit_row: ?usize = null,
    table_edit_buffer: std.ArrayList(u8),

    /// Initialize a new DataTable
    ///
    /// Parameters:
    ///   - allocator: Memory allocator
    ///   - store: StateStore for reading values
    ///
    /// Returns:
    ///   - Initialized DataTable with empty item list
    pub fn init(allocator: std.mem.Allocator, store: *StateStore) DataTable {
        // Initialize ArrayLists
        const items = std.ArrayList(TableItem).initCapacity(allocator, 0) catch unreachable;
        const component_buffer = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
        const edit_buffer = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
        const table_edit_buffer = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;

        return .{
            .allocator = allocator,
            .store = store,
            .items = items,
            // Column widths: Name 40%, Type 10%, Direction 10%, Value 30%
            // Remaining 10% for spacing/padding
            .column_widths = .{ 40, 10, 10, 30 },
            .filter_type = .all,
            .filter_component = "",
            .component_buffer = component_buffer,
            .component_filter_input = false,
            .edit_mode = false,
            .edit_item = null,
            .edit_buffer = edit_buffer,
            .pending_edits = std.StringHashMap(void).init(allocator),
            .error_message = null,
            .error_message_owner = null,
            .error_timeout = 0,
            .cursor_row = 0,
            .table_edit_mode = false,
            .table_edit_row = null,
            .table_edit_buffer = table_edit_buffer,
        };
    }

    /// Clean up DataTable resources
    pub fn deinit(self: *DataTable) void {
        // Free any owned names from items
        for (self.items.items) |*item| {
            if (item.name_owner) |name| {
                self.allocator.free(name);
            }
        }
        self.items.deinit(self.allocator);
        self.component_buffer.deinit(self.allocator);
        self.edit_buffer.deinit(self.allocator);
        self.table_edit_buffer.deinit(self.allocator);
        self.pending_edits.deinit();
        if (self.error_message_owner) |msg| {
            self.allocator.free(msg);
        }
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
        std.log.debug("setItems: received {} items", .{item_names.len});
        for (item_names, 0..) |name, i| {
            std.log.debug("  [{}] '{s}' ptr={*}", .{ i, name, name.ptr });
        }

        // Free any owned names from existing items
        for (self.items.items) |*item| {
            if (item.name_owner) |name| {
                self.allocator.free(name);
            }
        }
        self.items.clearRetainingCapacity();

        // Parse each item name and add to table (with filtering)
        for (item_names) |name| {
            // Duplicate the name so we own it (tree nodes may be freed)
            const name_copy = try self.allocator.dupe(u8, name);
            std.log.debug("  duplicating '{s}' -> '{s}' ptr={*}", .{ name, name_copy, name_copy.ptr });

            const item = try self.parseItem(name_copy);

            // Store the owned copy
            const item_with_owner = TableItem{
                .name = name_copy,
                .name_owner = name_copy,
                .item_type = item.item_type,
                .hal_type = item.hal_type,
                .direction = item.direction,
                .is_writable = item.is_writable,
            };

            // Apply type filter
            if (self.filter_type != .all) {
                const filter_hal_type: HalType = switch (self.filter_type) {
                    .all => unreachable, // handled above
                    .bit => .bit,
                    .float => .float,
                    .s32 => .s32,
                    .u32 => .u32,
                };
                if (item_with_owner.hal_type != filter_hal_type) {
                    self.allocator.free(name_copy);
                    continue;
                }
            }

            // Apply component filter (prefix match)
            if (self.filter_component.len > 0) {
                if (!std.mem.startsWith(u8, item_with_owner.name, self.filter_component)) {
                    self.allocator.free(name_copy);
                    continue;
                }
            }

            try self.items.append(self.allocator, item_with_owner);
            std.log.debug("  appended: name='{s}' name_ptr={*}", .{ item_with_owner.name, item_with_owner.name.ptr });
        }

        std.log.debug("setItems: now have {} items in table", .{self.items.items.len});
        for (self.items.items, 0..) |item, i| {
            std.log.debug("  [{}] name='{s}' name_ptr={*} owner_ptr={*}", .{ i, item.name, item.name.ptr, if (item.name_owner) |o| o.ptr else null });
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
                .in
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
                    std.log.warn("Item '{s}' not found in cache: {}", .{ name, err });
                    // Return a placeholder item (name_owner handled by caller)
                    return TableItem{
                        .name = name,
                        .name_owner = null,
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
            .name_owner = null, // Caller handles ownership
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

    /// Get HAL pin pointer by name
    fn getPinPointer(self: *DataTable, name: []const u8) !*const anyerror {
        const ffi = @import("../../ffi/safe.zig");
        // Allocate with null terminator for C API
        const name_c = try self.allocator.alloc(u8, name.len + 1);
        defer self.allocator.free(name_c);
        @memcpy(name_c[0..name.len], name);
        name_c[name.len] = 0;

        const pin_ptr = ffi.halprFindPinByName(@ptrCast(name_c)) orelse return error.PinNotFound;
        return @ptrCast(@alignCast(pin_ptr));
    }

    /// Get HAL param pointer by name
    fn getParamPointer(self: *DataTable, name: []const u8) !*const anyerror {
        const ffi = @import("../../ffi/safe.zig");
        // Allocate with null terminator for C API
        const name_c = try self.allocator.alloc(u8, name.len + 1);
        defer self.allocator.free(name_c);
        @memcpy(name_c[0..name.len], name);
        name_c[name.len] = 0;

        const param_ptr = ffi.halprFindParamByName(@ptrCast(name_c)) orelse return error.ParamNotFound;
        return @ptrCast(@alignCast(param_ptr));
    }

    /// Write value to HAL item
    fn writeValue(self: *DataTable, item: TableItem, value: HalValue) !void {
        switch (item.item_type) {
            .pin => {
                const pin_ptr = self.getPinPointer(item.name) catch {
                    // Pin not in HAL - this is a cache-only pin (test data)
                    // Just update cache, don't fail the edit
                    std.log.info("Pin '{s}' not in HAL, updating cache only", .{item.name});
                    return;
                };
                switch (value) {
                    .bit => |v| try safe.pinBitSet(@ptrCast(@alignCast(@constCast(pin_ptr))), v),
                    .float => |v| try safe.pinFloatSet(@ptrCast(@alignCast(@constCast(pin_ptr))), v),
                    .s32 => |v| try safe.pinS32Set(@ptrCast(@alignCast(@constCast(pin_ptr))), v),
                    .u32 => |v| try safe.pinU32Set(@ptrCast(@alignCast(@constCast(pin_ptr))), v),
                }
            },
            .param => {
                const param_ptr = try self.getParamPointer(item.name);
                switch (value) {
                    .bit => |v| try safe.setParamBit(@ptrCast(@alignCast(@constCast(param_ptr))), v),
                    .float => |v| try safe.setParamFloat(@ptrCast(@alignCast(@constCast(param_ptr))), v),
                    .s32 => |v| try safe.setParamS32(@ptrCast(@alignCast(@constCast(param_ptr))), v),
                    .u32 => |v| try safe.setParamU32(@ptrCast(@alignCast(@constCast(param_ptr))), v),
                }
            },
            .signal => {
                return error.ReadOnly; // Signals are read-only
            },
        }
    }

    /// Set an error message to display
    /// Error message will auto-clear after 5 seconds
    fn setError(self: *DataTable, msg: []const u8) !void {
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
    fn clearError(self: *DataTable) void {
        if (self.error_message_owner) |msg| {
            self.allocator.free(msg);
        }
        self.error_message_owner = null;
        self.error_message = null;
        self.error_timeout = 0;
    }

    /// Check if error timeout has expired and clear if so
    fn checkErrorTimeout(self: *DataTable) bool {
        if (self.error_timeout == 0) return false;

        const now = std.time.milliTimestamp();
        if (now >= self.error_timeout) {
            self.clearError();
            return true;
        }
        return false;
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
                // Check error timeout before handling key press
                if (self.checkErrorTimeout()) {
                    ctx.consumeAndRedraw();
                }

                // Component filter input mode handling
                if (self.component_filter_input) {
                    // Escape: exit component filter mode and clear
                    if (key.matches(vaxis.Key.escape, .{})) {
                        self.component_filter_input = false;
                        self.component_buffer.clearRetainingCapacity();
                        self.filter_component = "";
                        ctx.consumeAndRedraw();
                        return;
                    }

                    // Enter: apply component filter and exit input mode
                    if (key.matches(vaxis.Key.enter, .{})) {
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
                        try self.component_buffer.append(self.allocator, new_char);
                        self.filter_component = self.component_buffer.items;
                        ctx.consumeAndRedraw();
                        return;
                    }

                    return; // Ignore other keys in component filter mode
                }

                // Table edit mode handling (new in-place editing)
                if (self.table_edit_mode) {
                    // Escape: cancel edit
                    if (key.matches(vaxis.Key.escape, .{})) {
                        self.table_edit_mode = false;
                        self.table_edit_row = null;
                        self.table_edit_buffer.clearRetainingCapacity();
                        ctx.consumeAndRedraw();
                        return;
                    }

                    // Enter: confirm edit
                    if (key.matches(vaxis.Key.enter, .{})) {
                        if (self.table_edit_row) |row_idx| {
                            if (row_idx < self.items.items.len) {
                                const item = &self.items.items[row_idx];
                                const input = self.table_edit_buffer.items;

                                // Get original value to determine type
                                const orig_value = blk: {
                                    if (item.item_type == .pin) break :blk self.store.getPin(item.name) catch null;
                                    if (item.item_type == .signal) break :blk self.store.getSignal(item.name) catch null;
                                    if (item.item_type == .param) break :blk self.store.getParam(item.name) catch null;
                                    break :blk null;
                                };

                                if (orig_value) |v| {
                                    // Parse and validate input based on type
                                    const new_value: HalValue = switch (v) {
                                        .bit => |b| .{ .bit = b },
                                        .float => blk: {
                                            const parsed = std.fmt.parseFloat(f64, input) catch {
                                                self.setError("Invalid float") catch {};
                                                self.error_timeout = @intCast(std.time.nanoTimestamp() + 2_000_000_000);
                                                ctx.consumeAndRedraw();
                                                // Exit edit mode and return early from outer function
                                                self.table_edit_mode = false;
                                                self.table_edit_row = null;
                                                self.table_edit_buffer.clearRetainingCapacity();
                                                return;
                                            };
                                            break :blk .{ .float = parsed };
                                        },
                                        .s32 => blk: {
                                            const parsed = std.fmt.parseInt(i32, input, 10) catch {
                                                self.setError("Invalid integer") catch {};
                                                self.error_timeout = @intCast(std.time.nanoTimestamp() + 2_000_000_000);
                                                ctx.consumeAndRedraw();
                                                self.table_edit_mode = false;
                                                self.table_edit_row = null;
                                                self.table_edit_buffer.clearRetainingCapacity();
                                                return;
                                            };
                                            break :blk .{ .s32 = parsed };
                                        },
                                        .u32 => blk: {
                                            const parsed = std.fmt.parseInt(u32, input, 10) catch {
                                                self.setError("Invalid unsigned") catch {};
                                                self.error_timeout = @intCast(std.time.nanoTimestamp() + 2_000_000_000);
                                                ctx.consumeAndRedraw();
                                                self.table_edit_mode = false;
                                                self.table_edit_row = null;
                                                self.table_edit_buffer.clearRetainingCapacity();
                                                return;
                                            };
                                            break :blk .{ .u32 = parsed };
                                        },
                                    };

                                    // Write to HAL first (persists value to hardware)
                                    self.writeValue(item.*, new_value) catch |err| {
                                        std.log.err("FFI write failed for '{s}': {}", .{ item.name, err });
                                        self.setError("FFI write failed") catch {};
                                        self.error_timeout = @intCast(std.time.nanoTimestamp() + 2_000_000_000);
                                        // Exit edit mode but don't update store
                                        self.table_edit_mode = false;
                                        self.table_edit_row = null;
                                        self.table_edit_buffer.clearRetainingCapacity();
                                        ctx.consumeAndRedraw();
                                        return;
                                    };

                                    // Then update store cache
                                    if (item.item_type == .pin) {
                                        try self.store.updatePin(item.name, new_value);
                                    } else if (item.item_type == .signal) {
                                        try self.store.updateSignal(item.name, new_value);
                                    } else if (item.item_type == .param) {
                                        try self.store.updateParam(item.name, new_value);
                                    }
                                }
                            }

                            self.table_edit_mode = false;
                            self.table_edit_row = null;
                            self.table_edit_buffer.clearRetainingCapacity();
                            ctx.consumeAndRedraw();
                            return;
                        }
                    }

                    // Backspace: remove last character
                    if (key.codepoint == 127) {
                        if (self.table_edit_buffer.items.len > 0) {
                            _ = self.table_edit_buffer.pop();
                            ctx.consumeAndRedraw();
                        }
                        return;
                    }

                    // Type-specific character validation
                    if (key.codepoint >= 32 and key.codepoint < 127) {
                        const new_char = @as(u8, @intCast(key.codepoint));
                        // Same validation as tree view - allow digits, minus, decimal point
                        if (self.table_edit_row) |row_idx| {
                            if (row_idx < self.items.items.len) {
                                const item = &self.items.items[row_idx];
                                const allowed = switch (item.hal_type) {
                                    .float => blk: {
                                        // Allow: digits, minus (start only), decimal point (once)
                                        const result = if (new_char == '-' and self.table_edit_buffer.items.len == 0) true
                                            else if (new_char == '.' and std.mem.indexOfScalar(u8, self.table_edit_buffer.items, '.') == null) true
                                            else new_char >= '0' and new_char <= '9';
                                        break :blk result;
                                    },
                                    .s32 => blk: {
                                        // Allow: digits, minus (start only)
                                        const result = if (new_char == '-') self.table_edit_buffer.items.len == 0
                                            else new_char >= '0' and new_char <= '9';
                                        break :blk result;
                                    },
                                    .u32 => new_char >= '0' and new_char <= '9',
                                    .bit => false, // BIT values toggle, no edit mode
                                };

                                if (allowed) {
                                    try self.table_edit_buffer.append(self.allocator, new_char);
                                    ctx.consumeAndRedraw();
                                }
                            }
                        }
                        return;
                    }

                    return; // Ignore other keys in edit mode
                }

                // Cursor movement for row selection
                if (key.matches(vaxis.Key.up, .{})) {
                    if (self.cursor_row > 0) {
                        self.cursor_row -= 1;
                        ctx.consumeAndRedraw();
                    }
                    return;
                }

                if (key.matches(vaxis.Key.down, .{})) {
                    if (self.cursor_row + 1 < self.items.items.len) {
                        self.cursor_row += 1;
                        ctx.consumeAndRedraw();
                    }
                    return;
                }

                // "Enter": Edit value or toggle BIT at cursor
                if (key.matches(vaxis.Key.enter, .{})) {
                    if (self.items.items.len == 0 or self.cursor_row >= self.items.items.len) return;

                    const item = &self.items.items[self.cursor_row];

                    // Check if value is writable (input pins connected to signals are NOT writable)
                    const is_writable = blk: {
                        if (item.item_type == .pin) {
                            // Check if pin is connected to a signal
                            if (self.store.pin_links.get(item.name)) |_| {
                                break :blk false; // Connected pins get value from signal
                            }
                        }
                        break :blk item.is_writable; // Use TableItem's is_writable field
                    };

                    if (!is_writable) {
                        self.setError("Cannot edit - pin is connected to signal") catch {};
                        self.error_timeout = @intCast(std.time.nanoTimestamp() + 3_000_000_000); // 3 seconds
                        ctx.consumeAndRedraw();
                        return;
                    }

                    // Get current value to determine type
                    const value = blk: {
                        if (item.item_type == .pin) break :blk self.store.getPin(item.name) catch null;
                        if (item.item_type == .signal) break :blk self.store.getSignal(item.name) catch null;
                        if (item.item_type == .param) break :blk self.store.getParam(item.name) catch null;
                        break :blk null;
                    };

                    if (value) |v| {
                        switch (v) {
                            .bit => {
                                // BIT: Toggle value directly (no edit mode)
                                const new_value = !v.bit;
                                const new_hal_value = HalValue{ .bit = new_value };

                                // Write to HAL first (persists value to hardware)
                                self.writeValue(item.*, new_hal_value) catch |err| {
                                    std.log.err("FFI write failed for '{s}': {}", .{ item.name, err });
                                    self.setError("FFI write failed") catch {};
                                    self.error_timeout = @intCast(std.time.nanoTimestamp() + 2_000_000_000);
                                    ctx.consumeAndRedraw();
                                    return;
                                };

                                // Then update store cache
                                if (item.item_type == .pin) {
                                    try self.store.updatePin(item.name, new_hal_value);
                                } else if (item.item_type == .signal) {
                                    try self.store.updateSignal(item.name, new_hal_value);
                                } else if (item.item_type == .param) {
                                    try self.store.updateParam(item.name, new_hal_value);
                                }
                                ctx.consumeAndRedraw();
                                return;
                            },
                            .float, .s32, .u32 => {
                                // Numeric: Enter edit mode
                                self.table_edit_mode = true;
                                self.table_edit_row = self.cursor_row;
                                self.table_edit_buffer.clearRetainingCapacity();
                                // Pre-populate with current value
                                const current_str = formatHalValue(v, self.allocator) catch "";
                                defer self.allocator.free(current_str);
                                try self.table_edit_buffer.appendSlice(self.allocator, current_str);
                                ctx.consumeAndRedraw();
                                return;
                            },
                        }
                    }
                }

                // Legacy edit mode handling
                if (self.edit_mode) {
                    // Escape: cancel edit
                    if (key.matches(vaxis.Key.escape, .{})) {
                        self.edit_mode = false;
                        self.edit_item = null;
                        self.edit_buffer.clearRetainingCapacity();
                        ctx.consumeAndRedraw();
                        return;
                    }

                    // Enter: confirm edit
                    if (key.matches(vaxis.Key.enter, .{})) {
                        if (self.edit_item) |idx| {
                            const item = self.items.items[idx];
                            const input = self.edit_buffer.items;

                            // Parse and write value based on type
                            switch (item.hal_type) {
                                .bit => {
                                    // Accept "0", "1", "false", "true"
                                    const value = if (std.mem.eql(u8, input, "1") or
                                        std.mem.eql(u8, input, "true")) true else false;
                                    try self.writeValue(item, HalValue{ .bit = value });
                                },
                                .float => {
                                    const value = std.fmt.parseFloat(f64, input) catch {
                                        try self.setError("Invalid float: expected numeric value");
                                        ctx.consumeAndRedraw();
                                        return;
                                    };
                                    try self.writeValue(item, HalValue{ .float = value });
                                },
                                .s32 => {
                                    const value = std.fmt.parseInt(i32, input, 10) catch {
                                        try self.setError("Invalid integer: expected whole number");
                                        ctx.consumeAndRedraw();
                                        return;
                                    };
                                    try self.writeValue(item, HalValue{ .s32 = value });
                                },
                                .u32 => {
                                    const value = std.fmt.parseInt(u32, input, 10) catch {
                                        try self.setError("Invalid unsigned: expected positive whole number");
                                        ctx.consumeAndRedraw();
                                        return;
                                    };
                                    try self.writeValue(item, HalValue{ .u32 = value });
                                },
                            }

                            // Mark as pending and clear edit mode
                            try self.pending_edits.put(item.name, {});
                            self.edit_mode = false;
                            self.edit_item = null;
                            self.edit_buffer.clearRetainingCapacity();
                            ctx.consumeAndRedraw();
                            return;
                        }
                    }

                    // Backspace: remove last character
                    if (key.codepoint == 127) { // ASCII DEL (backspace)
                        if (self.edit_buffer.items.len > 0) {
                            _ = self.edit_buffer.pop();
                            ctx.consumeAndRedraw();
                        }
                        return;
                    }

                    // Regular character: add to edit buffer
                    if (key.codepoint >= 32 and key.codepoint < 127) {
                        const new_char = @as(u8, @intCast(key.codepoint));
                        try self.edit_buffer.append(self.allocator, new_char);
                        ctx.consumeAndRedraw();
                        return;
                    }

                    return; // Ignore other keys in edit mode
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
                if (key.matches(vaxis.Key.escape, .{})) {
                    self.filter_type = .all;
                    self.component_buffer.clearRetainingCapacity();
                    self.filter_component = "";
                    ctx.consumeAndRedraw();
                    return;
                }

                // Enter: Start editing or toggle bit value
                if (key.matches(vaxis.Key.enter, .{})) {
                    if (self.items.items.len > 0) {
                        // For simplicity, edit first item (TODO: add cursor selection)
                        const item = &self.items.items[0];

                        if (!item.is_writable) {
                            // Item is read-only - show error
                            try self.setError("Cannot edit read-only item");
                            ctx.consumeAndRedraw();
                            return;
                        }

                        if (item.hal_type == .bit) {
                            // Boolean: toggle value
                            const current_value = self.getItemValue(item.*) catch {
                                try self.setError("Failed to read value");
                                ctx.consumeAndRedraw();
                                return;
                            };
                            const new_value = switch (current_value) {
                                .bit => |v| !v,
                                else => {
                                    try self.setError("Type mismatch");
                                    ctx.consumeAndRedraw();
                                    return;
                                },
                            };
                            self.writeValue(item.*, HalValue{ .bit = new_value }) catch {
                                try self.setError("Write failed");
                                ctx.consumeAndRedraw();
                                return;
                            };
                            try self.pending_edits.put(item.name, {});
                            ctx.consumeAndRedraw();
                            return;
                        } else {
                            // Numeric: enter edit mode
                            self.edit_mode = true;
                            self.edit_item = 0;
                            self.edit_buffer.clearRetainingCapacity();
                            ctx.consumeAndRedraw();
                            return;
                        }
                    }
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
        const max = ctx.max.size();

        // Calculate column widths in characters
        const name_width = (max.width * self.column_widths[0]) / 100;
        const type_width = (max.width * self.column_widths[1]) / 100;
        const dir_width = (max.width * self.column_widths[2]) / 100;
        const value_width = (max.width * self.column_widths[3]) / 100;

        // Build list of text widgets for table content
        var widgets = std.ArrayList(vxfw.Widget).initCapacity(ctx.arena, 0) catch unreachable;
        defer widgets.deinit(ctx.arena);

        // Show filter indicators if filters are active
        if (self.filter_type != .all or self.filter_component.len > 0 or self.component_filter_input) {
            var filter_text = std.ArrayList(u8).initCapacity(ctx.arena, 0) catch unreachable;
            try filter_text.append(ctx.arena, '[');

            // Type filter
            try filter_text.appendSlice(ctx.arena, "Type: ");
            try filter_text.appendSlice(ctx.arena, self.filter_type.toString());

            // Component filter
            if (self.filter_component.len > 0) {
                try filter_text.appendSlice(ctx.arena, ", Comp: ");
                try filter_text.appendSlice(ctx.arena, self.filter_component);
            } else if (self.component_filter_input) {
                try filter_text.appendSlice(ctx.arena, ", Comp: ");
                try filter_text.appendSlice(ctx.arena, self.component_buffer.items);
            }

            try filter_text.append(ctx.arena, ']');

            const filter_style = vaxis.Style{ .bold = true, .fg = .{ .index = 3 } }; // Yellow
            const filter_text_widget = try ctx.arena.create(vxfw.Text);
            filter_text_widget.* = .{ .text = filter_text.items, .style = filter_style };
            try widgets.append(ctx.arena, filter_text_widget.widget());
        }

        // Row 1: Header
        const header_style = vaxis.Style{ .bold = true };
        // Build header string manually to avoid format specifier issues
        var header_buffer = std.ArrayList(u8).initCapacity(ctx.arena, 0) catch unreachable;
        try header_buffer.appendSlice(ctx.arena, "Name");
        {
            var i: usize = header_buffer.items.len;
            while (i < name_width) : (i += 1) {
                try header_buffer.append(ctx.arena, ' ');
            }
        }
        try header_buffer.appendSlice(ctx.arena, "Type");
        {
            var i: usize = header_buffer.items.len;
            while (i < name_width + type_width) : (i += 1) {
                try header_buffer.append(ctx.arena, ' ');
            }
        }
        try header_buffer.appendSlice(ctx.arena, "Dir");
        {
            var i: usize = header_buffer.items.len;
            while (i < name_width + type_width + dir_width) : (i += 1) {
                try header_buffer.append(ctx.arena, ' ');
            }
        }
        try header_buffer.appendSlice(ctx.arena, "Value");
        {
            const header_text = try ctx.arena.create(vxfw.Text);
            header_text.* = .{ .text = header_buffer.items, .style = header_style };
            try widgets.append(ctx.arena, header_text.widget());
        }

        // Row 2: Separator
        const total_width = name_width + type_width + dir_width + value_width;
        // Create separator string by repeating '-' character
        var sep_buffer = std.ArrayList(u8).initCapacity(ctx.arena, 0) catch unreachable;
        {
            var i: u16 = 0;
            while (i < total_width) : (i += 1) {
                try sep_buffer.append(ctx.arena, '-');
            }
        }
        const separator = sep_buffer.items;

        {
            const sep_text = try ctx.arena.create(vxfw.Text);
            sep_text.* = .{ .text = separator };
            try widgets.append(ctx.arena, sep_text.widget());
        }

        // Data rows
        for (self.items.items, 0..) |item, idx| {
            std.log.debug("draw row [{}]: name='{s}' name_ptr={*}", .{ idx, item.name, item.name.ptr });

            // Determine base row color
            const base_style = if (item.is_writable)
                vaxis.Style{ .fg = .{ .index = 2 } } // Green for editable
            else
                vaxis.Style{ .fg = .{ .index = 8 } }; // Dim gray for read-only

            // Highlight cursor row
            const is_cursor = (idx == self.cursor_row);

            // Highlight row being edited (legacy edit mode or table edit mode)
            const final_style = if (self.edit_mode and self.edit_item != null and self.edit_item.? == idx)
                vaxis.Style{ .fg = .{ .index = 2 }, .bold = true, .reverse = true } // Bold reverse for edit
            else if (self.table_edit_mode and self.table_edit_row != null and self.table_edit_row.? == idx)
                vaxis.Style{ .fg = base_style.fg, .reverse = true } // Reverse for table edit
            else if (is_cursor)
                vaxis.Style{ .fg = base_style.fg, .reverse = true } // Reverse for cursor
            else
                base_style;

            // Format item type
            const type_str = switch (item.hal_type) {
                .bit => "BIT",
                .float => "FLOAT",
                .s32 => "S32",
                .u32 => "U32",
            };

            // Format direction
            const dir_str = switch (item.direction) {
                .in => "IN",
                .out => "OUT",
                .io => "IO",
                .none => "",
            };

            // Get current value or edit buffer
            const value_str = blk: {
                // If table editing this row, show edit buffer
                if (self.table_edit_mode and self.table_edit_row != null and self.table_edit_row.? == idx) {
                    break :blk if (self.table_edit_buffer.items.len > 0)
                        self.table_edit_buffer.items
                    else
                        "_";
                }

                // If editing this item (legacy), show edit buffer
                if (self.edit_mode and self.edit_item != null and self.edit_item.? == idx) {
                    break :blk self.edit_buffer.items;
                }

                // If pending edit, show "..."
                if (self.pending_edits.get(item.name) != null) {
                    break :blk "...";
                }

                // Otherwise show current value from StateStore
                const value = self.getItemValue(item) catch |err| {
                    std.log.warn("Failed to get value for '{s}': {}", .{ item.name, err });
                    break :blk "ERR";
                };
                break :blk formatHalValue(value, ctx.arena) catch "ERR";
            };

            // Format row manually to avoid format specifier issues
            var row_buffer = std.ArrayList(u8).initCapacity(ctx.arena, 0) catch unreachable;

            // Add name
            try row_buffer.appendSlice(ctx.arena, item.name);
            {
                var i: usize = row_buffer.items.len;
                while (i < name_width) : (i += 1) {
                    try row_buffer.append(ctx.arena, ' ');
                }
            }

            // Add type
            try row_buffer.appendSlice(ctx.arena, type_str);
            {
                var i: usize = row_buffer.items.len;
                while (i < name_width + type_width) : (i += 1) {
                    try row_buffer.append(ctx.arena, ' ');
                }
            }

            // Add direction
            try row_buffer.appendSlice(ctx.arena, dir_str);
            {
                var i: usize = row_buffer.items.len;
                while (i < name_width + type_width + dir_width) : (i += 1) {
                    try row_buffer.append(ctx.arena, ' ');
                }
            }

            // Add value (right-aligned in value_width column)
            // Calculate current position and pad to right-align value
            const current_pos = row_buffer.items.len;
            const value_end_pos = name_width + type_width + dir_width + value_width;
            const value_width_needed = @min(ctx.stringWidth(value_str), value_width);
            const value_start_pos = value_end_pos -| value_width_needed;

            // Pad to start of value column
            {
                var i: usize = current_pos;
                while (i < value_start_pos) : (i += 1) {
                    try row_buffer.append(ctx.arena, ' ');
                }
            }

            // Add value string (use graphemeIterator for proper Unicode width)
            var char_iter = ctx.graphemeIterator(value_str);
            while (char_iter.next()) |char| {
                const grapheme = char.bytes(value_str);
                try row_buffer.appendSlice(ctx.arena, grapheme);
            }

            std.log.debug("  row_buffer='{s}'", .{row_buffer.items});
            // IMPORTANT: Allocate Text widget in arena so it persists
            // The widget stores a pointer to itself, so stack allocation would be invalidated
            const row_text = try ctx.arena.create(vxfw.Text);
            row_text.* = .{ .text = row_buffer.items, .style = final_style };
            try widgets.append(ctx.arena, row_text.widget());
        }

        // Show error message at bottom if present
        if (self.error_message) |msg| {
            const error_style = vaxis.Style{ .fg = .{ .index = 1 }, .bold = true }; // Red
            const error_text = try ctx.arena.create(vxfw.Text);
            error_text.* = .{ .text = msg, .style = error_style };
            try widgets.append(ctx.arena, error_text.widget());
        }

        // Create surface with widgets as children
        const children = try ctx.arena.alloc(vxfw.SubSurface, widgets.items.len);
        for (widgets.items, 0..) |w, i| {
            children[i] = .{
                .origin = .{ .row = @intCast(i), .col = 0 },
                .surface = try w.draw(ctx),
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

    /// Format a HAL value for display in the value column
    /// Uses compact formatting: ●/○ for BIT, 6-char precision for FLOAT/U32
    /// Matches tree_view.zig formatting for consistency
    fn formatHalValue(value: HalValue, allocator: std.mem.Allocator) ![]const u8 {
        return switch (value) {
            .bit => |v| if (v) "\xe2\x97\x8f" else "\xe2\x97\x8b", // UTF-8 for ●/○
            .float => |v| std.fmt.allocPrint(allocator, "{d:.6}", .{v}) catch "ERR",
            .s32 => |v| std.fmt.allocPrint(allocator, "{d}", .{v}) catch "ERR",
            .u32 => |v| std.fmt.allocPrint(allocator, "{d}", .{v}) catch "ERR",
        };
    }

    /// Get the currently selected (cursor) item name
    pub fn getCursorItemName(self: *const DataTable) ?[]const u8 {
        if (self.cursor_row < self.items.items.len) {
            return self.items.items[self.cursor_row].name;
        }
        return null;
    }

    /// Get the currently selected item type
    pub fn getCursorItemType(self: *const DataTable) ?ItemType {
        if (self.cursor_row < self.items.items.len) {
            return self.items.items[self.cursor_row].item_type;
        }
        return null;
    }

    /// Check if table is in edit mode
    pub fn isEditMode(self: *const DataTable) bool {
        return self.table_edit_mode;
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
