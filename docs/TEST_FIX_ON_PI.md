# Testing haltune EINTR Fix

## Problem
haltune was crashing with "unexpected errno: 6" (EINTR) when LinuxCNC was not running.

## Root Cause
The hal_init() C function internally opens shared memory files in /dev/shm (e.g., /dev/shm/hal_shm). When LinuxCNC is not running, these files don't exist, causing open() to fail with EINTR crashes.

## Fix Applied
1. Added HalNotAvailable error variant
2. Added checkHalAvailable() function to check for /dev/shm/hal_shm
3. Updated Model.init() to check HAL availability before calling hal_init()
4. Added user-friendly error message when HAL is not available

## Test Instructions

### Test 1: Verify error message when HAL not available
```bash
# On pib, with LinuxCNC NOT running
cd ~/prog/haltune
~/bin/zig build
LD_LIBRARY_PATH=/usr/lib ./zig-out/bin/haltune
```

**Expected output:**
```
ERROR: HAL is not available

haltune requires LinuxCNC to be running to access the HAL.

Please start LinuxCNC first:
  linuxcnc /path/to/your/config.ini

Then run haltune again.
```

**Should NOT see:**
- "unexpected errno: 6" error
- EINTR crash
- Stack trace

### Test 2: Verify normal operation when HAL IS available
```bash
# Start LinuxCNC first
linuxcnc /path/to/config.ini

# In another terminal, run haltune
cd ~/prog/haltune
LD_LIBRARY_PATH=/usr/lib ./zig-out/bin/haltune
```

**Expected:** haltune starts successfully and shows the TUI interface

## Files Changed
- src/ffi/errors.zig: Added HalNotAvailable error and checkHalAvailable()
- src/tui/model.zig: Added HAL availability check in init()
- src/tui/app.zig: Added error handling with helpful message

## Success Criteria
- [ ] No EINTR crash when LinuxCNC is not running
- [ ] Clear error message telling user to start LinuxCNC first
- [ ] haltune works normally when LinuxCNC IS running
