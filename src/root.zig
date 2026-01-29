const std = @import("std");

// Import safe HAL wrapper functions
const safe = @import("ffi/safe.zig");

pub fn main() !void {
    std.debug.print("haltune: HAL TUI for LinuxCNC\n", .{});

    // Initialize HAL component
    const comp_id = safe.halInit("haltune") catch |err| {
        std.debug.print("Failed to initialize HAL component: {}\n", .{err});
        return err;
    };
    std.debug.print("HAL component 'haltune' initialized (ID: {})\n", .{comp_id});

    // Ensure cleanup happens even if later code fails
    defer safe.halExit(comp_id);

    // Mark component as ready
    safe.halReady(comp_id) catch |err| {
        std.debug.print("Failed to mark HAL component as ready: {}\n", .{err});
        return err;
    };
    std.debug.print("HAL component 'haltune' ready for operation\n", .{});

    // TODO: In future phases, add pin/signal operations here
    // For now, just verify the FFI connection works

    std.debug.print("haltune exiting cleanly\n", .{});
}
