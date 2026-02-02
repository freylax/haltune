---
status: investigating
trigger: "haltune segfaults on startup when running on Raspberry Pi (ARM), recently started happening"
created: 2026-02-02T00:00:00Z
updated: 2026-02-02T00:00:00Z
---

## Current Focus
hypothesis: "RefreshThread starts before HAL is initialized, causing segfault when calling HAL functions"
test: Check if halInit() is called before RefreshThread.start()
expecting: Find that refresh thread calls HAL functions without initialization
next_action: Add HAL initialization before starting refresh thread

## Symptoms
expected: No crashes - application should start and run normally
actual: Crashes on startup with immediate segfault
errors: Simple segfault message (no backtrace yet)
reproduction: Running deployed build on pib (Raspberry Pi)
timeline: Recently broken - worked before, now segfaults

## Eliminated
- hypothesis: ArrayList API changes cause segfault
  evidence: ArrayList.initCapacity(allocator, 0) is used throughout codebase without issue on x86_64
  timestamp: 2026-02-02T00:00:00Z

## Evidence
- timestamp: 2026-02-02T00:00:00Z
  checked: src/tui/model.zig line 244-245
  found: RefreshThread is started without calling halInit() first
  implication: RefreshThread calls HAL FFI functions (getPinValueByName, etc.) which segfault without initialization

- timestamp: 2026-02-02T00:00:00Z
  checked: src/state/refresh.zig
  found: refreshPins() calls ffi.getPinValueByName() which uses HAL functions
  implication: HAL must be initialized before refresh thread starts

- timestamp: 2026-02-02T00:00:00Z
  checked: Entire codebase for halInit() calls
  found: No halInit() call exists in main application code (only in tests)
  implication: Application uses HAL without initialization - causes segfault

## Resolution
root_cause: RefreshThread starts calling HAL FFI functions before HAL component is initialized with halInit()
fix:
  1. Added `const ffi = @import("../ffi/safe.zig")` import to model.zig
  2. Added `hal_comp_id: c_int` field to Model struct
  3. Added HAL initialization in Model.init(): call halInit("haltune") then halReady()
  4. Added HAL cleanup in Model.deinit(): call halExit(hal_comp_id)
verification: Build and test on ARM
files_changed:
  - src/tui/model.zig
