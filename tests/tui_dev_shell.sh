#!/bin/bash
# Development shell wrapper for haltune TUI testing
# Sets up halrun with the same configuration as automated tests
# then drops you into a shell for interactive experimentation

set -e

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

# Create HAL file
cat > "$HAL_FILE" << 'EOF'
# TUI development HAL file
loadrt threads
EOF

echo -e "${GREEN}HAL configuration:${NC}"
cat "$HAL_FILE"
echo ""

# Start halrun
echo -e "${YELLOW}Starting halrun...${NC}"
halrun -I -f "$HAL_FILE" &
HALRUN_PID=$!
sleep 1.5

if ! kill -0 $HALRUN_PID 2>/dev/null; then
    echo -e "${RED}ERROR: halrun failed to start${NC}"
    exit 1
fi

echo -e "${GREEN}halrun started (PID: $HALRUN_PID)${NC}"
echo ""

# Show components
echo "Available components:"
halcmd list comp
echo ""

# Set up cleanup
cleanup() {
    echo ""
    echo -e "${YELLOW}Cleaning up...${NC}"
    echo exit | halcmd 2>/dev/null || true
    kill $HALRUN_PID 2>/dev/null || true
    wait $HALRUN_PID 2>/dev/null || true
    echo -e "${GREEN}Done${NC}"
}

trap cleanup EXIT INT TERM

# Export for use in shell
export HALTUNE_BIN
export HALRUN_PID
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
