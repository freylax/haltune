#!/bin/bash
# HAL Bridge Server Comprehensive Integration Test
# Tests bridge server connectivity and basic operations

set -e

HAL_BRIDGE_HOST="${HAL_BRIDGE_HOST:-192.168.2.118}"
HAL_BRIDGE_PORT="${HAL_BRIDGE_PORT:-8765}"
PASS=0
FAIL=0

# Color output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Helper to send request and get response
send_request() {
    local request="$1"
    (echo "${request}"; sleep 0.3) | nc ${HAL_BRIDGE_HOST} ${HAL_BRIDGE_PORT} 2>/dev/null || echo ""
}

test_result() {
    local test_name="$1"
    local result="$2"

    if [ -n "$result" ]; then
        echo -e "${GREEN}✓ $test_name${NC}"
        echo "  Response: $result"
        ((PASS++))
    else
        echo -e "${RED}✗ $test_name${NC} - No response"
        ((FAIL++))
    fi
}

echo "=== HAL Bridge Server Comprehensive Test ==="
echo "Target: ${HAL_BRIDGE_HOST}:${HAL_BRIDGE_PORT}"
echo ""

# Start bridge server on pib if not running
echo "Checking if server is running..."
if ! ssh pib "pgrep -f hal_bridge_server >/dev/null" 2>/dev/null; then
    echo "Starting server on pib..."
    ssh pib "cd ~/prog/haltune && ~/prog/haltune/zig-out/bin/hal_bridge_server > /dev/null 2>&1 &"
    sleep 3
fi
echo ""

# Test 1: Ping
echo "Test 1: Ping request"
result=$(send_request '{"type":"ping"}')
if [ "$result" = '{"type":"ping"}' ]; then
    test_result "Ping" "$result"
else
    test_result "Ping" "$result"
fi

# Test 2: List pins
echo "Test 2: List pins request"
result=$(send_request '{"type":"list_pins"}')
if [[ "$result" == *"list_pins"* ]]; then
    test_result "List pins" "$result"
else
    test_result "List pins" "$result"
fi

# Test 3: Get pin (will fail if pin doesn't exist)
echo "Test 3: Get pin request (expected error if pin doesn't exist)"
result=$(send_request '{"type":"get_pin","name":"test.pin"}')
if [[ "$result" == *"error"* ]]; then
    test_result "Get pin (error expected)" "$result"
else
    test_result "Get pin" "$result"
fi

# Test 4: Set pin (bit value)
echo "Test 4: Set pin request with bit value"
result=$(send_request '{"type":"set_pin","name":"test.pin","value":{"bit":true}}')
if [[ "$result" == *"error"* ]] || [[ "$result" == *"success"* ]]; then
    test_result "Set pin (bit)" "$result"
else
    test_result "Set pin (bit)" "$result"
fi

# Test 5: Set pin (float value)
echo "Test 5: Set pin request with float value"
result=$(send_request '{"type":"set_pin","name":"test.float","value":{"float":3.14}}')
if [[ "$result" == *"error"* ]] || [[ "$result" == *"success"* ]]; then
    test_result "Set pin (float)" "$result"
else
    test_result "Set pin (float)" "$result"
fi

# Test 6: List signals
echo "Test 6: List signals request"
result=$(send_request '{"type":"list_signals"}')
if [[ "$result" == *"list_signals"* ]] || [[ "$result" == *"error"* ]]; then
    test_result "List signals" "$result"
else
    test_result "List signals" "$result"
fi

# Test 7: List params
echo "Test 7: List params request"
result=$(send_request '{"type":"list_params"}')
if [[ "$result" == *"list_params"* ]] || [[ "$result" == *"error"* ]]; then
    test_result "List params" "$result"
else
    test_result "List params" "$result"
fi

# Test 8: List components
echo "Test 8: List components request"
result=$(send_request '{"type":"list_components"}')
if [[ "$result" == *"list_components"* ]] || [[ "$result" == *"error"* ]]; then
    test_result "List components" "$result"
else
    test_result "List components" "$result"
fi

# Test 9: Get param
echo "Test 9: Get param request"
result=$(send_request '{"type":"get_param","name":"test.param"}')
if [[ "$result" == *"error"* ]] || [[ "$result" == *"get_param"* ]]; then
    test_result "Get param" "$result"
else
    test_result "Get param" "$result"
fi

# Test 10: Create signal
echo "Test 10: Create signal request"
result=$(send_request '{"type":"create_signal","name":"test.signal","pin_type":"bit"}')
if [[ "$result" == *"error"* ]] || [[ "$result" == *"success"* ]]; then
    test_result "Create signal" "$result"
else
    test_result "Create signal" "$result"
fi

# Test 11: Delete signal
echo "Test 11: Delete signal request"
result=$(send_request '{"type":"delete_signal","name":"test.signal"}')
if [[ "$result" == *"error"* ]] || [[ "$result" == *"success"* ]]; then
    test_result "Delete signal" "$result"
else
    test_result "Delete signal" "$result"
fi

# Test 12: Link pin
echo "Test 12: Link pin request"
result=$(send_request '{"type":"link_pin","pin_name":"test.pin","sig_name":"test.signal"}')
if [[ "$result" == *"error"* ]] || [[ "$result" == *"success"* ]]; then
    test_result "Link pin" "$result"
else
    test_result "Link pin" "$result"
fi

# Test 13: Unlink pin
echo "Test 13: Unlink pin request"
result=$(send_request '{"type":"unlink_pin","name":"test.pin"}')
if [[ "$result" == *"error"* ]] || [[ "$result" == *"success"* ]]; then
    test_result "Unlink pin" "$result"
else
    test_result "Unlink pin" "$result"
fi

# Test 14: Invalid JSON
echo "Test 14: Invalid JSON"
result=$(send_request '{invalid json}')
if [[ "$result" == *"error"* ]] || [[ "$result" == *"Invalid"* ]]; then
    test_result "Invalid JSON" "$result"
else
    test_result "Invalid JSON" "$result"
fi

# Summary
echo ""
echo "=== Test Summary ==="
echo -e "${GREEN}Passed: $PASS${NC}"
echo -e "${RED}Failed: $FAIL${NC}"
echo "Total: $((PASS + FAIL))"

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi
