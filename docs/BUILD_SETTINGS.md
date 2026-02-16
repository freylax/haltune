# haltune Build Settings

**Last Updated:** 2026-02-09

## Critical Information

### Target Machine
- **Hostname:** `pib` (Raspberry Pi 5 with LinuxCNC)
- **User:** `cnc` (LinuxCNC user)
- **Purpose:** Development and testing of haltune TUI

### Zig Installation Paths

| Machine | Zig Location | Notes |
|---------|---------------|-------|
| laura (local) | `/usr/local/bin/zig` | Primary development machine |
| pib (remote) | `/home/cnc/prog/app/zig-aarch64-linux-0.15.2/zig` | Symlink: `~/bin/zig -> ../prog/app/zig/...` → Resolves to `/home/cnc/prog/app/zig-aarch64-linux-0.15.2/zig` |
|  | **zig binary:** `/home/cnc/prog/app/zig-aarch64-linux-0.15.2/zig` (verified ELF 64-bit LSB executable, ARM aarch64, version 1) |

### Build Script Behavior

**Location:** `/home/cnc/prog/zig/haltune/build-on-pi.sh`

**What it does:**
1. Changes to project directory: `cd ~/prog/haltune`
2. Calls zig: `~/bin/zig build -Dtarget=aarch64-linux-gnu`
3. Uses `build.zig` configuration (created automatically by zig)

### Build Script Behavior

**Location:** `/home/cnc/prog/zig/haltune/build-on-pi.sh`

**What it does:**
1. Changes to project directory: `cd ~/prog/haltune`
2. Calls zig: `~/bin/zig build -Dtarget=aarch64-linux-gnu`
3. Uses `build.zig` configuration (created automatically by zig)

**How to run on pib:**
```bash
ssh pib "cd ~/prog/haltune && zig build"
```

**How to run on laura (local):**
```bash
cd ~/prog/haltune && zig build
```

### Why Build Works on pib But Not Locally

When `zig build` is executed:
1. Shell is **NOT a login shell** (via SSH to pib)
2. PATH might not include `~/bin`
3. The symlink `~/bin/zig` doesn't resolve correctly
4. Zig binary at versioned path `/home/cnc/prog/app/zig-aarch64-linux-0.15.2/zig` IS found

### Configuration Modules (Created 2026-02-09)

| Module | File | Purpose |
|--------|------|---------|
| `src/config/hal_parser.zig` | Parse .hal files (setp, net, loadrt, etc.) |
| `src/config/ini_parser.zig` | Parse .ini files (sections, key-value pairs) |
| `src/config/origin.zig` | Origin tracking data structures (Origin enum, ItemOrigin, OriginTracker) |
| `src/root.zig` | CLI argument handling (-f, -i, --help, --test-mode) |
| `src/tui/app.zig` | Updated main() to accept Config parameter |
| `src/tui/widgets/data_table.zig` | Added origin field to TableItem, Origin column display |

### Current SSH Usage Rules

**ALWAYS USE:**
```bash
ssh pib "commands here"
```

**NEVER USE:**
```bash
zig build  # This will fail - zig not in PATH on pib
```

### Project Status

- **Config Parsing:** ✅ Complete and syntax-validated
- **Origin Tracking:** ✅ Data structures defined
- **CLI Args:** ✅ -f/-i/--help implemented
- **UI Extension:** ✅ Origin column added to data table
- **Next Phase:** Integrate parsers with StateStore for actual origin tracking

### Notes

- All config modules pass `zig ast-check` validation
- Build script uses zig's automatic `build.zig` file generation
- Path issue: `~/bin/zig` symlink works on pib but only when build script sets up environment properly
