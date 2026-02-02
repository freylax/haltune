# Deploying haltune to pib

## Prerequisites on pib

- ✓ Zig already installed
- ✓ LinuxCNC installed (with hal.h at /usr/include/linuxcnc/hal.h)

## Quick Deployment

### Option 1: Copy files via scp

From your development machine:

```bash
# Create directory on pib
ssh cnc@pib "mkdir -p ~/prog/haltune"

# Copy source files (excluding .zig-cache)
rsync -av --exclude='.zig-cache' --exclude='zig-cache' \
    /home/robert/prog/zig/haltune/ \
    cnc@pib:~/prog/haltune/

# Build on pib
ssh cnc@pib "cd ~/prog/haltune && bash scripts/build-on-pib.sh"
```

### Option 2: Clone git repo on pib

```bash
ssh cnc@pib
cd ~/prog
git clone <your-repo-url> haltune
cd haltune
bash scripts/build-on-pib.sh
```

### Option 3: Manual copy

```bash
# From dev machine, create a tarball
tar czf haltune-src.tar.gz \
    --exclude='.zig-cache' --exclude='zig-cache' \
    --exclude='zig-out' --exclude='.git' \
    /home/robert/prog/zig/haltune

# Copy to pib
scp haltune-src.tar.gz cnc@pib:~/prog/

# On pib:
ssh cnc@pib
cd ~/prog
tar xzf haltune-src.tar.gz
cd haltune
bash scripts/build-on-pib.sh
```

## What Gets Built

- `zig-out/bin/haltune` - Main executable
- Tests for Phase 2:
  - State cache (thread-safe RwLock)
  - Refresh thread (HAL polling at 100ms)
  - Pubsub notifications
  - Stale entry cleanup

## Testing on pib

After build completes:

```bash
# Run all tests
zig build test

# Run main program
zig build run
```

## What to Verify

Phase 2 features (all should pass):
- [ ] State cache stores pins/signals/params
- [ ] Refresh thread polls HAL at 100ms (configurable)
- [ ] New items from `halcmd loadusr` are discovered
- [ ] Stale items from `halcmd unload` are removed
- [ ] Multiple threads can read concurrently
- [ ] Pubsub notifications trigger callbacks

## Expected Test Results

With LinuxCNC running:
- ✓ State cache tests pass
- ✓ Refresh thread tests pass
- ✓ Pubsub tests pass
- ✓ All Phase 2 requirements verified

Without LinuxCNC:
- Some tests may skip (require running HAL)
- FFI bindings still tested

## Troubleshooting

**"hal.h: No such file"**
```bash
sudo apt install linuxcnc-dev
```

**"error: unable to find dynamic system library 'hal'"**
```bash
# Check LinuxCNC is installed
ldconfig -p | grep hal

# May need to set library path
export LD_LIBRARY_PATH=/usr/lib/linuxcnc:$LD_LIBRARY_PATH
```

**Build works but tests fail**
- Ensure LinuxCNC is running: `halcmd show pin`
- Check permissions: may need to be in `hal` group

**SSH Warning: "Please note that SSH may not work until a valid user has been set up"**
This is a BENIGN warning from Raspberry Pi OS about the deleted default 'pi' user.
The actual user 'cnc' is fully configured with SSH keys and works correctly.
- SSH connection is functional (key-based auth working)
- The warning can be safely ignored
- To suppress the warning, see: http://rptl.io/newuser

## SSH Configuration

The development machine has SSH configured for seamless connections:
- Host: `pib` (resolves to 192.168.2.114)
- User: `cnc`
- Authentication: SSH key-based (no password required)
- Config file: `~/.ssh/config` contains:
  ```
  Host pib
    HostName pib
    User cnc
    Compression yes
  ```

All deployment scripts work correctly. You can use either:
- `ssh pib` (uses SSH config)
- `ssh cnc@pib` (explicit user)
