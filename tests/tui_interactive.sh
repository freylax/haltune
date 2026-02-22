#!/bin/bash
# Interactive TUI test wrapper
# Sets up the same HAL environment as the automated tests
# but runs haltune interactively for manual exploration

HALTUNE_BIN="${HALTUNE_BIN:-./zig-out/bin/haltune}"
HAL_FILE="${1:-/tmp/test_interactive.hal}"
PYTHON_COMP="/tmp/haltune_test_comp.py"
FIFO="/tmp/halrun_stdin.$$"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=============================================="
echo "haltune Interactive TUI Test"
echo "=============================================="
echo ""

# Check if haltune binary exists
if [ ! -f "$HALTUNE_BIN" ]; then
    echo -e "${RED}ERROR: haltune binary not found at $HALTUNE_BIN${NC}"
    echo "Build haltune first: zig build"
    exit 1
fi

echo -e "${GREEN}Using haltune:${NC} $HALTUNE_BIN"
echo -e "${GREEN}HAL file:${NC} $HAL_FILE"
echo ""

# Stop any existing HAL session
echo -e "${YELLOW}Stopping any existing HAL session...${NC}"
halrun -U 2>/dev/null || true
pkill -f "python3.*$PYTHON_COMP" 2>/dev/null || true
sleep 0.5

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
# Interactive TUI test HAL file
# The test component is started separately via Python
EOF

echo "Python HAL component created at: $PYTHON_COMP"
echo ""

# Create a FIFO to keep halrun's stdin open
# halrun -I reads from stdin; we use a FIFO with write end never opened
# This causes halrun to block on read() forever, keeping HAL alive
rm -f "$FIFO"
mkfifo "$FIFO"

# Start halrun with FIFO as stdin
echo -e "${YELLOW}Starting halrun...${NC}"
halrun -I -f "$HAL_FILE" <"$FIFO" >/dev/null 2>&1 &
HALRUN_PID=$!
echo "  PID: $HALRUN_PID"

# Give halrun time to initialize HAL
sleep 0.5

# Start the Python HAL component
echo -e "${YELLOW}Starting Python HAL component...${NC}"
python3 "$PYTHON_COMP" &
PYTHON_COMP_PID=$!
echo "  PID: $PYTHON_COMP_PID"

# Wait for the component to be ready
echo -e "${YELLOW}Waiting for component to initialize...${NC}"
for i in {1..10}; do
    if halcmd list comp 2>/dev/null | grep -q "haltune-test-comp"; then
        echo "  Component ready!"
        break
    fi
    echo "  Waiting... ($i/10)"
    sleep 0.3
done

# Check if HAL is available
if halcmd list comp >/dev/null 2>&1; then
    echo -e "${GREEN}HAL is running${NC}"
    echo ""
    echo "Available HAL components:"
    halcmd list comp
    echo ""
    echo "Available pins:"
    halcmd list pin
    echo ""
    echo "Available parameters:"
    halcmd list param
else
    echo -e "${YELLOW}Warning: HAL may not be running properly${NC}"
fi
echo ""

# Instructions
echo "=============================================="
echo -e "${GREEN}haltune will start now${NC}"
echo ""
echo "Key bindings:"
echo "  Ctrl+Q    - Quit"
echo "  Ctrl+T    - Toggle tree/table view"
echo "  Enter     - Expand/collapse component, or edit value"
echo "  Space     - Toggle visibility (mark as visible)"
echo "  Up/Down   - Navigate items"
echo "  Backspace - Collapse parent component"
echo "  Escape    - Cancel edit mode"
echo ""
echo -e "${YELLOW}Press Ctrl+Q in haltune to exit${NC}"
echo "This will also shut down halrun and the Python component"
echo "=============================================="
echo ""

# Set trap to ensure everything is cleaned up
cleanup() {
    echo ""
    echo -e "${YELLOW}Shutting down...${NC}"

    # Stop Python component first
    kill $PYTHON_COMP_PID 2>/dev/null || true
    pkill -f "python3.*$PYTHON_COMP" 2>/dev/null || true

    # Stop halrun
    kill $HALRUN_PID 2>/dev/null || true
    pkill -f "halrun.*$HAL_FILE" 2>/dev/null || true
    halrun -U 2>/dev/null || true

    # Clean up FIFO
    rm -f "$FIFO" 2>/dev/null || true

    echo -e "${GREEN}Done${NC}"
}

trap cleanup EXIT INT TERM

# Start haltune
"$HALTUNE_BIN"

# If we get here, haltune exited normally
echo ""
echo -e "${GREEN}haltune exited${NC}"
