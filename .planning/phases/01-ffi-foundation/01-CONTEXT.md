# Phase 1: FFI Foundation - Context

**Gathered:** 2026-01-29
**Status:** Ready for planning

## Phase Boundary

Create safe Zig FFI bindings to the LinuxCNC HAL C API. This phase provides the foundational layer that all other phases depend on. The goal is to establish safe, idiomatic Zig wrappers that correctly handle C pointers, struct alignment, memory management, and version compatibility. Only wrap the functions actually needed for v1 requirements — add more wrappers in later phases as needed.

## Implementation Decisions

### FFI Abstraction Level

- **High-level safe API** — Zig types fully hide C pointers and structs for maximum safety
- **Wrap only what's needed** — Only wrap LinuxCNC HAL functions required for v1 requirements. Add more wrappers in later phases as needed
- **Safe Zig types hiding C details** — Define high-level Zig types that fully hide C representation. Maximum safety but more work to map to C
- **Group by functionality** — Organize Zig FFI code by functional modules (pins.zig, signals.zig, components.zig) rather than mirroring C headers

### Memory Ownership Strategy

- **HAL owns all memory** — Follow the pattern from LinuxCNC's Python bindings (halmodule.cc). HAL allocates via `hal_malloc()` and owns the memory. Zig never frees HAL pointers
- **HAL manages lifecycle** — When component exits via `hal_exit()`, HAL cleans up all its memory automatically
- **Zig owns Zig-side strings** — Strings allocated by Zig (names, prefixes) are owned and freed by Zig
- **Test allocator for leak detection** — Use Zig's testing allocator in unit tests to catch memory leaks. No runtime overhead in production

**Key insight from LinuxCNC Python bindings:**
Looking at the source code (halmodule.cc), the Python wrapper never frees memory allocated by `hal_malloc()`. It relies on HAL's cleanup when `hal_exit()` is called. This is the proven pattern we should follow.

### Error Handling Approach

- **Error unions (!T)** — Return Zig error unions for all FFI calls. Caller must handle errors explicitly (idiomatic Zig)
- **Specific HAL errors** — Map each HAL error code to a specific Zig error type (error.HalInit, error.PinNotFound, error.AlreadyLinked, etc.) for better error messages and type safety
- **Include error messages** — Include `strerror()` messages in errors for debugging. Performance impact is negligible since `strerror()` only runs when errors occur
- **Debug-only logging** — Log errors automatically in debug builds for easier debugging. Production builds don't log — caller handles logging

### LinuxCNC Version Compatibility

- **Runtime detection** — Detect LinuxCNC version at runtime so a single binary works with both 2.9.7 and 2.10
- **Lazy version detection** — Detect version on first HAL API call (slightly slower first call, simpler initialization)
- **Graceful degradation** — If running on unsupported version, degrade gracefully to lowest-common-denominator API rather than failing
- **Support 2.9.7 and 2.10** — Primary support for these versions. Handle API differences with runtime detection and conditional code paths

## Claude's Discretion

- Exact runtime version detection mechanism
- Test allocator implementation details for FFI leak detection
- When to trigger lazy version detection (first call vs explicit init)
- Graceful degradation strategy specifics for features not available in older versions
- Debug logging implementation and output format

## Specific Ideas

- "Follow the Python bindings pattern for memory — it's proven and works"
- Single binary deployment is important — user may have different LinuxCNC versions on different machines
- Want helpful error messages during development — debugging cryptic HAL error codes is painful
- Test coverage is critical for FFI — memory leaks and crashes are expensive to debug later

## Deferred Ideas

None — discussion stayed within Phase 1 scope.

---

*Phase: 01-ffi-foundation*
*Context gathered: 2026-01-29*
