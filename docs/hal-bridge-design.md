# HAL Bridge Server Architecture

## Problem

haltune TUI cannot be debugged locally on laura because it requires LinuxCNC HAL (only available on pib). Running via SSH doesn't provide proper terminal for vaxis TUI.

## Solution

Create a HAL bridge server that runs on pib and exposes HAL functionality over TCP. haltune on laura connects as a client.

## Architecture

```
laura (local)                          pib (remote)
┌─────────────────────┐                ┌──────────────────────────┐
│   haltune          │                │   hal_bridge_server      │
│   ├─ TUI (vaxis)   │                │   ├─ TCP Server (port)   │
│   ├─ StateStore    │◄── JSON/TCP ───►│   ├─ HalBackend (native) │
│   └─ HalBackend    │   discovery     │   └─ Refresh Thread      │
│      (remote)      │   & values      │                          │
└─────────────────────┘                └──────────────────────────┘
                                                     │
                                                     ▼
                                            LinuxCNC HAL (local)
```

## Protocol Design

### JSON over TCP

Simple JSON request/response pattern:

```json
// Request: List pins
{"type": "list_pins"}

// Response
{
  "type": "list_pins",
  "pins": [
    {"name": "pid.do-not-watch", "type": "bit", "dir": "in", "value": 0},
    {"name": "trapvel.enable", "type": "bit", "dir": "out", "value": 1}
  ]
}

// Request: Get pin value
{"type": "get_pin", "name": "trapvel.enable"}

// Request: Set pin value
{"type": "set_pin", "name": "trapvel.target-vel", "value": 123.45}

// Request: List signals
{"type": "list_signals"}

// Request: Create signal
{"type": "create_signal", "name": "my-signal", "type": "float"}
```

### Messages

| Type | Request | Response |
|------|---------|----------|
| `list_pins` | `{}` | `{pins: [...]}` |
| `list_signals` | `{}` | `{signals: [...]}` |
| `list_params` | `{}` | `{params: [...]}` |
| `list_components` | `{}` | `{components: [...]}` |
| `get_pin` | `{name}` | `{value}` |
| `set_pin` | `{name, value}` | `{success}` |
| `create_signal` | `{name, type}` | `{success}` |
| `delete_signal` | `{name}` | `{success}` |
| `ping` | `{}` | `{}` |

## HAL Backend Interface

```zig
/// HAL Backend Interface
/// All HAL operations go through this interface
pub const HalBackend = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        deinit: *const fn (ptr: *anyopaque) void,
        initComponent: *const fn (ptr: *anyopaque, name: []const u8) !c_int,
        readyComponent: *const fn (ptr: *anyopaque, comp_id: c_int) !void,
        exitComponent: *const fn (ptr: *anyopaque, comp_id: c_int) void,

        // Discovery
        listPins: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) ![]PinInfo,
        listSignals: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) ![]SignalInfo,
        listParams: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) ![]ParamInfo,
        listComponents: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) ![][]const u8,

        // Value access
        getPinValue: *const fn (ptr: *anyopaque, name: []const u8) !HalValue,
        setPinValue: *const fn (ptr: *anyopaque, name: []const u8, value: HalValue) !void,
    };

    // Helper methods
    pub fn deinit(self: HalBackend) void {
        self.vtable.deinit(self.ptr);
    }

    pub fn initComponent(self: HalBackend, name: []const u8) !c_int {
        return self.vtable.initComponent(self.ptr, name);
    }

    // ... more helpers
};

/// Native HAL Backend (direct FFI)
pub fn NativeBackend(allocator: std.mem.Allocator) !HalBackend { ... }

/// Remote HAL Backend (TCP client)
pub fn RemoteBackend(allocator: std.mem.Allocator, host: []const u8, port: u16) !HalBackend { ... }
```

## Configuration

### haltune.toml

```toml
[hal]
# Local (default) - uses direct HAL FFI
mode = "native"

# OR remote - uses HAL bridge server
mode = "remote"
host = "pib"
port = 8765
```

## File Structure

### New Files

```
src/hal/
├── backend.zig          # HalBackend interface
├── native.zig           # Native implementation (wraps existing FFI)
├── remote/
│   ├── client.zig       # TCP client implementation
│   └── protocol.zig     # JSON (de)serialization
└── bridge_server/
    ├── main.zig         # Standalone bridge server executable
    └── handler.zig      # Request handler using native backend
```

### Modified Files

```
src/ffi/safe.zig          # Add native backend wrapper
src/state/cache.zig       # Use backend interface instead of direct FFI
src/state/refresh.zig     # Use backend interface
src/tui/app.zig           # Select backend based on config
```

## Implementation Plan

1. **Phase 1**: Backend Interface
   - Create `src/hal/backend.zig` with interface struct
   - Move existing FFI code to `src/hal/native.zig`

2. **Phase 2**: Protocol**
   - Create `src/hal/remote/protocol.zig` with JSON (de)serialization
   - Define message types

3. **Phase 3**: Remote Client**
   - Create `src/hal/remote/client.zig`
   - TCP connection, JSON parsing
   - Implement backend interface

4. **Phase 4**: Bridge Server**
   - Create `src/hal/bridge_server/` as standalone executable
   - TCP server
   - Request handlers using native backend

5. **Phase 5**: Integration**
   - Update StateStore to use backend interface
   - Update refresh thread
   - Add config option to haltune.toml

6. **Phase 6**: Testing**
   - Test bridge server on pib
   - Test client on laura
   - Verify TUI works correctly

## Benefits

1. **TUI debugging**: Can run haltune locally with full terminal
2. **Network development**: Can develop from any machine
3. **Clean architecture**: Single interface, multiple implementations
4. **Testing**: Can mock HAL backend for unit tests
