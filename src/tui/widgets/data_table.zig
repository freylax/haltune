// Data table widget for displaying HAL item values
//
// This module provides DataTable, a table widget that displays selected HAL items
// (pins, signals, parameters) with their current values. The table updates in
// real-time via pubsub notifications from the RefreshThread.
//
// Design principles:
// - Display Name and Value in a simple format
// - Show only checked items from tree view
// - Read values from StateStore cache (fast, lock-free reads)
// - Use color to distinguish editable from read-only items
// - Share formatting and editing logic with TreeView via hal_value module

const std = @import("std");
const vxfw = @import("vaxis").vxfw;
const StateStore = @import("../../state/cache.zig").StateStore;
const HalValue = @import("../../state/cache.zig").HalValue;
const safe = @import("../../ffi/safe.zig");
const vaxis = @import("vaxis");
const hal_value = @import("hal_value.zig");

// Re-export ItemType from hal_value for compatibility
pub const ItemType = hal_value.ItemType;

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
/// Displays selected HAL items in a simple format:
/// - Name: HAL item name
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

    /// Cursor for selecting rows (for value editing)
    cursor_row: usize = 0,

    /// Table edit mode for in-place value editing
    table_edit_mode: bool = false,
    table_edit_row: ?usize = null,
    table_edit_buffer: std.ArrayList(u8),

    /// Width of name column (calculated from longest name)
    name_column_width: usize = 0,

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
        self.* = undefined;
    }

    /// Set the items to display in the table
    ///
    /// This function parses HAL item names to determine their type and
    /// editability, then populates the items list. Items are filtered
    /// by type and component if filters are active.
    ///
    /// Also calculates the name column width for alignment.
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

        // Reset name column width
        self.name_column_width = 0;

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

            // Update name column width (for alignment)
            self.name_column_width = @max(self.name_column_width, item_with_owner.name.len);
        }

        std.log.debug("setItems: now have {} items in table, name_column_width={}", .{ self.items.items.len, self.name_column_width });
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

            // Get direction from HAL by accessing hal_pin_t structure directly
            // This uses halpr_find_pin_by_name to get the pin structure,
            // then reads the dir field - just like halcmd does.
            direction = blk: {
                const name_z = try self.allocator.dupeZ(u8, name);
                defer self.allocator.free(name_z);

                if (safe.getPinDir(name_z)) |dir| switch (dir) {
                    .in => break :blk PinDirection.in,
                    .out => break :blk PinDirection.out,
                    .io => break :blk PinDirection.io,
                    .unspecified => break :blk PinDirection.none,
                } else |err| {
                    // Fallback to name-based detection if HAL access fails
                    std.log.warn("Failed to get pin direction for '{s}': {}, using name heuristic", .{ name, err });
                    if (std.mem.indexOf(u8, name, "-out") != null or
                        std.mem.indexOf(u8, name, "-io") != null)
                        break :blk PinDirection.out
                    else if (std.mem.indexOf(u8, name, "-in") != null)
                        break :blk PinDirection.in
                    else
                        break :blk PinDirection.none;
                }
            };
            is_writable = (direction == .in or direction == .io); // IN and IO pins are writable
        } else |_| {
            // Try signal
            if (self.store.getSignal(name)) |value| {
                item_type = .signal;
                hal_type = halTypeFromHalValue(value);
                direction = .none;
                is_writable = true; // Signals are writable (you can set their value)
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
    /// Write value to HAL item
    fn writeValue(self: *DataTable, item: TableItem, value: HalValue) !void {
        switch (item.item_type) {
            .pin => {
                // Create null-terminated name for HAL API
                const name_z = try self.allocator.dupeZ(u8, item.name);
                defer self.allocator.free(name_z);

                // Use setPinValueByName which uses hal_get_pin_value_by_name
                // to get the data pointer, then writes to it
                try safe.setPinValueByName(name_z, value);
            },
            .param => {
                // Create null-terminated name for HAL API
                const name_z = try self.allocator.dupeZ(u8, item.name);
                defer self.allocator.free(name_z);

                // Use setParamValueByName which uses hal_get_param_value_by_name
                // to get the data pointer, then writes to it
                try safe.setParamValueByName(name_z, value);
            },
            .signal => {
                return error.ReadOnly; // Signals are read-only
            },
        }
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
                                        .bit => |b| blk: {
                                            // Parse "0"/"1"/"true"/"false" (case-insensitive)
                                            const trimmed = std.mem.trim(u8, input, " \t");
                                            if (trimmed.len == 0) {
                                                // Empty input - keep current value
                                                break :blk .{ .bit = b };
                                            }
                                            // Convert to lowercase for comparison
                                            var lower_buf: [32]u8 = undefined;
                                            const lower_len = @min(trimmed.len, lower_buf.len);
                                            for (0..lower_len) |i| {
                                                lower_buf[i] = std.ascii.toLower(trimmed[i]);
                                            }
                                            const lower = lower_buf[0..lower_len];
                                            const value = if (std.mem.eql(u8, lower, "1") or
                                                std.mem.eql(u8, lower, "true") or
                                                std.mem.eql(u8, lower, "t")) true else if (std.mem.eql(u8, lower, "0") or
                                                std.mem.eql(u8, lower, "false") or
                                                std.mem.eql(u8, lower, "f")) false else {
                                                // Invalid input - exit edit mode
                                                ctx.consumeAndRedraw();
                                                self.table_edit_mode = false;
                                                self.table_edit_row = null;
                                                self.table_edit_buffer.clearRetainingCapacity();
                                                return;
                                            };
                                            break :blk .{ .bit = value };
                                        },
                                        .float => blk: {
                                            const parsed = std.fmt.parseFloat(f64, input) catch {
                                                // Invalid float - exit edit mode
                                                ctx.consumeAndRedraw();
                                                self.table_edit_mode = false;
                                                self.table_edit_row = null;
                                                self.table_edit_buffer.clearRetainingCapacity();
                                                return;
                                            };
                                            break :blk .{ .float = parsed };
                                        },
                                        .s32 => blk: {
                                            const parsed = std.fmt.parseInt(i32, input, 10) catch {
                                                // Invalid integer - exit edit mode
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
                                                // Invalid unsigned - exit edit mode
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
                                        const result = if (new_char == '-' and self.table_edit_buffer.items.len == 0) true else if (new_char == '.' and std.mem.indexOfScalar(u8, self.table_edit_buffer.items, '.') == null) true else new_char >= '0' and new_char <= '9';
                                        break :blk result;
                                    },
                                    .s32 => blk: {
                                        // Allow: digits, minus (start only)
                                        const result = if (new_char == '-') self.table_edit_buffer.items.len == 0 else new_char >= '0' and new_char <= '9';
                                        break :blk result;
                                    },
                                    .u32 => new_char >= '0' and new_char <= '9',
                                    .bit => blk: {
                                        // Allow: 0, 1, t, f, r, u, e, a, l, s (for true/false)
                                        const result = new_char == '0' or new_char == '1' or
                                            new_char == 't' or new_char == 'f' or
                                            new_char == 'r' or new_char == 'u' or
                                            new_char == 'e' or new_char == 'a' or
                                            new_char == 'l' or new_char == 's';
                                        break :blk result;
                                    },
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

                // Page Up: move cursor up by page size
                if (key.matches(vaxis.Key.page_up, .{})) {
                    const page_size = 10; // TODO: calculate based on visible rows
                    if (self.cursor_row > 0) {
                        self.cursor_row = if (self.cursor_row > page_size)
                            self.cursor_row - page_size
                        else
                            0;
                        ctx.consumeAndRedraw();
                    }
                    return;
                }

                // Page Down: move cursor down by page size
                if (key.matches(vaxis.Key.page_down, .{})) {
                    const page_size = 10; // TODO: calculate based on visible rows
                    if (self.cursor_row + 1 < self.items.items.len) {
                        self.cursor_row = @min(self.cursor_row + page_size, self.items.items.len - 1);
                        ctx.consumeAndRedraw();
                    }
                    return;
                }

                // "Enter": Edit value or toggle BIT at cursor
                if (key.matches(vaxis.Key.enter, .{})) {
                    if (self.items.items.len == 0 or self.cursor_row >= self.items.items.len) return;

                    const item = &self.items.items[self.cursor_row];

                    // Check if value is writable using shared logic
                    const is_writable = hal_value.isItemWritable(self.allocator, self.store, item.item_type, item.name);

                    if (!is_writable) {
                        // Not writable - silently ignore
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
                                const current_str = hal_value.formatHalValue(v, self.allocator) catch "";
                                defer self.allocator.free(current_str);
                                try self.table_edit_buffer.appendSlice(self.allocator, current_str);
                                ctx.consumeAndRedraw();
                                return;
                            },
                        }
                    }
                }

                // Legacy edit mode handling (no longer used, removed)
                // Table edit mode (handled earlier in this function)

                // Space to toggle BIT values (when not in edit mode)
                // Same logic as TreeView: check if pin is connected to signal first
                if (!self.table_edit_mode and !self.edit_mode and key.matches(' ', .{})) {
                    if (self.items.items.len == 0 or self.cursor_row >= self.items.items.len) return;

                    const item = &self.items.items[self.cursor_row];

                    // Check if value is writable using shared logic
                    const is_writable = hal_value.isItemWritable(self.allocator, self.store, item.item_type, item.name);

                    if (!is_writable) {
                        // Not writable - silently ignore
                        return;
                    }

                    // Only BIT values can be toggled
                    const value = blk: {
                        if (item.item_type == .pin) break :blk self.store.getPin(item.name) catch null;
                        if (item.item_type == .signal) break :blk self.store.getSignal(item.name) catch null;
                        if (item.item_type == .param) break :blk self.store.getParam(item.name) catch null;
                        break :blk null;
                    };

                    if (value) |v| {
                        switch (v) {
                            .bit => {
                                // Toggle BIT value (same as TreeView)
                                const new_value = !v.bit;
                                const new_hal_value = HalValue{ .bit = new_value };

                                // Write to HAL first (persists value to hardware)
                                self.writeValue(item.*, new_hal_value) catch |err| {
                                    std.log.err("FFI write failed for '{s}': {}", .{ item.name, err });
                                    return;
                                };

                                // Then update store cache (same as TreeView)
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
                            else => {
                                // Non-BIT values: silently ignore Space key
                                return;
                            },
                        }
                    }
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

        // Build list of text widgets for table content
        var widgets = std.ArrayList(vxfw.Widget).initCapacity(ctx.arena, 0) catch unreachable;
        defer widgets.deinit(ctx.arena);

        // Show filter indicator if type filter is active
        if (self.filter_type != .all) {
            var filter_text = std.ArrayList(u8).initCapacity(ctx.arena, 0) catch unreachable;
            try filter_text.appendSlice(ctx.arena, "[Type: ");
            try filter_text.appendSlice(ctx.arena, self.filter_type.toString());
            try filter_text.append(ctx.arena, ']');

            const filter_style = vaxis.Style{ .bold = true, .fg = .{ .index = 3 } }; // Yellow
            const filter_text_widget = try ctx.arena.create(vxfw.Text);
            filter_text_widget.* = .{ .text = filter_text.items, .style = filter_style };
            try widgets.append(ctx.arena, filter_text_widget.widget());
        }

        // Data rows - simplified: just Name and Value with aligned values
        for (self.items.items, 0..) |item, idx| {
            // Determine base row color
            const base_style = if (item.is_writable)
                vaxis.Style{ .fg = .{ .index = 2 } } // Green for editable
            else
                vaxis.Style{ .fg = .{ .index = 8 } }; // Dim gray for read-only

            // Highlight cursor row
            const is_cursor = (idx == self.cursor_row);

            // Highlight row being edited
            const final_style = if (self.table_edit_mode and self.table_edit_row != null and self.table_edit_row.? == idx)
                vaxis.Style{ .fg = base_style.fg, .reverse = true } // Reverse for table edit
            else if (is_cursor)
                vaxis.Style{ .fg = base_style.fg, .reverse = true } // Reverse for cursor
            else
                base_style;

            // Get current value or edit buffer
            const value_str = blk: {
                // If table editing this row, show edit buffer with cursor indicator
                if (self.table_edit_mode and self.table_edit_row != null and self.table_edit_row.? == idx) {
                    const buf = self.table_edit_buffer.items;
                    if (buf.len > 0) {
                        break :blk buf;
                    } else {
                        break :blk "_"; // Placeholder for empty buffer shows cursor position
                    }
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
                break :blk hal_value.formatHalValue(value, ctx.arena) catch "ERR";
            };

            // Format row: "name  value" (values aligned at name_column_width + 1 space)
            var row_buffer = std.ArrayList(u8).initCapacity(ctx.arena, 0) catch unreachable;

            // Add name
            try row_buffer.appendSlice(ctx.arena, item.name);

            // Add padding to align values (1 space after longest name)
            const padding = if (item.name.len < self.name_column_width)
                self.name_column_width - item.name.len + 1
            else
                1;
            var i: usize = 0;
            while (i < padding) : (i += 1) {
                try row_buffer.append(ctx.arena, ' ');
            }

            // Add value string
            var char_iter = ctx.graphemeIterator(value_str);
            while (char_iter.next()) |char| {
                const grapheme = char.bytes(value_str);
                try row_buffer.appendSlice(ctx.arena, grapheme);
            }

            // Create row text widget
            const row_text = try ctx.arena.create(vxfw.Text);
            row_text.* = .{ .text = row_buffer.items, .style = final_style };
            try widgets.append(ctx.arena, row_text.widget());
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
            .size = .{ .width = ctx.max.size().width, .height = @intCast(widgets.items.len) },
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
