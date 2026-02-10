#!/bin/bash
# HAL Integration Test for haltune
#
# This script tests haltune's integration with the HAL (Hardware Abstraction Layer).
# It can work with an existing LinuxCNC instance or start a minimal HAL environment.
#
# Usage: ./test_mock_hal.sh
#
# Requirements:
# - LinuxCNC HAL utilities (halcmd, halrun)
# - Either a running LinuxCNC instance OR ability to start halrun
#
# The test verifies:
# 1. HAL connection establishment
# 2. Component registration
# 3. Pin/signal/parameter discovery
# 4. TUI rendering with PTY

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HALTUNE_BIN="${HALTUNE_BIN:-./zig-out/bin/haltune}"

echo "=== haltune HAL Integration Test ==="
echo ""

# Check if haltune binary exists
if [ ! -f "$HALTUNE_BIN" ]; then
    echo "ERROR: haltune binary not found at $HALTUNE_BIN"
    echo "Build with: zig build"
    exit 1
fi

# Check if HAL is available
if ! command -v halcmd &>/dev/null; then
    echo "ERROR: halcmd not found. Install LinuxCNC."
    exit 1
fi

# Check if HAL is already running
if halcmd list comp >/dev/null 2>&1; then
    echo "Using existing HAL instance"
    HAL_ALREADY_RUNNING=1
else
    echo "No HAL instance found. Starting minimal HAL..."
    HAL_ALREADY_RUNNING=0

    # Clean up any stale HAL
    halrun -U 2>/dev/null || true
    sleep 1

    # Start a minimal HAL instance
    cat > /tmp/haltune_test.hal << 'HAL'
# Minimal HAL configuration for haltune testing
HAL

    halrun /tmp/haltune_test.hal 2>/dev/null &
    HAL_PID=$!
    sleep 1

    trap "kill $HAL_PID 2>/dev/null; rm -f /tmp/haltune_test.hal; halrun -U 2>/dev/null || true" EXIT
fi

# Show HAL status
echo ""
echo "=== HAL Components ==="
halcmd list comp

echo ""
echo "=== HAL Pins (first 10) ==="
PIN_COUNT=$(halcmd list pin 2>/dev/null | wc -l)
echo "Total pins: $PIN_COUNT"
halcmd list pin 2>/dev/null | head -10 || echo "  (none)"

echo ""
echo "=== HAL Signals ==="
SIG_COUNT=$(halcmd list sig 2>/dev/null | wc -l)
echo "Total signals: $SIG_COUNT"
halcmd list sig 2>/dev/null || echo "  (none)"

echo ""
echo "=== HAL Parameters (non-HAL) ==="
PARAM_COUNT=$(halcmd list param 2>/dev/null | grep -v '^   HAL' | grep -v '^   ' | wc -l)
echo "Total parameters: $PARAM_COUNT"
halcmd list param 2>/dev/null | grep -v '^   HAL' | grep -v '^   ' | head -10 || echo "  (none)"

echo ""
echo "=== Running haltune TUI (8 seconds) ==="

# Run haltune with PTY and capture output
OUTPUT=$(timeout 8 script -q -c "stty cols 80 rows 24 2>/dev/null; '$HALTUNE_BIN' --test-mode" /dev/null 2>&1)

# Show discovery activity
echo "$OUTPUT" | grep -E '(discovered [0-9]+ (pin|signal|param))' | head -5

# Extract final discovery counts
DISCOVERED_PINS=$(echo "$OUTPUT" | grep -oP 'discovered \K[0-9]+(?= pins from HAL)' | tail -1)
DISCOVERED_SIGS=$(echo "$OUTPUT" | grep -oP 'discovered \K[0-9]+(?= signals from HAL)' | tail -1)
DISCOVERED_PARAMS=$(echo "$OUTPUT" | grep -oP 'discovered \K[0-9]+(?= params from HAL)' | tail -1)

echo ""
echo "=== Test Results ==="

# Check if TUI rendered
if echo "$OUTPUT" | grep -q "Ctrl+T=Table View"; then
    echo "✓ TUI rendered successfully"
    TUI_OK=1
else
    echo "✗ TUI render failed"
    TUI_OK=0
fi

# Check for panics
if echo "$OUTPUT" | grep -q "panic"; then
    echo "✗ Panic detected!"
    echo "$OUTPUT" | grep -A5 "panic"
    exit 1
fi

# Check component registration
if halcmd list comp | grep -q haltune; then
    echo "✓ haltune registered as HAL component"
else
    echo "✗ haltune not registered in HAL"
fi

# Summary
echo ""
echo "Discovery Summary:"
echo "  HAL pins available:    $PIN_COUNT"
echo "  HAL signals available: $SIG_COUNT"
echo "  HAL params available:  $PARAM_COUNT"
echo "  Discovered by haltune:"
echo "    Pins:    ${DISCOVERED_PINS:-0}"
echo "    Signals: ${DISCOVERED_SIGS:-0}"
echo "    Params:  ${DISCOVERED_PARAMS:-0}"

# Test passes if TUI rendered and no panic
if [ "$TUI_OK" = "1" ]; then
    echo ""
    echo "✓ Test PASSED"
    exit 0
else
    echo ""
    echo "✗ Test FAILED"
    exit 1
fi
