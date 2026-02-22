#!/bin/bash
# Development shell wrapper for haltune TUI testing
# Uses halrun with logic components instead of Python component

HALTUNE_BIN="${HALTUNE_BIN:-./zig-out/bin/haltune}"
HAL_FILE="/tmp/tui_dev_hal.$$"
FIFO="/tmp/halrun_stdin.$$"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}  ${BOLD}haltune TUI Development Shell${NC}                       ${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if haltune binary exists
if [ ! -f "$HALTUNE_BIN" ]; then
    echo -e "${RED}ERROR: haltune binary not found at $HALTUNE_BIN${NC}"
    echo "Build haltune first: zig build"
    exit 1
fi

# Stop any existing HAL session
echo -e "${YELLOW}→ Cleaning up any existing HAL session...${NC}"
halrun -U 2>/dev/null || true
pkill -f "halrun.*$HAL_FILE" 2>/dev/null || true
sleep 0.5

# Create HAL file with built-in test components
# Using logic components and threads component which are always available
cat > "$HAL_FILE" << 'EOF'
# TUI development HAL file with built-in components

# Load the threads component (always available in HAL)
loadusr threads

# Create some test signals
net test-signal1
net test-signal2

# Create a logic component with AND/OR/NOT gates
# These create pins that can be viewed in haltune
loadusr logic AND and1
loadusr logic OR or1
loadusr logic NOT not1

# Create some mux components
loadusr mux2 mux1
loadusr mux2 mux2

# Create a counter component
loadusr count count1

# Create a debounce component
loadusr debounce debounce1

# Create some test pins with connections
net and-out and1.out
net or-out or1.out
net not-out not1.out

# Set some initial values
setp and1.in0 TRUE
setp and1.in1 FALSE
setp or1.in0 TRUE
setp or1.in1 FALSE

# Add a parameter to modify
setp count1.enable TRUE
setp count1.min 0
setp count1.max 100

# Show what we have
echo "=== HAL Test Environment Loaded ==="
echo "Components loaded:"
echo "  - threads (base HAL component)"
echo "  - logic gates (AND, OR, NOT)"
echo "  - mux components"
echo "  - counter"
echo "  - debounce"
echo ""
EOF

echo -e "${GREEN}✓ HAL file created with built-in components${NC}"
echo ""

# Create a FIFO to keep halrun's stdin open
rm -f "$FIFO"
mkfifo "$FIFO"

# Start halrun with FIFO as stdin
echo -e "${YELLOW}→ Starting halrun with test components...${NC}"
halrun -I -f "$HAL_FILE" <"$FIFO" 2>&1 &
HALRUN_PID=$!

# Give halrun time to initialize
sleep 1.0

# Check if halrun is still running
if ! ps -p $HALRUN_PID >/dev/null 2>&1; then
    echo -e "${RED}ERROR: halrun exited immediately${NC}"
    rm -f "$FIFO"
    exit 1
fi

echo -e "${GREEN}  halrun PID: $HALRUN_PID${NC}"

# Verify HAL is running and has components
echo -e "${YELLOW}→ Verifying HAL state...${NC}"
if halcmd list comp >/dev/null 2>&1; then
    COMP_COUNT=$(halcmd list comp 2>/dev/null | wc -w)
    PIN_COUNT=$(halcmd list pin 2>/dev/null | wc -w)
    PARAM_COUNT=$(halcmd list param 2>/dev/null | wc -w)
    echo -e "${GREEN}✓ HAL is running${NC}"
else
    echo -e "${RED}ERROR: HAL is not responding${NC}"
    rm -f "$FIFO"
    exit 1
fi

echo ""
echo -e "${BOLD}HAL Environment Status:${NC}"
echo "─────────────────────────────────────────────────────"

echo -e "  ${GREEN}●${NC} HAL is ${BOLD}running${NC}"
echo -e "  ${CYAN}├─${NC} Components: ${BOLD}$COMP_COUNT${NC}"
echo -e "  ${CYAN}├─${NC} Pins: ${BOLD}$PIN_COUNT${NC}"
echo -e "  ${CYAN}└─${NC} Parameters: ${BOLD}$PARAM_COUNT${NC}"
echo ""

echo -e "${BOLD}Components:${NC}"
halcmd list comp 2>/dev/null | head -20 | fold -w 70 | sed 's/^/  /'

echo ""
echo -e "  ${GREEN}●${NC} halrun: ${BOLD}running${NC} (PID: $HALRUN_PID)"
echo ""

# Set up cleanup
cleanup() {
    echo ""
    echo -e "${YELLOW}→ Shutting down...${NC}"

    # Stop halrun
    kill $HALRUN_PID 2>/dev/null || true
    pkill -f "halrun.*$HAL_FILE" 2>/dev/null || true
    halrun -U 2>/dev/null || true

    # Clean up FIFO
    rm -f "$FIFO" 2>/dev/null || true
    rm -f "$HAL_FILE" 2>/dev/null || true

    echo -e "${GREEN}✓ Cleanup complete${NC}"
}

trap cleanup EXIT INT TERM

# Export for use in shell
export HALTUNE_BIN
export HAL_FILE
export HALRUN_PID
export FIFO

# Custom prompt function to show we're in dev shell
_tui_dev_shell_prompt() {
    local EXIT_CODE=$?
    local PROMPT_SYMBOL="⟩⟩⟩"

    if [ $EXIT_CODE -eq 0 ]; then
        echo -ne "\01${CYAN}\02${PROMPT_SYMBOL}\01${NC}\02 "
    else
        echo -ne "\01${RED}\02${PROMPT_SYMBOL}[$EXIT_CODE]\01${NC}\02 "
    fi
}

# Set the prompt
PS1='$(_tui_dev_shell_prompt)\[\033[1;90m\]tui-dev\[\033[0m\] \$ '

echo -e "╔═══════════════════════════════════════════════════════════════════════════╗"
echo -e "║${NC}  ${BOLD}Interactive Development Shell${NC}                                      ${CYAN}║${NC}"
echo -e "╠═══════════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "║${NC}  ${BOLD}Available Commands:${NC}                                                      ${CYAN}║${NC}"
echo -e "║${NC}  ${CYAN}•${NC} ${GREEN}haltune${NC}              - Start haltune TUI                    ${CYAN}║${NC}"
echo -e "║${NC}  ${CYAN}•${NC} ${GREEN}halcmd list comp${NC}     - List all components                   ${CYAN}║${NC}"
echo -e "║${NC}  ${CYAN}•${NC} ${GREEN}halcmd list pin${NC}      - List all pins                        ${CYAN}║${NC}"
echo -e "║${NC}  ${CYAN}•${NC} ${GREEN}halcmd list param${NC}    - List all parameters                   ${CYAN}║${NC}"
echo -e "║${NC}                                                                               ${CYAN}║${NC}"
echo -e "║${NC}  ${YELLOW}Type 'exit' or Ctrl+D to leave the shell${NC}                             ${CYAN}║${NC}"
echo -e "╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Start interactive shell
$SHELL
