# Deployment Settings for haltune

## Build Locations

### Local (development machine)
- Path: `/home/robert/prog/zig/haltune`
- Zig: `/home/robert/prog/apps/zig-x86_64-linux-0.15.2/zig`
- Target: x86_64-linux

### Remote (pib - Raspberry Pi 5)
- Host: `pib` (SSH alias)
- Path: `/home/cnc/prog/haltune`
- Zig: `~/bin/zig` (symlink to `~/prog/app/zig-aarch64-linux-0.15.2/zig`)
- Target: aarch64-linux-gnu
- Binary: `/home/cnc/prog/haltune/zig-out/bin/haltune`

## Build Commands

### Local build
```bash
cd /home/robert/prog/zig/haltune
zig build
```

### Remote build (on pib)
```bash
ssh pib "cd ~/prog/haltune && ~/bin/zig build"
```

### Cross-compile for pib from local (not recommended - missing headers)
```bash
zig build -Dtarget=aarch64-linux-gnu -Dskip-hal-link=true
```

## SSH Access
- User: `cnc`
- Home: `/home/cnc`
- Project: `/home/cnc/prog/haltune`

## Deploy Workflow
1. Commit changes locally
2. `git push`
3. On pib: `cd ~/prog/haltune && git pull && ~/bin/zig build`
