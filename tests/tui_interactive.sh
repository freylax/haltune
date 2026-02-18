#!/bin/bash
# Interactive TUI test wrapper
# Sets up the same HAL environment as the automated tests
# but runs haltune interactively for manual exploration

HALTUNE_BIN="${HALTUNE_BIN:-./zig-out/bin/haltune}"
HAL_FILE="${1:-/tmp/test_interactive.hal}"
PYTHON_COMP="/tmp/haltune_test_comp.py"

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

# Create the HAL file (empty, component is started separately)
cat > "$HAL_FILE" << 'EOF'
# Interactive TUI test HAL file
# The test component is started separately via Python
EOF

echo "Python HAL component created at: $PYTHON_COMP"
echo ""

# Start the Python HAL component
echo -e "${YELLOW}Starting Python HAL component...${NC}"
python3 "$PYTHON_COMP" &
PYTHON_COMP_PID=$!
sleep 1.0

# Start halrun in background
echo -e "${YELLOW}Starting halrun in background...${NC}"

# Create a wrapper script to keep halrun alive
cat > /tmp/halrun_interactive_wrapper.sh << 'WRAPPER_EOF'
#!/bin/bash
HAL_FILE="$1"

# Feed halrun with wait commands to keep it alive
(
  while true; do
    echo "wait"
    sleep 10
  done
) | halrun -f "$HAL_FILE" 2>/dev/null &
echo $! > /tmp/halrun_interactive_wrapper.pid
WRAPPER_EOF

chmod +x /tmp/halrun_interactive_wrapper.sh
/tmp/halrun_interactive_wrapper.sh "$HAL_FILE"
sleep 1.5

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

    # Stop halrun wrapper
    if [ -f /tmp/halrun_interactive_wrapper.pid ]; then
        PID=$(cat /tmp/halrun_interactive_wrapper.pid)
        kill $PID 2>/dev/null || true
        rm -f /tmp/halrun_interactive_wrapper.pid
    fi
    pkill -f "halrun.*$HAL_FILE" 2>/dev/null || true

    # Stop Python component
    kill $PYTHON_COMP_PID 2>/dev/null || true
    pkill -f "python3.*$PYTHON_COMP" 2>/dev/null || true

    # Stop HAL
    halrun -U 2>/dev/null || true

    rm -f /tmp/halrun_interactive_wrapper.sh

    echo -e "${GREEN}Done${NC}"
}

trap cleanup EXIT INT TERM

# Start haltune
"$HALTUNE_BIN"

# If we get here, haltune exited normally
echo ""
echo -e "${GREEN}haltune exited${NC}"
