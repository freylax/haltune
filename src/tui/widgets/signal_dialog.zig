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
                // Handled in next task
            },
            .select_pins => {
                // Handled in next task
            },
            .confirm => {
                // Handled in next task
            },
        }
        return true;
    }

    // TODO: Add draw(), createSignal(), loadAvailablePins() in subsequent tasks
};
