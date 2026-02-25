#!/bin/bash
# HAL Bridge Server Integration Test
# Tests the bridge server connectivity and basic operations

set -e

HAL_BRIDGE_HOST="${HAL_BRIDGE_HOST:-192.168.2.118}"
HAL_BRIDGE_PORT="${HAL_BRIDGE_PORT:-8765}"

echo "=== HAL Bridge Server Integration Test ==="
echo "Target: ${HAL_BRIDGE_HOST}:${HAL_BRIDGE_PORT}"
echo ""

# Test 1: Ping
echo "Test 1: Ping request"
(echo '{"type":"ping"}'; sleep 0.5) | nc ${HAL_BRIDGE_HOST} ${HAL_BRIDGE_PORT} && echo "OK: Ping successful"
echo ""

# Test 2: List pins
echo "Test 2: List pins request"
(echo '{"type":"list_pins"}'; sleep 0.5) | nc ${HAL_BRIDGE_HOST} ${HAL_BRIDGE_PORT} && echo "OK: List pins successful"
echo ""

# Test 3: Get pin (will fail if pin doesn't exist)
echo "Test 3: Get pin request (expected error if not connected to HAL)"
(echo '{"type":"get_pin","name":"test.pin"}'; sleep 0.5) | nc ${HAL_BRIDGE_HOST} ${HAL_BRIDGE_PORT}
echo ""

# Test 4: Unknown request type
echo "Test 4: Unknown request (expected error)"
(echo '{"type":"unknown"}'; sleep 0.5) | nc ${HAL_BRIDGE_HOST} ${HAL_BRIDGE_PORT}
echo ""

echo "=== Tests Complete ==="
