#!/bin/bash
# Interactive TUI test wrapper
# Sets up the same HAL environment as the automated tests
# but runs haltune interactively for manual exploration

HALTUNE_BIN="${HALTUNE_BIN:-./zig-out/bin/haltune}"
HAL_FILE="${1:-/tmp/test_interactive.hal}"

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
sleep 0.5

# Create the HAL file (same as automated test)
cat > "$HAL_FILE" << 'EOF'
# Interactive TUI test HAL file
# This loads the threads component which has pins of all types

# Load threads component (creates thread.0 with time and timed-out pins)
loadrt threads
EOF

echo "HAL file contents:"
echo "----------------------------------------------"
cat "$HAL_FILE"
echo "----------------------------------------------"
echo ""

# Start halrun in background using a wrapper that keeps it alive
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
echo "This will also shut down halrun"
echo "=============================================="
echo ""

# Set trap to ensure halrun is cleaned up
cleanup() {
    echo ""
    echo -e "${YELLOW}Shutting down halrun...${NC}"
    if [ -f /tmp/halrun_interactive_wrapper.pid ]; then
        PID=$(cat /tmp/halrun_interactive_wrapper.pid)
        kill $PID 2>/dev/null || true
        rm -f /tmp/halrun_interactive_wrapper.pid
    fi
    pkill -f "halrun.*$HAL_FILE" 2>/dev/null || true
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
