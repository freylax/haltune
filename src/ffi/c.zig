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

// Import opaque types from types.zig for use in extern declarations
const hal_pin_t = @import("types.zig").hal_pin_t;
const hal_sig_t = @import("types.zig").hal_sig_t;
const hal_param_t = @import("types.zig").hal_param_t;

// Manual declarations for HAL private (halpr_*) discovery functions
//
// These functions exist in liblinuxcnchal.so but are not declared in hal.h.
// They are used to discover pins, signals, and parameters by name.
//
// Source: LinuxCNC HAL source code (src/hal/hal_lib.c)
// Documentation: https://linuxcnc.org/docs/html/hal/HAL_Introduction.html

pub extern "c" fn halpr_find_pin_by_name(name: ?[*:0]const u8) ?*hal_pin_t;
pub extern "c" fn halpr_find_sig_by_name(name: ?[*:0]const u8) ?*hal_sig_t;
pub extern "c" fn halpr_find_param_by_name(name: ?[*:0]const u8) ?*hal_param_t;

// Additional discovery functions (available if needed)
// Note: hal_comp_t and hal_thread_t are also opaque in ULAPI
// extern "c" fn halpr_find_comp_by_name(name: ?[*:0]const u8) ?*opaque {};
// extern "c" fn halpr_find_comp_by_id(comp_id: c_int) ?*opaque {};
pub extern "c" fn halpr_find_pin_by_owner(comp_id: c_int) ?*hal_pin_t;
pub extern "c" fn halpr_find_sig_by_owner(comp_id: c_int) ?*hal_sig_t;
pub extern "c" fn halpr_find_param_by_owner(comp_id: c_int) ?*hal_param_t;
// extern "c" fn halpr_find_thread_by_name(name: ?[*:0]const u8) ?*opaque {};
