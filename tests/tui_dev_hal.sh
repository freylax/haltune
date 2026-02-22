#!/bin/bash
# Simple development shell for haltune TUI testing
# Uses only halrun with a simple HAL file (no external components)

HALTUNE_BIN="/home/cnc/prog/haltune/zig-out/bin/haltune"
HAL_FILE="/tmp/tui_dev_simple.hal"
FIFO="/tmp/halrun_fifo.$$"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}  ${BOLD}haltune TUI Development Shell (Simple)${NC}              ${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if haltune binary exists
if [ ! -f "$HALTUNE_BIN" ]; then
    echo -e "${RED}ERROR: haltune binary not found at $HALTUNE_BIN${NC}"
    exit 1
fi

# Stop any existing HAL session
echo -e "${YELLOW}→ Cleaning up...${NC}"
halrun -U 2>/dev/null || true
pkill -f "halrun.*$HAL_FILE" 2>/dev/null || true
sleep 0.5

# Create a simple HAL file that creates a test component via comp
# We'll create a C component using halcompile
cat > "$HAL_FILE" << 'EOF'
# Simple HAL test file
# Create a test component using halcompile if available

# First, try to load the test component if it exists
# (You can build it with: halcompile --install test_comp)

# For now, just verify HAL is running
echo "HAL is running"
list comp
EOF

# Create FIFO
rm -f "$FIFO"
mkfifo "$FIFO"

# Start halrun
echo -e "${YELLOW}→ Starting halrun...${NC}"
halrun -I -f "$HAL_FILE" <"$FIFO" >/dev/null 2>&1 &
HALRUN_PID=$!
sleep 1.0

# Check if halrun is running
if ! ps -p $HALRUN_PID >/dev/null 2>&1; then
    echo -e "${RED}ERROR: halrun exited${NC}"
    rm -f "$FIFO"
    exit 1
fi

echo -e "${GREEN}✓ halrun running (PID: $HALRUN_PID)${NC}"

# Show HAL status
echo ""
echo -e "${BOLD}HAL Status:${NC}"
if halcmd list comp >/dev/null 2>&1; then
    COMP_COUNT=$(halcmd list comp 2>/dev/null | wc -w)
    echo -e "  ${GREEN}●${NC} HAL is running with $COMP_COUNT components"
    halcmd list comp 2>/dev/null | head -5 | sed 's/^/    /'
else
    echo -e "  ${YELLOW}●${NC} HAL running but no components yet"
fi
echo ""

# Note to user
echo -e "${YELLOW}Note: To create test pins/params, run:${NC}"
echo -e "  ${CYAN}python3 -c \"import hal; h=hal.component('test'); h.newpin('p', hal.HAL_BIT, hal.HAL_OUT); h.ready(); import time; time.sleep(3600)\" &${NC}"
echo ""

# Cleanup function
cleanup() {
    echo ""
    echo -e "${YELLOW}→ Shutting down...${NC}"
    kill $HALRUN_PID 2>/dev/null || true
    halrun -U 2>/dev/null || true
    rm -f "$FIFO" 2>/dev/null || true
    rm -f "$HAL_FILE" 2>/dev/null || true
    echo -e "${GREEN}✓ Cleanup complete${NC}"
}

trap cleanup EXIT INT TERM

# Export
export HALTUNE_BIN
export HAL_FILE
export HALRUN_PID

# Custom prompt
PS1='\[\033[1;90m\]tui-dev-simple\[\033[0m\] \$ '

echo -e "${BOLD}Ready! Type 'haltune' to start the TUI.${NC}"
echo ""

# Start shell
$SHELL
