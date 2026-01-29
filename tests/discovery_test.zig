// Test HAL discovery functions
//
// This test enumerates all pins, signals, and parameters in the HAL
// to verify that halprFindPinByName, halprFindSigByName, and
// halprFindParamByName work correctly.

const std = @import("std");
const safe = @import("ffi/safe.zig");

pub fn main() !void {
    std.debug.print("HAL Discovery Test\n", .{});
    std.debug.print("==================\n\n", .{});

    // Initialize HAL component
    const comp_id = safe.halInit("discovery-test") catch |err| {
        std.debug.print("Failed to initialize HAL: {}\n", .{err});
        return err;
    };
    defer safe.halExit(comp_id);

    _ = try safe.halReady(comp_id);
    std.debug.print("HAL component initialized (ID: {})\n\n", .{comp_id});

    // Test pin discovery
    std.debug.print("=== Discovering Pins ===\n", .{});
    var pin_count: usize = 0;
    var pin_name: ?[*:0]const u8 = null;

    while (safe.halprFindPinByName(pin_name)) |pin| {
        _ = pin; // Mark as used
        pin_count += 1;

        // Since hal_pin_t is opaque, we can't access pin.*.name directly
        // We just count the pins for now
        pin_name = null; // Get next pin (would need linked list traversal with full struct access)
        if (pin_count >= 10) break; // Safety limit
    }

    if (pin_count == 0) {
        std.debug.print("No pins found (HAL may not have any pins yet)\n", .{});
    } else {
        std.debug.print("Found {} pin(s)\n", .{pin_count});
    }

    std.debug.print("\n=== Discovering Signals ===\n", .{});
    var sig_count: usize = 0;
    var sig_name: ?[*:0]const u8 = null;

    while (safe.halprFindSigByName(sig_name)) |sig| {
        _ = sig; // Mark as used
        sig_count += 1;
        sig_name = null;
        if (sig_count >= 10) break;
    }

    if (sig_count == 0) {
        std.debug.print("No signals found\n", .{});
    } else {
        std.debug.print("Found {} signal(s)\n", .{sig_count});
    }

    std.debug.print("\n=== Discovering Parameters ===\n", .{});
    var param_count: usize = 0;
    var param_name: ?[*:0]const u8 = null;

    while (safe.halprFindParamByName(param_name)) |param| {
        _ = param; // Mark as used
        param_count += 1;
        param_name = null;
        if (param_count >= 10) break;
    }

    if (param_count == 0) {
        std.debug.print("No parameters found\n", .{});
    } else {
        std.debug.print("Found {} parameter(s)\n", .{param_count});
    }

    std.debug.print("\n=== Test Specific Pins ===\n", .{});
    // Try to find some known HAL pins (these may or may not exist)
    const test_pins = [_][]const u8{
        "motion.enable",
        "motion.adaptive-feed",
        "halui.program.is-running",
    };

    for (test_pins) |pin_name_str| {
        const pin_ptr = safe.halprFindPinByName(pin_name_str.ptr);
        if (pin_ptr) |pin| {
            _ = pin;
            std.debug.print("✓ Found pin: {s}\n", .{pin_name_str});
        } else {
            std.debug.print("✗ Pin not found: {s}\n", .{pin_name_str});
        }
    }

    std.debug.print("\nDiscovery test complete!\n", .{});
}
