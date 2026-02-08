// Simple test for HAL discovery without TUI

const std = @import("std");
const discovery = @import("ffi/safe_discovery.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== HAL Discovery Test ===\n", .{});

    // List pins
    std.debug.print("\n--- Testing listPinNames ---\n", .{});
    {
        var pins = discovery.listPinNames(allocator) catch |err| {
            std.debug.print("Error listing pins: {}\n", .{err});
            return err;
        };
        defer {
            for (pins.items) |p| allocator.free(p);
            pins.deinit();
        }
        std.debug.print("Found {d} pins:\n", .{pins.items.len});
        for (pins.items) |pin| {
            std.debug.print("  - {s}\n", .{pin});
        }
    }

    // List params
    std.debug.print("\n--- Testing listParamNames ---\n", .{});
    {
        var params = discovery.listParamNames(allocator) catch |err| {
            std.debug.print("Error listing params: {}\n", .{err});
            return err;
        };
        defer {
            for (params.items) |p| allocator.free(p);
            params.deinit();
        }
        std.debug.print("Found {d} params:\n", .{params.items.len});
        for (params.items) |param| {
            std.debug.print("  - {s}\n", .{param});
        }
    }

    // List signals
    std.debug.print("\n--- Testing listSignalNames ---\n", .{});
    {
        var sigs = discovery.listSignalNames(allocator) catch |err| {
            std.debug.print("Error listing signals: {}\n", .{err});
            return err;
        };
        defer {
            for (sigs.items) |s| allocator.free(s);
            sigs.deinit();
        }
        std.debug.print("Found {d} signals:\n", .{sigs.items.len});
        for (sigs.items) |sig| {
            std.debug.print("  - {s}\n", .{sig});
        }
    }

    std.debug.print("\n=== Test Complete ===\n", .{});
}
