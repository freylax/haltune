#!/bin/bash
# Setup and build haltune on pib
# Run this as: bash setup-on-pib.sh

set -e

echo "=== haltune Setup on pib ==="
echo "Installing Zig if not present..."

if ! command -v zig &> /dev/null; then
    echo "Zig not found. Installing Zig 0.15.2..."
    cd /tmp
    wget https://ziglang.org/download/0.15.2/zig-linux-aarch64-0.15.2.tar.xz
    tar -xf zig-linux-aarch64-0.15.2.tar.xz
    sudo mv zig-linux-aarch64-0.15.2 /opt/zig
    sudo ln -sf /opt/zig/zig /usr/local/bin/zig
    echo "Zig installed: $(zig version)"
fi

echo ""
echo "Checking LinuxCNC HAL development files..."
if [ ! -f "/usr/include/linuxcnc/hal.h" ]; then
    echo "ERROR: LinuxCNC headers not found at /usr/include/linuxcnc/hal.h"
    echo "Install with: sudo apt install linuxcnc-dev"
    exit 1
fi

echo "LinuxCNC headers found"
echo ""
echo "Building haltune..."
zig build
echo ""
echo "Building tests..."
zig build test
echo ""
echo "=== Build Complete ==="
echo ""
echo "Run tests: zig build test"
echo "Run main:  zig build run"
