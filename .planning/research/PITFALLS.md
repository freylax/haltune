# Pitfalls Research

**Domain:** LinuxCNC HAL integration in Zig with FFI and TUI
**Researched:** 2025-01-28
**Confidence:** MEDIUM

## Critical Pitfalls

### Pitfall 1: Blocking Calls in Real-time Context

**What goes wrong:**
Making blocking system calls (I/O, allocation, locks) from real-time HAL threads causes deterministic timing failures. The real-time thread misses its scheduling deadline, causing stepper pulse errors or machine position faults.

**Why it happens:**
Developers accustomed to userspace programming use normal I/O, heap allocation, or blocking locks without considering real-time constraints. The HAL API doesn't prevent these calls, and LinuxCNC's real-time threads (using RTAI or PREEMPT_RT) have strict timing requirements.

**Consequences:**
- Real-time thread deadline miss
- Stepper motor stuttering or missed steps
- Machine position errors
- Possible E-stop trigger
- Machine damage from uncontrolled motion

**How to avoid:**
1. **Identify real-time context:** Only functions marked with `function fp|nofp` in `.comp` files run in real-time threads
2. **No blocking operations:** Never call `malloc()`, `free()`, file I/O, or blocking mutexes in real-time functions
3. **Pre-allocate resources:** Allocate all memory during component initialization (`rtapi_app_main()`), not in update functions
4. **Use spinlocks carefully:** If you need mutual exclusion, use spinlocks with minimal critical sections
5. **Document real-time boundaries:** Clearly mark which code runs in real-time context in FFI layer

**Warning signs:**
- Intermittent timing glitches during machine operation
- "Realtime delay" warnings in LinuxCNC logs
- Jitter spikes during latency test that correlate with your component
- Machine errors only under load (not in idle testing)

**Phase to address:**
Phase: FFI Layer Foundation
**Rationale:** The FFI layer must establish which contexts are real-time vs userspace and prevent blocking calls at the boundary.

---

### Pitfall 2: Memory Management Across FFI Boundary

**What goes wrong:**
Memory allocated by C code (LinuxCNC HAL) is freed by Zig code, or vice versa, causing heap corruption or double-free errors. Zig's allocator and the C runtime may use different heaps, leading to undefined behavior.

**Why it happens:**
Zig and C have different memory management models. Zig uses its own allocator (e.g., GPA, Arena), while LinuxCNC uses standard C malloc/free. When pointers cross the FFI boundary, ownership becomes ambiguous, and error paths often forget to clean up properly.

**Consequences:**
- Heap corruption and mysterious crashes
- Double-free errors
- Memory leaks that accumulate over long runs
- Use-after-free vulnerabilities
- Data corruption in shared HAL structures

**How to avoid:**
1. **Explicit ownership:** Define clear rules: who allocates, who frees, documented at every FFI boundary
2. **Prefer Zig allocation:** Allocate memory in Zig, pass pointers to C for read-only access when possible
3. **Use arena allocators:** For temporary C data, use arena allocators that can be freed in one batch
4. **Clone when crossing boundaries:** Copy HAL data into Zig-owned memory before returning to Zig code
5. **Error path testing:** Unit tests must trigger error paths to verify cleanup (memory leaks often occur only in error paths)
6. **Document pointer lifetimes:** Every pointer type in FFI layer should document its lifetime scope

**Warning signs:**
- Segfaults that only occur after extended runtime
- Valgrind reports "invalid free" or "definitely lost"
- Crashes that don't reproduce in debug builds
- Memory usage growing over time in long-running processes

**Phase to address:**
Phase: FFI Layer Foundation
**Rationale:** Memory management rules must be established before writing FFI code; retrofitting ownership is painful.

---

### Pitfall 3: Struct Alignment and Padding Mismatches

**What goes wrong:**
Zig struct layout doesn't match C struct layout, causing FFI calls to read wrong fields or misaligned memory. Zig's default struct layout differs from C's padding and alignment rules.

**Why it happens:**
Zig optimizes struct layout for size and may reorder fields or insert different padding than C. Without explicit `extern` or `packed` attributes, Zig structs won't match C ABI requirements. This is particularly insidious because it may "work" on some architectures (e.g., x86_64) but fail on ARM64 (Raspberry Pi 5).

**Consequences:**
- Reading garbage values from HAL structures
- Writing to wrong memory locations
- Subtle data corruption that's hard to debug
- Architecture-specific bugs (works on x86, fails on ARM64)
- Incorrect pin/signal/parameter values

**How to avoid:**
1. **Use `extern struct`:** All structs that cross FFI boundary must be declared `extern struct` in Zig
2. **Match C header types:** Use exact types from C headers (`hal_s32_t` not `i32` if typedef differs)
3. **Verify with `@sizeOf` and `@offsetOf`:** Write compile-time tests that assert Zig struct size matches C sizeof
4. **Check ARM64 specifically:** Test struct layout on ARM64 (Pi 5) early; alignment rules differ from x86_64
5. **Document conversion:** Where conversion is needed, write explicit to/from functions rather than casting
6. **Include actual C headers:** Use Zig's `@cImport` to reference actual LinuxCNC headers when possible

**Warning signs:**
- Pin values don't match halcmd output
- "Wrong" values that change when struct fields are reordered
- Bugs that only appear on Raspberry Pi 5 (ARM64) but not x86 development machine
- Subtle arithmetic errors that look like bit shifts or masking problems

**Phase to address:**
Phase: FFI Layer Foundation
**Rationale:** Struct definitions are foundational; getting them wrong requires rewriting all FFI code.

---

### Pitfall 4: Race Conditions on HAL State

**What goes wrong:**
Multiple threads (TUI update thread, HAL callback threads, user input) access HAL state without proper synchronization, causing read-write conflicts, torn reads, or use-after-free errors.

**Why it happens:**
HAL components can be loaded/unloaded dynamically. The TUI reads HAL state while the user manipulates pins/signals. Without locking, a component can be unloaded mid-read, or a pin value can be updated while being read, causing inconsistent views.

**Consequences:**
- TUI crashes when components disappear
- Stale data displayed (pin values that no longer exist)
- Race condition crashes (use-after-free when component unloaded)
- Incorrect values leading to wrong machine adjustments
- Non-deterministic bugs that are hard to reproduce

**How to avoid:**
1. **HAL lock discipline:** LinuxCNC uses mutexes to protect shared HAL structures; acquire/release properly around FFI calls
2. **Snapshot pattern:** Copy HAL state into Zig-owned memory under lock, then release lock and process snapshot
3. **Component lifecycle tracking:** Subscribe to HAL load/unload events; invalidate cached state when components change
4. **Defensive copying:** Never hold pointers to HAL memory across lock boundaries
5. **Retry on inconsistency:** If read detects component vanished, retry rather than crash
6. **Thread-safe caching:** Cache HAL reads for TUI updates, but invalidate on component state changes

**Warning signs:**
- Intermittent crashes when loading/unloading components
- "Component not found" errors during normal operation
- Stale pin values that don't update
- Valgrind reports "race conditions" or "data races"
- Bugs that only appear with certain refresh rates

**Phase to address:**
Phase: HAL State Management
**Rationale:** Concurrency handling is core to HAL interaction; must be designed before adding TUI.

---

### Pitfall 5: Real-time Thread Starvation on Pi 5

**What goes wrong:**
The TUI or HAL inspector runs heavy operations (CPU-intensive pin enumeration, complex filtering) that starve real-time threads, causing timing failures. Raspberry Pi 5 has limited CPU headroom for real-time work.

**Why it happens:**
Pi 5 runs at the edge of real-time capability. LinuxCNC latency tests show failures at sustained high load (50,000+ pings). Complex TUI operations or heavy HAL iteration can consume enough CPU to delay the real-time thread's scheduling.

**Consequences:**
- Real-time thread misses deadline (even if no blocking calls)
- Increased latency jitter
- Machine faults under heavy UI load
- Degraded stepper performance
- Possible E-stop from watchdog timeout

**How to avoid:**
1. **Batch HAL reads:** Don't iterate all pins on every frame; cache and update incrementally
2. **Throttle refresh rate:** Limit TUI updates to 10-30fps even if terminal supports 60fps+
3. **Background thread:** Run heavy HAL operations in separate thread from real-time thread
4. **Load-aware design:** Monitor system load; skip non-critical updates under high load
5. **Lazy evaluation:** Only read pins/signals currently visible in TUI
6. **Profile on Pi 5:** Test TUI performance on actual Pi 5 hardware early; desktop results are misleading

**Warning signs:**
- Latency test jitter increases when TUI is running
- Machine errors correlate with TUI refreshes
- CPU usage spikes on TUI updates
- "Realtime delay" messages during active UI use

**Phase to address:**
Phase: TUI Implementation
**Rationale:** Performance optimization must be considered during TUI design; retrofitting for Pi 5 constraints is difficult.

---

### Pitfall 6: LinuxCNC API Version Mismatches

**What goes wrong:**
Code written for LinuxCNC 2.9 breaks on 2.10 (or vice versa) due to API changes, type redefinitions, or function signature changes. Python2→Python3 and Gtk2→Gtk3 migrations in 2.10 caused significant breaking changes.

**Why it happens:**
LinuxCNC 2.9 and 2.10 have subtle API incompatibilities. HAL types may be redefined (e.g., `s32` vs `signed`), function signatures change, or header reorganization changes include paths. Code tested on one version may not detect these issues until deployed on another.

**Consequences:**
- Compilation failures when switching LinuxCNC versions
- Runtime crashes from changed struct layouts
- Symbol not found errors for renamed functions
- Deployed software fails on user machines
- Support burden for multiple versions

**How to avoid:**
1. **Version detection:** Use compile-time or runtime checks to detect LinuxCNC version
2. **Conditional compilation:** Use `comptime` blocks in Zig to version FFI code
3. **Minimize direct API use:** Prefer higher-level HAL operations that abstract version differences
4. **Test both versions:** Continuous testing against both 2.9 and 2.10
5. **Document supported versions:** Clearly state which LinuxCNC versions are tested/supported
6. **Version-specific CI:** Build and test against both 2.9 and 2.10 in CI
7. **Feature detection:** Prefer runtime feature detection over version checks when possible

**Warning signs:**
- Build succeeds but runtime behavior differs
- Warnings about deprecated symbols or functions
- Struct size mismatches between versions
- Users report "works on 2.9 but fails on 2.10"

**Phase to address:**
Phase: FFI Layer Foundation
**Rationale:** Version compatibility must be designed into FFI layer from the start; adding it later is expensive.

---

## Moderate Pitfalls

### Pitfall 7: TUI Input Lag on Pi 5

**What goes wrong:**
The TUI feels sluggish or unresponsive on Raspberry Pi 5 hardware due to excessive redraw work, blocking operations on input thread, or inefficient terminal updates.

**Why it happens:**
Terminal input latency is perceptible even at 2-5ms. Heavy frame calculations (e.g., complex filtering, sorting, many widgets) can cause noticeable input lag. Pi 5 has slower single-thread performance than desktop systems.

**Consequences:**
- Poor user experience (feels "laggy")
- Mistyped commands or missed input
- User frustration and reluctance to use tool
- Perceived lack of polish

**How to avoid:**
1. **Incremental rendering:** Only redraw changed widgets, not entire screen
2. **Debounce input:** Filter rapid input events to reduce processing
3. **Off-thread rendering:** Move heavy layout calculations off input thread
4. **Simple layouts:** Avoid complex nested layouts that require multiple passes
5. **Benchmark on Pi 5:** Test TUI responsiveness on actual hardware early
6. **Lazy evaluation:** Don't calculate display data until needed for render

**Warning signs:**
- Keystrokes feel delayed
- Screen "tears" or flickers during updates
- Input queue backing up
- Subjective "sluggishness" compared to terminal

**Phase to address:**
Phase: TUI Implementation
**Rationale:** TUI performance must be validated on Pi 5 during development; users won't tolerate laggy interfaces.

---

### Pitfall 8: Riocore Config Drift

**What goes wrong:**
HAL state changes made in haltune become out of sync with riocore's source-of-truth config, causing confusion when riocore regenerates HAL files. Users expect haltune changes to persist but they're overwritten.

**Why it happens:**
Riocore uses `rio-setup` config file as source of truth, generating `.ini` and `.hal` files. Haltune manipulates HAL at runtime but doesn't update the rio config. When riocore regenerates (e.g., after FPGA rebuild), haltune's changes are lost.

**Consequences:**
- User confusion ("my changes disappeared!")
- Loss of tuning work
- Mismatch between runtime state and config file
- Support burden explaining riocore workflow

**How to avoid:**
1. **Explicit read-only:** Make riocore awareness explicitly view-only in UI
2. **Warn on riocore detected:** Show clear warning when riocore present that changes are volatile
3. **Export to riocore format:** Provide export function that generates rio-config snippets from current HAL state
4. **Document workflow:** Explain that haltune is for tuning, rio-setup is for persistent config
5. **Detect riocore changes:** Watch for rio config file changes and warn user to reload
6. **Label volatile state:** Mark HAL values that differ from riocore config

**Warning signs:**
- Users report "my changes disappeared"
- Confusion about which tool is source of truth
- Support requests about lost tuning work

**Phase to address:**
Phase: Riocore Integration
**Rationale:** Riocore workflow must be clear from initial implementation; users will assume persistence otherwise.

---

### Pitfall 9: HAL Pin Type Coercion Errors

**What goes wrong:**
Assigning wrong type to HAL pin (e.g., writing float to bit pin, or signed to unsigned) causes silent type coercion, data loss, or runtime errors. Zig's type system doesn't prevent this across FFI boundary.

**Why it happens:**
HAL pins have specific types (HAL_BIT, HAL_FLOAT, HAL_S32, HAL_U32). The C API uses void* or unions that don't enforce type safety. Zig FFI layer can't prevent passing wrong type to C function.

**Consequences:**
- Incorrect pin values
- Silent data truncation (float→int)
- Runtime type errors from HAL
- Machines tuning with wrong parameter values
- Safety hazards from misinterpreted values

**How to avoid:**
1. **Type-safe wrappers:** Wrap HAL pin access in Zig types that enforce correct usage
2. **Tagged pin types:** Use Zig enums to represent pin types, encode in API
3. **Compile-time checks:** Use `comptime` to verify pin operations match types
4. **Runtime validation:** Check pin type before read/write; error on mismatch
5. **Explicit conversions:** Require explicit float→int, signed→unsigned conversion functions
6. **Document type semantics:** Clearly explain which types are compatible and why

**Warning signs:**
- Pin values are "wrong" in subtle ways (e.g., 0 or 1 when expecting float)
- Truncation warnings from compiler
- Rounding errors in displayed values
- Machine behavior doesn't match set parameters

**Phase to address:**
Phase: FFI Layer Foundation
**Rationale:** Type safety must be built into FFI layer; retrofitting is dangerous.

---

## Minor Pitfalls

### Pitfall 10: Terminal Capability Assumptions

**What goes wrong:**
TUI assumes terminal features that aren't available (e.g., true color, mouse support, unicode), causing rendering issues or fallback to degraded experience.

**Why it happens:**
Development happens on modern terminal with full features. Users may have limited terminals (SSH session, serial console, older terminal emulators) without color, mouse, or unicode support.

**Consequences:**
- Garbled display
- Missing UI elements
- Unusable interface
- User frustration
- "Works on my machine" bugs

**How to avoid:**
1. **Capability detection:** Query terminal capabilities on startup (Vaxis does this)
2. **Graceful degradation:** Fall back to basic TUI if advanced features unavailable
3. **Test on limited terminals:** Test over SSH, serial console, basic xterm
4. **Feature flags:** Allow disabling advanced features (colors, mouse) via command line
5. **Document requirements:** Clearly state minimum terminal requirements

**Warning signs:**
- Users report "display is garbled"
- Visual artifacts over SSH
- Mouse clicks don't work
- Unicode rendering issues

**Phase to address:**
Phase: TUI Implementation
**Rationale:** Terminal compatibility is low-cost to address early but expensive to retrofit.

---

### Pitfall 11: Insufficient HAL Error Context

**What goes wrong:**
HAL API errors return generic error codes without context, making debugging difficult. Users see "HAL error: -1" without knowing which pin/signal/component caused it.

**Why it happens:**
LinuxCNC HAL C API returns integer error codes with minimal context. The FFI layer must capture and preserve context (function called, parameters, HAL state) when errors occur.

**Consequences:**
- Difficult debugging
- Poor error messages
- User frustration
- Increased support burden
- Long debugging sessions

**How to avoid:**
1. **Wrap all HAL calls:** Never call HAL API directly; always go through error-handling wrapper
2. **Capture context:** Log function name, parameters, relevant HAL state on error
3. **Translate errors:** Map HAL error codes to meaningful Zig error enums
4. **Provide diagnostics:** Show relevant HAL state (component list, pin count) in error messages
5. **Error recovery:** Suggest corrective actions (e.g., "component not loaded", "pin not found")

**Warning signs:**
- Debugging requires adding print statements
- Error messages are cryptic
- Users can't self-diagnose issues

**Phase to address:**
Phase: FFI Layer Foundation
**Rationale:** Error handling infrastructure must be built from the start; adding it later misses many error paths.

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Skipping struct alignment tests | Faster initial development | Subtle bugs on ARM64, hard to debug | Never - ARM64 is target platform |
| Casting pointers instead of proper FFI types | Less boilerplate code | Memory corruption, type confusion | Never - safety is critical |
| Assuming single LinuxCNC version | Simpler codebase | Version incompatibility, user complaints | Only in initial prototype, never in production |
| Mocking HAL in tests instead of using real HAL | Faster tests, no setup required | Tests don't catch real integration bugs | Acceptable for unit tests, but integration tests must use real HAL |
| Throttling TUI refresh to "fix" performance | Hides performance issues | Masks underlying inefficiency, doesn't scale | Acceptable as temporary workaround, but must file bug to fix root cause |
| Hardcoding LinuxCNC paths | Simpler initial code | Won't work on non-standard installs | Only for initial prototype, must make configurable before release |
| Ignoring HAL memory leak warnings | Faster development | Accumulates over long runs, crashes | Never - memory leaks are unacceptable in long-running CNC software |

## Integration Gotchas

Common mistakes when connecting to external services.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| LinuxCNC HAL lib | Calling `hal_exit()` without proper cleanup | Use Zig defer patterns to ensure cleanup even on error |
| HAL shared memory | Accessing without acquiring mutex first | Always wrap HAL access in lock/unlock pair |
| Pin iteration | Assuming pin list is stable during iteration | Copy pin list under lock, iterate copy |
| Component lifecycle | Not handling load/unload events | Subscribe to component state changes, invalidate caches |
| Riocore detection | Assuming riocore files exist without checking | Check for rio config before using; degrade gracefully |
| LinuxCNC version detection | Assuming header version matches runtime version | Query runtime HAL for actual version |

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Reading all HAL pins every frame | TUI lag increases with pin count | Read only visible pins, cache others | 100+ pins (typical riocore config) |
| No render throttling | High CPU usage, input lag | Limit to 10-30fps max | Always, especially on Pi 5 |
| Synchronous HAL calls in input thread | Input lag, blocking UI | Move to background thread | When HAL has 50+ components |
| String allocations in hot path | Memory fragmentation, GC pressure | Use stack buffers or arena allocators | When displaying 100+ pins/signals |
| Full widget tree rebuild every frame | CPU spikes, visual flicker | Incremental updates, diff old vs new | With 20+ widgets or complex layouts |

## Security Mistakes

Domain-specific security issues beyond general security.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Writing HAL pins without validation | Machine damage from invalid values | Range-check all writes, especially velocity/acceleration |
| Trusting HAL input without validation | crashes from malformed data | Validate all HAL data before use |
| Loading untrusted HAL components | Code execution, system compromise | Only load components from trusted paths, validate signatures |
| Exposing HAL manipulation to network | Remote attacks on CNC machine | No network access; local-only operation |
| PID tuning without safeguards | Oscillation, machine damage | Enforce conservative PID ranges, warn on dangerous values |

## UX Pitfalls

Common user experience mistakes in this domain.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Cryptic pin names (e.g., "stepgen.00.position") | Users can't find what they need | Group/organize pins by function, provide search |
| No indication of real-time constraints | Users unknowingly cause timing issues | Warn when operations may affect real-time performance |
| Allowing dangerous parameter changes | Machine damage from mistakes | Confirm dialogs for dangerous changes (velocity limits, PID gains) |
| No undo/redo | Costly mistakes during tuning | Implement undo stack for parameter changes |
| Hiding HAL errors | Users don't know why things failed | Always show HAL errors with context and suggested fixes |
| Assuming CNC knowledge | New users can't use tool | Provide tooltips, help text, context-sensitive documentation |

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **FFI struct alignment:** Often missing ARM64 testing — verify struct sizes on Pi 5 with `@sizeOf` assertions
- [ ] **HAL error paths:** Often missing error handling — verify cleanup happens even when HAL calls fail
- [ ] **Real-time safety:** Often missing load testing — verify no blocking calls in hot path under stress
- [ ] **Riocore integration:** Often missing config file watching — verify haltune detects rio config changes
- [ ] **Version compatibility:** Often only tested on one version — verify both 2.9 and 2.10 work
- [ ] **TUI performance on Pi 5:** Often tested on desktop only — verify acceptable performance on actual Pi 5
- [ ] **Component lifecycle:** Often only tests static HAL — verify behavior when components load/unload dynamically
- [ ] **Memory leaks:** Often missing long-running tests — run for hours monitoring memory usage

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Struct alignment mismatch | HIGH | 1. Add `extern struct` to all FFI structs 2. Write size/offset assertions 3. Retest on Pi 5 4. Audit all type conversions |
| Memory leaks | MEDIUM | 1. Run with Valgrind 2. Identify leaks in FFI layer 3. Add explicit cleanup 4. Add arena allocators for temporary data |
| Real-time violations | HIGH | 1. Profile to find blocking operations 2. Move to pre-allocation 3. Add real-time safety checks 4. Rewrite update functions to be lock-free |
| Race conditions | HIGH | 1. Add HAL mutex locking 2. Implement snapshot pattern 3. Add lifecycle tracking 4. Test with concurrent load/unload |
| TUI performance | MEDIUM | 1. Profile on Pi 5 with flamegraph 2. Identify hot functions 3. Add incremental rendering 4. Implement render throttling |
| Version incompatibility | MEDIUM | 1. Add version detection 2. Implement conditional compilation 3. Test on both versions 4. Add CI for both 2.9 and 2.10 |

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Blocking calls in real-time context | FFI Layer Foundation | Unit tests with real-time analysis, lint for blocking operations |
| Memory management across FFI | FFI Layer Foundation | Valgrind clean, leak detection in CI |
| Struct alignment mismatches | FFI Layer Foundation | Compile-time size assertions, ARM64 testing |
| Race conditions on HAL state | HAL State Management | ThreadSanitizer, concurrent load/unload stress tests |
| Real-time thread starvation | TUI Implementation | Latency tests under heavy TUI load, CPU profiling |
| LinuxCNC API version mismatches | FFI Layer Foundation | CI testing on both 2.9 and 2.10, version feature detection |
| TUI input lag | TUI Implementation | User acceptance testing on Pi 5, input latency benchmarks |
| Riocore config drift | Riocore Integration | User testing with riocore, workflow validation |
| HAL pin type coercion | FFI Layer Foundation | Type-safe wrapper tests, fuzz testing of pin operations |
| Terminal capability assumptions | TUI Implementation | Test on multiple terminals, SSH, serial console |
| Insufficient HAL error context | FFI Layer Foundation | Error handling tests, user reports of error messages |

## Sources

### Official Documentation
- [LinuxCNC HAL Component Documentation](https://linuxcnc.org/docs/stable/html/hal/comp.html) - HAL component generator syntax and options (Updated Dec 15, 2025)
- [LinuxCNC Python HAL Module](https://linuxcnc.org/docs/stable/html/hal/halmodule.html) - Non-realtime component patterns and delays
- [LinuxCNC Developer Manual V2.9.7](http://linuxcnc.org/docs/2.9/pdf/LinuxCNC_Developer_nb.pdf) - Shared memory IPC and real-time architecture (Oct 22, 2025)
- [LinuxCNC Code Notes](https://linuxcnc.org/docs/html/code/code-notes.html) - IPC mechanisms and shared memory (Dec 15, 2025)

### Community Issues
- [HAL RT Module Problem](https://forum.linuxcnc.org/24-hal-components/47927-hal-rt-module-problem) - Component loading conflicts and memory issues (Jan 2023)
- [Insufficient Memory for Signal/Pin](https://forum.linuxcnc.org/10-advanced-configuration/3894-insufficient-memory-for-signal-pin) - Memory limits with large pin counts (Aug 2017)
- [GitHub Issue #3082 - Blocking jogging](https://github.com/LinuxCNC/linuxcnc/issues/3082) - Blocking behavior during MDI operations (Aug 2024)
- [LinuxCNC 2.9.2 Pi 5 Debian Bookworm](https://github.com/LinuxCNC/linuxcnc/issues/2969) - Pi 5 compatibility issues

### Raspberry Pi 5 Performance
- [LinuxCNC on Raspberry Pi 5 Forum Thread](https://forum.linuxcnc.org/9-installing-linuxcnc/50203-linuxcnc-on-raspberry-pi-5) - Real-time stability and latency issues
- [TinyCNC-II Pi 5 Implementation](https://www.dqrwagon.com/14-raspberry-pi-5-linuxcnc) - Practical Pi 5 deployment experiences
- [PREEMPT_RT on Pi 5 Discussion](https://forums.raspberrypi.com/viewtopic.php?t=382231) - Real-time kernel performance inconsistencies

### FFI and Memory Management
- [Zig Memory Management 2025](https://strongly-typed-thoughts.net/blog/zig-2025) - Zig's manual memory management challenges (Feb 2025)
- [Zig Resource Management Discussion](https://ziggit.dev/t/zig-what-i-think-after-months-of-using-it/9434) - Error path memory leaks common (Apr 2025)
- [Zig vs Rust Memory Safety](https://dev.to/tomastomas/zig-wants-to-replace-go-and-rust-does-it-have-what-it-takes-2412) - FFI safety improvements over C (Jul 2025)
- [A Study of Undefined Behavior in FFI](https://arxiv.org/pdf/2404.11671) - Spatial/temporal memory errors and alignment issues (2024)
- [FFI Struct Alignment Discussion](https://users.rust-lang.org/t/align-size-of-questions-for-ffi/30870) - Struct packing and alignment across FFI boundaries

### TUI Performance
- [VS Code Terminal Input Latency Bug](https://github.com/anthropics/claude-code/issues/12459) - Terminal input lag issues (Nov 2025)
- [Terminal Latency Comparison 2025](https://timinsight.com/ai-terminal-guide-2025-en/) - Ghostty ~2ms, WezTerm ~5ms input latency
- [Netflix Workbench Latency Investigation](https://netflixtechblog.com/investigation-of-a-workbench-ui-latency-issue-faa017d4653d) - Debugging UI latency (Oct 2024)

### Version Compatibility
- [LinuxCNC 2.9 to 2.10 Update](https://forum.linuxcnc.org/9-installing-linuxcnc/49736-linuxcnc-debian-bookworm-update-from-2-9-to-2-10) - Python 2→3 and Gtk2→3 breaking changes
- [Emc-developers 2.10 Migration Discussion](https://sourceforge.net/p/emc/mailman/message/58718096/) - API breaking changes during migration
- [LinuxCNC GitHub Changelog](https://github.com/LinuxCNC/linuxcnc/blob/master/debian/changelog) - Official version history

### Threading and Race Conditions
- [LinuxCNC Race Condition Fixes](https://github.com/LinuxCNC/linuxcnc/blob/master/debian/changelog) - Race between signal handlers and hal_ready()
- [Glade VCP Race Condition](https://forum.linuxcnc.org/) - HAL component threading synchronization issues (Aug 2021)
- [MachineKit HAL Source](https://github.com/machinekit/machinekit/blob/master/src/hal/lib/hal.h) - Mutex protection for shared memory blocks

### Riocore Integration
- [Riocore Setup from Scratch](https://forum.linuxcnc.org/9-installing-linuxcnc/53710-riocore-setup-from-scratch-for-dummies) - Installation and setup guide (Sep 2024)
- [HAL Property Error](https://www.facebook.com/groups/465128047350433/posts/2186297978566756/) - Invalid property errors and Glade fixes
- [RealtimeIO FPGA Discussion](https://162.243.45.186/18-computer/49142-linuxcnc-rio-realtimeio-for-linuxcnc-based-on-fpga-ice40-ecp5) - Terminal errors with riocore (May 2023)

---
*Pitfalls research for: LinuxCNC HAL integration in Zig*
*Researched: 2025-01-28*
