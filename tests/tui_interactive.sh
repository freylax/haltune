#!/bin/bash
# Interactive TUI test wrapper
# Sets up the same HAL environment as the automated tests
# but runs haltune interactively for manual exploration

set -e

HALTUNE_BIN="${HALTUNE_BIN:-./zig-out/bin/haltune}"
HAL_FILE="${1:-/tmp/test_interactive.hal}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Start halrun in background with -I (interactive mode)
echo -e "${YELLOW}Starting halrun in background...${NC}"
halrun -I -f "$HAL_FILE" &
HALRUN_PID=$!
sleep 1.5

# Check if halrun is still running
if ! kill -0 $HALRUN_PID 2>/dev/null; then
    echo -e "${RED}ERROR: halrun failed to start${NC}"
    exit 1
fi

echo -e "${GREEN}halrun started (PID: $HALRUN_PID)${NC}"
echo ""

# Show available components
echo "Available HAL components:"
halcmd list comp
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
trap "echo ''; echo -e '${YELLOW}Shutting down halrun...${NC}'; echo exit | halcmd; kill $HALRUN_PID 2>/dev/null || true; wait $HALRUN_PID 2>/dev/null || true; echo -e '${GREEN}Done${NC}'" EXIT INT TERM

# Start haltune
"$HALTUNE_BIN"

# If we get here, haltune exited normally
echo ""
echo -e "${GREEN}haltune exited${NC}"
