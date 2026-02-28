#!/bash
# Build script for haltune on local machine (without LinuxCNC)
# This builds haltune for development/testing on machines that don't have LinuxCNC installed

zig build -Dskip-hal-link=true

echo "Build complete. Binary: ./zig-out/bin/haltune"
