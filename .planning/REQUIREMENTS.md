# Requirements: haltune v0.5 View Switching

**Defined:** 2026-02-05
**Core Value:** Make LinuxCNC HAL manipulation and machine setup efficient through an intuitive TUI interface, replacing cryptic halcmd commands with structured workflows for machine configuration and tuning.

## v0.5 Requirements

Requirements for view switching milestone. Replace two-panel layout with alternative view modes.

### Layout

- [ ] **LAY-01**: Tree view and data table displayed alternatively (not simultaneously)
- [ ] **LAY-02**: Active view uses full terminal width
- [ ] **LAY-03**: Tree view is default mode on startup

### View Switching

- [ ] **SWITCH-01**: User can switch between views with 't' key
- [ ] **SWITCH-02**: Mode indicator displayed in UI (e.g., "[Tree]" or "[Table]")
- [ ] **SWITCH-03**: View selection persists during session (not saved to disk)

### Tree View Mode

- [ ] **TREE-01**: Component hierarchy displayed with expand/collapse
- [ ] **TREE-02**: Visibility toggles (*, +, none) for each item
- [ ] **TREE-03**: Cursor indicator (>) shows current position
- [ ] **TREE-04**: In-place editing of selected items
- [ ] **TREE-05**: Search/filter with '/' key
- [ ] **TREE-06**: Backspace collapses current layer

### Data Table Mode

- [ ] **TABLE-01**: Tabular view of currently checked items
- [ ] **TABLE-02**: Columns: Name, Type, Value, Editability
- [ ] **TABLE-03**: Real-time value updates via pubsub
- [ ] **TABLE-04**: In-place editing of editable values
- [ ] **TABLE-05**: Empty state message when no items checked

### Help Text

- [ ] **HELP-01**: Key binding hints displayed at bottom of screen
- [ ] **HELP-02**: Shows 't' for view switching
- [ ] **HELP-03**: Context-sensitive hints (tree view vs table view)

## Future Requirements

Deferred to later milestones.

### Signal Creation UI

- **SIGNAL-01**: Multi-step wizard for creating new signals
- **SIGNAL-02**: Pin selection with type filtering

### Plugins

- **PLUGIN-01**: Velocity tester plugin
- **PLUGIN-02**: Trapvel plugin
- **PLUGIN-03**: PID tuning plugin

### Bookmarks

- **BOOKMARK-01**: Save frequently monitored items
- **BOOKMARK-02**: Persistent storage

## Out of Scope

| Feature | Reason |
|---------|--------|
| Simultaneous two-panel view | User explicitly requested alternative views |
| Saving view mode preference | Session-only persistence is sufficient |
| Customizable layouts | Single-mode design is simpler |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| LAY-01 | Phase 5 | Pending |
| LAY-02 | Phase 5 | Pending |
| LAY-03 | Phase 5 | Pending |
| SWITCH-01 | Phase 5 | Pending |
| SWITCH-02 | Phase 5 | Pending |
| SWITCH-03 | Phase 5 | Pending |
| TREE-01 | Phase 5 | Pending |
| TREE-02 | Phase 5 | Pending |
| TREE-03 | Phase 5 | Pending |
| TREE-04 | Phase 5 | Pending |
| TREE-05 | Phase 5 | Pending |
| TREE-06 | Phase 5 | Pending |
| TABLE-01 | Phase 5 | Pending |
| TABLE-02 | Phase 5 | Pending |
| TABLE-03 | Phase 5 | Pending |
| TABLE-04 | Phase 5 | Pending |
| TABLE-05 | Phase 5 | Pending |
| HELP-01 | Phase 5 | Pending |
| HELP-02 | Phase 5 | Pending |
| HELP-03 | Phase 5 | Pending |

**Coverage:**
- v0.5 requirements: 18 total
- Mapped to phases: 18
- Unmapped: 0 ✓

---
*Requirements defined: 2026-02-05*
*Last updated: 2026-02-05 after v0.5 milestone started*
