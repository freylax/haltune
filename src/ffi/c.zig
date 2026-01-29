// Raw C imports from LinuxCNC HAL headers
//
// This file contains raw C declarations imported via @cImport.
// These are NOT safe for direct use - they expose C pointers, types, and
// functions exactly as they appear in the LinuxCNC HAL API.
//
// Safe Zig wrappers will be provided in higher-level modules (pins.zig, signals.zig, etc.)

pub const c = @cImport({
    // Define ULAPI for userspace HAL API (not RTAPI realtime)
    @cDefine("ULAPI", "");
    @cInclude("hal.h");
});
