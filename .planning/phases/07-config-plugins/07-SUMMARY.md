# Phase 07: Configuration Origin & Plugins - Planning Summary

**Created:** 2026-02-13
**Status:** Plans Complete, Ready for Execution

## Overview

Phase 07 extends haltune with two major feature sets:
1. **Configuration Origin Tracking** - Display where HAL values come from (.hal files, .ini files, runtime)
2. **Plugin Foundation** - Extensible architecture for domain-specific workflows

**Note:** Bookmarks feature moved to Phase 08 to prioritize core functionality.

## Plans Created

| Plan | Description | Tasks | Status |
|-------|-------------|--------|--------|
| 07-01 | Integrate Origin Tracking into StateStore | 5 | Pending |
| 07-02 | Display Origin in UI | 4 | Pending |
| 07-03 | Define Plugin API | 3 | Pending |
| 07-04 | Implement Plugin Manager | 4 | Pending |
| 07-05 | Create Example Plugin (Hello) | 4 | Pending |

**Total: 5 plans, 20 tasks**

## Already Implemented (Needs Integration)

The following modules were implemented in earlier work and are included in Phase 07:

- **src/config/hal_parser.zig** (516 lines) - Parse .hal files
- **src/config/ini_parser.zig** (389 lines) - Parse .ini files
- **src/config/origin.zig** (330 lines) - Origin tracking data structures
- **src/root.zig** - CLI with Config struct (-f, -i, --help)

These are integrated into Phase 07 via plans 07-01 and 07-02.

## New Modules to Create

- **src/plugin/interface.zig** - Plugin API definitions
- **src/plugin/manager.zig** - Plugin discovery and lifecycle
- **src/plugin/builtin/hello_plugin.zig** - Example plugin
- **src/plugin/builtin/registry.zig** - Compile-time plugin registry

## Key Features

### Configuration Origin Tracking
- Parse .hal files (setp, net commands) at startup via CLI args
- Parse .ini files (HAL variables) at startup
- Display origin in data table as color-coded column
- Colors: Blue (.hal file), Green (.ini file), Yellow (runtime modified)

### Plugin System
- Compile-time plugin registration (built-in plugins)
- Plugin API with init(), deinit(), render(), handleEvent()
- PluginContext for read-only HAL access
- 'P' key to activate hello plugin
- Escape to deactivate plugin
- Plugin takes over screen when active

## Success Criteria

1. ✅ Configuration files can be loaded via CLI arguments (-f, -i)
2. ✅ Origin column displays in data table with color coding
3. ✅ Plugin API is defined and example plugin exists
4. ✅ Plugin manager can list and activate plugins

## Dependencies

- Phase 01 (FFI Foundation) ✅
- Phase 02 (State Management) ✅
- Phase 03 (TUI Core) ✅
- Phase 04 (Configuration & Editing) ✅
- Phase 05 (View Switching) ✅
- Phase 06 (Live Values & Editing) ✅

## Files Modified/Created

### Already Created (Integration Required)
- `src/config/hal_parser.zig`
- `src/config/ini_parser.zig`
- `src/config/origin.zig`
- `docs/CONFIG_PARSING_IMPLEMENTATION.md`
- `docs/HAL_FILE_FORMATS.md`

### To Be Created in Phase 07
- `src/plugin/interface.zig`
- `src/plugin/manager.zig`
- `src/plugin/builtin/registry.zig`
- `src/plugin/builtin/hello_plugin.zig`

### To Be Modified in Phase 07
- `src/state/cache.zig` - Add origin tracking
- `src/tui/widgets/data_table.zig` - Add origin column
- `src/tui/model.zig` - Add plugins
- `src/tui/layout.zig` - Update help text, key bindings

## Estimated Duration

Based on previous phases (avg 6.5 min per plan):
- **Phase 07 total:** ~30 minutes
- **Per plan:** 2-8 minutes depending on complexity

## Next Steps

1. **Review plans** - Verify all tasks are clear and complete
2. **Execute Plan 07-01** - Integrate origin tracking
3. **Execute Plan 07-02** - Display origin in UI
4. **Execute Plan 07-03** - Define plugin API
5. **Execute Plan 07-04** - Implement plugin manager
6. **Execute Plan 07-05** - Create example plugin
7. **Verification** - Test all features work together

## Notes

- Configuration parsing work was already implemented (commit f2e3ed6)
- Phase 07 formalizes this work into the plan structure
- Plugin system is MVP (compile-time, single active plugin)
- Future enhancements can add dynamic loading, multiple concurrent plugins
- Bookmarks deferred to Phase 08 to focus on core plugin/origin features
