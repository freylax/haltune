# Deploying haltune to pib

## Quick Start

On pib (as cnc user):

```bash
# 1. Create project directory
mkdir -p ~/prog
cd ~/prog

# 2. Clone your repo (adjust URL as needed)
# If you have git access:
git clone <your-repo-url> haltune
cd haltune

# OR copy files from your development machine:
# scp -r /home/robert/prog/zig/haltune cnc@pib:~/prog/

# 3. Run setup script
bash scripts/setup-on-pib.sh
```

## What the Setup Script Does

1. Installs Zig 0.15.2 if not present
2. Checks for LinuxCNC headers
3. Builds haltune
4. Builds tests

## Manual Setup (if script fails)

```bash
# Install Zig manually
cd /tmp
wget https://ziglang.org/download/0.15.2/zig-linux-aarch64-0.15.2.tar.xz
tar -xf zig-linux-aarch64-0.15.2.tar.xz
sudo mv zig-linux-aarch64-0.15.2 /opt/zig
sudo ln -sf /opt/zig/zig /usr/local/bin/zig

# Install LinuxCNC dev headers (if not present)
sudo apt install linuxcnc-dev

# Build
cd ~/prog/haltune
zig build
zig build test
```

## Testing

After build completes:

```bash
# Run unit tests
zig build test

# Run main program
zig build run
```

## What to Verify

Phase 2 features to test:
- [ ] State cache can store pins/signals/params
- [ ] Refresh thread polls HAL at 100ms
- [ ] New items from loaded components are discovered
- [ ] Stale items from unloaded components are removed
- [ ] Multiple threads can read concurrently
- [ ] Pubsub notifications work

## Troubleshooting

**"zig: command not found"** - Zig not installed or not in PATH
**"hal.h: No such file"** - LinuxCNC dev headers missing, install linuxcnc-dev
**"error: unable to find dynamic system library 'hal'"** - libhal.so not found, check LinuxCNC installation
