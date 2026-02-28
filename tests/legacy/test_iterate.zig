const std = @import("std");
const c_import = @import("src/ffi/c.zig");
const c = c_import.c;
const halpr_find_pin_by_owner = c_import.halpr_find_pin_by_owner;

pub fn main() !void {
    std.debug.print("Testing HAL iteration...\n", .{});
    
    var count: usize = 0;
    var current_pin: ?*anyopaque = null;
    
    while (true) {
        const pin_ptr = halpr_find_pin_by_owner(null, current_pin);
        std.debug.print("Iteration {d}: pin_ptr = {*}\n", .{count, pin_ptr});
        if (pin_ptr == null) break;
        count += 1;
        if (count > 5) break; // Limit for testing
        current_pin = pin_ptr;
    }
    
    std.debug.print("Found {d} pins\n", .{count});
}
