#!/bin/bash
# Commands to run on pib to rebuild haltune with the protocol fix

cd ~/prog/haltune

# Pull the latest changes (if using git)
# git pull

# Or manually patch src/hal_protocol.zig with the switch statement pattern

# Rebuild
zig build

# Then test with hal_bridge_server running:
# ./zig-out/bin/haltune
