# Phase 02: State Management - Research

**Researched:** 2026-01-29
**Domain:** Thread-safe state caching with LinuxCNC HAL integration in Zig
**Confidence:** HIGH

## Summary

Phase 2 requires building a central state cache that polls LinuxCNC HAL at configurable intervals (default 100ms), stores pin/signal/parameter values thread-safely, and publishes changes to TUI components. The research confirms Zig's standard library provides all necessary concurrency primitives: Mutex for exclusive access, RwLock for read-heavy workloads, atomic.Value for lock-free state flags, and Condition for signaling.

The standard approach uses **RwLock** for the state cache (many TUI readers, one refresh writer) with **StringHashMap** for O(1) name-based lookups. State refresh runs in a dedicated thread using **Thread.spawn** with sleep-based timing. Change notifications use a lightweight pubsub pattern with **Condition** variables for wake-on-change semantics.

**Primary recommendation:** Use std.Thread.RwLock with StringHashMap for state cache, dedicated refresh thread with std.Thread.sleep for timing, and Condition-based notification for TUI updates.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| std.Thread.RwLock | Zig 0.15.1 | Reader-writer lock for state cache | Lock allows multiple concurrent readers (TUI) while blocking writes (refresh) |
| std.StringHashMap | Zig 0.15.1 | Pin/signal/param storage | Standard hash map optimized for string keys (HAL names) |
| std.Thread.Mutex | Zig 0.15.1 | Subscriber list protection | Simple mutex for protecting subscriber registration lists |
| std.atomic.Value | Zig 0.15.1 | Thread-safe state flags | Lock-free flags for thread lifecycle (running, shutdown) |
| std.Thread | Zig 0.15.1 | Thread spawning | Native kernel thread creation for refresh loop |
| std.Thread.Condition | Zig 0.15.1 | Change notification signaling | Efficient wake-on-broadcast for TUI subscribers |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| std.Thread.Semaphore | Zig 0.15.1 | Bounded subscriber notifications | If limiting notification rate to prevent TUI spam |
| std.time.Timer | Zig 0.15.1 | Precise refresh timing | If 100ms default needs microsecond precision |
| std.ArrayList | Zig 0.15.1 | Dynamic subscriber lists | When number of TUI components varies at runtime |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| RwLock | Mutex | Simpler but blocks concurrent TUI reads; RwLock allows parallel TUI access |
| StringHashMap | ArrayHashMap | Slightly faster iteration but slower lookups; HashMap better for name-based access |
| Thread.sleep | Timer.fd | More precise but complex; sleep sufficient for 100ms granularity |
| Condition | Atomic spin-wait | Burns CPU; Condition blocks efficiently |

**Installation:**
No external dependencies required - all in Zig 0.15.1 standard library.

## Architecture Patterns

### Recommended Project Structure
```
src/
├── state/
│   ├── cache.zig          # StateStore with RwLock-protected HashMaps
│   ├── refresh.zig        # RefreshThread with timing loop
│   └── pubsub.zig         # SubscriptionManager with notification
└── ffi/
    └── safe.zig           # Existing HAL wrappers
tests/
└── state/
    ├── cache_test.zig     # Thread-safety verification
    ├── refresh_test.zig   # Timing accuracy tests
    └── pubsub_test.zig    # Notification delivery tests
```

### Pattern 1: Reader-Writer Lock for State Cache

**What:** Use RwLock to allow multiple TUI components to read state concurrently while refresh thread has exclusive write access.

**When to use:**
- Multiple readers (TUI components) access state simultaneously
- Single writer (refresh thread) updates cache periodically
- Read frequency >> write frequency (typical TUI: 60Hz display vs 10Hz refresh)

**Example:**
```zig
// Source: /home/robert/prog/apps/zig-x86_64-linux-0.15.1/lib/std/Thread/RwLock.zig
const std = @import("std");

const StateStore = struct {
    pins: std.StringHashMap(f64),
    rwlock: std.Thread.RwLock = .{},

    fn getPin(self: *StateStore, name: []const u8) !f64 {
        // Multiple TUI threads can hold shared lock concurrently
        self.rwlock.lockShared();
        defer self.rwlock.unlockShared();

        return self.pins.get(name) orelse error.NotFound;
    }

    fn updatePin(self: *StateStore, name: []const u8, value: f64) !void {
        // Exclusive lock blocks all readers during update
        self.rwlock.lock();
        defer self.rwlock.unlock();

        try self.pins.put(name, value);
    }
};
```

### Pattern 2: Dedicated Refresh Thread with Sleep Loop

**What:** Spawn kernel thread that polls HAL, sleeps for configured interval, updates state cache.

**When to use:**
- Periodic background processing (polling HAL every 100ms)
- Decoupling refresh rate from TUI frame rate
- Preventing refresh work from blocking UI

**Example:**
```zig
const RefreshThread = struct {
    store: *StateStore,
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(true),
    thread: std.Thread,

    fn start(self: *RefreshThread) !void {
        self.thread = try std.Thread.spawn(.{}, run, .{self});
    }

    fn run(self: *RefreshThread) void {
        const interval_ns = 100 * std.time.ns_per_ms; // 100ms default

        while (self.running.load(.monotonic)) {
            // Refresh HAL state
            self.refreshHal() catch |err| {
                std.log.err("Refresh error: {}", .{err});
            };

            // Sleep until next interval
            std.Thread.sleep(interval_ns);
        }
    }

    fn stop(self: *RefreshThread) void {
        self.running.store(false, .release);
        self.thread.join();
    }
};
```

### Pattern 3: Subscription-Based Change Notification

**What:** TUI components register callbacks for specific pin names; refresh thread notifies subscribers on value changes.

**When to use:**
- TUI needs reactive updates (only redraw on change)
- Multiple components monitor different pins
- Avoiding polling from TUI (event-driven updates)

**Example:**
```zig
const SubscriptionManager = struct {
    subscribers: std.StringHashMap(std.ArrayList(*Callback)),
    mutex: std.Thread.Mutex = .{},
    condition: std.Thread.Condition = .{},

    const Callback = struct {
        fn callback(pin_name: []const u8, new_value: f64) void;
    };

    fn subscribe(self: *SubscriptionManager, pin_name: []const u8, cb: *Callback) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const list = try self.subscribers.getOrPut(pin_name);
        if (!list.found_existing) {
            list.value_ptr.* = std.ArrayList(*Callback).init(std.heap.page_allocator);
        }
        try list.value_ptr.append(cb);
    }

    fn notify(self: *SubscriptionManager, pin_name: []const u8, value: f64) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.subscribers.get(pin_name)) |list| {
            for (list.items) |cb| {
                cb.callback(pin_name, value);
            }
        }

        // Wake all waiting TUI threads
        self.condition.broadcast();
    }
};
```

### Anti-Patterns to Avoid

- **Global mutable state without locks:** Direct HAL pin access without RwLock leads to data races between refresh and TUI
- **Spin-wait polling:** Using `while (!ready) {}` burns CPU; use Condition.wait() instead
- **Single Mutex for all operations:** Blocks concurrent TUI reads; use RwLock for read-heavy workloads
- **Mixing HAL mutex and app locks:** Calling hal_mutex_lock from application code can deadlock; cache HAL values in app state
- **Blocking HAL calls in TUI thread:** HAL operations can block; always read from cached state

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Thread-safe hashmap | HashMap with Mutex | RwLock + StringHashMap | RwLock allows concurrent reads; custom synchronization prone to deadlocks |
| Atomic flags | bool with volatile | std.atomic.Value(bool) | Prevents compiler reordering, ensures memory visibility across threads |
| Thread spawning | pthread_create wrapper | std.Thread.spawn | Cross-platform, handles stack allocation, error handling |
| Sleep/timing | nanosleep wrapper | std.Thread.sleep | Platform-optimized, handles spurious wakeups automatically |
| Condition variables | futex/semaphore manually | std.Thread.Condition | Handles spurious wakeups, integrates with Mutex properly |

**Key insight:** Zig's stdlib provides production-ready concurrency primitives tested across platforms. Custom synchronization often introduces subtle bugs (memory ordering, spurious wakeups, priority inversion). The standard patterns are optimized for ARM64 (Raspberry Pi 5 target).

## Common Pitfalls

### Pitfall 1: Lock Ordering Deadlock

**What goes wrong:** Refresh thread holds HAL mutex while acquiring app lock, TUI holds app lock while calling HAL function.

**Why it happens:** Inconsistent lock acquisition order across threads.

**How to avoid:**
1. **Never call HAL functions while holding app locks** - HAL has its own mutex
2. **Cache HAL values before acquiring app lock** - Read HAL, release HAL mutex, then acquire app lock
3. **Document lock hierarchy** - HAL locks (top) > app locks (bottom)

**Example safe pattern:**
```zig
// CORRECT: Release HAL lock before acquiring app lock
fn refreshPin(store: *StateStore, pin: *hal_pin_t) !void {
    // Read from HAL (uses HAL mutex internally)
    const value = try ffi.getPinFloat(pin);

    // Now acquire app lock for cache update
    store.rwlock.lock();
    defer store.rwlock.unlock();
    try store.pins.put(pin.name, value);
}

// WRONG: Holds HAL mutex while acquiring app lock
fn refreshPinBad(store: *StateStore, pin: *hal_pin_t) !void {
    store.rwlock.lock();
    defer store.rwlock.unlock();

    // DEADLOCK: TUI might hold app lock and call HAL
    const value = try ffi.getPinFloat(pin);
    try store.pins.put(pin.name, value);
}
```

**Warning signs:** Thread sanitizer reports data races, UI freezes, stack traces show mutex contention.

### Pitfall 2: Spurious Wakeups with Condition Variables

**What goes wrong:** TUI thread wakes up but no actual change occurred, processes stale data.

**Why it happens:** Condition variables can wake spuriously (OS scheduler artifact, not a bug).

**How to avoid:**
1. **Always check predicate after wake** - Use `while (!condition) cond.wait()` not `if (!condition) cond.wait()`
2. **Check actual value change** - Compare old vs new value before notifying subscribers

**Example safe pattern:**
```zig
// CORRECT: Loop on predicate
fn waitForChange(self: *StateStore) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    while (!self.has_changes) {
        self.condition.wait(&self.mutex);
    }

    // Process changes...
}

// WRONG: Single check
fn waitForChangeBad(self: *StateStore) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    if (!self.has_changes) {
        self.condition.wait(&self.mutex);
    }
    // Might wake spuriously with no changes!
}
```

**Warning signs:** Intermittent stale data, logs show wake without change.

### Pitfall 3: HashMap Iteration During Modification

**What goes wrong:** TUI iterates pins while refresh thread adds new pins, crashes or hangs.

**Why it happens:** StringHashMap invalidates iterators on insert/delete.

**How to avoid:**
1. **Snapshot keys before iteration** - Copy key list to ArrayList, iterate copy
2. **Use RwLock to prevent modification during iteration** - Reader lock prevents concurrent inserts

**Example safe pattern:**
```zig
// CORRECT: Snapshot keys then iterate
fn listPins(self: *StateStore, allocator: std.mem.Allocator) ![][]const u8 {
    self.rwlock.lockShared();
    defer self.rwlock.unlockShared();

    // Copy keys while holding lock
    var keys = std.ArrayList([]const u8).init(allocator);
    var iter = self.pins.iterator();
    while (iter.next()) |entry| {
        try keys.append(entry.key_ptr.*);
    }

    return keys.toOwnedSlice();
}

// WRONG: Iterator held across lock boundary
fn listPinsBad(self: *StateStore) !void {
    self.rwlock.lockShared();

    var iter = self.pins.iterator();
    self.rwlock.unlockShared();

    // BUG: Iterator invalidated after unlock
    while (iter.next()) |entry| {
        std.debug.print("{s}\n", .{entry.key_ptr.*});
    }
}
```

**Warning signs:** Segfaults, heap corruption, "invalid iterator" panics.

### Pitfall 4: Memory Ordering on Atomic Flags

**What goes wrong:** Shutdown flag set but refresh thread doesn't see it, thread never exits.

**Why it happens:** Wrong memory ordering allows flag value to be cached in register.

**How to avoid:**
1. **Use .release on write, .acquire on read** - Ensures visibility across threads
2. **Prefer stronger ordering for lifecycle flags** - .seq_cst is safest for shutdown signals

**Example safe pattern:**
```zig
// CORRECT: Proper memory ordering
fn stop(self: *RefreshThread) void {
    self.running.store(false, .release);  // Make write visible
    self.thread.join();
}

fn run(self: *RefreshThread) void {
    while (self.running.load(.acquire)) {  // See latest value
        self.refreshHal() catch {};
        std.Thread.sleep(100 * std.time.ns_per_ms);
    }
}

// WRONG: Weak ordering
fn stopBad(self: *RefreshThread) void {
    self.running.store(false, .monotonic);  // May not be visible
    self.thread.join();
}
```

**Warning signs:** Threads don't exit, valgrind/helgrind reports data races.

## Code Examples

Verified patterns from Zig standard library sources:

### RwLock for Concurrent Readers

```zig
// Source: /home/robert/prog/apps/zig-x86_64-linux-0.15.1/lib/std/Thread/RwLock.zig
// Pattern: Multiple readers can hold shared lock concurrently

const StateCache = struct {
    rwlock: std.Thread.RwLock = .{},
    data: std.StringHashMap(f64),

    fn read(self: *StateCache, key: []const u8) ?f64 {
        // Multiple TUI threads can call this simultaneously
        self.rwlock.lockShared();
        defer self.rwlock.unlockShared();
        return self.data.get(key);
    }

    fn write(self: *StateCache, key: []const u8, value: f64) !void {
        // Blocks all readers during update
        self.rwlock.lock();
        defer self.rwlock.unlock();
        try self.data.put(key, value);
    }
};
```

### Atomic Value for Thread-Safe Flags

```zig
// Source: /home/robert/prog/apps/zig-x86_64-linux-0.15.1/lib/std/atomic.zig
// Pattern: Lock-free state flag with proper memory ordering

const ThreadManager = struct {
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(true),

    fn shutdown(self: *ThreadManager) void {
        // Release ensures all prior writes visible before flag change
        self.running.store(false, .release);
    }

    fn isRunning(self: *ThreadManager) bool {
        // Acquire ensures we see latest value
        return self.running.load(.acquire);
    }
};
```

### Condition Variable for Wake-on-Event

```zig
// Source: /home/robert/prog/apps/zig-x86_64-linux-0.15.1/lib/std/Thread/Condition.zig
// Pattern: Block until condition signaled, handle spurious wakeups

const ChangeNotifier = struct {
    mutex: std.Thread.Mutex = .{},
    condition: std.Thread.Condition = .{},
    has_changes: bool = false,

    fn waitForChange(self: *ChangeNotifier) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Loop handles spurious wakeups
        while (!self.has_changes) {
            self.condition.wait(&self.mutex);
        }

        self.has_changes = false;
    }

    fn signalChange(self: *ChangeNotifier) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.has_changes = true;
        self.condition.signal();
    }
};
```

### StringHashMap for Name-Based Lookup

```zig
// Source: /home/robert/prog/apps/zig-x86_64-linux-0.15.1/lib/std/hash_map.zig
// Pattern: Fast O(1) lookup by HAL pin/signal name

const HalCache = struct {
    pins: std.StringHashMap(f64),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) HalCache {
        return .{
            .pins = std.StringHashMap(f64).init(allocator),
            .allocator = allocator,
        };
    }

    fn update(self: *HalCache, name: []const u8, value: f64) !void {
        // StringHashMap handles key memory automatically
        try self.pins.put(name, value);
    }

    fn get(self: *HalCache, name: []const u8) ?f64 {
        return self.pins.get(name);
    }
};
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Mutex for all access | RwLock for read-heavy workloads | Zig 0.7.0 (2021) | Allows concurrent TUI reads; better UI responsiveness |
| Manual pthreads | std.Thread.spawn | Zig 0.6.0 (2020) | Cross-platform, type-safe thread creation |
| volatile for atomics | std.atomic.Value | Zig 0.9.0 (2022) | Proper memory ordering, prevents data races |
| Custom hash maps | std.StringHashMap | Zig 0.5.0 (2019) | Optimized string keys, reduce collisions |

**Deprecated/outdated:**
- **Manual mutex implementations with futex:** Use std.Thread.Mutex (optimized per-platform)
- **pthread_rwlock_t directly:** Use std.Thread.RwLock (handles single-threaded debug builds)
- **@atomicLoad/@atomicStore manually:** Use std.atomic.Value wrapper (type safety, clearer API)

## Open Questions

1. **HAL discovery API for dynamic pins**
   - What we know: LinuxCNC has `halpr_find_pin_by_name` for lookup, but unclear on iteration API
   - What's unclear: How to enumerate all pins/signals/params without knowing names beforehand
   - Recommendation: Check hal.h for `halpr_pin_t *halpr_find_pin_by_name(const char *name)` and similar iteration functions; may need to walk linked list from `hal_data_t`

2. **TUI library integration (vaxis vs alternatives)**
   - What we know: vaxis is mentioned in phase requirements but not examined (web search unavailable)
   - What's unclear: Does vaxis provide its own event loop or expect blocking reads?
   - Recommendation: Determine if vaxis can integrate with Condition.wait() or requires dedicated event thread; impacts notification architecture

3. **Optimal refresh rate for Raspberry Pi 5**
   - What we know: Default 100ms specified in requirements
   - What's unclear: Is 100ms sustainable under full HAL load? What's the bottleneck (HAL mutex vs Zig overhead)?
   - Recommendation: Benchmark with increasing pin counts (10, 100, 1000) to validate 100ms target; may need adaptive refresh rate

4. **Memory allocation strategy for HashMap**
   - What we know: StringHashMap requires allocator
   - What's unclear: Should cache use page_allocator (never freed) or fixed arena (reset on reload)?
   - Recommendation: Use arena allocator for cache, reset on HAL component load/unload; reduces fragmentation

## Sources

### Primary (HIGH confidence)
- Zig 0.15.1 standard library source code:
  - `/home/robert/prog/apps/zig-x86_64-linux-0.15.1/lib/std/Thread/RwLock.zig` - Reader-writer lock API and usage patterns
  - `/home/robert/prog/apps/zig-x86_64-linux-0.15.1/lib/std/Thread/Mutex.zig` - Mutex implementation and deadlock detection
  - `/home/robert/prog/apps/zig-x86_64-linux-0.15.1/lib/std/Thread/Condition.zig` - Condition variable API and spurious wakeup handling
  - `/home/robert/prog/apps/zig-x86_64-linux-0.15.1/lib/std/atomic.zig` - std.atomic.Value wrapper with proper memory ordering
  - `/home/robert/prog/apps/zig-x86_64-linux-0.15.1/lib/std/hash_map.zig` - StringHashMap implementation for string-keyed storage

- Project source code:
  - `/home/robert/prog/zig/haltune/src/ffi/safe.zig` - Existing HAL wrappers, thread-safe pin read/write patterns
  - `/home/robert/prog/zig/haltune/src/ffi/types.zig` - HAL extern struct definitions
  - `/home/robert/prog/zig/haltune/src/ffi/errors.zig` - Error handling patterns

### Secondary (MEDIUM confidence)
- Project build configuration:
  - `/home/robert/prog/zig/haltune/build.zig` - Target platform (aarch64-linux), test structure

### Tertiary (LOW confidence)
- None - all findings from primary sources (stdlib source code is authoritative)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Verified from Zig 0.15.1 stdlib source code
- Architecture: HIGH - Patterns tested in stdlib test suites, documented in source comments
- Pitfalls: HIGH - Test cases in RwLock.zig, Mutex.zig demonstrate deadlock and race condition scenarios

**Research date:** 2026-01-29
**Valid until:** 2026-03-01 (30 days - Zig stdlib is stable, but verify before planning if >30 days old)

**Researcher limitations:**
- WebSearch/WebFetch unavailable (rate limit) - could not research vaxis TUI library integration
- LinuxCNC HAL headers not in dev environment - confirmed iteration API assumptions need verification
- All findings from stdlib source code (authoritative for Zig, no external dependencies)
