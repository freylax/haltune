# haltune Remote HAL Setup

This guide explains how to run haltune on `laura` (x86_64) connected to the HAL bridge server on `pib` (aarch64).

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                        laura (x86_64)                        │
│                                                              │
│  ┌────────────┐     TCP/JSON      ┌────────────────────┐   │
│  │  haltune   │ ─────────────────>│ HAL Bridge Server  │   │
│  │   (TUI)    │  192.168.2.118:8765   (pib)           │   │
│  └────────────┘                    └────────────────────┘   │
│                                                  │         │
│                                                  ▼         │
│                                    ┌────────────────────┐   │
│                                    │   LinuxCNC HAL     │   │
│                                    └────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. **HAL Bridge Server** must be running on pib:
   ```bash
   ssh pib "cd ~/prog/haltune && ./zig-out/bin/hal_bridge_server"
   ```

2. **Verify server is accessible** from laura:
   ```bash
   echo '{"type":"ping"}' | nc 192.168.2.118 8765
   # Should return: {"type":"ping"}
   ```

## Building haltune on laura

Build for the native x86_64 architecture (without local HAL linkage):

```bash
cd ~/prog/zig/haltune
zig build -Dtarget=native -Dskip-hal-link
```

The `-Dskip-hal-link` flag allows building without the local HAL library.

## Configuration

Create or edit `haltune.toml` in the haltune directory:

```toml
# haltune configuration for remote HAL connection

[files]
# HAL files to load for origin tracking
# hal_files = ["custom.hal"]

[logging]
# Log file path (optional)
# file = "debug.log"

[plugins]
# Enabled plugins
# enabled = ["plugin1", "plugin2"]

[remote]
# Remote HAL server configuration
enabled = true
host = "192.168.2.118"
port = 8765
```

## Launching haltune

### Option 1: Direct launch

```bash
cd ~/prog/zig/haltune
./zig-out/bin/haltune
```

### Option 2: With custom config file

```bash
./zig-out/bin/haltune -c /path/to/config.toml
```

### Option 3: With HAL files for origin tracking

```bash
./zig-out/bin/haltune -f custom.hal
```

## Testing Remote Connection

Before launching the TUI, verify the remote connection works:

```bash
# Quick ping test
echo '{"type":"ping"}' | nc 192.168.2.118 8765

# Or use the test script
python3 test_remote_hal.py
```

## Troubleshooting

### "HAL is not available" error

This means haltune is trying to use local HAL instead of remote. Ensure:
1. `haltune.toml` has `[remote]` section with `enabled = true`
2. The config file is in the current directory when launching
3. Or use `-c haltune.toml` to specify config path

### Connection refused

1. Check if HAL bridge server is running on pib:
   ```bash
   ssh pib "pgrep -f hal_bridge_server"
   ```

2. Check if port is accessible:
   ```bash
   nc -zv 192.168.2.118 8765
   ```

### Empty pin/signal lists

This is expected if LinuxCNC is not running or no HAL components have been loaded yet. Once LinuxCNC starts and creates pins/signals, they will appear in haltune.

## Starting HAL Bridge Server on pib

If the server is not running:

```bash
# Start in foreground (for debugging)
ssh pib "cd ~/prog/haltune && ./zig-out/bin/hal_bridge_server"

# Start in background
ssh pib "cd ~/prog/haltune && ./zig-out/bin/hal_bridge_server > /dev/null 2>&1 &"

# Check status
ssh pib "pgrep -f hal_bridge_server"

# Stop server
ssh pib "pkill -f hal_bridge_server"
```

## Protocol Reference

The HAL bridge server uses JSON over TCP. Example requests:

```json
// Ping
{"type":"ping"}

// List pins
{"type":"list_pins"}

// Get pin value
{"type":"get_pin","name":"motion.enable-pin"}

// Set pin value
{"type":"set_pin","name":"my.pin","value":{"bit":true}}

// Create signal
{"type":"create_signal","name":"my.signal","pin_type":"bit"}

// Link pin to signal
{"type":"link_pin","pin_name":"my.pin","sig_name":"my.signal"}
```
