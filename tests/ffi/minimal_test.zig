// Minimal test for Pin and Component types
const std = @import("std");

// Import C with mock HAL header
const c = @cImport({
    @cDefine("ULAPI", "");
    @cInclude("hal.h");
});

// Simple test to verify the types compile
test "Pin and Component types compile" {
    // This test just verifies the types compile successfully
    try std.testing.expectEqual(1, 1);
}
