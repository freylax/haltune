# haltune TUI Development Guide

## Quick Start

To test haltune interactively with HAL components:

```bash
cd ~/prog/haltune
./tests/tui_dev_shell.sh
```

This will:
1. Start halrun in the background
2. Start a Python HAL component with test pins/parameters
3. Drop you into a shell where you can run `haltune`

## Available Test Scripts

| Script | Description | Components |
|--------|-------------|------------|
| `tui_dev_shell.sh` | Full dev shell with Python component | 10 pins, 3 params |
| `tui_dev_hal.sh` | Simple shell (manual component creation) | None by default |

## Running haltune

### From Interactive Shell (Recommended)

```bash
# SSH into your machine
ssh pib

# Run the dev shell
cd ~/prog/haltune
./tests/tui_dev_shell.sh

# In the dev shell, just run:
haltune
```

### Automated Testing with PTY

```bash
# Using script to create PTY
timeout 5 script -q -c "stty cols 80 rows 24 && ./zig-out/bin/haltune --test-mode" /dev/null
```

### Using pexpect (Python)

```python
import pexpect

child = pexpect.spawn(
    "/home/cnc/prog/haltune/zig-out/bin/haltune",
    dimensions=(80, 24),
    encoding="utf-8"
)
child.expect("Table View", timeout=5)
# ... interact with TUI
child.send("\x11")  # Ctrl+Q to quit
```

## Common Issues

### EINTR Crash (errno 6)

**Symptom**: `unexpected errno: 6` when running haltune non-interactively

**Cause**: haltune requires a PTY (pseudo-terminal) for proper operation. Zig 0.15.2's stdlib doesn't handle EINTR properly on some system calls.

**Solution**: Always run haltune with a PTY:
- Interactive SSH session: works automatically
- Automated testing: use `script` or `pexpect`
- Wrong: `timeout 5 haltune --test-mode` (no PTY)
- Right: `timeout 5 script -q -c "haltune --test-mode" /dev/null`

### No Components Visible

**Symptom**: haltune shows 0 components

**Cause**: HAL components not loaded

**Solution**:
```bash
# Check if HAL has components
halcmd list comp
halcmd list pin

# If empty, create a test component:
python3 -c "
import hal, time
h = hal.component('test-comp')
h.newpin('pin1', hal.HAL_BIT, hal.HAL_OUT)
h.newparam('param1', hal.HAL_FLOAT, hal.HAL_RW)
h['param1'] = 1.23
h.ready()
time.sleep(3600)
" &
```

### Duplicate Component Name

**Symptom**: `Using component name 'haltune1'`

**Cause**: Previous haltune instance didn't clean up

**Solution**:
```bash
halcmd del comp haltune
# or
halrun -U
```

## Creating Custom Test Components

### Using Python

```python
#!/usr/bin/env python3
import hal
import time

h = hal.component("my-test-comp")

# Add pins
h.newpin("enable", hal.HAL_BIT, hal.HAL_IN)
h.newpin("output", hal.HAL_FLOAT, hal.HAL_OUT)

# Add parameters
h.newparam("scale", hal.HAL_FLOAT, hal.HAL_RW)
h["scale"] = 2.5

h.ready()

try:
    while True:
        time.sleep(1)
except:
    pass
finally:
    h.exit()
```

### Using C with halcompile

```c
// test_comp.c
#include "hal.h"

static void *update(void *arg, long period) {
    // Component update logic
    return 0;
}

int rtapi_app_main(void) {
    comp_id = hal_init("test-comp");
    // Create pins, params, functions...
    hal_ready(comp_id);
    return 0;
}

void rtapi_app_exit(void) {
    hal_exit(comp_id);
}
```

Build and install:
```bash
halcompile --install test_comp.c
```

## Key Bindings

| Key | Action |
|-----|--------|
| `Ctrl+Q` | Quit |
| `Ctrl+T` | Toggle tree/table view |
| `Enter` | Expand/collapse or edit |
| `Space` | Toggle visibility |
| `Esc` | Clear selection |
| `/` | Search |
| `n` | New signal (tree) |
| `s` | Save config (tree) |
| `+/-` | Expand/collapse all |
| `Up/Down` | Navigate |
