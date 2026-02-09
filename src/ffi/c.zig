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
// We use *anyopaque here because the actual hal_pin_t, hal_sig_t, hal_param_t
// types are opaque in ULAPI.
//
// Source: LinuxCNC HAL source code (src/hal/hal_lib.c)
// Documentation: https://linuxcnc.org/docs/html/hal/HAL_Introduction.html

pub extern "c" fn halpr_find_pin_by_name(name: ?[*:0]const u8) ?*anyopaque;
pub extern "c" fn halpr_find_sig_by_name(name: ?[*:0]const u8) ?*anyopaque;
pub extern "c" fn halpr_find_param_by_name(name: ?[*:0]const u8) ?*anyopaque;

// Additional discovery and iteration functions
// halpr_find_pin_by_owner: Find pins owned by a component (start=null for first, returns next)
// halpr_find_param_by_owner: Find params owned by a component
// halpr_find_pin_by_sig: Find pins linked to a signal (start=null for first)
// Note: No halpr_find_sig_by_owner - signals aren't owned by components in HAL
pub extern "c" fn halpr_find_pin_by_owner(owner: ?*anyopaque, start: ?*anyopaque) ?*anyopaque;
pub extern "c" fn halpr_find_param_by_owner(owner: ?*anyopaque, start: ?*anyopaque) ?*anyopaque;
pub extern "c" fn halpr_find_funct_by_owner(owner: ?*anyopaque, start: ?*anyopaque) ?*anyopaque;
pub extern "c" fn halpr_find_pin_by_sig(sig: ?*anyopaque, start: ?*anyopaque) ?*anyopaque;

// Component discovery functions
pub extern "c" fn halpr_find_comp_by_name(name: ?[*:0]const u8) ?*anyopaque;
pub extern "c" fn halpr_find_comp_by_id(comp_id: c_int) ?*anyopaque;
pub extern "c" fn halpr_find_comp_by_owner(start: ?*anyopaque) ?*anyopaque;

// Component name accessor (public API from hal.h)
pub extern "c" fn hal_comp_name(comp_id: c_int) [*:0]const u8;

// HAL constant for name field length
// Name is stored at the end of each HAL struct as char name[HAL_NAME_LEN + 1]
pub const HAL_NAME_LEN = 47;

// HAL pin direction constants (from hal.h)
// Source: LinuxCNC HAL source code (src/hal/hal.h)
pub const HAL_DIR_UNSPECIFIED = -1;
pub const HAL_IN = 16;
pub const HAL_OUT = 32;
pub const HAL_IO = 48; // HAL_IN | HAL_OUT

// HAL shared memory base pointer (exported by liblinuxcnchal.so)
// This points to the base of HAL shared memory where hal_data_t is located
pub extern "c" var hal_shmem_base: [*c]u8;

// HAL data structure (opaque, but we need the list head pointers)
// We access comp_list_ptr, pin_list_ptr, sig_list_ptr, param_list_ptr at known offsets
pub const HAL_DATA_COMP_LIST_OFFSET = 72; // offset to comp_list_ptr in hal_data_t
pub const HAL_DATA_PIN_LIST_OFFSET = 76;  // offset to pin_list_ptr in hal_data_t
pub const HAL_DATA_SIG_LIST_OFFSET = 80;  // offset to sig_list_ptr in hal_data_t
pub const HAL_DATA_PARAM_LIST_OFFSET = 84; // offset to param_list_ptr in hal_data_t

// HAL memory allocation
// hal_malloc allocates memory from HAL's shared memory region.
// This is required for pin data pointers in hal_pin_*_new functions.
// Source: LinuxCNC HAL source code (src/hal/hal_lib.c)
pub extern "c" fn hal_malloc(size: c_long) ?*anyopaque;

// HAL signal manipulation functions
// These functions are declared in hal.h but we add them explicitly for clarity.
// hal_signal_new: Create a new signal with specified name and type
// hal_link: Link a pin to a signal (both must exist and have same type)
// hal_unlink: Unlink a pin from its signal
// hal_signal_delete: Delete a signal (unlinks all pins first)
pub extern "c" fn hal_signal_new(name: [*:0]const u8, type: c_int) c_int;
pub extern "c" fn hal_link(pin_name: [*:0]const u8, signal_name: [*:0]const u8) c_int;
pub extern "c" fn hal_unlink(pin_name: [*:0]const u8) c_int;
pub extern "c" fn hal_signal_delete(name: [*:0]const u8) c_int;

// HAL value reading functions
// These functions read pin/signal/param values by name, returning type and data union
// hal_get_pin_value_by_name: Read pin value, also returns if pin is connected to signal
// hal_get_signal_value_by_name: Read signal value
// hal_get_param_value_by_name: Read parameter value
//
// Note: These use hal_data_u from the C header, which is a union of all HAL types
pub extern "c" fn hal_get_pin_value_by_name(
    name: [*:0]const u8,
    type_ptr: *c_int,
    data_ptr: [*c][*c]c.hal_data_u,
    connected_ptr: [*c]bool,
) c_int;

pub extern "c" fn hal_get_signal_value_by_name(
    name: [*:0]const u8,
    type_ptr: *c_int,
    data_ptr: [*c][*c]c.hal_data_u,
    has_writers_ptr: [*c]bool,
) c_int;

pub extern "c" fn hal_get_param_value_by_name(
    name: [*:0]const u8,
    type_ptr: *c_int,
    data_ptr: [*c][*c]c.hal_data_u,
) c_int;

// HAL pin direction type (from hal.h)
pub const hal_pin_dir_t = c_int;

// HAL pin structure (from hal_priv.h)
// This is the actual structure layout in HAL shared memory.
// Source: LinuxCNC HAL source code (src/hal/hal_priv.h)
//
// NOTE: In userspace (ULAPI), we access this via halpr_find_pin_by_name
// which returns a pointer to this structure in shared memory.
pub const hal_pin_t = extern struct {
    next_ptr: [*c]hal_pin_t,
    data_ptr_addr: ?*anyopaque,
    owner_ptr: ?*anyopaque,
    signal: ?*anyopaque,
    dummysig: c.hal_data_u,
    oldname: ?*anyopaque,
    type: c_int,
    dir: hal_pin_dir_t, // This is what we need - pin direction!
    name: [HAL_NAME_LEN + 1]u8,
};

// HAL param direction type (from hal.h)
pub const hal_param_dir_t = c_int;
