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

// Manual declarations for HAL private (halpr_*) discovery functions
//
// These functions exist in liblinuxcnchal.so but are not declared in hal.h.
// They are used to discover pins, signals, and parameters by name.
//
// We use *opaque {} here because the actual hal_pin_t, hal_sig_t, hal_param_t
// types are opaque in ULAPI. The safe.zig wrapper will convert these to the
// properly-typed opaque pointers from types.zig.
//
// Source: LinuxCNC HAL source code (src/hal/hal_lib.c)
// Documentation: https://linuxcnc.org/docs/html/hal/HAL_Introduction.html

pub extern "c" fn halpr_find_pin_by_name(name: ?[*:0]const u8) ?*opaque {};
pub extern "c" fn halpr_find_sig_by_name(name: ?[*:0]const u8) ?*opaque {};
pub extern "c" fn halpr_find_param_by_name(name: ?[*:0]const u8) ?*opaque {};

// Additional discovery functions (available if needed)
pub extern "c" fn halpr_find_pin_by_owner(comp_id: c_int) ?*opaque {};
pub extern "c" fn halpr_find_sig_by_owner(comp_id: c_int) ?*opaque {};
pub extern "c" fn halpr_find_param_by_owner(comp_id: c_int) ?*opaque {};
