# HAL Configuration File Formats Research

**Research Date:** 2026-02-09
**Purpose:** Document .hal and .ini file formats for implementing configuration parsing, editing, and origin tracking in haltune

## Summary

This document summarizes the LinuxCNC HAL configuration file formats (.hal and .ini) to support:
1. Parsing existing configuration files to find origin of HAL settings
2. Displaying configuration origin in the TUI (tree/table view)
3. Editing HAL settings and writing changes back to origin files
4. Understanding the relationship between HAL runtime state and configuration files

## HAL Commands Reference

### Core HAL Commands

| Command | Purpose | Syntax | Example |
|----------|-----------|--------|---------|
| **loadrt** | Load realtime HAL component | `loadrt <component> <options>` | `loadrt or2 count=1` |
| **loadusr** | Load userspace HAL component | `loadusr <component> <options>` | `loadusr halui` |
| **addf** | Add function to thread | `addf <function> <thread>` | `addf siggen.0.update servo-thread` |
| **net** | Create signal connection (replaces newsig/linkps/linksp) | `net <sig-name> <pin1> <arrow> <pin2>...` | `net X-vel stepgen.0.out => parport.0.pin-02-out` |
| **setp** | Set parameter/pin value | `setp <pin/param-name> <value>` | `setp stepgen.0.position-scale 10000` |
| **sets** | Set signal value | `sets <signal-name> <value>` | `sets mysignal 1` |
| **unlinkp** | Unlink pin from signal | `unlinkp <pin-name>` | `unlinkp parport.0.pin-02-out` |
| **save** | Save current HAL configuration to stdout | `save` or `save <filename>` | `halcmd: save all saved.hal` |
| **start** | Start realtime threads | `start` | `start` |

### Direction Arrows (for net command)

The `net` command supports optional direction arrows for readability:

| Arrow | Meaning | Usage | Example |
|-------|---------|-------|---------|
| `=>` | Signal flows TO the pin (source) | `net signal-name source-pin => dest-pin` |
| `<=` | Signal flows FROM the pin (sink/IN) | `net signal-name dest-pin <= source-pin` |
| `<=>` | Bidirectional signal flow | `net signal-name pin1 <=> pin2` |

**Important:** These arrows are purely for readability - they do NOT affect HAL signal routing. The actual direction is determined by pin types (IN/OUT/IO).

## .hal File Format

### Structure

A .hal file is a text file containing HAL commands executed sequentially:

```hal
# My HAL configuration file
# Comments start with # or ;

# Load realtime components
loadrt threads name1=test-thread period1=1000000
loadrt siggen
loadrt stepgen step_type=0,0 ctrl_type=v,v

# Load userspace components
loadusr -Wn halui

# Add functions to threads
addf siggen.0.update slow
addf stepgen.update-freq slow
addf stepgen.make-pulses fast

# Create signals and connect pins
net X-vel siggen.0.cosine => stepgen.0.velocity-cmd
net Y-vel siggen.0.sine => stepgen.1.velocity-cmd

# Set parameter values
setp stepgen.0.position-scale 10000
setp stepgen.1.position-scale 10000
setp stepgen.0.enable 1
setp stepgen.1.enable 1

# Start realtime execution
start
```

### Key Patterns

1. **Comments:** Lines starting with `#` or `;` are ignored
2. **Line continuation:** Commands can span multiple lines using backslash `\`
3. **Execution order:** Commands execute top-to-bottom; order matters (e.g., loadrt before net)
4. **net creates signals:** If signal doesn't exist, `net` creates it automatically
5. **Obsolete commands:** `newsig`, `linkps`, `linksp` are deprecated - use `net` instead

## .ini File Format

### Structure

An .ini file uses **sections**, **variables**, and **comments**:

```ini
# This is a comment line
; This is also a comment

[EMC]
VERSION = 1.1
MACHINE = My Controller
DEBUG = 0

[DISPLAY]
DISPLAY = axis
POSITION_OFFSET = RELATIVE
POSITION_FEEDBACK = COMMANDED
CYCLE_TIME = 100

[HAL]
HALFILE = core_stepper.hal
HALFILE = custom.hal
POSTGUI_HALFILE = custom_postgui.hal

[TRAJ]
COORDINATES = X Y Z
LINEAR_UNITS = mm
DEFAULT_LINEAR_VELOCITY = 0.0167
MAX_LINEAR_VELOCITY = 1.0
MIN_VELOCITY = 0.01
INCREMENTS = 1 mm, .5 in

[JOINT_0]
TYPE = LINEAR
SCALE = 16000
MAX_VELOCITY = 1.2
MAX_ACCELERATION = 20.0
FERROR = 1.0
MIN_FERROR = 0.010

[SPINDLE_0]
DEFAULT_SPINDLE_SPEED = 1000
MAX_FORWARD_VELOCITY = 20000
MIN_FORWARD_VELOCITY = 3000

[AXIS_0]
TYPE = LINEAR
MAX_VELOCITY = 1.2
MAX_ACCELERATION = 20.0
MIN_LIMIT = -100.0
MAX_LIMIT = 100.0
HOME = 0
HOME_OFFSET = 0.0
HOME_SEARCH_VEL = 0.0

[KINS]
JOINTS = 3
KINEMATICS = trivkins

[HAL_0]
# Custom section for HAL
DEBUG = 0
```

### Key Concepts

1. **Comments:** `;` or `#` at start of line
2. **Sections:** `[SECTION_NAME]` encloses related variables
3. **Variables:** `KEY = value` - spaces around `=` are part of value
4. **Boolean values:** `TRUE`, `YES`, `1` = true; `FALSE`, `NO`, `0` = false (case-insensitive)
5. **Custom sections:** Can create arbitrary sections (e.g., `[PROBE]`, `[HAL_0]`)
6. **Include files:** `#INCLUDE filename` to include another file

### How .ini References .hal Files

The `[HAL]` section specifies .hal files to execute:

```ini
[HAL]
HALFILE = core_stepper.hal    # Executed first
HALFILE = custom.hal            # Executed second
POSTGUI_HALFILE = custom_postgui.hal  # Executed after GUI loads
```

HAL files are found via:
1. Same directory as .ini file
2. System library path
3. Absolute path (starts with `/`)
4. User home path (starts with `~`)

### Using .ini Variables in .hal Files

HAL commands can reference .ini variables using bracket syntax:

```hal
# Reference ini variable in HAL command
setp stepgen.0.position-scale [JOINT_0]SCALE
setp stepgen.1.position-scale [JOINT_1]SCALE

# Reference in G-code using #<ini[section]variable> syntax
G91
G38.2 Z#<[HAL_0]Z_FEEDRATE> F#<[HAL_0]Z_OFFSET>
```

## Relationship Between HAL Runtime and Configuration Files

### Source of Truth

**The HAL runtime system is the primary source of truth.**

Configuration files (.hal, .ini) are executed at LinuxCNC startup to:
1. Load HAL components
2. Create signals and connect pins
3. Set initial parameter values

Once loaded, the HAL system contains the actual state. Changes made via haltune or halcmd modify the live HAL state.

### The Challenge for haltune

When haltune displays a HAL pin/parameter, it shows:
1. The **current live value** from HAL shared memory
2. The **origin** of that value (which file it came from)

**Example scenario:**
- `stepgen.0.maxvel` parameter exists in HAL with value `1.2`
- This value may have been set from:
  - Default value in component code
  - A `setp` command in `custom.hal`
  - Manual halcmd at runtime
  - Modified via haltune (not yet implemented)

**To track origin:** haltune must:
1. Parse .hal and .ini files
2. Map HAL items (pins, params, signals) to their origin
3. Display origin metadata in the UI
4. When editing, update the original file

## Origin Tracking Design

### Recommended Data Structure

```zig
const std = @import("std");

pub const Origin = enum {
    none,
    hal_file,      // From .hal file
    ini_file,      // From .ini file
    default_value,  // Component default
    runtime_modified, // Changed via halcmd/haltune after load
};

pub const HalItem = struct {
    name: []const u8,

    // Current runtime state
    value: HalValue,
    type: HalType,
    direction: HalDirection,

    // Origin tracking
    origin: Origin,
    origin_file: ?[]const u8,  // Which file
    origin_line: ?usize,          // Line number in file

    // For .ini items: section and variable names
    ini_section: ?[]const u8,
    ini_variable: ?[]const u8,
};

pub const ConfigMapping = struct {
    allocator: std.mem.Allocator,

    // Map HAL item names to their configuration origin
    hal_items: StringHashMap(*HalItem),

    // Map .ini variables to HAL items that use them
    // Example: [JOINT_0]SCALE -> stepgen.0.position-scale
    ini_to_hal: StringHashMap([]const u8),

    // Loaded files for reference
    hal_files: ArrayList([]const u8),
    ini_files: ArrayList([]const u8),
};

pub fn parseHalFile(allocator: std.mem.Allocator, content: []const u8) !ConfigMapping {
    // Parse .hal file line by line
    // Track origin_file and origin_line for each item
    // Handle loadrt, loadusr, net, setp commands
    // Expand #INCLUDE directives
}

pub fn parseIniFile(allocator: std.mem.Allocator, content: []const u8) !ConfigMapping {
    // Parse .ini file
    // Extract [SECTION] and KEY = VALUE pairs
    // Track which section/variable each item came from
}
```

### Display Strategy

In tree view, show origin with visual indicators:

```
stepgen.0.maxvel ── 1.2 [core_stepper.hal:42]
├─ stepgen.0.position-scale (RW) = 10000 [custom.hal:15]
```

Color coding:
- **Default values** - no marker
- **From .hal file** - blue
- **From .ini file** - green
- **Runtime modified** - yellow (with reset option)

## File Write-Back Strategy

### When User Edits a Value

1. **Determine target file:**
   - If `origin == .hal_file`, write to the .hal file
   - If `origin == .ini_file`, update the .ini variable
   - If `origin == none`, create new entry in custom.hal

2. **Preserve file structure:**
   - Maintain comments and whitespace
   - Update existing lines rather than appending
   - Handle multi-line continuations correctly

3. **Parameter vs Pin:**
   - Pins connected to signals cannot use `setp`
   - Only disconnected pins or parameters can be set
   - Check pin connection state via HAL FFI

### Example Write-Back

```zig
// Updating a .hal file
fn updateHalFile(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    item_name: []const u8,
    new_value: HalValue,
) !void {
    var file = try std.fs.cwd().open(file_path, .{ .read = true });
    defer file.close();

    // Read all lines
    var buffer = std.ArrayList(u8).init(allocator);
    const reader = file.reader();

    while (try reader.readUntilDelimiterOrEof(&buffer, '\n')) {
        // Check if this line sets our item
        if (std.mem.startsWith(u8, buffer.items, "setp ")) {
            const start = std.mem.indexOf(u8, buffer.items, item_name);
            if (start != -1) {
                // Found the line - update it
                const new_line = try std.fmt.allocPrint(
                    allocator,
                    "setp {s} {s}",
                    .{item_name, new_value}
                );

                // Replace the line
                try buffer.replaceRange(start, buffer.items.len, new_line);
            }
        }
    }

    // Write back modified content
    try file.writeAll(buffer.items);
}
```

## Implementation Tasks

1. **File Argument Parsing**
   - Add `-f <file.hal>` command line argument to load specific .hal file
   - Parse command line: `haltune -f file1.hal -f file2.hal`

2. **Origin Mapping**
   - During discovery, track which file each pin/param/signal came from
   - For .ini values, track section and variable name
   - Cross-reference: map .ini `[SECTION]VAR` to HAL items that reference them

3. **UI Extensions**
   - Add "Origin" column to data table
   - Show origin file name in tree view
   - Mark runtime-modified values distinctly
   - Add "Revert" and "Update File" actions

4. **Safe Writing**
   - Write to temporary file, then atomic rename
   - Backup original before modifications
   - Validate HAL syntax before writing

5. **HAL Command Generation**
   - When user creates new signal/pin connection, generate `net` command
   - When user sets parameter value, generate `setp` command
   - Handle direction arrows for readability

## Sources

### Official LinuxCNC Documentation

- [HAL Basics](https://www.linuxcnc.org/docs/html/hal/basic-hal.html) - Core HAL commands reference
- [HAL Tutorial](https://www.linuxcnc.org/docs/html/hal/tutorial.html) - Complete HAL usage examples
- [INI Configuration](https://www.linuxcnc.org/docs/html/config/ini-config.html) - .ini file format reference
- [Configuration Intro](https://www.linuxcnc.org/docs/html/config/intro.html) - Configuration overview

### Key Insights

1. **HAL files are command scripts** - They are executed sequentially at startup
2. **.ini files are declarative** - They define variables and references
3. **The "net" command is primary** - It creates signals AND connects pins
4. **Direction arrows are cosmetic** - They don't affect routing, only readability
5. **setp vs sets** - `setp` is for pins/params, `sets` is for signal values

## Notes for haltune Implementation

- Start simple: Parse .hal files for display origin only
- Don't initially support writing back to .ini (complex with variable expansion)
- Focus on .hal file editing first (most common use case)
- The HAL runtime is always source of truth - files are just initialization
- Track "runtime modified" flag separately from "from file" origin
