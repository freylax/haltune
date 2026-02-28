#!/usr/bin/bash
# Build script for haltune on local machine (without LinuxCNC)
# This builds haltune for development/testing on machines that don't have LinuxCNC installed

# Build for host architecture (x86_64-linux-gnu) instead of default aarch64
zig build -Dskip-hal-link=true -Dtarget=x86_64-linux-gnu

echo "Build complete. Binary: ./zig-out/bin/haltune"
