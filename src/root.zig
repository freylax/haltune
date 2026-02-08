// Import TUI application
const tui_app = @import("tui/app.zig");
const std = @import("std");

pub fn main() !void {
    // Parse command-line arguments
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Check for --test-mode flag
    var test_mode: bool = false;
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--test-mode") or std.mem.eql(u8, arg, "-t")) {
            test_mode = true;
            break;
        }
    }

    // Run the TUI application
    // This initializes HAL, starts the refresh thread, and runs the Vaxis TUI
    try tui_app.main(test_mode);
}
