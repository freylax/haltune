# Haltune Debugging Status

## Current State (2025-01-30)

**Build:** ✓ Successful (4.5MB aarch64 binary)
**Runtime:** ✗ Crashes on startup

## Recent Changes

### FFI Enhancements (`src/ffi/c.zig`)
- Added `halpr_find_pin_by_owner(comp, start)` - iterate pins by component
- Added `halpr_find_param_by_owner(comp, start)` - iterate params by component
- Added `halpr_find_comp_by_owner(start)` - iterate components
- Added `hal_comp_name(comp_id)` - get component name by ID
- Added `HAL_NAME_LEN = 47` constant

### Safe Wrappers (`src/ffi/safe.zig`)
- Added `getPinName(pin)` - extract name from opaque hal_pin_t (offset: 56)
- Added `getSignalName(sig)` - extract name from opaque hal_sig_t (offset: 40)
- Added `getParamName(param)` - extract name from opaque hal_param_t (offset: 48)
- Added `getCompNameById(comp_id)` - wrapper around hal_comp_name()
- Added `findPinByOwner(comp, start)` - iterate pins owned by component
- Added `findParamByOwner(comp, start)` - iterate params owned by component
- Added `findCompByName(name)`, `findCompById(id)`, `findCompByOwner(start)`

### Refresh Thread (`src/state/refresh.zig`)
- Modified `refreshPins()` to seed cache with known pins when empty:
  - `motion.analog-in-00`
  - `motion.analog-in-01`
  - `motion.digital-in-00`
  - `motion.digital-in-01`

## Likely Crash Cause

The name accessor functions use **hardcoded offsets** that may be incorrect:
```zig
const name_offset = 56; // For pins - may be wrong
const name_offset = 40; // For signals - may be wrong
const name_offset = 48; // For params - may be wrong
```

If these offsets don't match the actual struct layout, reading the name will:
1. Read garbage data as a string
2. Potentially cause segfault if offset points outside valid memory

## Next Steps to Debug

### 1. Get Crash Details
```bash
ssh pib "cd ~/prog/haltune && gdb -batch -ex 'run' -ex 'bt' --args ~/prog/haltune/zig-out/bin/haltune"
# Or run with core dump:
ssh pib "cd ~/prog/haltune && sudo -E ~/prog/haltune/zig-out/bin/haltune 2>&1 | tee crash.log"
```

### 2. Alternative: Disable Discovery Temporarily
Comment out the discovery code in `refreshPins()` to isolate the issue:
```zig
// In src/state/refresh.zig, line 252-276
// Comment out the entire if (cached_names.len == 0) { ... } block
```

### 3. Fix Name Offsets (if crash is in name access)

Calculate correct offsets by examining hal_priv.h struct layouts:

```c
// From hal_priv.h:
struct hal_pin_t {
    SHMFIELD(hal_pin_t) next_ptr;        // 8 bytes (offset as rtapi_intptr_t)
    SHMFIELD(void*) data_ptr_addr;       // 8 bytes
    SHMFIELD(hal_comp_t) owner_ptr;      // 8 bytes
    SHMFIELD(hal_sig_t) signal;          // 8 bytes
    hal_data_u dummysig;                  // 8 bytes (union)
    SHMFIELD(hal_oldname_t) oldname;     // 8 bytes (offset)
    hal_type_t type;                      // 4 bytes
    hal_pin_dir_t dir;                    // 4 bytes
    char name[HAL_NAME_LEN + 1];         // 48 bytes (offset 56?)
};
```

The SHMFIELD macro stores offsets (rtapi_intptr_t = 8 bytes on 64-bit).

**Correct offsets likely:**
- `hal_pin_t.name`: 56 bytes (8*6 + 4 + 4 + padding?)
- `hal_sig_t.name`: Need to calculate from hal_sig_t struct
- `hal_param_t.name`: Need to calculate from hal_param_t struct

### 4. Better Solution: Use halcmd for Discovery

Instead of wrestling with opaque structs, use halcmd to list pins:
```bash
halcmd list 2>&1 | grep '^   '
```

Parse this output to get all pin names, then use `getPinValueByName()` for values.

## Quick Recovery Commands

```bash
# Sync latest code
rsync -avz --exclude='zig-cache' --exclude='zig-out' \
  /home/robert/prog/zig/haltune/ pib:prog/haltune/

# Build on Pi
ssh pib 'cd ~/prog/haltune && ~/bin/zig build -Dtarget=aarch64-linux-gnu'

# Test run (with output)
ssh pib 'cd ~/prog/haltune && sudo -E ~/prog/haltune/zig-out/bin/haltune 2>&1'
```

## Files Modified This Session

- `src/ffi/c.zig` - Added discovery functions
- `src/ffi/safe.zig` - Added name accessors and iteration functions
- `src/state/refresh.zig` - Added cache seeding
- `src/hal/export.zig` - Fixed import path (earlier)

## Git Status

Check what's changed:
```bash
git status
git diff src/ffi/c.zig
git diff src/ffi/safe.zig
git diff src/state/refresh.zig
```

## When You Return

1. Get the crash traceback/backtrace
2. Check if crash is in name accessor (getPinName, etc.)
3. Either fix offsets or disable discovery temporarily
4. Consider using halcmd for discovery instead of FFI

Good luck! 🍵
