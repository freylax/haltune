#!/usr/bin/env zig
// Test HAL initialization to debug EINTR issue
// Run: LD_LIBRARY_PATH=/usr/lib zig run test_hal_init.zig

const std = @import("std");
const c = @cImport({
    @cDefine("ULAPI", "");
    @cInclude("hal.h");
});

pub fn main() !void {
    std.debug.print("Testing HAL initialization...\n", .{});
    std.debug.print("HAL library: hal_init\n", .{});

    // Check if /dev/shm exists
    {
        const shm_dir = std.fs.openDirAbsolute("/dev/shm", .{}) catch |err| {
            std.debug.print("ERROR: Cannot open /dev/shm: {}\n", .{err});
            return err;
        };
        defer shm_dir.close();

        std.debug.print("✓ /dev/shm is accessible\n", .{});

        // List files in /dev/shm
        var iter = shm_dir.iterate(null, ".");
        var hal_files_found = false;
        while (try iter.next()) |entry| {
            if (std.mem.indexOf(u8, entry.name, "hal") != null) {
                std.debug.print("  Found: {s}\n", .{entry.name});
                hal_files_found = true;
            }
        }

        if (!hal_files_found) {
            std.debug.print("  WARNING: No HAL shared memory files found\n", .{});
        }
    }

    // Check ulimit
    {
        const result = std.process.Child.run(.{
            .allocator = std.heap.page_allocator,
            .argv = &.{ "/bin/sh", "-c", "ulimit -l" },
        }) catch |err| {
            std.debug.print("WARNING: Cannot check ulimit: {}\n", .{err});
            null
        };

        if (result) |r| {
            std.debug.print("Locked memory limit (ulimit -l): {s}\n", .{r.stdout});
        }
    }

    // Try to initialize HAL
    std.debug.print("\nCalling hal_init(\"haltune-test\")...\n", .{});

    const comp_id = c.hal_init("haltune-test");
    if (comp_id < 0) {
        std.debug.print("✗ hal_init failed with code: {}\n", .{comp_id});
        const errno = std.os.errno(@intFromEnum(std.os.errno(-1)));
        std.debug.print("  errno: {} ({})\n", .{ errno, @intFromEnum(errno) });
        return error.HalInitFailed;
    }

    std.debug.print("✓ hal_init succeeded, component ID: {}\n", .{comp_id});

    // Try hal_ready
    std.debug.print("Calling hal_ready()...\n", .{});
    const ready_result = c.hal_ready(comp_id);
    if (ready_result != 0) {
        std.debug.print("✗ hal_ready failed with code: {}\n", .{ready_result});
        c.hal_exit(comp_id);
        return error.HalReadyFailed;
    }

    std.debug.print("✓ hal_ready succeeded\n", .{});

    // Clean up
    std.debug.print("Calling hal_exit()...\n", .{});
    c.hal_exit(comp_id);
    std.debug.print("✓ hal_exit succeeded\n", .{});

    std.debug.print("\nAll HAL initialization tests PASSED\n", .{});
}
