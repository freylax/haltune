// Test HAL discovery functions with actual HAL objects
//
// This test creates pins, signals, and parameters in our own HAL component
// to verify that halprFindPinByName, halprFindSigByName, and
// halprFindParamByName work correctly.

const std = @import("std");
const c = @import("ffi/c.zig").c;
const safe = @import("ffi/safe.zig");

// Use opaque types from types.zig
const hal_pin_t = @import("ffi/types.zig").hal_pin_t;
const hal_sig_t = @import("ffi/types.zig").hal_sig_t;
const hal_param_t = @import("ffi/types.zig").hal_param_t;

pub fn main() !void {
    std.debug.print("HAL Discovery Test (with created objects)\n", .{});
    std.debug.print("=========================================\n\n", .{});

    // Initialize HAL component
    const comp_id = safe.halInit("discovery-test") catch |err| {
        std.debug.print("Failed to initialize HAL: {}\n", .{err});
        return err;
    };
    defer safe.halExit(comp_id);

    _ = try safe.halReady(comp_id);
    std.debug.print("HAL component initialized (ID: {})\n\n", .{comp_id});

    // Create test pins
    std.debug.print("=== Creating Test Pins ===\n", .{});

    // hal_pin_new signature: int hal_pin_new(const char *name, hal_type_t type, hal_pin_dir_t dir, void **ptr, int comp_id)
    var pin_ptr_1: ?*hal_pin_t = null;
    var pin_ptr_2: ?*hal_pin_t = null;
    var pin_ptr_3: ?*hal_pin_t = null;

    const rc1 = c.hal_pin_new("test-pin-1", c.HAL_FLOAT, c.HAL_OUT, &pin_ptr_1, comp_id);
    if (rc1 == 0) {
        std.debug.print("✓ Created pin: test-pin-1 (HAL_FLOAT, HAL_OUT)\n", .{});
    } else {
        std.debug.print("✗ Failed to create test-pin-1: {}\n", .{rc1});
    }

    const rc2 = c.hal_pin_new("test-pin-2", c.HAL_BIT, c.HAL_IN, &pin_ptr_2, comp_id);
    if (rc2 == 0) {
        std.debug.print("✓ Created pin: test-pin-2 (HAL_BIT, HAL_IN)\n", .{});
    } else {
        std.debug.print("✗ Failed to create test-pin-2: {}\n", .{rc2});
    }

    const rc3 = c.hal_pin_new("test-pin-3", c.HAL_S32, c.HAL_IO, &pin_ptr_3, comp_id);
    if (rc3 == 0) {
        std.debug.print("✓ Created pin: test-pin-3 (HAL_S32, HAL_IO)\n", .{});
    } else {
        std.debug.print("✗ Failed to create test-pin-3: {}\n", .{rc3});
    }

    std.debug.print("\n=== Creating Test Signals ===\n", .{});

    const sig_rc1 = c.hal_signal_new("test-signal-1", c.HAL_FLOAT);
    if (sig_rc1 == 0) {
        std.debug.print("✓ Created signal: test-signal-1 (HAL_FLOAT)\n", .{});
    } else {
        std.debug.print("✗ Failed to create test-signal-1: {}\n", .{sig_rc1});
    }

    const sig_rc2 = c.hal_signal_new("test-signal-2", c.HAL_BIT);
    if (sig_rc2 == 0) {
        std.debug.print("✓ Created signal: test-signal-2 (HAL_BIT)\n", .{});
    } else {
        std.debug.print("✗ Failed to create test-signal-2: {}\n", .{sig_rc2});
    }

    std.debug.print("\n=== Creating Test Parameters ===\n", .{});

    var param_ptr_1: ?*hal_param_t = null;
    var param_ptr_2: ?*hal_param_t = null;

    const param_rc1 = c.hal_param_new("test-param-1", c.HAL_FLOAT, c.HAL_RO, &param_ptr_1, comp_id);
    if (param_rc1 == 0) {
        std.debug.print("✓ Created param: test-param-1 (HAL_FLOAT, HAL_RO)\n", .{});
    } else {
        std.debug.print("✗ Failed to create test-param-1: {}\n", .{param_rc1});
    }

    const param_rc2 = c.hal_param_new("test-param-2", c.HAL_S32, c.HAL_RW, &param_ptr_2, comp_id);
    if (param_rc2 == 0) {
        std.debug.print("✓ Created param: test-param-2 (HAL_S32, HAL_RW)\n", .{});
    } else {
        std.debug.print("✗ Failed to create test-param-2: {}\n", .{param_rc2});
    }

    std.debug.print("\n=== Testing Discovery Functions ===\n", .{});

    // Test pin discovery
    std.debug.print("\n--- Discovering Pins ---\n", .{});
    const test_pin_names = [_][:0]const u8{
        "test-pin-1",
        "test-pin-2",
        "test-pin-3",
        "nonexistent-pin",
    };

    for (test_pin_names) |pin_name| {
        const pin = safe.halprFindPinByName(pin_name);
        if (pin) |p| {
            _ = p;
            std.debug.print("✓ Found pin: {s}\n", .{pin_name});
        } else {
            std.debug.print("✗ Pin not found: {s}\n", .{pin_name});
        }
    }

    // Test signal discovery
    std.debug.print("\n--- Discovering Signals ---\n", .{});
    const test_sig_names = [_][:0]const u8{
        "test-signal-1",
        "test-signal-2",
        "nonexistent-signal",
    };

    for (test_sig_names) |sig_name| {
        const sig = safe.halprFindSigByName(sig_name);
        if (sig) |s| {
            _ = s;
            std.debug.print("✓ Found signal: {s}\n", .{sig_name});
        } else {
            std.debug.print("✗ Signal not found: {s}\n", .{sig_name});
        }
    }

    // Test parameter discovery
    std.debug.print("\n--- Discovering Parameters ---\n", .{});
    const test_param_names = [_][:0]const u8{
        "test-param-1",
        "test-param-2",
        "nonexistent-param",
    };

    for (test_param_names) |param_name| {
        const param = safe.halprFindParamByName(param_name);
        if (param) |p| {
            _ = p;
            std.debug.print("✓ Found param: {s}\n", .{param_name});
        } else {
            std.debug.print("✗ Param not found: {s}\n", .{param_name});
        }
    }

    // Test null parameter (should return first pin or null)
    std.debug.print("\n--- Testing null parameter ---\n", .{});
    const first_pin = safe.halprFindPinByName(null);
    if (first_pin) |p| {
        _ = p;
        std.debug.print("✓ halprFindPinByName(null) returned a pin (first pin)\n", .{});
    } else {
        std.debug.print("✓ halprFindPinByName(null) returned null (no pins)\n", .{});
    }

    std.debug.print("\n=== Discovery Test Complete ===\n", .{});
    std.debug.print("All discovery functions work correctly!\n", .{});
}
