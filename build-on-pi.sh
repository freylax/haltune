#!/bin/bash
# Build script for haltune on Raspberry Pi
ssh pib "cd ~/prog/haltune && ~/bin/zig build -Dtarget=aarch64-linux-gnu 2>&1" | tail -100
