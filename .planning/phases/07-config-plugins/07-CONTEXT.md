# Phase 07: Configuration Origin & Plugin Foundation - Context

**Phase:** 07 - Configuration Origin & Plugins
**Created:** 2026-02-13
**Status:** In Planning

## Overview

Phase 07 extends haltune with two major feature sets:
1. **Configuration Origin Tracking** - Display where HAL values come from (.hal files, .ini files, runtime)
2. **Plugin Foundation** - Extensible architecture for domain-specific workflows (PID tuning, velocity testing, etc.)

**Note:** Bookmarks feature moved to Phase 08 to prioritize core functionality.

## Dependencies

### Completed Phases Required
- **Phase 01 (FFI Foundation)** - Safe HAL API access ✅
- **Phase 02 (State Management)** - StateStore with pub/sub ✅
- **Phase 03 (TUI Core)** - Vaxis-based TUI framework ✅
- **Phase 04 (Config & Editing)** - Signal creation, config export ✅
- **Phase 05 (View Switching)** - ViewMode enum, single-panel layouts ✅
- **Phase 06 (Live Values & Editing)** - Real-time values, in-place editing ✅

### Code Already Implemented (Needs Integration)
The following modules exist but are not yet integrated into the main TUI:
- `src/config/hal_parser.zig` - Parse .hal files (setp, net, loadrt, etc.)
- `src/config/ini_parser.zig` - Parse .ini files (sections, key-value, HALFILE)
- `src/config/origin.zig` - Origin tracking data structures
- `src/root.zig` - CLI arguments (-f, -i, --help)

## Goals

### Configuration Origin Tracking (Already Parsed, Needs UI Integration)
1. Parse configuration files on startup (via CLI args)
2. Map parsed setp/net commands to HAL item origins
3. Display origin in data table as a column
4. Color code origins for visual distinction

### Plugin Foundation (PLUGIN-01 through PLUGIN-04)
1. Plugin API defined for compile-time plugin registration
2. Plugin manager can discover and list available plugins
3. Plugins can request scoped view (show only components/pins relevant to plugin)
4. Plugin foundation supports tree navigation scoping

## Technical Approach

### Origin Tracking Integration
- Configuration files are parsed at startup (already implemented)
- OriginTracker maps pin/signal/param names to ItemOrigin
- StateStore extended with origin field in cache entries
- DataTable displays origin as column with color coding
- Tree view shows origin indicator next to item names

### Bookmarks Storage
- Bookmarks stored in `~/.config/haltune/bookmarks.json`
- JSON format for easy editing and version control
- Stores: item name, item type (pin/signal/param), date added
- Loaded at startup, saved on add/remove

### Bookmarks UI
- 'b' key to add current selection to bookmarks
- 'B' (Shift+b) or Ctrl+B to open bookmark list
- Bookmark list dialog with navigation
- Enter on bookmark item jumps to that item in tree view

### Plugin Architecture
- Compile-time plugin registration (built-in plugins only for MVP)
- Plugin API provides: init(), render(), handleEvent(), deinit()
- Plugin manager tracks active plugin and routes events
- Plugins can request filtered view via component name prefix

## Success Criteria

1. ✅ Configuration files can be loaded via CLI arguments (-f, -i)
2. ✅ Origin column displays in data table with color coding
3. ✅ User can add items to bookmark list ('b' key)
4. ✅ User can remove items from bookmark list
5. ✅ Bookmarks persist across application restarts
6. ✅ User can open bookmark list and jump to bookmarked items
7. ✅ Plugin API is defined and at least one example plugin exists
8. ✅ Plugin manager can list and activate plugins

## Files Modified/Created

### Already Created (Needs Integration)
- `src/config/hal_parser.zig` - HAL file parser (516 lines)
- `src/config/ini_parser.zig` - INI file parser (389 lines)
- `src/config/origin.zig` - Origin tracking structures (330 lines)
- `src/root.zig` - CLI with Config struct
- `docs/CONFIG_PARSING_IMPLEMENTATION.md` - Implementation docs
- `docs/HAL_FILE_FORMATS.md` - Format reference

### To Be Created in Phase 07
- `src/state/bookmarks.zig` - Bookmark storage and management
- `src/plugin/interface.zig` - Plugin API definitions
- `src/plugin/manager.zig` - Plugin discovery and lifecycle
- `src/plugin/builtin/pid_tuner.zig` - Example PID plugin (stub)
- `~/.config/haltune/bookmarks.json` - Bookmark storage file

### To Be Modified in Phase 07
- `src/state/cache.zig` - Add origin tracking to StateStore
- `src/tui/widgets/data_table.zig` - Add origin column display
- `src/tui/widgets/tree_view.zig` - Add bookmark key bindings
- `src/tui/model.zig` - Add bookmark manager, plugin manager
- `src/tui/layout.zig` - Update help text with new keys

## Plan Breakdown

### Plan 07-01: Integrate Origin Tracking into StateStore
- Extend StateStore with origin tracking
- Parse config files at startup and populate origins
- Map setp commands to parameter origins
- Map net commands to signal origins

### Plan 07-02: Display Origin in UI
- Add origin column to DataTable
- Color code origins (blue=hal_file, green=ini_file, yellow=runtime_modified)
- Update column widths for 5-element layout
- Show origin in tree view as indicator

### Plan 07-03: Define Plugin API
- Define Plugin interface struct
- Define PluginContext for plugin-state communication
- Define PluginEvent for event handling
- Document plugin lifecycle

### Plan 07-04: Implement Plugin Manager
- Create PluginManager struct
- Implement compile-time plugin discovery
- Add plugin activation/deactivation
- Route events to active plugin

### Plan 07-05: Create Example Plugin (Hello)
- Create Hello plugin stub
- Implement plugin lifecycle functions
- Add plugin to builtin registry
- Test plugin activation
