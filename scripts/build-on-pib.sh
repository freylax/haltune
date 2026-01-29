#!/bin/bash
# Build haltune on pib
# Run: ./scripts/build-on-pib.sh

set -e

echo "=== Building haltune ==="
echo "Zig version: $(zig version)"

# Check LinuxCNC headers
if [ ! -f "/usr/include/linuxcnc/hal.h" ]; then
    echo "ERROR: LinuxCNC headers not found"
    echo "Install with: sudo apt install linuxcnc-dev"
    exit 1
fi

echo "Building..."
zig build

echo ""
echo "Building tests..."
zig build test

echo ""
echo "=== Build Complete ==="
echo ""
echo "Run tests:  zig build test"
echo "Run main:   zig build run"
