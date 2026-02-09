# haltune

Tool to view, manipulate and try out LinuxCNC HAL (Hardware Abstraction Layer) components.

## Features

- **TUI Interface**: Terminal UI built with [vaxis](https://github.com/rockdreamer/vaxis)
- **HAL Discovery**: Automatically discovers pins, signals, and parameters from HAL
- **Refresh Thread**: Continuously polls HAL for updates
- **Multiple Views**: Tree view and table view for exploring HAL components

## Building

```bash
zig build
```

The binary will be output to `zig-out/bin/haltune`.

## Requirements

- Zig 0.15.2
- LinuxCNC (for HAL libraries and utilities)

## Running

### Interactive

```bash
./zig-out/bin/haltune
```

Requires an active LinuxCNC session with HAL running.

### Keyboard Controls

- `Ctrl+C`: Quit application
- `Ctrl+T`: Switch to table view
- `Space`: Check/select item
- `+/-`: Toggle visibility
- `/`: Search
- `Esc`: Clear selection

## Testing

### Automated PTY Testing

The `--test-mode` flag allows running haltune without an interactive terminal for automated testing:

```bash
# Basic test (5 seconds)
timeout 5 script -q -c 'stty cols 80 rows 24 2>/dev/null; ./zig-out/bin/haltune --test-mode' /dev/null
```

The `stty cols 80 rows 24` command is **critical** - it sets the PTY dimensions that vaxis requires to avoid division-by-zero errors.

### Test Scripts

Two test scripts are included:

1. **`test_pty.sh`**: Basic PTY test, verifies TUI renders
2. **`test_mock_hal.sh`**: HAL integration test, checks component registration and discovery

```bash
# Run the basic PTY test
./test_pty.sh 5

# Run the HAL integration test
./test_mock_hal.sh
```

### Testing via SSH

When testing haltune via SSH (e.g., on a remote machine like a Raspberry Pi running LinuxCNC):

```bash
ssh pib "cd ~/prog/haltune && timeout 10 script -q -c 'stty cols 80 rows 24 2>/dev/null; ./zig-out/bin/haltune --test-mode' /dev/null"
```

### Why `stty` inside `script`?

The `script` command allocates a pseudo-terminal (PTY), but without setting dimensions, vaxis gets 0x0 screen size and panics with division by zero. Running `stty cols 80 rows 24` **inside** the script command sets the PTY dimensions before haltune starts.

## HAL Integration

haltune registers itself as a HAL component named `haltune`. You can verify this with:

```bash
halcmd list comp
```

The application continuously polls HAL for:
- Pins (all types: bit, float, s32, u32)
- Signals
- Parameters

### Troubleshooting

#### Duplicate Component Name

If haltune crashes or is killed forcefully, the HAL component may not be properly cleaned up. On the next run, you'll see:

```
Using component name 'haltune1' (original 'haltune' was in use)
```

To clean up stuck components:

```bash
# List all HAL components
halcmd list comp

# Remove a stuck component
halcmd del comp haltune

# Or stop the entire HAL session
halrun -U
```

The application will automatically try incrementing suffixes (`haltune1`, `haltune2`, etc.) if the primary name is in use.

#### No Pins/Signals Discovered

If haltune runs but shows 0 pins/signals/parameters, make sure HAL has components loaded:

```bash
# Check if HAL is running
halcmd list comp

# Check for existing pins
halcmd list pin

# If using LinuxCNC, make sure it's running with a configuration
linuxcnc /path/to/config.ini
```

## Development

### Project Structure

```
src/
├── root.zig          # Entry point, parses --test-mode flag
├── tui/
│   ├── app.zig       # TUI application initialization
│   └── model.zig     # Main widget and application state
├── state/
│   ├── cache.zig     # StateStore for HAL data caching
│   ├── pubsub.zig    # SubscriptionManager for updates
│   └── refresh.zig   # RefreshThread for HAL polling
└── ffi/
    ├── c.zig         # C FFI bindings to HAL
    ├── safe.zig      # Safe wrappers for HAL functions
    └── types.zig     # HAL type definitions
```

### Memory Management

- Uses `std.heap.c_allocator` throughout to avoid memory corruption with vaxis
- The Model is heap-allocated and must be destroyed before allocator cleanup
- Refresh thread uses thread-safe allocator for concurrent access

## License

[Specify your license here]
