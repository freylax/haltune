---
phase: 01-ffi-foundation
plan: 01
subsystem: build-infrastructure
tags: build-system, c-ffi, linuxcnc-hal, zig-0.15.1

# Dependency graph
requires: []
provides:
  - Zig build configuration with LinuxCNC HAL library linkage
  - Project structure (build.zig, src/root.zig, src/ffi/c.zig)
  - C header import infrastructure for LinuxCNC HAL API
affects: All subsequent phases that wrap HAL functions

# Tech tracking
tech-stack:
  added: [Zig 0.15.1, LinuxCNC HAL library (libhal)]
  patterns: [Build options for cross-platform development, Lazy @cImport for C headers]

key-files:
  created: [build.zig, src/root.zig, src/ffi/c.zig]
  modified: []

key-decisions:
  - "Added -Dskip-hal-link build option for development on machines without LinuxCNC"
  - "Target aarch64-linux for Raspberry Pi 5 compatibility"
  - "Use std.debug.print instead of std.io.getStdOut (Zig 0.15.1 API)"
  - "Lazy @cImport allows development without hal.h present"

patterns-established:
  - "Pattern 1: Build options enable development on non-LinuxCNC machines"
  - "Pattern 2: @cImport in dedicated c.zig file, not mixed with Zig code"
  - "Pattern 3: Raw C imports marked unsafe - wrappers will be added later"

# Metrics
duration: 15min
completed: 2026-01-29
---

# Phase 1 Plan 1: Project Scaffolding Summary

**Zig build system with LinuxCNC HAL library linkage and C header import infrastructure using Zig 0.15.1**

## Performance

- **Duration:** 15 min
- **Started:** 2026-01-29T07:28:52Z
- **Completed:** 2026-01-29T07:43:52Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments

- Zig build configuration targeting aarch64-linux (Raspberry Pi 5) with LinuxCNC HAL library linkage
- Project structure established (build.zig, src/root.zig, src/ffi/c.zig)
- C header import infrastructure using @cImport for hal.h
- Development workflow support via -Dskip-hal-link and -Dlinuxcnc-include options
- Binary successfully builds and prints "haltune FFI layer initialized"

## Task Commits

Each task was committed atomically:

1. **Task 1: Create build.zig with LinuxCNC HAL linkage** - `4bdb820` (feat)
2. **Task 2: Create src/root.zig entry point** - `8407b4d` (feat)
3. **Task 3: Create src/ffi/c.zig with @cImport for HAL headers** - `af929fa` (feat)

**Plan metadata:** (to be created after SUMMARY.md)

## Files Created/Modified

- `build.zig` - Zig build configuration with LinuxCNC HAL library linkage and include paths
- `src/root.zig` - Main entry point with minimal "haltune FFI layer initialized" message
- `src/ffi/c.zig` - Raw C imports from LinuxCNC HAL headers via @cImport

## Decisions Made

- **Build option for HAL library linking**: Added `-Dskip-hal-link` option to enable development on machines without LinuxCNC installed. This allows building and testing the project structure without libhal.so present.
- **Zig 0.15.1 API compatibility**: Used `std.debug.print` instead of non-existent `std.io.getStdOut()` API. Discovered through testing - this is the correct approach for Zig 0.15.1.
- **Lazy @cImport strategy**: @cImport doesn't process headers until C types/functions are actually referenced. This allows development without hal.h present, enabling workflow on non-LinuxCNC machines.
- **Target architecture**: Default to aarch64-linux for Raspberry Pi 5 deployment, but can be overridden with `-Dtarget` for development on x86_64.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added -Dskip-hal-link build option**
- **Found during:** Task 1 (build.zig creation)
- **Issue:** `zig build` fails with "unable to find dynamic system library 'hal'" on development machine without LinuxCNC
- **Fix:** Added `-Dskip-hal-link` build option to conditionally skip `exe.linkSystemLibrary("hal")`. Allows building on dev machines without LinuxCNC installed.
- **Files modified:** build.zig
- **Verification:** `zig build -Dskip-hal-link=true` succeeds without libhal present
- **Committed in:** 8407b4d (Task 2 commit - included in comprehensive commit message)

**2. [Rule 3 - Blocking] Fixed Zig 0.15.1 API compatibility**
- **Found during:** Task 2 (src/root.zig creation)
- **Issue:** `std.io.getStdOut()` does not exist in Zig 0.15.1. Compilation error: "struct 'Io' has no member named 'getStdOut'"
- **Fix:** Changed to use `std.debug.print` which is the correct API for Zig 0.15.1
- **Files modified:** src/root.zig
- **Verification:** Binary compiles and prints "haltune FFI layer initialized" successfully
- **Committed in:** 8407b4d (Task 2 commit)

**3. [Rule 1 - Bug] Fixed Zig build.zig API for module creation**
- **Found during:** Task 1 (build.zig creation)
- **Issue:** Initial build.zig used `.root_source_file = b.path(...)` which doesn't exist in Zig 0.15.1 ExecutableOptions struct
- **Fix:** Created module separately using `b.createModule()` then passed to `b.addExecutable()`
- **Files modified:** build.zig
- **Verification:** `zig build --help` succeeds and shows proper build options
- **Committed in:** 4bdb820 (Task 1 commit)

**4. [Rule 3 - Blocking] Fixed absolute path handling for include directories**
- **Found during:** Task 1 (build.zig creation)
- **Issue:** Build panic: "sub_path is expected to be relative to the build root, but was this absolute path: '/usr/include/linuxcnc'"
- **Fix:** Changed from `b.path(linuxcnc_include)` to `.{ .cwd_relative = linuxcnc_include }` for absolute paths
- **Files modified:** build.zig
- **Verification:** Build accepts absolute LinuxCNC include path without errors
- **Committed in:** 4bdb820 (Task 1 commit)

---

**Total deviations:** 4 auto-fixed (3 blocking, 1 bug)
**Impact on plan:** All deviations were necessary for basic functionality with Zig 0.15.1 API and development workflow. No scope creep - all fixes enable the planned work to execute correctly.

## Issues Encountered

None - all issues were auto-fixed via deviation rules.

## Configuration Details

**LinuxCNC header path discovered:**
- Standard path: `/usr/include/linuxcnc`
- Configurable via `-Dlinuxcnc-include` build option
- Include path added to module using `addIncludePath(.{ .cwd_relative = path })`

**Build configuration:**
- Target: aarch64-linux (Raspberry Pi 5) by default
- Override with `-Dtarget=x86_64-linux` for development
- LinuxCNC HAL library: libhal.so (system library search path)
- Additional libraries: librt (required by LinuxCNC HAL)

**Zig version:** 0.15.1

## Verification Results

All verification criteria passed:

1. ✅ `zig build -Dskip-hal-link=true -Dtarget=x86_64-linux` completes without errors
2. ✅ `./zig-out/bin/haltune` prints "haltune FFI layer initialized"
3. ✅ `src/ffi/c.zig` contains `@cInclude("hal.h")` via @cImport

**Project structure verified:**
- `build.zig` - ✅ Exists and compiles
- `src/root.zig` - ✅ Exists and runs
- `src/ffi/c.zig` - ✅ Exists with @cImport for hal.h

## User Setup Required

None - no external service configuration required for this plan.

**Note:** To build on the actual Raspberry Pi 5 with LinuxCNC installed:
- Run `zig build` (without -Dskip-hal-link) to link against libhal.so
- Ensure hal.h is available at /usr/include/linuxcnc (standard LinuxCNC installation)
- The binary will be automatically placed in `zig-out/bin/haltune`

## Next Phase Readiness

**Ready:**
- Build infrastructure in place and tested
- C header import structure established
- Development workflow functional on non-LinuxCNC machines
- Zig 0.15.1 API compatibility confirmed

**Blockers/concerns:**
- None - foundation is solid for next plan

**Next steps:**
- Plan 01-02 will wrap basic HAL functions (init, exit, component management)
- Safe Zig wrappers will be added in src/ffi/hal.zig or similar
- Memory ownership pattern from Python bindings will be implemented

---
*Phase: 01-ffi-foundation*
*Completed: 2026-01-29*
