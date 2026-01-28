# Architecture Research

**Domain:** LinuxCNC HAL management tools with TUI and plugin architecture
**Researched:** 2025-01-28
**Confidence:** HIGH

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                          User Interface                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐        │
│  │ Browser  │  │  Editor  │  │ Plugin   │  │ Settings │        │
│  │  View    │  │  View    │  │  View    │  │  View    │        │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘        │
│       └─────────────┴─────────────┴─────────────┴──────────────┘ │
│                            ↓                                     │
├─────────────────────────────────────────────────────────────────┤
│                      Application Logic                          │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    State Management                       │  │
│  │  • HAL Values (pins, signals, params)                     │  │
│  │  • User Preferences                                       │  │
│  │  • Watch Lists                                            │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    Plugin Manager                         │  │
│  │  • Discovery                                              │  │
│  │  • Loading                                                │  │
│  │  • Execution                                              │  │
│  └──────────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│                      HAL Abstraction Layer                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ HAL Wrapper  │  │  Config      │  │  Real-time   │          │
│  │   (FFI)      │  │  Loader      │  │  Updates     │          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
└─────────┼──────────────────┼──────────────────┼──────────────────┘
          ↓                  ↓                  ↓
┌─────────────────────────────────────────────────────────────────┐
│                    LinuxCNC HAL (C API)                        │
│  • Shared Memory  • Pins  • Signals  • Parameters  • Threads   │
└─────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Communicates With |
|-----------|----------------|-------------------|
| **TUI Framework (Vaxis)** | Terminal rendering, event handling, layout management | Application State, Views |
| **HAL Wrapper** | Safe FFI interface to LinuxCNC HAL C API | State Manager, Config Loader |
| **State Manager** | Centralized state cache, change notifications, threading | All components |
| **Config Loader** | Parse INI/HAL files, detect riocore/machine configs | HAL Wrapper, State Manager |
| **Plugin Manager** | Discover, load, execute domain-specific plugins | State Manager, HAL Wrapper |
| **View: Browser** | Navigate HAL hierarchy, view pin/signal/param values | State Manager, HAL Wrapper |
| **View: Editor** | Modify HAL values, create watch lists | State Manager, Config Loader |
| **View: Plugin UI** | Execute plugin operations, display plugin-specific UI | Plugin Manager, State Manager |

## Recommended Project Structure

```
src/
├── main.zig                 # Application entry point
├── ffi/                     # LinuxCNC HAL C API bindings
│   ├── hal.zig             # Core HAL definitions and types
│   ├── hal_lib.zig         # Direct C library imports
│   └── safe_wrapper.zig    # Safe abstractions over raw HAL API
├── hal/                     # HAL interaction layer
│   ├── component.zig       # Component discovery and inspection
│   ├── pin.zig             # Pin operations (read/write/watch)
│   ├── signal.zig          # Signal inspection and linking
│   ├── param.zig           # Parameter operations
│   ├── thread.zig          # Thread inspection
│   └── watcher.zig         # Real-time value monitoring
├── config/                  # Configuration parsing
│   ├── ini.zig             # INI file parser
│   ├── hal_file.zig        # .hal file parser
│   └── detector.zig        # Machine/riocore detection
├── state/                   # State management
│   ├── store.zig           # Central state container
│   ├── subscription.zig    # Pub/sub for value changes
│   └── cache.zig           # Cached HAL values
├── ui/                      # TUI implementation
│   ├── app.zig             # Main Vaxis application
│   ├── views/
│   │   ├── browser.zig     # Pin/signal/param browser
│   │   ├── editor.zig      # Value editing interface
│   │   ├── plugin.zig      # Plugin execution UI
│   │   └── settings.zig    # Configuration UI
│   ├── widgets/
│   │   ├── tree.zig        # HAL hierarchy tree widget
│   │   ├── value.zig       # Value display widget
│   │   └── watchlist.zig   # Watch list widget
│   └── layout.zig          # Screen layout management
├── plugin/                  # Plugin system
│   ├── manager.zig         # Plugin discovery and loading
│   ├── registry.zig        # Plugin metadata registry
│   ├── interface.zig       # Plugin API definitions
│   └── builtin/            # Built-in plugins
│       ├── pid_tuner.zig
│       ├── stepper_cal.zig
│       └── ...
└── utils/                   # Utilities
    ├── thread_pool.zig     # Background task management
    ├── logger.zig          # Logging utilities
    └── allocator.zig       # Memory management
```

### Structure Rationale

- **ffi/**: Isolates all unsafe C interop at the bottom of the dependency tree
- **hal/**: Provides safe, idiomatic Zig wrappers for HAL operations
- **state/**: Central state management enables clean separation between HAL and UI
- **ui/**: All Vaxis-specific code isolated here for easy TUI framework swaps
- **plugin/**: Plugin system as top-level feature with clear API boundary
- **config/**: Configuration loading independent of HAL operations

## Architectural Patterns

### Pattern 1: Safe FFI Wrapper Layer

**What:** Wraps all unsafe C API calls in safe Zig abstractions with proper error handling and memory management.

**When to use:** All interactions with LinuxCNC HAL C API.

**Trade-offs:**
- Pro: Leverages Zig's first-class C interop without sacrificing safety
- Pro: Clear boundary between safe and unsafe code
- Con: Initial overhead to write wrapper functions
- Con: May need to update when LinuxCNC API changes

**Example:**
```zig
// src/hal/pin.zig
const hal = @import("../ffi/hal.zig");
const std = @import("std");

pub const Pin = struct {
    id: hal.pin_id_t,
    name: []const u8,
    type: PinType,
    direction: PinDirection,

    pub const Type = enum {
        bit,
        float,
        s32,
        u32,
    };

    pub const Direction = enum {
        input,
        output,
        io,
    };

    /// Safely read a pin value
    pub fn read(self: Pin, allocator: std.mem.Allocator) !Value {
        switch (self.type) {
            .bit => {
                const val = hal.hal_get_bit(self.id) orelse return error.HalReadFailed;
                return Value{ .bit = val };
            },
            .float => {
                const val = hal.hal_get_float(self.id) orelse return error.HalReadFailed;
                return Value{ .float = val };
            },
            // ... other types
        }
    }

    /// Safely write to a writable pin
    pub fn write(self: Pin, value: Value) !void {
        if (self.direction == .input) return error.PinNotWritable;

        switch (self.type) {
            .bit => hal.hal_set_bit(self.id, value.bit) orelse return error.HalWriteFailed,
            .float => hal.hal_set_float(self.id, value.float) orelse return error.HalWriteFailed,
            // ... other types
        }
    }
};
```

### Pattern 2: Centralized State Store with Pub/Sub

**What:** Single source of truth for all application state with subscription-based change notifications.

**When to use:** Anytime multiple UI components need to react to HAL value changes.

**Trade-offs:**
- Pro: Single source of truth prevents state inconsistency
- Pro: Pub/sub enables reactive UI updates
- Pro: Easy to add change logging for debugging
- Con: More boilerplate than direct component state
- Con: Potential performance issues with many subscribers

**Example:**
```zig
// src/state/store.zig
const std = @import("std");

pub const Store = struct {
    mutex: std.Thread.Mutex,
    hal_values: std.StringHashMap(Value),
    subscribers: std.ArrayList(Subscriber),

    pub const Subscriber = struct {
        callback: *const fn ([]const u8, Value) void,
        filter: ?[]const u8 = null, // Optional name prefix filter
    };

    pub fn init(allocator: std.mem.Allocator) Store {
        return Store{
            .mutex = std.Thread.Mutex{},
            .hal_values = std.StringHashMap(Value).init(allocator),
            .subscribers = std.ArrayList(Subscriber).init(allocator),
        };
    }

    /// Update a HAL value and notify subscribers
    pub fn update(store: *Store, name: []const u8, value: Value) !void {
        store.mutex.lock();
        defer store.mutex.unlock();

        try store.hal_values.put(name, value);

        // Notify matching subscribers
        for (store.subscribers.items) |sub| {
            if (sub.filter) |filter| {
                if (!std.mem.startsWith(u8, name, filter)) continue;
            }
            sub.callback(name, value);
        }
    }

    /// Subscribe to value changes
    pub fn subscribe(store: *Store, subscriber: Subscriber) !void {
        store.mutex.lock();
        defer store.mutex.unlock();

        try store.subscribers.append(subscriber);
    }

    /// Get current value
    pub fn get(store: *Store, name: []const u8) ?Value {
        store.mutex.lock();
        defer store.mutex.unlock();

        return store.hal_values.get(name);
    }
};
```

### Pattern 3: View-Plugin Architecture

**What:** Plugins provide domain-specific workflows as reusable view components that integrate with main UI.

**When to use:** Domain-specific operations (PID tuning, stepper calibration, etc.) that don't belong in core.

**Trade-offs:**
- Pro: Extensible without modifying core
- Pro: Domain experts can contribute plugins
- Pro: Clear API boundary enforces separation
- Con: Plugin API must be stable
- Con: Dynamic plugin loading in Zig is challenging (LOW confidence - see Pitfalls)

**Example:**
```zig
// src/plugin/interface.zig
const std = @import("std");
const Store = @import("../state/store.zig").Store;

pub const Plugin = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8,

    // Plugin lifecycle
    init: *const fn (*std.mem.Allocator, *Store) anyerror!Context,
    deinit: *const fn (Context) void,

    // View rendering (receives Vaxis widget to draw into)
    render: *const fn (Context, anytype) anyerror!void,

    // Event handling
    handle_event: *const fn (Context, Event) anyerror!void,

    pub const Context = *anyopaque;
    pub const Event = union(enum) {
        key_press: []const u8,
        hal_change: struct { name: []const u8, value: Value },
    };
};

// Example: PID tuner plugin
// src/plugin/builtin/pid_tuner.zig
export const pid_tuner_plugin: Plugin = .{
    .name = "PID Tuner",
    .version = "1.0.0",
    .description = "Interactive PID loop tuning assistant",

    .init = pidTunerInit,
    .deinit = pidTunerDeinit,
    .render = pidTunerRender,
    .handle_event = pidTunerHandleEvent,
};
```

## Data Flow

### Request Flow

```
[User Input]
    ↓
[Vaxis Event] → [UI Component] → [State Manager]
    ↓              ↓                  ↓
[Action]      [View Update]    [HAL Wrapper Call]
                                   ↓
                            [C API Call to LinuxCNC]
                                   ↓
                            [HAL Shared Memory Update]
```

### Real-time Update Flow

```
[LinuxCNC HAL Thread]
    ↓ (writes to shared memory)
[Background Watcher Thread]
    ↓ (polls or receives notification)
[HAL Wrapper] → [State Manager]
    ↓              ↓ (publishes change)
[Update Cache] → [Subscribers]
                       ↓
                  [UI Components]
                       ↓
                  [Vaxis Redraw]
```

### Key Data Flows

1. **PIN VALUE READ:** UI View → State Manager → HAL Wrapper → FFI → LinuxCNC
2. **PIN VALUE WRITE:** UI View → State Manager → HAL Wrapper → FFI → LinuxCNC → Update Notification
3. **CONFIG LOAD:** Config Loader → INI/HAL Parser → State Manager (updates config, not HAL values)
4. **PLUGIN EXECUTION:** UI Plugin View → Plugin Manager → Plugin Code → HAL Wrapper → LinuxCNC

## Component Boundaries

### FFI Layer (Bottom Boundary)

**Responsibility:** Translate between Zig and C
- Contains all `extern` function declarations
- Handles C memory management
- Converts between C and Zig types

**Never contains:**
- Business logic
- UI code
- State management

**Communicates with:** HAL wrapper only

### HAL Wrapper (Safe Abstraction)

**Responsibility:** Provide safe Zig API for HAL operations
- Pin/signal/param discovery
- Type-safe read/write operations
- Error handling and propagation

**Never contains:**
- Direct UI rendering
- Plugin logic
- Configuration parsing

**Communicates with:** FFI layer (below), State Manager (above)

### State Manager (Central Hub)

**Responsibility:** Maintain application state
- Cache current HAL values
- Manage subscriptions
- Coordinate updates

**Never contains:**
- UI rendering
- Direct HAL access (through FFI)

**Communicates with:** All components

### UI Layer (Top Boundary)

**Responsibility:** User interaction and display
- Render TUI with Vaxis
- Handle user input
- Display state

**Never contains:**
- Direct HAL access
- Business logic
- State mutations (through State Manager only)

**Communicates with:** State Manager, Plugin Manager

### Plugin System (Extension Point)

**Responsibility:** Enable domain-specific workflows
- Discover plugins
- Provide plugin API
- Execute plugin operations

**Never contains:**
- Core UI layout
- HAL wrapper implementation

**Communicates with:** State Manager, UI Layer, HAL Wrapper (through API)

## Build Order & Dependencies

### Phase 1: Foundation (no UI)
1. **FFI Layer** (`src/ffi/`)
   - No dependencies on other project code
   - Defines all C interop
   - Unit test with mock LinuxCNC library

2. **HAL Wrapper** (`src/hal/`)
   - Depends only on FFI layer
   - Implement pin/signal/param operations
   - Test against real LinuxCNC instance

3. **State Manager** (`src/state/`)
   - Depends only on HAL wrapper
   - Implement cache and pub/sub
   - Test with simulated HAL changes

### Phase 2: Configuration
4. **Config Loader** (`src/config/`)
   - Depends on: FFI layer (for types)
   - Implement INI/HAL file parsing
   - Test with sample config files

### Phase 3: UI Foundation
5. **TUI Framework Integration** (`src/ui/app.zig`)
   - Depends on: State Manager
   - Basic Vaxis setup and event loop
   - Test with simple static views

6. **Basic Views** (`src/ui/views/`)
   - Depends on: State Manager, Vaxis
   - Implement browser and editor views
   - Test with mock HAL data

### Phase 4: Plugins
7. **Plugin System** (`src/plugin/`)
   - Depends on: State Manager, UI framework
   - Implement plugin manager and API
   - Create 1-2 example plugins

### Phase 5: Integration
8. **Main Application** (`src/main.zig`)
   - Wire all components together
   - Command-line argument handling
   - Integration testing

## Anti-Patterns

### Anti-Pattern 1: Direct FFI in UI Code

**What people do:** Call LinuxCNC C functions directly from Vaxis event handlers.

**Why it's wrong:**
- Violates separation of concerns
- Makes UI code unsafe
- Hard to test UI without real LinuxCNC
- Error handling scattered across UI

**Do this instead:**
- All HAL access goes through safe wrapper layer
- UI components only talk to State Manager
- UI code is 100% safe Zig

### Anti-Pattern 2: Thread-Unsafe State Access

**What people do:** Share HAL state between UI and background threads without synchronization.

**Why it's wrong:**
- LinuxCNC HAL runs in separate threads
- Race conditions cause crashes or data corruption
- Values can change mid-read

**Do this instead:**
- State Manager uses mutex for all access
- Cache updates are atomic
- UI always reads from consistent snapshots

### Anti-Pattern 3: Monolithic View Functions

**What people do:** Put entire UI logic in single massive render function.

**Why it's wrong:**
- Hard to maintain
- Can't reuse components
- Performance suffers (redraws entire screen)

**Do this instead:**
- Break views into small widgets
- Each widget manages its own state
- Only redraw changed widgets

### Anti-Pattern 4: Tight Plugin-Core Coupling

**What people do:** Plugins reach directly into internal core structures.

**Why it's wrong:**
- Plugins break when internal implementation changes
- Security/safety boundaries violated
- Can't version plugin API independently

**Do this instead:**
- Clear plugin API with stable interface
- Plugins access HAL only through provided API
- Core internals opaque to plugins

## FFI Safety Patterns

### Pattern: Null-Safe FFI Wrappers

LinuxCNC HAL C functions can return null pointers. Zig's option types make this safe:

```zig
// src/ffi/safe_wrapper.zig
const hal = @import("hal.zig");

pub fn getPin(name: []const u8) !Pin {
    // C function can return null
    const ptr = hal.hal_find_pin_by_name(name.ptr) orelse return error.PinNotFound;

    return Pin{
        .id = ptr.*.id,
        .name = try std.fmt.allocPrint(allocator, "{s}", .{name}),
        // ... other fields
    };
}
```

### Pattern: Owned Memory Management

C functions that return strings often require manual free:

```zig
// src/ffi/safe_wrapper.zig
pub fn listComponents(allocator: std.mem.Allocator) ![][]const u8 {
    var next: ?*hal.hal_comp_t = hal.hal_cmp_list;
    var list = std.ArrayList([]const u8).init(allocator);

    while (next) |comp| {
        // Copy C string to Zig-owned memory
        const name = try std.fmt.allocPrint(allocator, "{s}", .{comp.*.name});
        try list.append(name);
        next = comp.*.next;
    }

    return list.toOwnedSlice();
}
```

### Pattern: Type-Safe Enums

Map C integer types to Zig enums for safety:

```zig
// src/ffi/hal.zig
pub const hal_type_t = enum(c_int) {
    bit = 0,
    float = 1,
    s32 = 2,
    u32 = 3,
};

// Usage in wrapper:
pub fn readPin(pin: Pin, comptime T: type) !T {
    const hal_type = hal.hal_get_pin_type(pin.id);
    const expected_type = switch (T) {
        bool => hal_type_t.bit,
        f64 => hal_type_t.float,
        i32 => hal_type_t.s32,
        u32 => hal_type_t.u32,
        else => return error.UnsupportedType,
    };

    if (hal_type != expected_type) return error.TypeMismatch;
    // ... read value
}
```

### Pattern: Thread-Safe Access

LinuxCNC HAL uses shared memory accessed by multiple threads:

```zig
// src/hal/watcher.zig
pub const Watcher = struct {
    thread: std.Thread,
    running: std.atomic.Value(bool),
    state: *state.Store,

    pub fn start(self: *Watcher) !void {
        self.running.store(true, .seq_cst);
        self.thread = try std.Thread.spawn(.{}, watcherLoop, .{self});
    }

    fn watcherLoop(self: *Watcher) void {
        while (self.running.load(.seq_cst)) {
            // Read HAL values (thread-safe through HAL mutex)
            if (self.updatePins()) |_| {
                // Update state manager (thread-safe through state mutex)
            }
            std.time.sleep(100 * std.time.ns_per_ms); // 10Hz update
        }
    }
};
```

## Scalability Considerations

### Performance on Raspberry Pi 5

| Concern | Approach |
|---------|----------|
| **TUI Responsiveness** | Cache values, update only changed widgets, limit refresh rate |
| **HAL Polling Overhead** | Batch reads, use LinuxCNC's change notifications if available |
| **Memory Constraints** | String interning for names, limit cache size, free unused data |
| **Thread Overhead** | Single background watcher thread, not one per component |

### Optimization Priorities

1. **First bottleneck:** TUI redraw frequency
   - Fix: Dirty flag system, only redraw changed widgets
   - Target: 30 FPS UI updates (Raspberry Pi 5 can handle this easily)

2. **Second bottleneck:** HAL value caching
   - Fix: LRU cache for frequently accessed pins
   - Background thread pre-fetches watchlist values

## Plugin Architecture Details

### Plugin Discovery

**Challenge:** Dynamic plugin loading in Zig is not well-supported (LOW confidence - 2025 research shows this is an active pain point in the Zig community).

**Options:**

1. **Compile-time plugins (Recommended for MVP):**
   - Plugins are imported Zig modules
   - Built into main binary
   - Simple, safe, idiomatic Zig

2. **Process-based plugins (Post-MVP):**
   - Each plugin is separate executable
   - Communicate via stdio or socket
   - Language-agnostic plugins
   - More complex but more flexible

**Implementation (Compile-time):**
```zig
// src/plugin/manager.zig
pub const builtin_plugins = &[_]*const Plugin{
    &pid_tuner_plugin,
    &stepper_cal_plugin,
    // Add built-in plugins here
};

pub fn listPlugins() []const *const Plugin {
    return builtin_plugins;
}
```

### Plugin API

Plugins receive callbacks for:
- **Initialization** with allocator and state store access
- **Rendering** into provided widget container
- **Events** (keyboard, HAL value changes)
- **Cleanup** on plugin unload

```zig
// Plugin API contract
pub const PluginAPI = struct {
    // Read-only access to state
    fn get_state(plugin: *PluginAPI, name: []const u8) ?Value;

    // Request HAL read/write (goes through wrapper)
    fn read_pin(plugin: *PluginAPI, pin: []const u8) !Value;
    fn write_pin(plugin: *PluginAPI, pin: []const u8, value: Value) !void;

    // Subscribe to HAL changes
    fn subscribe(plugin: *PluginAPI, pattern: []const u8, callback: fn (Value) void) !void;

    // Log to application logger
    fn log(plugin: *PluginAPI, comptime level: std.log.Level, comptime fmt: []const u8, args: anytype) void;
};
```

## Sources

### LinuxCNC HAL Documentation
- [HAL Introduction](https://linuxcnc.org/docs/html/hal/intro.html) - Updated Dec 15, 2025
- [HAL General Reference](https://linuxcnc.org/docs/html/hal/general-ref.html) - Updated Sep 20, 2024
- [HAL Tools](https://linuxcnc.org/docs/html/hal/tools.html) - Updated Dec 15, 2025
- [HAL Component List](https://linuxcnc.org/docs/html/hal/components.html) - Updated Dec 15, 2025
- [INI Configuration](https://linuxcnc.org/docs/html/config/ini-config.html) - Updated Dec 15, 2025

### LinuxCNC Developer Resources
- [LinuxCNC Developer Manual v2.9.7](http://www.docs/2.9/pdf/LinuxCNC_Developer_nb.pdf) - October 22, 2025
- [halcmd source code](https://github.com/LinuxCNC/linuxcnc/blob/master/src/hal/utils/halcmd.c)
- [Developing HAL component in C - Forum](https://forum.linuxcnc.org/24-hal-components/40339-developing-hal-component-in-c)

### Zig Ecosystem
- [libvaxis - Modern TUI library for Zig](https://github.com/rockorager/libvaxis) - Active 2025
- [Zig FFI Safety Patterns](https://marsmatics.com/how-zig-lets-you-gradually-migrate-or-mix-c-code-safely/) - June 2025
- [Zig C Interoperability Discussion](https://ziggit.dev/t/creating-cross-platform-plugin-system/8099) - January 2025
- [Runtime-Extensible Code in Zig](https://ziggit.dev/t/writing-runtime-extensible-code-in-zig-is-massively-inconvenient/10036) - May 2025

### Architecture Patterns
- [Architecting for Control with CLIs and TUIs](https://www.golodiuk.com/news/ui-in-architecture-01-cli-tui/) - TUI vs CLI architecture
- [Why MVC Architecture Still Matters in 2025](https://agamitechnologies.com/blog/why-mvc-architecture-still-matters-in-2025) - October 2025
- [Building a Terminal UI Broke My Brain](https://dev.to/manasmudbar/building-a-terminal-ui-broke-my-brain-hpc) - December 15, 2025

---
*Architecture research for: LinuxCNC HAL manager in Zig*
*Researched: 2025-01-28*
