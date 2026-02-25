#!/usr/bin/env python3
"""
Test haltune connecting to remote HAL bridge server on pib.
This demonstrates the remote HAL connection without needing local HAL.
"""

import socket
import json
import sys

# HAL bridge server configuration
HAL_BRIDGE_HOST = "192.168.2.118"
HAL_BRIDGE_PORT = 8765

def send_request(request):
    """Send JSON request to HAL bridge server and get response."""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(2)
        sock.connect((HAL_BRIDGE_HOST, HAL_BRIDGE_PORT))

        # Send request
        json_str = json.dumps(request) + "\n"
        sock.sendall(json_str.encode())

        # Receive response
        data = sock.recv(4096)
        sock.close()

        response = json.loads(data.decode().strip())
        return response
    except Exception as e:
        return {"error": str(e)}

def main():
    print("=" * 60)
    print("HAL Remote Connection Test")
    print("=" * 60)
    print(f"Connecting to: {HAL_BRIDGE_HOST}:{HAL_BRIDGE_PORT}")
    print()

    # Test 1: Ping
    print("1. Testing ping...")
    resp = send_request({"type": "ping"})
    if resp.get("type") == "ping":
        print("   ✓ Server is responding")
    else:
        print(f"   ✗ Ping failed: {resp}")
        return 1

    # Test 2: List pins
    print("2. Listing pins...")
    resp = send_request({"type": "list_pins"})
    if resp.get("type") == "list_pins":
        pins = resp.get("pins", [])
        print(f"   ✓ Found {len(pins)} pins")
        if pins:
            for pin in pins[:5]:  # Show first 5
                print(f"      - {pin.get('name', 'unknown')}")
    else:
        print(f"   ✗ List pins failed: {resp}")

    # Test 3: List signals
    print("3. Listing signals...")
    resp = send_request({"type": "list_signals"})
    if resp.get("type") == "list_signals":
        signals = resp.get("signals", [])
        print(f"   ✓ Found {len(signals)} signals")
    else:
        print(f"   ✗ List signals failed: {resp}")

    # Test 4: List components
    print("4. Listing components...")
    resp = send_request({"type": "list_components"})
    if resp.get("type") == "list_components":
        components = resp.get("components", [])
        print(f"   ✓ Found {len(components)} components")
    else:
        print(f"   ✗ List components failed: {resp}")

    # Test 5: Try to get a pin (will fail if not exists, but tests connection)
    print("5. Testing get_pin (may fail if pin doesn't exist)...")
    resp = send_request({"type": "get_pin", "name": "motion.enable-pin"})
    if resp.get("type") == "get_pin":
        print(f"   ✓ Got pin value: {resp.get('value')}")
    elif resp.get("type") == "error":
        print(f"   ✓ Server responded (expected error for non-existent pin)")
    else:
        print(f"   ? Response: {resp}")

    print()
    print("=" * 60)
    print("Remote HAL connection test complete!")
    print("=" * 60)
    return 0

if __name__ == "__main__":
    sys.exit(main())
