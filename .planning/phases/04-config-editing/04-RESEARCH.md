# Phase 04: Configuration & Editing - Research

**Researched:** 2026-01-29
**Domain:** LinuxCNC HAL runtime manipulation, FFI signal creation, TUI dialog patterns
**Confidence:** HIGH

## Summary

This phase focuses on three core capabilities: (1) Creating new HAL signals and linking pins to them via FFI, (2) Saving current HAL configuration to halcmd-compatible format, and (3) Building TUI dialogs for multi-step signal creation workflows.

**Primary recommendations:**
- Use `hal_signal_new()` and `hal_link()` C API functions for runtime signal creation
- Follow halcmd save format: `net signame pin1 pin2...` for signals, `setp param value` for parameters
- Build modal dialog widget using vxfw pattern (SubSurface with input fields)
- Reuse existing FFI safety patterns from Phase 3 (mutex locking, error unions)

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| LinuxCNC HAL API | 2.9.7+ | Signal/pin manipulation | Official API for runtime HAL changes |
| vxfw (Vaxis framework) | Current | TUI modal dialogs | Already used in Phase 3, automatic redraw |
| Existing FFI layer | Phase 1 | hal_signal_new, hal_link wrappers | Follow established patterns |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Zig stdlib | 0.15.1 | ArrayList for dialog buffers | Form input management |
| Zig stdlib | 0.15.1 | StringHashMap for pin selection | Tracking multi-select state |
| Zig stdlib | 0.15.1 | Buffered file writer | Saving HAL configuration |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| hal_signal_new + hal_link | net command via system() | Loses FFI safety, no error handling |
| vxfw modal dialogs | Split-screen overlay | More complex state management |
| Direct file write | halcmd save subprocess | Adds external dependency, slower |

**Installation:**
No new dependencies required. All libraries already in use from Phase 3.

## Architecture Patterns

### Recommended Project Structure

```
src/
├── ffi/
│   └── safe.zig          # Add halSignalNew, halLink, halUnlink
├── tui/
│   ├── widgets/
│   │   └── dialog.zig    # NEW: Modal dialog widget
│   ├── model.zig         # Extend with dialog state
│   └── app.zig           # Add key bindings for dialogs
├── hal/
│   └── export.zig        # NEW: Configuration export module
└── state/
    └── cache.zig         # May need direction flag tracking
```

### Pattern 1: FFI Signal Creation

**What:** Wrap LinuxCNC's hal_signal_new and hal_link functions with Zig safety

**When to use:** CORE-08 requirement - creating signals and linking pins at runtime

**Example:**
```zig
// Source: https://linuxcnc.org/docs/html/man/man3/hal_signal_new.3hal.html
// Function signature: int hal_signal_new(const char *signal_name, hal_type_t type)

pub fn halSignalNew(name: [:0]const u8, hal_type: hal_type_t) !void {
    const rc = c.hal_signal_new(name, hal_type);
    if (rc != 0) return HalError.InitFailed;
}

// Function signature: int hal_link(const char *pin_name, const char *signal_name)

pub fn halLink(pin_name: [:0]const u8, signal_name: [:0]const u8) !void {
    // Acquire HAL mutex before linking
    _ = c.hal_mutex_lock(c.hal_mutex.ptr);
    defer c.hal_mutex_unlock(c.hal_mutex.ptr);

    const rc = c.hal_link(pin_name, signal_name);
    if (rc != 0) return HalError.LinkFailed;
}

pub fn halUnlink(pin_name: [:0]const u8) !void {
    _ = c.hal_mutex_lock(c.hal_mutex.ptr);
    defer c.hal_mutex_unlock(c.hal_mutex.ptr);

    const rc = c.hal_unlink(pin_name);
    if (rc != 0) return HalError.UnlinkFailed;
}
```

### Pattern 2: TUI Modal Dialog

**What:** SubSurface-based modal dialog for multi-input forms

**When to use:** Signal creation requires name, type, and pin selection

**Example:**
```zig
// vxfw pattern for modal dialogs
pub const SignalDialog = struct {
    visible: bool = false,
    signal_name: ArrayList(u8),
    signal_type: hal_type_t = HAL_BIT,
    selected_pins: ArrayList([]const u8),
    current_step: u8 = 1, // 1=name, 2=type, 3=pins, 4=confirm

    pub fn draw(self: *const SignalDialog, ctx: vxfw.DrawContext) !void {
        if (!self.visible) return;

        // Draw centered modal box
        const width = @min(60, ctx.max.width);
        const height = 20;
        const x = (ctx.max.width - width) / 2;
        const y = (ctx.max.height - height) / 2;

        // Use SubSurface for modal overlay
        const modal_surface = try ctx.subSurface(.{
            .x_off = x,
            .y_off = y,
            .width = width,
            .height = height,
        });

        // Draw dialog content based on current_step
        // Step 1: Signal name input
        // Step 2: Type selection (bit/s32/u32/float)
        // Step 3: Pin selection (multi-select from table)
        // Step 4: Confirmation and creation
    }
};
```

### Pattern 3: Configuration Export

**What:** Generate halcmd-compatible file from current HAL state

**When to use:** CORE-11 requirement - save configuration for backup/restoration

**Example:**
```zig
pub fn exportHalConfiguration(
    allocator: std.mem.Allocator,
    store: *const StateStore,
    writer: anytype,
) !void {
    // Export signals with pin connections
    // Format: net signame pin1 pin2 pin3...
    try writer.print("# HAL configuration exported by haltune\n", .{});
    try writer.print("# Generated: {s}\n\n", .{timestamp});

    // Export signals
    var sig_iter = store.listSignals();
    while (sig_iter.next()) |sig_name| {
        const sig_value = try store.getSignal(sig_name);
        // Find pins linked to this signal
        // Format: net signame pin1 <= pin2 <= pin3
        try writer.print("net {s}", .{sig_name});
        // TODO: Add linked pins from cache
        try writer.writeAll("\n");
    }

    // Export parameters
    try writer.writeAll("\n# Parameters\n");
    var param_iter = store.listParams();
    while (param_iter.next()) |param_name| {
        const param_value = try store.getParam(param_name);
        // Format: setp param.name value
        switch (param_value) {
            .bit => |v| try writer.print("setp {s} {}\n", .{param_name, v}),
            .float => |v| try writer.print("setp {s} {d}\n", .{param_name, v}),
            .s32 => |v| try writer.print("setp {s} {}\n", .{param_name, v}),
            .u32 => |v| try writer.print("setp {s} {}\n", .{param_name, v}),
        }
    }
}
```

### Anti-Patterns to Avoid

- **Blocking TUI during FFI calls:** Use async pattern or keep FFI calls fast (signal creation is fast)
- **Forgetting HAL mutex:** All HAL write operations must acquire mutex
- **Type mismatches in net command:** All pins on signal must have same type as signal
- **Leaking dialog buffers:** Always ArrayList.deinit() dialog buffers on close

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| File writing | Manual formatting with string concatenation | std.io.BufferedWriter | Handles newlines, buffering, error propagation |
| Multi-step wizard | Custom state machine | Simple step counter + enum | Dialog pattern is well-established |
| Pin selection UI | Custom list widget | Reuse DataTable with multi-select | DataTable already has item display |
| Input validation | Manual parsing per type | Switch on hal_type_t | Centralized validation logic |

**Key insight:** Configuration export is just text formatting. Don't build a template engine - use print/format with string literals.

## Common Pitfalls

### Pitfall 1: HAL Mutex Deadlock

**What goes wrong:** Calling HAL functions while holding RwLock causes deadlock

**Why it happens:** HAL has internal mutex; StateStore has RwLock. Lock order inversion = deadlock.

**How to avoid:**
1. Never call HAL FFI while holding StateStore lock
2. Acquire HAL mutex before all hal_signal_new/hal_link calls
3. Release HAL mutex immediately after FFI call

**Warning signs:** Application hangs during signal creation or linking

### Pitfall 2: Type Mismatch in Signals

**What goes wrong:** hal_link fails when pin type != signal type

**Why it happens:** hal_signal_new creates signal with specific type, pins must match

**How to avoid:**
1. Check pin type before allowing selection
2. Validate type match in dialog step 3 (pin selection)
3. Filter available pins by signal type
4. Show error if user tries to link mismatched types

**Code:**
```zig
// In pin selection step
const pin_type = store.getPinType(pin_name);
if (pin_type != dialog.signal_type) {
    return error.TypeMismatch;
}
```

### Pitfall 3: Missing Linked Pin Information

**What goes wrong:** Export doesn't show which pins are linked to which signals

**Why it happens:** Current StateStore only tracks values, not pin->signal relationships

**How to avoid:**
1. Extend StateStore to track signal links (HashMap: pin_name -> signal_name)
2. Update refresh thread to capture hal_pin_t.signal pointer
3. Export format: `net signame pin1 pin2 pin3` (all pins on same signal)

**Detection:** Export shows `net signame` with no pins listed

### Pitfall 4: Dialog State Persistence

**What goes wrong:** Dialog buffers leak memory or show stale data

**Why it happens:** ArrayList not deinitialized when dialog closes

**How to avoid:**
1. Deinit all ArrayList fields in closeDialog()
2. Reset step counter to 1
3. Clear selected_pins list
4. Set visible = false

**Detection:** Memory usage grows each time dialog is opened

## Code Examples

### Signal Creation FFI Wrapper

```zig
// Source: LinuxCNC hal.h man pages
// https://linuxcnc.org/docs/html/man/man3/hal_signal_new.3hal.html

const c = @import("c.zig").c;
const HalError = @import("errors.zig").HalError;
const hal_type_t = @import("types.zig").hal_type_t;

/// Create a new HAL signal
/// Returns: error.InitFailed if signal already exists or type invalid
pub fn halSignalNew(name: [:0]const u8, hal_type: hal_type_t) !void {
    const rc = c.hal_signal_new(name, @intFromEnum(hal_type));
    if (rc != 0) return HalError.InitFailed;
}

/// Link a pin to a signal
/// Returns: error.LinkFailed if pin/signal not found or types don't match
pub fn halLink(pin_name: [:0]const u8, signal_name: [:0]const u8) !void {
    _ = c.hal_mutex_lock(c.hal_mutex.ptr);
    defer c.hal_mutex_unlock(c.hal_mutex.ptr);

    const rc = c.hal_link(pin_name, signal_name);
    if (rc != 0) return HalError.LinkFailed;
}

/// Unlink a pin from its signal
pub fn halUnlink(pin_name: [:0]const u8) !void {
    _ = c.hal_mutex_lock(c.hal_mutex.ptr);
    defer c.hal_mutex_unlock(c.hal_mutex.ptr);

    const rc = c.hal_unlink(pin_name);
    if (rc != 0) return HalError.UnlinkFailed;
}
```

### Dialog Input Validation

```zig
// Validate signal name input
fn validateSignalName(name: []const u8) !void {
    if (name.len == 0) return error.EmptyName;
    if (name.len > HAL_NAME_LEN) return error.NameTooLong;
    // Check for invalid characters
    for (name) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '-' and c != '.') {
            return error.InvalidCharacter;
        }
    }
}

// Validate numeric value for setp
fn validateNumericValue(text: []const u8, hal_type: hal_type_t) !HalValue {
    switch (hal_type) {
        .HAL_BIT => {
            if (std.mem.eql(u8, text, "1") or std.mem.eql(u8, text, "true")) {
                return HalValue{ .bit = true };
            }
            if (std.mem.eql(u8, text, "0") or std.mem.eql(u8, text, "false")) {
                return HalValue{ .bit = false };
            }
            return error.InvalidBitValue;
        },
        .HAL_FLOAT => {
            const value = try std.fmt.parseFloat(f64, text);
            return HalValue{ .float = value };
        },
        .HAL_S32 => {
            const value = try std.fmt.parseInt(i32, text, 10);
            return HalValue{ .s32 = value };
        },
        .HAL_U32 => {
            const value = try std.fmt.parseInt(u32, text, 10);
            return HalValue{ .u32 = value };
        },
    }
}
```

### Multi-Step Dialog State Machine

```zig
pub const DialogStep = enum(u8) {
    input_name = 1,
    select_type = 2,
    select_pins = 3,
    confirm = 4,
};

pub fn handleDialogKey(self: *SignalDialog, key: vxfw.Key) !void {
    switch (self.current_step) {
        .input_name => {
            // Handle alphanumeric input, backspace
            // Enter advances to step 2 if name valid
            if (key == .Enter) {
                try validateSignalName(self.signal_name.items);
                self.current_step = .select_type;
            }
        },
        .select_type => {
            // Arrow keys cycle through types
            // Enter advances to step 3
            if (key == .Enter) {
                self.current_step = .select_pins;
            }
        },
        .select_pins => {
            // Space toggles pin selection
            // Enter advances to step 4
            if (key == .Enter and self.selected_pins.items.len > 0) {
                self.current_step = .confirm;
            }
        },
        .confirm => {
            // 'y' creates signal and links pins
            // 'n' or Escape closes dialog
            if (key == .Char and key.Char == 'y') {
                try self.createSignal();
            }
        },
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| halcmd newsig + linkps | halcmd net | LinuxCNC 2.5+ | Single command creates signal AND links pins |
| Separate dialog per pin | Multi-step wizard | Modern TUI standard | Better UX for complex operations |
| Save all to single file | Selective export (signals/params) | halcmd -s flag | Users can save partial configs |

**Deprecated/outdated:**
- **newsig command**: Replaced by `net` command (auto-creates signal)
- **linkps/linksp commands**: Replaced by `net` command
- **Separate signal creation workflow**: Modern pattern is combined signal+link in one operation

## Open Questions

1. **Pin direction tracking in StateStore**
   - What we know: hal_pin_t has dir field (HAL_IN/HAL_OUT/HAL_IO)
   - What's unclear: Current cache.zig doesn't store pin direction
   - Recommendation: Extend StateStore to track pin direction (needed for linking validation)

2. **Signal-to-pin mapping in cache**
   - What we know: hal_pin_t has signal pointer (null or linked signal)
   - What's unclear: Current cache doesn't track which pins are linked to which signal
   - Recommendation: Add pin_links HashMap to StateStore for export format

3. **Dialog cancellation state cleanup**
   - What we know: ArrayList must be deinitialized
   - What's unclear: Should we save draft state or discard on cancel?
   - Recommendation: Discard on cancel (simpler, matches halcmd behavior)

## Sources

### Primary (HIGH confidence)

- [hal_signal_new(3hal) man page](https://linuxcnc.org/docs/html/man/man3/hal_signal_new.3hal.html) - Official function signatures and return codes
- [halcmd(1) man page](https://linuxcnc.org/docs/html/man/man1/halcmd.1.html) - Complete command reference including `net`, `save`, `setp`
- [LinuxCNC HAL Examples](https://linuxcnc.org/docs/html/hal/hal-examples.html) - Real-world HAL file format examples with `net` and `setp` commands
- [LinuxCNC source: hal.h](https://github.com/LinuxCNC/linuxcnc/blob/master/src/hal/hal.h) - Authoritative C API definitions

### Secondary (MEDIUM confidence)

- [HAL Basics Documentation](https://linuxcnc.org/docs/html/hal/basic-hal.html) - Signal creation workflow verified against official docs
- [GitHub HAL file examples](https://github.com/flosse/linuxcnc-mirror/blob/master/docs/src/hal/pyvcp_examples_pl.txt) - Real-world `.hal` file format patterns

### Tertiary (LOW confidence)

- [TUI form validation patterns](https://medium.com/@Nexumo_/8-tui-patterns-to-turn-python-scripts-into-apps-ce6f964d3b6f) - General TUI patterns, not Vaxis-specific (verified against Vaxis examples)
- [libvaxis GitHub](https://github.com/rockorager/libvaxis) - Vaxis TUI library (examples section referenced for SubSurface pattern)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All components verified against official LinuxCNC documentation
- Architecture: HIGH - FFI patterns proven in Phase 1-3, TUI patterns from Vaxis examples
- Pitfalls: HIGH - Mutex deadlock documented in Phase 2 RESEARCH.md, type mismatches in hal_link man page

**Research date:** 2026-01-29
**Valid until:** 2026-03-01 (60 days - LinuxCNC 2.9/2.10 API is stable)
