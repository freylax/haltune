// Import TUI application
const tui_app = @import("tui/app.zig");

pub fn main() !void {
    // Run the TUI application
    // This initializes HAL, starts the refresh thread, and runs the Vaxis TUI
    try tui_app.main();
}
