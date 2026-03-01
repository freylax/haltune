# Plugin Tabbar UI Design

**Date:** 2025-03-01
**Status:** Approved

## Overview

Replace the modal plugin dialog with a persistent tabbar at the top of the TUI. The tabbar contains a "Clear" tab and tabs for each plugin marked with `use = true` in haltune.toml. When a plugin tab is active, the UI splits into left (tree/table) and right (plugin) panels.

## Motivation

The current plugin dialog has usability issues:
- Plugins can be activated but nothing visible happens after closing the dialog
- No clear indication of which plugins are active
- No way to see plugin UI alongside HAL data

## Tabbar Layout

```
┌─────────────────────────────────────────────────────────────┐
│ [Clear] [velocity_control] [trapvel_control]                │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│                    Main Content Area                        │
│                    (varies by tab)                          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Tab appearance:**
- Active tab: highlighted (reverse video)
- Inactive tabs: normal
- Tabs scroll if too many to fit width

## Tab Modes

### Clear Tab (Alt+1)
- Full-screen content area
- Shows TreeView or DataTable (toggle with Ctrl+T)
- No plugins active
- Existing behavior preserved

### Plugin Tab (Alt+2, Alt+3, etc.)
- Split view with two panels:
  - **Left panel**: TreeView or DataTable (toggle with Ctrl+T)
  - **Right panel**: Plugin UI with border and title
- Plugin receives remaining width after left panel
- Plugin title shown in border header

## Configuration

### haltune.toml
```toml
[plugins]
# Which plugins appear as tabs (only these show in tabbar)
enabled = ["velocity_control", "trapvel_control"]

# Per-tab lifecycle (optional, default = "deactivate")
[plugins.velocity_control]
lifecycle = "deactivate"  # "deactivate" | "background" | "always_active"

[plugins.trapvel_control]
lifecycle = "deactivate"
```

### Lifecycle Modes
| Mode | Behavior |
|------|----------|
| `deactivate` | `init()` on enter, `deinit()` on leave (default) |
| `background` | Stays initialized but doesn't render/receive events |
| `always_active` | Continues working even when not visible |

## Key Bindings

| Key | Action |
|-----|--------|
| Alt+1 | Switch to Clear tab |
| Alt+2, Alt+3, ... | Switch to plugin tabs |
| Ctrl+T | Toggle left panel (TreeView/DataTable) |
| Mouse click | Click tabs to switch |

## Architecture

### New Components

1. **TabBar Widget** (`src/tui/widgets/tabbar.zig`)
   - Renders tabs at top of screen
   - Handles tab selection via keyboard/mouse
   - Manages tab state (active/inactive)

2. **TabPanelLayout** (`src/tui/layout/tab_panel.zig`)
   - Layout manager for different tab modes
   - Full view for Clear tab
   - Split view for plugin tabs
   - Handles panel resizing

3. **PluginContainer** (`src/tui/widgets/plugin_container.zig`)
   - Wraps plugin render with border and title
   - Manages plugin lifecycle (init/deinit calls)
   - Handles lifecycle configuration

### Modified Components

1. **Model** (`src/tui/model.zig`)
   - Add `active_tab` state
   - Add `tab_bar` widget reference
   - Modify layout to accommodate tabbar

2. **Plugin Manager** (`src/plugin/manager.zig`)
   - Add lifecycle management per plugin
   - Track which plugins are visible vs active
   - Call init/deinit based on tab switches

3. **TOML Config** (`src/config/toml_config.zig`)
   - Parse `plugins.enabled` array
   - Parse per-plugin `lifecycle` settings

### Data Flow

```
User presses Alt+2
    ↓
TabBar receives event, updates active_tab
    ↓
Model notifies PluginManager of tab change
    ↓
PluginManager calls deinit() on old plugin (if deactivate mode)
    ↓
PluginManager calls init() on new plugin (if deactivate mode)
    ↓
TabPanelLayout requests redraw with new layout
    ↓
PluginContainer wraps new plugin with border/title
```

## Implementation Notes

1. **Tab storage**: Store tabs in array in Model, index maps to Alt+N key
2. **Tab width**: Calculate dynamically based on terminal width
3. **Plugin title**: Use `plugin.name` from Plugin interface
4. **Split ratio**: Default 30/70, stored in Model for persistence
5. **Error handling**: If plugin init fails, show error in status line

## Files to Create

- `src/tui/widgets/tabbar.zig` - TabBar widget
- `src/tui/layout/tab_panel.zig` - TabPanelLayout
- `src/tui/widgets/plugin_container.zig` - PluginContainer wrapper

## Files to Modify

- `src/tui/model.zig` - Add tab state, layout changes
- `src/tui/app.zig` - Integrate TabBar into main widget tree
- `src/plugin/manager.zig` - Add lifecycle management
- `src/config/toml_config.zig` - Add plugins.enabled parsing
- `haltune.toml` - Add plugins section example
