#!/bin/bash
# Development shell wrapper for haltune TUI testing
# Sets up halrun with the same configuration as automated tests
# then drops you into a shell for interactive experimentation

HALTUNE_BIN="${HALTUNE_BIN:-./zig-out/bin/haltune}"
HAL_FILE="/tmp/tui_dev.hal"

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
sleep 0.5

# Create HAL file
cat > "$HAL_FILE" << 'EOF'
# TUI development HAL file
loadrt threads
EOF

echo -e "${GREEN}HAL configuration:${NC}"
cat "$HAL_FILE"
echo ""

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
else
    echo -e "${YELLOW}Warning: HAL may not be running properly${NC}"
fi
echo ""

# Set up cleanup
cleanup() {
    echo ""
    echo -e "${YELLOW}Cleaning up...${NC}"
    if [ -f /tmp/halrun_wrapper.pid ]; then
        PID=$(cat /tmp/halrun_wrapper.pid)
        kill $PID 2>/dev/null || true
        rm -f /tmp/halrun_wrapper.pid
    fi
    # Kill any halrun processes
    pkill -f "halrun.*$HAL_FILE" 2>/dev/null || true
    halrun -U 2>/dev/null || true
    rm -f /tmp/halrun_wrapper.sh
    echo -e "${GREEN}Done${NC}"
}

trap cleanup EXIT INT TERM

# Export for use in shell
export HALTUNE_BIN
export HAL_FILE

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
