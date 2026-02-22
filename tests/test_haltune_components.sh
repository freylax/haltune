#!/bin/bash
# Test script to verify haltune can see components in different scenarios

set -e

HALTUNE_BIN="${HALTUNE_BIN:-./zig-out/bin/haltune}"
PYTHON_COMP="/tmp/haltune_test_comp.$$"
FIFO="/tmp/halrun_stdin_test.$$"
HAL_FILE="/tmp/test_haltune.hal"

echo "=== Test 1: Start halrun + Python component, then check with haltune ==="

# Create the Python test component
cat > "$PYTHON_COMP" << 'EOF'
#!/usr/bin/env python3
import hal
import time

h = hal.component('haltune-test-comp')

# Create different pin types (IN, OUT, IO)
h.newpin('bit-in', hal.HAL_BIT, hal.HAL_IN)
h.newpin('bit-out', hal.HAL_BIT, hal.HAL_OUT)
h.newpin('bit-io', hal.HAL_BIT, hal.HAL_IO)

h.newpin('float-in', hal.HAL_FLOAT, hal.HAL_IN)
h.newpin('float-out', hal.HAL_FLOAT, hal.HAL_OUT)
h.newpin('float-io', hal.HAL_FLOAT, hal.HAL_IO)

h.newpin('u32-in', hal.HAL_U32, hal.HAL_IN)
h.newpin('u32-out', hal.HAL_U32, hal.HAL_OUT)

h.newpin('s32-in', hal.HAL_S32, hal.HAL_IN)
h.newpin('s32-out', hal.HAL_S32, hal.HAL_OUT)

# Create some parameters
h.newparam('float-param', hal.HAL_FLOAT, hal.HAL_RW)
h.newparam('u32-param', hal.HAL_U32, hal.HAL_RW)
h.newparam('s32-param', hal.HAL_S32, hal.HAL_RW)

# Set initial values
h['float-param'] = 3.14159
h['u32-param'] = 42
h['s32-param'] = -10

h.ready()

try:
    while True:
        time.sleep(1)
except:
    pass
finally:
    h.exit()
EOF

chmod +x "$PYTHON_COMP"

# Create the HAL file
cat > "$HAL_FILE" << 'EOF'
# Test HAL file
EOF

# Cleanup function
cleanup() {
    pkill -f "python3.*$PYTHON_COMP" 2>/dev/null || true
    pkill -f "halrun.*$HAL_FILE" 2>/dev/null || true
    halrun -U 2>/dev/null || true
    rm -f "$FIFO" 2>/dev/null || true
    rm -f "$PYTHON_COMP" 2>/dev/null || true
    rm -f "$HAL_FILE" 2>/dev/null || true
}

trap cleanup EXIT INT TERM

# Stop any existing HAL session
halrun -U 2>/dev/null || true
pkill -f "python3.*haltune_test_comp" 2>/dev/null || true
sleep 0.5

# Create FIFO
rm -f "$FIFO"
mkfifo "$FIFO"

# Start halrun
echo "Starting halrun..."
halrun -I -f "$HAL_FILE" <"$FIFO" >/dev/null 2>&1 &
HALRUN_PID=$!
sleep 0.5

# Start Python component
echo "Starting Python component..."
python3 "$PYTHON_COMP" &
PYTHON_COMP_PID=$!
sleep 1

# Check components with halcmd
echo ""
echo "=== halcmd list comp ==="
halcmd list comp
echo ""

echo "=== halcmd list pin ==="
halcmd list pin
echo ""

# Check if haltune binary exists
if [ ! -f "$HALTUNE_BIN" ]; then
    echo "ERROR: haltune binary not found at $HALTUNE_BIN"
    exit 1
fi

# Test 1: Run haltune for 3 seconds with --test-mode
echo "=== Test: Running haltune --test-mode for 3 seconds ==="
timeout 3 "$HALTUNE_BIN" --test-mode 2>&1 || echo "haltune exited with code: $?"

echo ""
echo "=== Cleanup ==="
kill $PYTHON_COMP_PID 2>/dev/null || true
kill $HALRUN_PID 2>/dev/null || true
sleep 0.5

echo "Test complete!"
