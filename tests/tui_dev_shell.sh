#!/bin/bash
# Development shell wrapper for haltune TUI testing
# Sets up halrun with the same configuration as automated tests
# then drops you into a shell for interactive experimentation

HALTUNE_BIN="${HALTUNE_BIN:-./zig-out/bin/haltune}"
HAL_FILE="/tmp/tui_dev.hal"
PYTHON_COMP="/tmp/haltune_test_comp.py"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}==============================================${NC}"
echo -e "${BLUE}haltune TUI Development Shell${NC}"
echo -e "${BLUE}==============================================${NC}"
echo ""

# Check if haltune binary exists
if [ ! -f "$HALTUNE_BIN" ]; then
    echo -e "${RED}ERROR: haltune binary not found at $HALTUNE_BIN${NC}"
    echo "Build haltune first: zig build"
    exit 1
fi

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
# TUI development HAL file
# The test component is started separately via Python
EOF

echo -e "${GREEN}Python HAL component created at: $PYTHON_COMP${NC}"
echo ""

# Start the Python HAL component
echo -e "${YELLOW}Starting Python HAL component...${NC}"
python3 "$PYTHON_COMP" &
PYTHON_COMP_PID=$!
sleep 1.0

# Start halrun in background using a wrapper that keeps it alive
echo -e "${YELLOW}Starting halrun...${NC}"

# Use a simple loop to keep halrun alive when run in background
cat > /tmp/halrun_wrapper.sh << 'WRAPPER_EOF'
#!/bin/bash
# Keep halrun alive by piping commands to it
HAL_FILE="$1"

# Start halrun and feed it a "wait" command to keep it alive
(
  while true; do
    echo "wait"
    sleep 10
  done
) | halrun -f "$HAL_FILE" 2>/dev/null &
echo $! > /tmp/halrun_wrapper.pid
WRAPPER_EOF

chmod +x /tmp/halrun_wrapper.sh
/tmp/halrun_wrapper.sh "$HAL_FILE"
sleep 1.5

# Check if HAL is available
if halcmd list comp >/dev/null 2>&1; then
    echo -e "${GREEN}HAL is running${NC}"
    echo ""
    echo "Available components:"
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

# Set up cleanup
cleanup() {
    echo ""
    echo -e "${YELLOW}Cleaning up...${NC}"

    # Stop Python component
    kill $PYTHON_COMP_PID 2>/dev/null || true
    pkill -f "python3.*$PYTHON_COMP" 2>/dev/null || true

    # Stop halrun wrapper
    if [ -f /tmp/halrun_wrapper.pid ]; then
        PID=$(cat /tmp/halrun_wrapper.pid)
        kill $PID 2>/dev/null || true
        rm -f /tmp/halrun_wrapper.pid
    fi
    pkill -f "halrun.*$HAL_FILE" 2>/dev/null || true

    # Stop HAL
    halrun -U 2>/dev/null || true

    rm -f /tmp/halrun_wrapper.sh
    echo -e "${GREEN}Done${NC}"
}

trap cleanup EXIT INT TERM

# Export for use in shell
export HALTUNE_BIN
export HAL_FILE
export PYTHON_COMP

echo -e "${BLUE}==============================================${NC}"
echo -e "${GREEN}Environment ready!${NC}"
echo ""
echo "Available commands:"
echo "  haltune              - Start haltune TUI"
echo "  halcmd list comp     - List components"
echo "  halcmd list pin      - List all pins"
echo "  halcmd list param    - List all parameters"
echo ""
echo -e "${YELLOW}Type 'exit' or Ctrl+D to leave the shell${NC}"
echo -e "${BLUE}==============================================${NC}"
echo ""

# Start interactive shell
$SHELL
