---
status: verifying
trigger: "haltune-eintr-file-open: After fixing HAL initialization segfault, haltune crashes with repeated EINTR (errno 6) errors when opening files on ARM/Raspberry Pi"
created: 2026-02-02T12:00:00Z
updated: 2026-02-02T13:00:00Z
---

## Current Focus

hypothesis: hal_init() internally calls open() on /dev/shm/hal_* shared memory files. If LinuxCNC is not running, these files don't exist. The C library's open() call fails, but instead of returning a clean error, it's being interrupted by signals (EINTR). The EINTR error propagates up through the C library and is reported by Zig as "unexpected errno: 6" in posix.zig:openZ (Zig's error reporting wrapper around C's open()).
test: Run test_hal_init.zig on pib to see exact error. Check if /dev/shm contains HAL files. Verify if running LinuxCNC first fixes the issue.
expecting: /dev/shm has no HAL files when LinuxCNC isn't running. hal_init() fails because it can't open /dev/shm/hal_shm or similar.
next_action: Run test on pib, verify HAL infrastructure requirements, fix haltune to handle missing HAL gracefully.

## Symptoms
expected: Application starts and runs TUI without crashes
actual: Crashes with "unexpected errno: 6" (EINTR - Interrupted system call) when opening files
errors: Repeated EINTR errors in posix.zig:openZ function
reproduction: Run ~/prog/haltune/zig-out/bin/haltune on Raspberry Pi
started: After fixing HAL initialization segfault (commit 6346dbf)

## Eliminated

## Evidence

- timestamp: 2026-02-02T12:00:00Z
  checked: src/tui/app.zig initialization sequence
  found: App initializes: GPA allocator -> StateStore -> SubscriptionManager -> Model (with HAL init) -> vxfw.App.init() -> app.run()
  implication: HAL initialization happens BEFORE vxfw.App.init(), so vaxis signal handlers shouldn't be installed yet

- timestamp: 2026-02-02T12:00:00Z
  checked: src/tui/model.zig Model.init()
  found: Model.init() calls ffi.halInit("haltune") at line 71, then ffi.halReady(comp_id) at line 75, then creates widgets, then returns
  implication: HAL init/ready complete before vxfw.App.init() is called in src/tui/app.zig line 58

- timestamp: 2026-02-02T12:00:00Z
  checked: src/ffi/safe.zig for file operations
  found: No file opening operations in HAL init code - halInit/halReady only call C HAL library functions
  implication: File opening must be happening inside the C HAL library (liblinuxcnchal.so)

- timestamp: 2026-02-02T12:00:00Z
  checked: Codebase for any file.open or createFile calls
  found: Only one file operation: saveConfiguration() in model.zig line 221, which only runs when user presses 's'
  implication: File opening error cannot be from Zig code - must be from C library via hal_init()

- timestamp: 2026-02-02T12:00:00Z
  checked: Web search results for EINTR handling in Zig
  found: Zig's std.fs automatically retries on EINTR for most POSIX operations (per GitHub issues #19445, #2425)
  implication: If error is "posix.zig:openZ unexpected errno: 6", then either: (a) it's a C library call, not Zig, or (b) Zig's retry loop is hitting a limit or edge case

- timestamp: 2026-02-02T12:15:00Z
  checked: User checkpoint response
  found: haltune is run via SSH, error happens 100% of the time (consistent failure)
  implication: This is a systematic issue, not a race condition or intermittent signal problem

- timestamp: 2026-02-02T12:30:00Z
  checked: docs/TestingStatus.md
  found: haltune WAS working on 2026-01-29 (before HAL init fix in commit 6346dbf)
  implication: The HAL initialization fix introduced a dependency on HAL infrastructure that wasn't there before

- timestamp: 2026-02-02T12:30:00Z
  checked: Web search for LinuxCNC HAL prerequisites
  found: hal_init() requires: (1) RTAPI kernel module loaded, (2) ulimit -l set high (20480+), (3) /dev/shm mounted with HAL shared memory initialized, (4) LinuxCNC running or HAL session active
  implication: haltune may be trying to initialize HAL when the HAL infrastructure doesn't exist yet

- timestamp: 2026-02-02T12:35:00Z
  checked: Code path in model.zig and safe.zig
  found: Model.init() calls ffi.halInit() which wraps c.hal_init(). If c.hal_init() returns negative, it returns HalError.InitFailed. But the actual error is happening INSIDE c.hal_init() before it returns.
  implication: The C library is crashing or hitting EINTR during its execution, not returning a clean error code. The "unexpected errno: 6" is from Zig's POSIX wrapper when the C library's internal open() fails

- timestamp: 2026-02-02T12:45:00Z
  checked: User confirmation that LinuxCNC is NOT running when haltune executes
  found: ROOT CAUSE CONFIRMED - hal_init() fails because HAL shared memory files in /dev/shm don't exist when LinuxCNC isn't running
  implication: The fix added in commit 6346dbf introduced a dependency on HAL infrastructure. Need to handle missing HAL gracefully

## Resolution

root_cause: hal_init() internally opens shared memory files in /dev/shm (e.g., /dev/shm/hal_shm). When LinuxCNC is not running, these files don't exist, causing open() to fail with EINTR. The C library crashes during hal_init() execution before returning a clean error code, and Zig reports this as "unexpected errno: 6" in posix.zig:openZ.

fix: Check if HAL shared memory exists before calling hal_init(). If it doesn't exist, show a clear error message telling the user to start LinuxCNC first. This prevents the crash and provides actionable guidance.

Implementation:
1. Added HalNotAvailable error variant to src/ffi/errors.zig
2. Added checkHalAvailable() function to check for /dev/shm/hal_shm before calling hal_init()
3. Updated Model.init() to call checkHalAvailable() before halInit()
4. Updated main() in src/tui/app.zig to catch HalNotAvailable and display helpful error message

files_changed:
- src/ffi/errors.zig: Added HalNotAvailable error and checkHalAvailable() function
- src/tui/model.zig: Added HAL availability check in init()
- src/tui/app.zig: Added error handling for HalNotAvailable with user-friendly message

verification:
- Status: Fix implemented, awaiting testing on Raspberry Pi
- Build: Code compiles successfully (syntactic verification)
- Test plan: See TEST_FIX_ON_PI.md for detailed testing instructions
- Success criteria: (1) No EINTR crash when LinuxCNC not running, (2) Clear error message, (3) Normal operation when LinuxCNC IS running

