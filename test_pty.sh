#!/bin/bash
# Automated PTY test for haltune TUI
#
# This script tests haltune with a pseudo-terminal (PTY) to enable
# automated testing without requiring an interactive terminal.
#
# Usage: ./test_pty.sh [timeout_seconds]
#
# The script uses `script` to allocate a PTY and `stty` to set
# terminal dimensions (80x24), which is required for vaxis to
# initialize properly without division by zero errors.
#
# Environment variables:
#   HALTUNE_BIN - Path to haltune binary (default: ./zig-out/bin/haltune)
#   TIMEOUT    - Test duration in seconds (default: 5)

set -e

# Configuration
TIMEOUT=${1:-5}
HALTUNE_BIN=${HALTUNE_BIN:-./zig-out/bin/haltune}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== haltune Automated PTY Test ==="
echo "Binary: $HALTUNE_BIN"
echo "Timeout: ${TIMEOUT}s"
echo ""

# Check if binary exists
if [ ! -f "$HALTUNE_BIN" ]; then
    echo "ERROR: haltune binary not found at $HALTUNE_BIN"
    echo "Build with: zig build"
    exit 1
fi

# Optional: Start HAL with test components if LinuxCNC is not running
if ! halcmd list comp >/dev/null 2>&1; then
    echo "Starting test HAL instance..."

    # Create a minimal HAL configuration for testing
    cat > /tmp/haltune_test.hal << 'HAL'
# Test HAL configuration for haltune
# This creates a minimal HAL environment for testing

# Load basic threading support
loadrt threads

# Create a test signal
newsig test-signal float

HAL

    halrun /tmp/haltune_test.hal 2>/dev/null &
    HAL_PID=$!
    sleep 1

    # Cleanup on exit
    trap "kill $HAL_PID 2>/dev/null; rm -f /tmp/haltune_test.hal" EXIT

    echo "HAL PID: $HAL_PID"
else
    echo "Using existing HAL instance"
fi

echo ""
echo "HAL Components:"
halcmd list comp 2>/dev/null || echo "  (none)"

echo ""
echo "HAL Pins (first 5):"
halcmd list pin 2>/dev/null | head -5 || echo "  (none)"

echo ""
echo "Running haltune with PTY..."
echo "Expected output: 'Ctrl+T=Table View' indicates successful TUI render"
echo ""

# Run haltune with PTY and capture key output
# The key parts:
# - script -q: Quiet mode, allocate PTY
# - stty cols 80 rows 24: Set terminal dimensions (CRITICAL for vaxis)
# - --test-mode: Bypass terminal size validation
# - timeout: Prevent infinite run during automated testing
timeout "$TIMEOUT" script -q -c "stty cols 80 rows 24 2>/dev/null; '$HALTUNE_BIN' --test-mode" /dev/null 2>&1 | \
    grep -E '(Tree initialized|discovered [0-9]+ (pin|signal|param)|Ctrl\+T|panic|resizing screen)' || true

echo ""
echo "=== Test complete ==="
echo ""
echo "To test interactively, run:"
echo "  ./zig-out/bin/haltune"
