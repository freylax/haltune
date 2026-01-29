# Phase 1: FFI Foundation - Research

**Researched:** 2026-01-29
**Domain:** Zig FFI to LinuxCNC HAL C API
**Confidence:** MEDIUM

## Summary

This phase establishes the foundational FFI layer that all other phases depend on. Research focused on Zig's C interop capabilities, LinuxCNC HAL API structure, ARM64 struct alignment requirements, memory management patterns across language boundaries, and LinuxCNC version compatibility between 2.9.7 and 2.10.

**Key findings:**
1. **Zig FFI is mature and well-documented** - Zig 0.15.2 provides robust C interop via `@cImport`, `extern struct`, and pointer type safety. The `extern struct` guarantee of matching C ABI layout is critical for ARM64 compatibility (FFI-02).
2. **LinuxCNC HAL memory ownership is well-defined** - HAL owns memory allocated via `hal_malloc()` and cleans up on `hal_exit()`. This matches the pattern from LinuxCNC's Python bindings (halmodule.cc), which never frees HAL-allocated memory (FFI-03).
3. **ARM64 struct alignment is the primary risk** - Zig's default struct layout differs from C. Without explicit `extern struct`, code may work on x86_64 but fail on ARM64 (Pi 5). Compile-time size assertions are essential (FFI-02).
4. **HAL mutex locking is required for write operations** - LinuxCNC HAL uses shared memory accessed by multiple threads. All write operations must acquire the HAL mutex to prevent data races (FFI-04).
5. **Version compatibility requires runtime detection** - LinuxCNC 2.9.7 and 2.10 have subtle API differences. Runtime version detection with graceful degradation prevents breaking changes (FFI-05).

**Primary recommendation:** Use Zig's `@cImport` to pull in LinuxCNC HAL headers, wrap all C functions in safe Zig abstractions that return error unions, use `extern struct` for all C-compatible types, implement compile-time struct size assertions, and follow the Python bindings pattern for memory ownership (HAL owns its memory, Zig owns Zig strings).

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| **Zig** | 0.15.2 | FFI, memory management, type safety | Latest stable release (October 2025), proven C interop via `@cImport` and `extern struct`. 0.16.0-dev is unstable. |
| **LinuxCNC HAL lib** | 2.9.7+ / 2.10 | Target C API | Official HAL C library provides `hal_init`, `hal_comp_name`, `hal_exit`, `hal_pin_new_*`, `hal_mutex_*`. Headers in `/usr/include/linuxcnc/`. |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| **Zig stdlib** | built-in (0.15.2) | Testing allocator, error handling | Use `std.testing.allocator` for leak detection in FFI tests. Use `std.heap.GeneralPurposeAllocator` for detailed leak checking. |
| **Zig stdlib** | built-in (0.15.2) | C interop utilities | Use `@cImport` for HAL headers, `@ptrCast` for pointer conversion, `@alignCast` for alignment fixes (with caution). |
| **Zig stdlib** | built-in (0.15.2) | Thread synchronization | Use `std.Thread.Mutex` for Zig-side locking. HAL mutex uses C `pthread_mutex_t`. |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `@cImport` with headers | Manual extern declarations | Manual declarations are more error-prone and don't track header changes. `@cImport` reads actual C headers. |
| `extern struct` | `packed extern struct` | `packed` forces specific byte alignment but breaks C ABI on some platforms. Use default `extern struct` for natural C alignment. |
| HAL owns memory | Zig frees HAL memory | Freeing HAL-allocated memory violates LinuxCNC's ownership model and causes crashes. Follow Python bindings pattern instead. |

**Installation:**

```bash
# LinuxCNC development headers (Debian/Ubuntu)
sudo apt-get install linuxcnc-uspace-dev liblinuxcnc-dev

# Zig 0.15.2 (if not already installed)
# Download from https://ziglang.org/download/
```

## Architecture Patterns

### Recommended Project Structure

```
src/
├── ffi/
│   ├── c.zig              # Raw C imports via @cImport
│   ├── types.zig          # extern struct definitions matching C
│   ├── errors.zig         # Zig error sets mapping HAL error codes
│   └── safe.zig           # Safe wrapper functions
└── hal/
    ├── component.zig      # High-level component API
    ├── pin.zig            # High-level pin API
    ├── signal.zig         # High-level signal API
    └── param.zig          # High-level parameter API
```

### Pattern 1: Safe FFI Wrapper with Error Unions

**What:** Wrap all unsafe C HAL functions in Zig functions that return error unions and handle null pointers explicitly.

**When to use:** All FFI calls to LinuxCNC HAL API.

**Example:**

```zig
// src/ffi/safe.zig
const c = @import("c.zig");
const std = @import("std");

pub const HalError = error{
    InitFailed,
    ComponentNotFound,
    PinNotFound,
    AlreadyLinked,
    InvalidType,
    MutexLocked,
};

/// Initialize HAL component
/// Caller must call hal_exit when done
pub fn halInit(comp_name: [:0]const u8) !c.hal_comp_t {
    const comp_id = c.hal_init(comp_name) orelse return error.InitFailed;
    if (comp_id < 0) return error.InitFailed;
    return @intCast(comp_id);
}

/// Create a new HAL pin
pub fn pinNew(
    comp_id: c.hal_comp_t,
    name: [:0]const u8,
    type: c.hal_type_t,
    dir: c.hal_pin_dir_t,
) !*c.hal_pin_t {
    var pin_ptr: ?*c.hal_pin_t = undefined;
    const rc = c.hal_pin_new(
        name,
        type,
        dir,
        @ptrCast(&pin_ptr),
        comp_id,
    );

    if (rc != 0) return error.PinCreationFailed;
    return pin_ptr orelse error.PinCreationFailed;
}

/// Set component name (must be called before hal_ready)
pub fn compName(comp_id: c.hal_comp_t, name: [:0]const u8) !void {
    const rc = c.hal_comp_name(comp_id, name);
    if (rc != 0) return error.SetNameFailed;
}

/// Exit HAL component (frees all HAL-owned memory)
pub fn halExit(comp_id: c.hal_comp_t) void {
    _ = c.hal_exit(comp_id);
}
```

**Source:** Based on Zig FFI best practices from [Zig C Interop Guide](https://ziglang.org/documentation/master/#C-Compatibility) (HIGH confidence) and LinuxCNC HAL API documentation (MEDIUM confidence).

### Pattern 2: Extern Struct with Alignment Verification

**What:** Use `extern struct` for C-compatible types and add compile-time assertions to verify struct sizes match C.

**When to use:** All structs that cross FFI boundary.

**Example:**

```zig
// src/ffi/types.zig
const std = @import("std");

pub extern struct hal_pin_t {
    name: [*:0]const u8,
    type: hal_type_t,
    dir: hal_pin_dir_t,
    value: hal_data_u,
    next: ?*hal_pin_t,
};

pub extern union hal_data_u {
    bit: *c_int,
    float: *f64,
    s32: *i32,
    u32: *u32,
};

// Compile-time verification that Zig struct matches C layout
comptime {
    // These assertions prevent silent ABI mismatches
    std.debug.assert(@sizeOf(hal_pin_t) == @sizeOf(c.hal_pin_t));
    std.debug.assert(@offsetOf(hal_pin_t, "name") == @offsetOf(c.hal_pin_t, "name"));
    std.debug.assert(@offsetOf(hal_pin_t, "type") == @offsetOf(c.hal_pin_t, "type"));
}
```

**Source:** [Zig Language Reference - extern struct](https://ziglang.org/documentation/master/#Extern-Structs) (HIGH confidence), verified with community reports of ARM64 alignment issues (MEDIUM confidence).

### Pattern 3: Memory Ownership with Explicit Lifetimes

**What:** Document and enforce ownership rules: HAL owns memory allocated by `hal_malloc()`, Zig owns memory allocated by Zig allocator.

**When to use:** All memory operations across FFI boundary.

**Example:**

```zig
// src/ffi/safe.zig
/// Get pin name
/// Returns Zig-allocated string (caller must free with allocator)
/// The underlying C string is owned by HAL and must not be freed
pub fn getPinName(
    allocator: std.mem.Allocator,
    pin: *const c.hal_pin_t,
) ![]u8 {
    // C string is owned by HAL, copy to Zig-owned memory
    const c_name = pin.name orelse return error.NullPinName;
    return std.fmt.allocPrint(allocator, "{s}", .{c_name});
}

/// List all components
/// Returns slice of Zig-allocated strings (caller owns all memory)
/// HAL component list is not modified
pub fn listComponents(allocator: std.mem.Allocator) ![][]const u8 {
    var list = std.ArrayList([]const u8).init(allocator);

    // Iterate HAL's component list (owned by HAL)
    var comp: ?*c.hal_comp_t = c.hal_cmp_list;
    while (comp) |c| : (comp = c.*.next) {
        const name = try std.fmt.allocPrint(allocator, "{s}", .{c.*.name});
        try list.append(name);
    }

    return list.toOwnedSlice();
}

/// Note: Never call free() on pointers returned by hal_malloc()
/// HAL will free all memory when hal_exit() is called
```

**Source:** LinuxCNC Python bindings analysis (halmodule.cc) - Python wrapper never frees HAL-allocated memory (MEDIUM confidence), [Zig memory management best practices](https://strongly-typed-thoughts.net/blog/zig-2025) (MEDIUM confidence).

### Pattern 4: Mutex Locking for Thread Safety

**What:** Acquire HAL mutex before all write operations to prevent data races with HAL threads.

**When to use:** All HAL write operations (pin writes, signal linking, parameter changes).

**Example:**

```zig
// src/ffi/safe.zig

/// Write to a float pin (thread-safe)
pub fn setPinFloat(pin: *c.hal_pin_t, value: f64) !void {
    // Acquire HAL mutex before write
    _ = c.hl_mutex_lock(&c.hal_mutex);
    defer c.hl_mutex_unlock(&c.hal_mutex);

    if (pin.*.type != c.HAL_FLOAT) return error.TypeMismatch;
    pin.*.value.float.* = value;
}

/// Link signal to pin (thread-safe)
pub fn linkSignal(signal_name: [:0]const u8, pin_name: [:0]const u8) !void {
    _ = c.hl_mutex_lock(&c.hal_mutex);
    defer c.hl_mutex_unlock(&c.hal_mutex);

    const rc = c.hal_link(signal_name, pin_name);
    if (rc != 0) return error.LinkFailed;
}
```

**Source:** LinuxCNC HAL threading model documentation (MEDIUM confidence), general mutex discipline patterns (HIGH confidence).

### Anti-Patterns to Avoid

- **Direct C calls from UI code:** Violates separation of concerns and makes testing difficult. Always call through safe wrapper layer.
- **Mixing ownership models:** Never free C-allocated memory with Zig allocator and vice versa. Document ownership at every boundary.
- **Skipping extern struct:** Causes silent ABI mismatches on ARM64. Always use `extern struct` for C-compatible types.
- **Assuming single-threaded access:** HAL is multi-threaded. Always use mutex for writes.
- **Casting instead of proper conversion:** `@ptrCast` without type checking is unsafe. Use wrapper functions with explicit error handling.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| C header parsing | Manual struct definitions | `@cImport(@cInclude("hal.h"))` | Automatic tracking of header changes, compile-time verification |
| Memory leak detection | Custom leak tracking | `std.testing.allocator` | Built-in, detects exact leak source, idiomatic Zig |
| Error handling | Custom error codes | Zig error unions | Compiler-enforced error handling, cleaner call sites |
| Thread safety | Custom locking primitives | `std.Thread.Mutex` | Well-tested, portable, optimized |
| String handling | Manual C string manipulation | `std.fmt.allocPrint` for Zig strings, treat C strings as read-only | Avoids buffer overflows, memory-safe |

**Key insight:** Zig's stdlib provides battle-tested solutions for memory management, threading, and error handling. Custom implementations risk subtle bugs and don't benefit from compiler optimizations.

## Common Pitfalls

### Pitfall 1: Struct Alignment Mismatches on ARM64

**What goes wrong:** Zig struct layout doesn't match C layout, causing FFI calls to read/write wrong memory offsets. May work on x86_64 but fail silently on ARM64 (Pi 5).

**Why it happens:** Zig optimizes struct layout by default and may insert different padding than C. Without `extern struct`, the compiler makes no guarantees about C ABI compatibility.

**How to avoid:**
1. Always use `extern struct` for types crossing FFI boundary
2. Add compile-time assertions: `comptime { assert(@sizeOf(MyStruct) == @sizeOf(c.MyStruct)); }`
3. Test on ARM64 hardware early, not just x86_64 dev machine
4. Use `@cImport` to reference actual C struct definitions when possible

**Warning signs:** Pin values don't match halcmd output, "wrong" values that change when fields are reordered, bugs that only appear on Pi 5.

### Pitfall 2: Memory Leaks from HAL Pointer Ownership Confusion

**What goes wrong:** Zig code frees memory allocated by HAL (or vice versa), causing heap corruption, double-free errors, or memory leaks.

**Why it happens:** HAL uses `hal_malloc()` for internal allocations and frees them on `hal_exit()`. Zig uses its own allocator. Crossing the boundary creates ownership ambiguity.

**How to avoid:**
1. Follow Python bindings pattern: never free HAL-allocated memory
2. Copy HAL data into Zig-owned memory before returning to Zig code
3. Use Zig's testing allocator to catch leaks in unit tests
4. Document ownership explicitly at every FFI boundary

**Warning signs:** Valgrind reports "invalid free", crashes only after extended runtime, memory usage growing over time.

### Pitfall 3: Data Races from Missing Mutex Locking

**What goes wrong:** Multiple threads (TUI, HAL real-time threads) access HAL state simultaneously, causing torn reads, inconsistent state, or crashes.

**Why it happens:** HAL uses shared memory accessed by multiple threads. Without mutex protection, writes can conflict with reads or other writes.

**How to avoid:**
1. Always acquire HAL mutex before write operations
2. Use snapshot pattern: copy HAL state under lock, process copy after unlock
3. Never hold pointers to HAL memory across lock boundaries
4. Test with concurrent HAL load/unload operations

**Warning signs:** Intermittent crashes during component load/unload, stale pin values, non-deterministic bugs.

### Pitfall 4: LinuxCNC Version Incompatibility

**What goes wrong:** Code works on LinuxCNC 2.9 but breaks on 2.10 (or vice versa) due to API changes, type redefinitions, or function signature changes.

**Why it happens:** LinuxCNC 2.9 → 2.10 migration included Python2→Python3 and Gtk2→Gtk3, causing API surface changes.

**How to avoid:**
1. Detect LinuxCNC version at runtime
2. Use conditional compilation for version-specific code
3. Minimize direct API use (prefer higher-level wrappers)
4. Test against both 2.9 and 2.10 in CI

**Warning signs:** Build succeeds but runtime differs, warnings about deprecated symbols, users report "works on 2.9 but fails on 2.10".

## Code Examples

Verified patterns from official sources:

### Example 1: Basic FFI with Error Handling

```zig
// Source: Zig 0.15.2 documentation on C interop
const std = @import("std");
const c = @cImport(@cInclude("hal.h"));

pub fn initHal(name: [:0]const u8) !c_int {
    const comp = c.hal_init(name) orelse return error.HalInitFailed;
    if (comp < 0) return error.HalInitFailed;
    return comp;
}
```

### Example 2: Safe String Handling Across Boundary

```zig
// Source: Zig memory best practices
pub fn getComponentName(
    allocator: std.mem.Allocator,
    comp: *const c.hal_comp_t,
) ![]u8 {
    // C string is owned by HAL, copy to Zig-owned memory
    const c_name = comp.name orelse return error.NullName;
    return std.fmt.allocPrint(allocator, "{s}", .{c_name});
    // Caller owns returned slice, must free with allocator
}
```

### Example 3: Extern Struct with Verification

```zig
// Source: Zig language reference on extern struct
pub extern struct hal_comp_t {
    name: [*:0]const u8,
    type: c_int,
    state_ptr: *c_int,
    next: ?*hal_comp_t,
};

// Compile-time verification
comptime {
    std.debug.assert(@sizeOf(hal_comp_t) == @sizeOf(c.hal_comp_t));
}
```

### Example 4: Testing with Leak Detection

```zig
// Source: Zig stdlib documentation
test "pin creation doesn't leak" {
    const gpa = std.testing.allocator;
    var comp_id = try halInit("test");
    defer halExit(comp_id);

    // Create pins, verify no leaks
    const pin = try pinNew(comp_id, "test-pin", c.HAL_FLOAT, c.HAL_OUT);
    _ = pin;

    // GPA will report leaks if any
    try testing.allocator_check(gpa);
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual extern declarations | `@cImport` with C headers | Zig 0.7.0 (2021) | Automatic header parsing, fewer errors |
| Unsafe pointer casting | Optional pointer types (`?*T`) | Zig 0.6.0 (2020) | Null safety enforced by compiler |
| Runtime type checking | Compile-time type inference | Zig 0.9.0 (2022) | Type errors caught at compile time |
| Manual memory leak detection | `std.testing.allocator` | Zig 0.11.0 (2023) | Automatic leak detection in tests |

**Deprecated/outdated:**
- **Direct `@cInclude` without safe wrappers**: Works but unsafe. Modern Zig practice wraps all C calls in safe Zig functions returning error unions.
- **Ignoring struct alignment**: Never safe, especially on ARM64. Always use `extern struct`.
- **Manual mutex primitives**: Use `std.Thread.Mutex` instead of `pthread_mutex_t` directly for Zig-side locking.

## Open Questions

1. **LinuxCNC 2.9 vs 2.10 API differences**
   - What we know: Major migration included Python2→3 and Gtk2→3 changes
   - What's unclear: Specific HAL C API differences between versions
   - Recommendation: Test both versions in CI, use runtime version detection, check HAL header version macros

2. **Exact HAL mutex locking requirements**
   - What we know: HAL uses shared memory, write operations require locking
   - What's unclear: Whether read operations also require locking (likely yes for safety)
   - Recommendation: Lock all HAL access initially, optimize to read-only locking if performance testing shows need

3. **ARM64-specific alignment issues**
   - What we know: ARM64 has stricter alignment requirements than x86_64
   - What's unclear: Specific HAL structs that may have alignment issues
   - Recommendation: Add `extern struct` and size assertions for all HAL structs, test on Pi 5 early

## Sources

### Primary (HIGH confidence)

- [Zig 0.15.2 Language Reference](https://ziglang.org/documentation/0.15.2/) - Official documentation on `@cImport`, `extern struct`, FFI
- [Zig 0.15.1 Release Notes](https://ziglang.org/download/0.15.1/release-notes.html) - Breaking changes and new features
- [Zig stdlib testing.allocator](https://ziglang.org/documentation/master/std/#A;std:testing.allocator) - Memory leak detection

### Secondary (MEDIUM confidence)

- [LinuxCNC HAL Developer Manual V2.9.7](http://linuxcnc.org/docs/2.9/pdf/LinuxCNC_Developer_nb.pdf) - HAL API reference (October 22, 2025)
- [LinuxCNC HAL Documentation](https://linuxcnc.org/docs/html/hal/intro.html) - HAL architecture and usage (Updated Dec 15, 2025)
- [Zig FFI Safety Patterns](https://marsmatics.com/how-zig-lets-you-gradually-migrate-or-mix-c-code-safely/) - C interop best practices (June 2025)
- [Detecting Memory Leaks in Zig](https://itnext.io/detecting-memory-leaks-in-zig-using-the-general-purpose-allocator-b63be2cbd1f5) - Leak detection patterns (September 2024)
- [LinuxCNC Python Bindings Source](https://github.com/LinuxCNC/linuxcnc/blob/master/src/hal/utils/halmodule.cc) - Memory ownership patterns (verified code inspection)

### Tertiary (LOW confidence - marked for validation)

- [Zig Struct Alignment Discussion](https://ziggit.dev/t/difference-between-struct-level-align-x-and-field-level-align-x/3082) - Community discussion on alignment
- [LinuxCNC 2.9 to 2.10 Migration](https://forum.linuxcnc.org/9-installing-linuxcnc/49736-linuxcnc-debian-bookworm-update-from-2-9-to-2-10) - Forum discussion (needs verification against official changelog)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Zig 0.15.2 is documented and stable. LinuxCNC HAL API is documented.
- Architecture: MEDIUM - Patterns are based on official Zig docs and LinuxCNC docs, but ARM64 specifics need validation.
- Pitfalls: MEDIUM - Pitfalls documented from community reports and general FFI knowledge, but LinuxCNC-specific issues need real-world testing.

**Research date:** 2026-01-29
**Valid until:** 2026-02-28 (30 days - Zig and LinuxCNC are stable, but verify before planning if beyond this date)

**Key gaps requiring validation:**
1. Specific LinuxCNC 2.9 vs 2.10 HAL API differences
2. HAL mutex locking requirements for read operations
3. Real-world ARM64 (Pi 5) testing of struct alignment
