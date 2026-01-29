// Signal creation dialog widget
//
// This module provides SignalDialog, a multi-step modal dialog for creating
// HAL signals and linking pins. The dialog guides users through:
// 1. Signal name input (with validation)
// 2. Signal type selection (BIT/FLOAT/S32/U32)
// 3. Pin selection (multi-select from matching type pins)
// 4. Confirmation and creation
//
// Design principles:
// - Modal overlay using vxfw SubSurface
// - Step-by-step wizard with clear navigation
// - Input validation with helpful error messages
// - Memory-safe ArrayList/StringHashMap management
// - FFI integration for signal creation and pin linking

const std = @import("std");
const vxfw = @import("vaxis").vxfw;
const StateStore = @import("../../state/cache.zig").StateStore;
const HalValue = @import("../../state/cache.zig").HalValue;
const hal_type_t = @import("../../ffi/types.zig").hal_type_t;
const ffi = @import("../../ffi/safe.zig");

/// Dialog step enumeration
pub const DialogStep = enum(u8) {
    input_name = 1,
    select_type = 2,
    select_pins = 3,
    confirm = 4,
};

/// Signal creation dialog widget
pub const SignalDialog = struct {
    allocator: std.mem.Allocator,
    store: *StateStore,

    // Dialog state
    visible: bool = false,
    current_step: DialogStep = .input_name,

    // Step 1: Signal name input
    signal_name: std.ArrayList(u8),

    // Step 2: Signal type selection
    signal_type: hal_type_t = .HAL_BIT,
    type_index: usize = 0, // Index into TYPES array

    // Step 3: Pin selection
    available_pins: std.ArrayList([]const u8),
    selected_pins: std.StringHashMap(void),
    pin_cursor: usize = 0,

    // Step 4: Confirmation
    error_message: ?[]const u8 = null,

    // Available types for selection (in display order)
    const TYPES = [_]hal_type_t{
        .HAL_BIT,
        .HAL_FLOAT,
        .HAL_S32,
        .HAL_U32,
    };

    const TYPE_NAMES = [_][]const u8{
        "BIT    (boolean)",
        "FLOAT  (decimal)",
        "S32    (signed integer)",
        "U32    (unsigned integer)",
    };

    /// Initialize dialog
    pub fn init(allocator: std.mem.Allocator, store: *StateStore) SignalDialog {
        return .{
            .allocator = allocator,
            .store = store,
            .signal_name = std.ArrayList(u8).init(allocator),
            .available_pins = std.ArrayList([]const u8).init(allocator),
            .selected_pins = std.StringHashMap(void).init(allocator),
        };
    }

    /// Clean up dialog resources
    pub fn deinit(self: *SignalDialog) void {
        self.signal_name.deinit();
        for (self.available_pins.items) |pin| {
            self.allocator.free(pin);
        }
        self.available_pins.deinit();
        self.selected_pins.deinit();
        if (self.error_message) |msg| {
            self.allocator.free(msg);
        }
    }

    /// Open dialog for creating new signal
    pub fn open(self: *SignalDialog) !void {
        // Reset state
        self.visible = true;
        self.current_step = .input_name;
        self.signal_name.clearRetainingCapacity();
        self.type_index = 0;
        self.signal_type = .HAL_BIT;
        self.pin_cursor = 0;
        self.error_message = null;

        // Clear selected pins
        {
            var iter = self.selected_pins.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
        }
        self.selected_pins.clearRetainingCapacity();

        // Clear available pins
        for (self.available_pins.items) |pin| {
            self.allocator.free(pin);
        }
        self.available_pins.clearRetainingCapacity();
    }

    /// Close dialog and clean up state
    pub fn close(self: *SignalDialog) void {
        self.visible = false;

        // Free selected pin names
        {
            var iter = self.selected_pins.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
        }
        self.selected_pins.clearRetainingCapacity();

        // Free available pin names
        for (self.available_pins.items) |pin| {
            self.allocator.free(pin);
        }
        self.available_pins.clearRetainingCapacity();

        // Clear input buffer
        self.signal_name.clearRetainingCapacity();

        // Clear error
        if (self.error_message) |msg| {
            self.allocator.free(msg);
            self.error_message = null;
        }
    }

    /// Validate signal name
    fn validateSignalName(name: []const u8) !void {
        if (name.len == 0) return error.EmptyName;
        if (name.len > 41) return error.NameTooLong; // HAL_NAME_LEN
        for (name) |c| {
            if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '-' and c != '.') {
                return error.InvalidCharacter;
            }
        }
    }

    /// Set error message (allocates copy)
    fn setError(self: *SignalDialog, msg: []const u8) void {
        if (self.error_message) |old| {
            self.allocator.free(old);
        }
        self.error_message = self.allocator.dupe(u8, msg) catch null;
    }

    /// Handle key press in dialog
    pub fn handleKey(self: *SignalDialog, key: vxfw.Key) !bool {
        if (!self.visible) return false;

        switch (self.current_step) {
            .input_name => {
                // Handle alphanumeric input
                if (key == .Char) {
                    const c = key.Char;
                    if (std.ascii.isAlphanumeric(c) or c == '_' or c == '-' or c == '.') {
                        try self.signal_name.append(c);
                    }
                    return true;
                }
                // Backspace
                if (key.matchesChar(127, .{})) { // DEL/Backspace
                    if (self.signal_name.popOrNull()) |_| {
                        // Character removed
                    }
                    return true;
                }
                // Enter to advance
                if (key == .Enter) {
                    validateSignalName(self.signal_name.items) catch |err| {
                        self.setError(switch (err) {
                            error.EmptyName => "Name cannot be empty",
                            error.NameTooLong => "Name too long (max 41 chars)",
                            error.InvalidCharacter => "Use only letters, numbers, _, -, .",
                            else => "Invalid name",
                        });
                        return true;
                    };
                    self.error_message = null;
                    self.current_step = .select_type;
                    return true;
                }
                // Escape to cancel
                if (key == .Escape) {
                    self.close();
                    return true;
                }
            },
            .select_type => {
                // Arrow keys to cycle types
                if (key.matches('k', .{}) or key.matchesChar('A', .{ .ctrl = true })) {
                    // Up arrow (Ctrl+A or 'k')
                    if (self.type_index == 0) {
                        self.type_index = TYPES.len - 1;
                    } else {
                        self.type_index -= 1;
                    }
                    self.signal_type = TYPES[self.type_index];
                    return true;
                }
                if (key.matches('j', .{}) or key.matchesChar('B', .{ .ctrl = true })) {
                    // Down arrow (Ctrl+B or 'j')
                    self.type_index = (self.type_index + 1) % TYPES.len;
                    self.signal_type = TYPES[self.type_index];
                    return true;
                }
                // Enter to advance
                if (key == .Enter) {
                    // Load available pins of this type
                    try self.loadAvailablePins();
                    self.current_step = .select_pins;
                    return true;
                }
                // Escape to cancel
                if (key == .Escape) {
                    self.close();
                    return true;
                }
            },
            .select_pins => {
                const pin_count = self.available_pins.items.len;

                // Arrow keys to navigate
                if (key.matches('k', .{}) or key.matchesChar('A', .{ .ctrl = true })) {
                    // Up arrow
                    if (self.pin_cursor > 0) self.pin_cursor -= 1;
                    return true;
                }
                if (key.matches('j', .{}) or key.matchesChar('B', .{ .ctrl = true })) {
                    // Down arrow
                    if (self.pin_cursor + 1 < pin_count) self.pin_cursor += 1;
                    return true;
                }

                // Space to toggle selection
                if (key == .Space) {
                    if (pin_count > 0) {
                        const pin = self.available_pins.items[self.pin_cursor];
                        if (self.selected_pins.get(pin)) |_| {
                            // Deselect
                            _ = self.selected_pins.remove(pin);
                        } else {
                            // Select (store copy of key)
                            const pin_copy = try self.allocator.dupe(u8, pin);
                            try self.selected_pins.put(pin_copy, {});
                        }
                    }
                    return true;
                }

                // Enter to advance (must have at least one pin selected)
                if (key == .Enter) {
                    if (self.selected_pins.count() == 0) {
                        self.setError("Select at least one pin");
                        return true;
                    }
                    self.error_message = null;
                    self.current_step = .confirm;
                    return true;
                }

                // Escape to cancel
                if (key == .Escape) {
                    self.close();
                    return true;
                }
            },
            .confirm => {
                // 'y' to create signal
                if (key.matchesChar('y', .{})) {
                    self.error_message = null;
                    self.createSignal() catch |err| {
                        self.setError(switch (err) {
                            error.InitFailed => "Failed: Signal may already exist",
                            error.LinkFailed => "Failed: Pin link error (wrong type?)",
                            error.OutOfMemory => "Failed: Out of memory",
                            else => "Failed: Unknown error",
                        });
                        return true;
                    };
                    self.close();
                    return true;
                }
                // 'n' or Escape to cancel
                if (key.matchesChar('n', .{}) or key == .Escape) {
                    self.close();
                    return true;
                }
            },
        }
        return true;
    }

    /// Load pins that match selected signal type
    fn loadAvailablePins(self: *SignalDialog) !void {
        // Clear previous
        for (self.available_pins.items) |pin| {
            self.allocator.free(pin);
        }
        self.available_pins.clearRetainingCapacity();

        // Get all pin names
        const pin_names = try self.store.listPins(self.allocator);
        defer self.allocator.free(pin_names);

        // Filter by matching type
        for (pin_names) |pin_name| {
            const pin_value = self.store.getPin(pin_name) catch continue;
            const pin_matches = switch (self.signal_type) {
                .HAL_BIT => pin_value == .bit,
                .HAL_FLOAT => pin_value == .float,
                .HAL_S32 => pin_value == .s32,
                .HAL_U32 => pin_value == .u32,
            };
            if (pin_matches) {
                try self.available_pins.append(self.allocator.dupe(u8, pin_name));
            }
        }
    }

    /// Create signal and link selected pins
    fn createSignal(self: *SignalDialog) !void {
        // Null-terminate signal name
        const name_terminated = try self.allocator.dupeZ(u8, self.signal_name.items);
        defer self.allocator.free(name_terminated);

        // Create signal
        try ffi.halSignalNew(name_terminated, self.signal_type);

        // Link all selected pins
        var iter = self.selected_pins.iterator();
        while (iter.next()) |entry| {
            const pin_name = entry.key_ptr.*;
            const pin_terminated = try self.allocator.dupeZ(u8, pin_name);
            defer self.allocator.free(pin_terminated);

            try ffi.halLink(pin_terminated, name_terminated);
        }
    }

    // TODO: Add draw() in subsequent task
};
