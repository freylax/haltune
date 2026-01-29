# Requirements: haltune

**Defined:** 2025-01-28
**Core Value:** Make LinuxCNC HAL manipulation and machine setup efficient through an intuitive TUI interface, replacing cryptic halcmd commands with structured workflows for machine configuration and tuning.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### FFI Layer (FFI)

Foundation layer - safe Zig bindings to LinuxCNC HAL C API.

- [x] **FFI-01**: Zig can call LinuxCNC HAL C API functions with proper type conversions
- [x] **FFI-02**: FFI layer handles struct alignment correctly on ARM64 (Pi 5 target)
- [x] **FFI-03**: FFI layer manages memory ownership across Zig/C boundary without leaks
- [x] **FFI-04**: HAL mutex lock/unlock is called correctly for all write operations
- [x] **FFI-05**: Compatible with LinuxCNC 2.9.7+ API (no Python2 dependencies)

### State Management (STATE)

Thread-safe caching and synchronization between HAL and TUI.

- [ ] **STATE-01**: Central state store caches current HAL pin/signal/parameter values
- [ ] **STATE-02**: State refresh timer polls HAL at configurable rate (default 100ms)
- [ ] **STATE-03**: State cache handles dynamic HAL changes (components load/unload)
- [ ] **STATE-04**: Thread-safe access prevents race conditions between refresh and TUI reads
- [ ] **STATE-05**: State changes are published to TUI for reactive updates

### HAL Inspector (CORE)

Primary user-facing feature - browse and manipulate HAL components.

- [ ] **CORE-01**: User can view all loaded HAL components in tree structure
- [ ] **CORE-02**: Tree view supports collapse/expand navigation and item selection (checkboxes to add to data table view)
- [ ] **CORE-03**: User can view all HAL pins with type (bit/s32/u32/float), direction (IN/OUT/I/O), and current value
- [ ] **CORE-04**: User can view all HAL signals with type, value, and connected pins
- [ ] **CORE-05**: User can view all HAL parameters with visual distinction between read-only and writable (color or icon indicators)
- [ ] **CORE-06**: Values update in real-time (configurable refresh rate)
- [ ] **CORE-07**: User can edit writable parameter values in data table (setp equivalent); only writable items are editable, visual indicators show editability
- [ ] **CORE-08**: User can create new signals and link pins to them (net equivalent)
- [ ] **CORE-09**: User can search pins/signals/params by name with glob pattern matching
- [ ] **CORE-10**: User can filter view by pin type (bit/s32/u32/float)
- [ ] **CORE-11**: User can save current HAL configuration to file in halcmd-compatible format
- [ ] **CORE-12**: Smart filtering shows all items owned by a specific component (e.g., "show all pins for pid.0")

### Bookmarks (BKMK)

Quick access to frequently monitored HAL items.

- [ ] **BKMK-01**: User can add pins/signals/params to bookmark list
- [ ] **BKMK-02**: User can remove items from bookmark list
- [ ] **BKMK-03**: Bookmark list persists across application restarts
- [ ] **BKMK-04**: User can quickly jump to bookmarked items in main view

### TUI Framework (TUI)

Terminal user interface built on Vaxis.

- [ ] **TUI-01**: Application displays responsive TUI interface using Vaxis framework
- [ ] **TUI-02**: TUI renders correctly on Raspberry Pi 5 terminal (80x24 minimum)
- [ ] **TUI-03**: User can navigate tree view with keyboard (arrow keys, enter, collapse/expand)
- [ ] **TUI-04**: TUI updates display in response to state changes (reactive rendering)
- [ ] **TUI-05**: TUI handles user input for editing values without blocking HAL refresh
- [ ] **TUI-05-1**: Input validation prevents type errors (numeric fields only accept numbers, boolean fields only accept toggle)
- [ ] **TUI-05-2**: Boolean/bit pins: pressing Enter toggles value (True ↔ False) without opening edit dialog; cell shows unsaved color while waiting for HAL refresh
- [ ] **TUI-05-3**: Numeric pins: pressing Enter enables in-place editing in data table cell with validation (only valid numeric input accepted, Enter confirms, Escape cancels); cell shows unsaved color during editing
- [ ] **TUI-05-4**: After edit confirmation (Enter): clear cell immediately and wait for next HAL refresh to display actual value (confirms write succeeded)
- [ ] **TUI-06**: TUI displays error messages for invalid operations (type mismatches, attempting to edit read-only items)
- [ ] **TUI-07**: TUI performs smoothly on Pi 5 hardware (no lag or stutter during refresh)
- [ ] **TUI-08**: Data table uses color or icon indicators to show which items are editable vs read-only

### Plugin Foundation (PLUGIN)

Architecture for future plugin extensibility.

- [ ] **PLUGIN-01**: Plugin API defined for compile-time plugin registration
- [ ] **PLUGIN-02**: Plugin manager can discover and list available plugins
- [ ] **PLUGIN-03**: Plugins can request scoped view (show only components/pins relevant to plugin)
- [ ] **PLUGIN-04**: Plugin foundation supports tree navigation scoping (show/hide components per plugin)

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Velocity Testing Plugin

- **VEL-01**: User can test stepper velocity limits in real-time
- **VEL-02**: Plugin displays velocity feedback during test
- **VEL-03**: Plugin saves discovered velocity limits to configuration

### PID Plugin

- **PID-01**: Plugin auto-discovers all PID components in HAL
- **PID-02**: Plugin presents unified tuning interface per axis
- **PID-03**: User can adjust P, I, D, FF0, FF1, FF2 parameters with immediate feedback
- **PID-04**: Plugin saves tuned parameter sets for different materials/tools

### Trapvel Plugin

- **TRAP-01**: Plugin integrates trapvel.comp component for single-axis testing
- **TRAP-02**: User can execute ramped velocity profile movements
- **TRAP-03**: Plugin displays velocity/position feedback during movement

### Riocore Awareness

- **RIO-01**: Application detects riocore framework presence
- **RIO-02**: Application reads and displays riocore configuration context (view-only)
- **RIO-03**: Application warns when runtime HAL differs from riocore source config
- **RIO-04**: User can trace HAL parameter/signal back to its originating configuration file (.ini, .hal, or riocore config)
- **RIO-05**: Application displays which configuration file defines each HAL item (reverse mapping)

### Advanced Features

- **ADV-01**: Live value graphs (mini halscope in TUI)
- **ADV-02**: History/undo for configuration changes
- **ADV-03**: Diff mode (compare current HAL to saved file)
- **ADV-04**: Configuration validation (warn unconnected pins, type mismatches)

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Full HAL file editing | Becomes a full-blown IDE; use text editor for files, TUI for runtime manipulation only |
| HAL component development | Different domain; use existing tools (comp/comp2, Python) for component dev |
| Persistent background daemon | Adds lifecycle management complexity; user runs TUI when needed |
| G-code integration | Requires motion controller understanding; use AXIS GUI for G-code visualization |
| Real-time waveform graphing | Terminal refresh rates too slow; use halscope GUI for waveform analysis |
| Machine control (jog, MDI) | Duplicates existing GUIs; safety concerns; use existing LinuxCNC GUIs |
| Remote/network operation | Security implications; use SSH to run haltune remotely |
| Configuration wizard | Every machine is different; provide good documentation instead |
| Auto-discovery of machine topology | Heuristics will be wrong; let user explicitly define what's important |
| Editing riocore config | Riocore config is source of truth; edits go through rio-setup to prevent drift |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| FFI-01 | Phase 1 | Complete |
| FFI-02 | Phase 1 | Complete |
| FFI-03 | Phase 1 | Complete |
| FFI-04 | Phase 1 | Complete |
| FFI-05 | Phase 1 | Complete |
| STATE-01 | Phase 2 | Complete |
| STATE-02 | Phase 2 | Complete |
| STATE-03 | Phase 2 | Complete |
| STATE-04 | Phase 2 | Complete |
| STATE-05 | Phase 2 | Complete |
| TUI-01 | Phase 3 | Pending |
| TUI-02 | Phase 3 | Pending |
| TUI-03 | Phase 3 | Pending |
| TUI-04 | Phase 3 | Pending |
| TUI-05 | Phase 3 | Pending |
| TUI-06 | Phase 3 | Pending |
| TUI-07 | Phase 3 | Pending |
| CORE-01 | Phase 3 | Pending |
| CORE-02 | Phase 3 | Pending |
| CORE-03 | Phase 3 | Pending |
| CORE-04 | Phase 3 | Pending |
| CORE-05 | Phase 3 | Pending |
| CORE-06 | Phase 3 | Pending |
| CORE-07 | Phase 4 | Pending |
| CORE-08 | Phase 4 | Pending |
| CORE-09 | Phase 3 | Pending |
| CORE-10 | Phase 3 | Pending |
| CORE-11 | Phase 4 | Pending |
| CORE-12 | Phase 3 | Pending |
| BKMK-01 | Phase 5 | Pending |
| BKMK-02 | Phase 5 | Pending |
| BKMK-03 | Phase 5 | Pending |
| BKMK-04 | Phase 5 | Pending |
| PLUGIN-01 | Phase 5 | Pending |
| PLUGIN-02 | Phase 5 | Pending |
| PLUGIN-03 | Phase 5 | Pending |
| PLUGIN-04 | Phase 5 | Pending |

**Coverage:**
- v1 requirements: 33 total
- Mapped to phases: 33 (100%)
- Unmapped: 0 ✓

**Phase Distribution:**
- Phase 1 (FFI Foundation): 5 requirements
- Phase 2 (State Management): 5 requirements
- Phase 3 (TUI Core): 16 requirements
- Phase 4 (Configuration & Editing): 3 requirements
- Phase 5 (Bookmarks & Plugins): 8 requirements
- Phase 6 (Polish & Optimization): 0 requirements (polish phase)

---
*Requirements defined: 2025-01-28*
*Last updated: 2026-01-28 after roadmap creation*
