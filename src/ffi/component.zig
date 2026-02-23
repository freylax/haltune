// HAL Component type with lifecycle management
//
// This module provides a Component type that manages HAL component lifecycle.
// Components can create pins with cached data pointers for efficient access.
//
// Design principles:
// - Component manages hal_init(), hal_ready(), hal_exit() lifecycle
// - Pins created by component cache their data pointers
// - All pins owned by component are tracked and cleaned up on exit

const std = @import("std");

// Import C functions directly - this file needs the include path
pub const c = @cImport({
    @cDefine("ULAPI", "");
    @cInclude("hal.h");
});

// Import pin types from pin module (relative import)
pub const Pin = @import("pin.zig").Pin;
pub const PinType = @import("pin.zig").PinType;
pub const PinDir = @import("pin.zig").PinDir;

// Import errors from errors module (relative import)
pub const HalError = @import("errors.zig").HalError;

/// HAL Component with lifecycle management
///
/// A Component represents a HAL component with its own pins and parameters.
/// The component must be initialized, marked ready, and eventually exited.
pub const Component = struct {
    /// Component ID from hal_init()
    comp_id: c_int,
    /// Component name (owned by Component)
    name: []const u8,
    /// Whether component is ready (hal_ready was called)
    is_ready: bool = false,
    /// Pins owned by this component
    pins: std.ArrayList(Pin),
    /// Memory allocator
    allocator: std.mem.Allocator,

    /// Initialize a new HAL component
    ///
    /// This function calls hal_init() to create a new HAL component.
    /// The component must be marked ready before creating pins.
    ///
    /// Parameters:
    ///   - allocator: Memory allocator for component storage
    ///   - name: Component name (must be unique in HAL)
    ///
    /// Returns:
    ///   - Component on success
    ///   - error.InitFailed if HAL initialization fails
    pub fn init(allocator: std.mem.Allocator, name: []const u8) !Component {
        // Create null-terminated name for C API
        const name_z = try std.fmt.allocPrint(allocator, "{s}\x00", .{name});
        defer allocator.free(name_z);

        // Initialize HAL component
        const comp_id = c.hal_init(name_z.ptr);
        if (comp_id < 0) {
            // Try with numbered suffix
            var suffix: u32 = 1;
            while (suffix <= 100) : (suffix += 1) {
                const numbered_name = try std.fmt.allocPrint(allocator, "{s}{d}\x00", .{ name, suffix });
                defer allocator.free(numbered_name);

                const id = c.hal_init(numbered_name.ptr);
                if (id >= 0) {
                    // Success with modified name - need to keep it null-terminated
                    return Component{
                        .comp_id = id,
                        .name = numbered_name,
                        .pins = std.ArrayList(Pin).initCapacity(allocator, 0) catch unreachable,
                        .allocator = allocator,
                    };
                }
            }
            return HalError.InitFailed;
        }

        // Success - need to keep a null-terminated copy
        const owned_name = try allocator.alloc(u8, name.len + 1);
        @memcpy(owned_name[0..name.len], name);
        owned_name[name.len] = 0;

        return Component{
            .comp_id = comp_id,
            .name = owned_name,
            .pins = std.ArrayList(Pin).initCapacity(allocator, 0) catch unreachable,
            .allocator = allocator,
        };
    }

    /// Mark component as ready
    ///
    /// This function calls hal_ready() to mark the component as ready.
    /// After calling this, the component can create pins and parameters.
    ///
    /// Returns:
    ///   - void on success
    ///   - error.NotReady if component is in invalid state
    ///   - error.InitFailed if HAL initialization failed
    pub fn ready(self: *Component) !void {
        if (self.is_ready) return; // Already ready

        const rc = c.hal_ready(self.comp_id);
        if (rc != 0) {
            if (rc < 0)
                return HalError.InitFailed
            else
                return HalError.NotReady;
        }

        self.is_ready = true;
    }

    /// Exit the HAL component
    ///
    /// This function calls hal_exit() to clean up the component.
    /// All pins and parameters are automatically removed from HAL.
    /// After calling this, the component must not be used.
    pub fn exit(self: *Component) void {
        if (!self.is_ready) return; // Already exited or never ready

        // Clean up all pins
        for (self.pins.items) |*pin| {
            pin.deinit();
        }
        self.pins.deinit(self.allocator);

        // Exit HAL component
        _ = c.hal_exit(self.comp_id);
        self.is_ready = false;
    }

    /// Create a new pin in this component
    ///
    /// This function creates a new HAL pin and returns a Pin object
    /// with the data pointer cached for direct access.
    ///
    /// Parameters:
    ///   - name: Pin name (must be unique within component)
    ///   - pin_type: Type of pin (bit, float, s32, u32)
    ///   - dir: Pin direction (in, out, io)
    ///
    /// Returns:
    ///   - Pointer to Pin with cached data pointer
    ///   - error.InitFailed if pin creation fails
    ///   - error.NotReady if component is not ready
    pub fn newPin(self: *Component, name: []const u8, pin_type: PinType, dir: PinDir) !*Pin {
        if (!self.is_ready) return HalError.NotReady;

        // Duplicate pin name for ownership
        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);

        // Create null-terminated name for C API
        const name_z = try std.fmt.allocPrint(self.allocator, "{s}\x00", .{name});
        defer self.allocator.free(name_z);

        // Create pin based on type
        const pin = switch (pin_type) {
            .bit => try self.createBitPin(name_z, dir, owned_name),
            .float => try self.createFloatPin(name_z, dir, owned_name),
            .s32 => try self.createS32Pin(name_z, dir, owned_name),
            .u32 => try self.createU32Pin(name_z, dir, owned_name),
        };

        // Store pin in component's list
        try self.pins.append(self.allocator, pin);

        // Return pointer to stored pin
        return &self.pins.items[self.pins.items.len - 1];
    }

    /// Create a bit pin
    fn createBitPin(self: *Component, name_z: []const u8, dir: PinDir, owned_name: []const u8) !Pin {
        // Allocate memory for pin pointer from HAL shared memory
        const mem = c.hal_malloc(@sizeOf(?*volatile u8)) orelse return HalError.InitFailed;
        const pin_ptr_ptr: [*c]?*volatile u8 = @ptrCast(@alignCast(mem));

        // name_z is already null-terminated from allocPrint above
        const rc = c.hal_pin_bit_new(@ptrCast(name_z), @intFromEnum(dir), @ptrCast(pin_ptr_ptr), self.comp_id);
        if (rc != 0) return HalError.InitFailed;

        return Pin{
            .name = owned_name,
            .pin_type = .bit,
            .dir = dir,
            .data_ptr = .{ .bit = pin_ptr_ptr.*.? },
            .allocator = self.allocator,
        };
    }

    /// Create a float pin
    fn createFloatPin(self: *Component, name_z: []const u8, dir: PinDir, owned_name: []const u8) !Pin {
        const mem = c.hal_malloc(@sizeOf(?*volatile f64)) orelse return HalError.InitFailed;
        const pin_ptr_ptr: [*c]?*volatile f64 = @ptrCast(@alignCast(mem));

        const rc = c.hal_pin_float_new(@ptrCast(name_z), @intFromEnum(dir), @ptrCast(pin_ptr_ptr), self.comp_id);
        if (rc != 0) return HalError.InitFailed;

        return Pin{
            .name = owned_name,
            .pin_type = .float,
            .dir = dir,
            .data_ptr = .{ .float = pin_ptr_ptr.*.? },
            .allocator = self.allocator,
        };
    }

    /// Create an s32 pin
    fn createS32Pin(self: *Component, name_z: []const u8, dir: PinDir, owned_name: []const u8) !Pin {
        const mem = c.hal_malloc(@sizeOf(?*volatile i32)) orelse return HalError.InitFailed;
        const pin_ptr_ptr: [*c]?*volatile i32 = @ptrCast(@alignCast(mem));

        const rc = c.hal_pin_s32_new(@ptrCast(name_z), @intFromEnum(dir), @ptrCast(pin_ptr_ptr), self.comp_id);
        if (rc != 0) return HalError.InitFailed;

        return Pin{
            .name = owned_name,
            .pin_type = .s32,
            .dir = dir,
            .data_ptr = .{ .s32 = pin_ptr_ptr.*.? },
            .allocator = self.allocator,
        };
    }

    /// Create a u32 pin
    fn createU32Pin(self: *Component, name_z: []const u8, dir: PinDir, owned_name: []const u8) !Pin {
        const mem = c.hal_malloc(@sizeOf(?*volatile u32)) orelse return HalError.InitFailed;
        const pin_ptr_ptr: [*c]?*volatile u32 = @ptrCast(@alignCast(mem));

        const rc = c.hal_pin_u32_new(@ptrCast(name_z), @intFromEnum(dir), @ptrCast(pin_ptr_ptr), self.comp_id);
        if (rc != 0) return HalError.InitFailed;

        return Pin{
            .name = owned_name,
            .pin_type = .u32,
            .dir = dir,
            .data_ptr = .{ .u32 = pin_ptr_ptr.*.? },
            .allocator = self.allocator,
        };
    }

    /// Clean up component resources
    pub fn deinit(self: *Component) void {
        self.exit();
        self.allocator.free(self.name);
        self.* = undefined;
    }
};

// Compile-time tests
comptime {
    _ = Component.init;
    _ = Component.ready;
    _ = Component.exit;
    _ = Component.newPin;
    _ = Component.deinit;
}
