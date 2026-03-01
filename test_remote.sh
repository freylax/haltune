#!/bin/bash
# Build and run remote HAL test on pib

ssh cnc@192.168.2.118 "bash -c '
cd ~/prog/haltune
/home/cnc/prog/app/zig-aarch64-linux-0.15.2/zig build-exe \
  -Mtest=src/test_remote_only.zig \
  -Mbackend=src/hal/backend.zig \
  -Mremote_client=src/remote_hal/client.zig \
  -Mprotocol=src/hal_protocol.zig \
  --dep backend \
  --dep remote_client:backend,protocol \
  --dep protocol:backend \
  -I src/hal \
  -lc \
  -femit-bin=zig-out/bin/test_remote_only \
  src/test_remote_only.zig 2>&1

if [ -f zig-out/bin/test_remote_only ]; then
    echo "=== Running remote HAL test ==="
    timeout 10 ./zig-out/bin/test_remote_only 2>&1 || true
fi
'"
