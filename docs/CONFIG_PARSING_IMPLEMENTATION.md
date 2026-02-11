# Configuration File Parsing Implementation

**Date:** 2026-02-09
**Purpose:** Track origin of HAL settings from .hal and .ini configuration files

## Summary

Implemented configuration file parsing modules for tracking where HAL pin, parameter, and signal values originate. This enables haltune to display configuration origin in the TUI and supports future file write-back functionality.

## Files Created

### src/config/hal_parser.zig

**Purpose:** Parse .hal configuration files and extract HAL commands

**Key Structures:**
```zig
pub const HalCommand = union(enum) {
    setp: struct { name, value, line },
    net: struct { signal_name, pins, line },
    loadrt: struct { component, options, line },
    loadusr: struct { component, options, line },
    addf: struct { function_name, thread_name, line },
    unlinkp: struct { pin_name, line },
    start: struct { line },
    comment: struct { text, line },
};
```

**Key Functions:**
- `parseHalFile()` - Main parser function
- `processLineContinuations()` - Handles backslash line continuation
- `parseSetp()` - Extracts parameter settings
- `parseNet()` - Extracts signal connections
- `parseHalValue()` - Converts value strings to HalValue union

**Features:**
- Line continuation with backslash (\)
- Comments (# and ;)
- Whitespace handling
- Value parsing (bit, float, s32, u32)

### src/config/ini_parser.zig

**Purpose:** Parse .ini configuration files and extract sections/variables

**Key Structures:**
```zig
pub const IniEntry = union(enum) {
    section: struct { name, line },
    key_value: struct { section, key, value, line },
    comment: struct { text, line },
    include: struct { filename, line },
    halfile: struct { filename, line },
    postgui_halfile: struct { filename, line },
};
```

**Key Functions:**
- `parseIniFile()` - Main parser function
- `parseIniLine()` - Routes to appropriate parser
- `parseSection()` - Extracts [SECTION] headers
- `parseKeyValue()` - Extracts KEY = VALUE pairs
- `parseHalfileDirective()` - Extracts HALFILE references

**Features:**
- Section tracking (current section context)
- Comment stripping (# and ;)
- Whitespace handling
- HALFILE and POSTGUI_HALFILE detection

### src/config/origin.zig

**Purpose:** Track origin information for HAL items

**Key Structures:**
```zig
pub const Origin = enum(u8) {
    none,              // No explicit origin (component default)
    hal_file,          // Value set from .hal file (setp command)
    ini_file,          // Value from .ini file variable
    default_value,      // Component default value
    runtime_modified,    // Modified after load via halcmd/haltune
};

pub const ItemOrigin = struct {
    origin: Origin,
    file_path: ?[]const u8,
    line: ?usize,
    ini_section: ?[]const u8,
    ini_variable: ?[]const u8,
};
```

**Key Functions:**
- `ItemOrigin.fromHalFile()` - Create origin from .hal file
- `ItemOrigin.fromIniFile()` - Create origin from .ini file
- `ItemOrigin.format()` - Format origin as display string
- `OriginTracker` - Full tracking store for pins/params/signals

## Command-Line Interface Changes

### src/root.zig

**Added Config structure:**
```zig
pub const Config = struct {
    test_mode: bool = false,
    hal_files: std.ArrayList([]const u8),
    ini_files: std.ArrayList([]const u8),
};
```

**New Arguments:**
- `-f <file.hal>` - Add .hal file for origin tracking
- `-i <file.ini>` - Add .ini file for origin tracking
- `-h, --help` - Show help message
- `--test-mode, -t` - Enable test mode (existing)

**Examples:**
```bash
haltune -f custom.hal
haltune -f core_stepper.hal -f custom.hal -i myconfig.ini
haltune --test-mode -f test.hal
```

### src/tui/app.zig

**Changed function signature:**
```zig
// Before:
pub fn main(test_mode: bool) !void

// After:
pub fn main(config: Config) !void
```

**Added:** Configuration file logging on startup:
```zig
if (config.hal_files.items.len > 0 or config.ini_files.items.len > 0) {
    std.log.info("Loading configuration files:", .{});
    for (config.hal_files.items) |file| {
        std.log.info("  .hal: {s}", .{file});
    }
    // TODO: Parse config files and populate origin tracker
}
```

## Next Steps

### Phase 4a: Integrate Parsers with StateStore
1. Extend `StateStore` with `OriginTracker` member
2. Parse configuration files on startup
3. Map parsed setp commands to parameter origins
4. Map parsed net commands to signal origins

### Phase 4b: UI Extensions
1. Add "Origin" column to data table
2. Show origin file name in tree view
3. Color code origins:
   - Blue: From .hal file
   - Green: From .ini file
   - Yellow: Runtime modified
   - No marker: Default value

### Phase 4c: File Write-Back
1. Implement `updateHalFile()` to write changes back to .hal
2. Implement `updateIniFile()` to write changes back to .ini
3. Use atomic writes (temp file + rename)
4. Add backup before modification

### Phase 4d: Ini Variable Expansion
1. Handle `[SECTION]VARIABLE` syntax in .hal files
2. Cross-reference .ini variables to HAL items
3. Display .ini variable references in origin display

## Testing

All modules pass `zig ast-check`:
- `src/config/hal_parser.zig` ✓
- `src/config/ini_parser.zig` ✓
- `src/config/origin.zig` ✓
- `src/root.zig` ✓
- `src/tui/app.zig` ✓

## Design Decisions

1. **Separate modules** - Created distinct modules for .hal parsing, .ini parsing, and origin tracking to maintain separation of concerns.

2. **Command unions** - Using `union(enum)` for HalCommand and IniEntry allows efficient storage and type-safe pattern matching.

3. **Line number tracking** - All parsed items include source line number for accurate origin display and future write-back.

4. **Const where possible** - Strings are passed as `[]const u8` where the source doesn't need modification, reducing allocations.

5. **Parser validation** - Syntax-only checking (`zig ast-check`) is used since full build requires HAL library linkage.

## References

- Design documented in `docs/HAL_FILE_FORMATS.md`
- Research from `.planning/phases/04-config-editing/04-RESEARCH.md`
- Existing patterns from `src/state/cache.zig`, `src/ffi/errors.zig`
