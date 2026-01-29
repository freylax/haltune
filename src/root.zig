const std = @import("std");

// Import C FFI declarations
// Note: @cImport is lazy - won't fail until we actually reference something
// This will be used in later phases when we wrap HAL functions
const c_hal = @import("ffi/c.zig");

pub fn main() !void {
    // Reference c_hal to verify the import works (even if we don't use it yet)
    _ = c_hal;

    std.debug.print("haltune FFI layer initialized\n", .{});
}
