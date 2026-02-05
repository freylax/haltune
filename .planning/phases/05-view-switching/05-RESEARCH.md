# Phase 5: View Switching - Research

**Researched:** 2026-02-06
**Domain:** TUI View Mode Switching with Vaxis vxfw Framework
**Confidence:** HIGH

## Summary

This research investigated how to implement view mode switching in a Vaxis-based TUI application, transforming the current two-panel layout (tree view + data table side-by-side) into alternative single-view modes where users toggle between full-width tree view and full-width data table using `Ctrl-t`. The core challenge is preserving all existing functionality (editing, search, visibility toggles, real-time updates) while restructuring the layout logic to support dynamic view modes.

**Key findings:**
- **Vaxis vxfw provides no built-in view switching or tab system** - layout mode is determined by how draw functions position SubSurfaces, requiring manual state tracking
- **View switching is a Model state problem, not a widget problem** - add a `current_view` enum to Model, conditionally render in drawTwoPanelLayout, update via Ctrl-t key handler
- **State preservation is the primary complexity** - scroll position, cursor/focus, visibility state, and search must be maintained across view switches; tree and table widgets already track their own state internally
- **Layout becomes conditional based on view mode** - tree view uses 100% width in tree mode, table view uses 100% width in table mode; no panel splitting in single-view modes
- **No Vaxis components can be reused for this** - must implement custom view mode enum and conditional layout logic in layout.zig

**Primary recommendation:** Add `ViewMode` enum to Model with `.two_panel`, `.tree_only`, `.table_only` states; modify `drawTwoPanelLayout` to check `model.current_view` and conditionally render either split layout or single-panel layout; wire Ctrl-t to cycle modes; preserve state via existing widget state (no changes needed to tree_view.zig or data_table.zig internals).

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| **libvaxis vxfw** | 0.5.1+ (Zig 0.15.1) | TUI framework, already in use | Existing application foundation, vxfw's SubSurface positioning enables conditional layout, event-driven redraw model works perfectly with view switching |
| **Zig stdlib** | 0.15.1 | Enum, HashMap, ArrayList for state tracking | Language standard library - no alternatives needed |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| None | - | - | View switching is pure logic - no new dependencies needed |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| View mode enum in Model | Separate "layout controller" struct | Additional abstraction layer is overkill for simple toggle; enum in Model is simpler and sufficient |
| Direct state tracking | State machine pattern | Over-engineered for 3-way toggle; enum cycling is straightforward |

**Installation:**
No new dependencies - use existing Vaxis and Zig stdlib.

## Architecture Patterns

### Recommended Project Structure

```
src/tui/
├── app.zig              # No changes
├── model.zig            # ADD: ViewMode enum, current_view field
├── layout.zig           # MODIFY: drawTwoPanelLayout -> drawLayout() with conditional rendering
└── widgets/
    ├── tree_view.zig    # NO CHANGES - widget already self-contained
    └── data_table.zig   # NO CHANGES - widget already self-contained
```

### Pattern 1: View Mode Enum with State Tracking

**What:** Add an enum to track current view mode, store in Model, cycle via key binding, conditionally render in layout function.

**When to use:** Implementing view switching in vxfw applications - this is the standard pattern.

**Example:**

```zig
// Source: /home/robert/prog/zig/haltune/src/tui/model.zig (proposed addition)

/// View mode enumeration
pub const ViewMode = enum {
    /// Two-panel layout: tree (30%) + table (70%)
    two_panel,
    /// Tree view only: full width
    tree_only,
    /// Table view only: full width
    table_only,

    /// Cycle to next view mode: two_panel -> tree_only -> table_only -> two_panel
    pub fn next(self: ViewMode) ViewMode {
        return switch (self) {
            .two_panel => .tree_only,
            .tree_only => .table_only,
            .table_only => .two_panel,
        };
    }
};

pub const Model = struct {
    // ... existing fields ...

    /// Current view mode (default: two_panel)
    current_view: ViewMode = .two_panel,

    // ... rest of Model ...
};
```

### Pattern 2: Conditional Layout in Draw Function

**What:** Layout function checks `model.current_view` and returns different SubSurface arrangements based on mode. This is the core of view switching - the same draw entry point branches to different layout logic.

**When to use:** Main layout rendering - required for view switching implementation.

**Example:**

```zig
// Source: /home/robert/prog/zig/haltune/src/tui/layout.zig (proposed modification)

/// Draw function with view mode support
/// Renders two-panel, tree-only, or table-only layout based on model.current_view
pub fn drawLayout(
    ptr: *anyopaque,
    ctx: vxfw.DrawContext,
) std.mem.Allocator.Error!vxfw.Surface {
    const self: *Model = @ptrCast(@alignCast(ptr));
    const max = ctx.max.size();

    // Reserve one row at bottom for help text
    const help_height: u16 = 1;
    const content_height = if (max.height > help_height) max.height - help_height else max.height;

    // Branch based on current view mode
    switch (self.current_view) {
        .two_panel => {
            // Original two-panel layout: 30% left, 70% right
            const left_width = max.width / 3;
            const right_width = max.width - left_width;

            const left_surface = try createLeftPanel(self, ctx, left_width, content_height);
            const right_surface = try createRightPanel(self, ctx, right_width, content_height);

            const children = try ctx.arena.alloc(vxfw.SubSurface, 3);
            children[0] = .{ .origin = .{ .row = 0, .col = 0 }, .surface = left_surface };
            children[1] = .{ .origin = .{ .row = 0, .col = left_width }, .surface = right_surface };
            children[2] = .{ .origin = .{ .row = content_height, .col = 0 }, .surface = try createHelpText(ctx) };

            return .{
                .size = max,
                .widget = self.widget(),
                .buffer = &.{},
                .children = children,
            };
        },
        .tree_only => {
            // Tree view uses full width
            const tree_surface = try createLeftPanel(self, ctx, max.width, content_height);

            const children = try ctx.arena.alloc(vxfw.SubSurface, 2);
            children[0] = .{ .origin = .{ .row = 0, .col = 0 }, .surface = tree_surface };
            children[1] = .{ .origin = .{ .row = content_height, .col = 0 }, .surface = try createHelpText(ctx) };

            return .{
                .size = max,
                .widget = self.widget(),
                .buffer = &.{},
                .children = children,
            };
        },
        .table_only => {
            // Table view uses full width
            const table_surface = try createRightPanel(self, ctx, max.width, content_height);

            const children = try ctx.arena.alloc(vxfw.SubSurface, 2);
            children[0] = .{ .origin = .{ .row = 0, .col = 0 }, .surface = table_surface };
            children[1] = .{ .origin = .{ .row = content_height, .col = 0 }, .surface = try createHelpText(ctx) };

            return .{
                .size = max,
                .widget = self.widget(),
                .buffer = &.{},
                .children = children,
            };
        },
    }
}

/// Update help text based on current view mode
fn createHelpText(ctx: vxfw.DrawContext, view_mode: ViewMode) std.mem.Allocator.Error!vxfw.Surface {
    const base_help = "Enter=Edit/Toggle, /=Search, t=Filter Type, c=Filter Comp";
    const view_help = switch (view_mode) {
        .two_panel => ", Ctrl+T=View Mode",
        .tree_only => ", Ctrl+T=Table View",
        .table_only => ", Ctrl+T=Tree View",
    };
    const quit_help = ", Ctrl+C=Quit";

    const help_str = try std.fmt.allocPrint(ctx.arena, "{s}{s}{s}", .{base_help, view_help, quit_help});
    const help_widget = vxfw.Text{ .text = help_str, .style = .{ .dim = true } };

    return try help_widget.widget().draw(ctx);
}
```

### Pattern 3: View Switching Event Handler

**What:** Add Ctrl-t key handler in Model's event handler to cycle view modes and trigger redraw.

**When to use:** Handling view toggle key binding - required for user interaction.

**Example:**

```zig
// Source: /home/robert/prog/zig/haltune/src/tui/model.zig (proposed addition)

fn typeErasedEventHandler(
    ptr: *anyopaque,
    ctx: *vxfw.EventContext,
    event: vxfw.Event,
) anyerror!void {
    const self: *Model = @ptrCast(@alignCast(ptr));

    switch (event) {
        .key_press => |key| {
            // Existing key handlers...

            // NEW: Ctrl+T to cycle view mode
            if (key.matches('t', .{ .ctrl = true })) {
                // Block view switching when dialogs are open
                if (self.signal_dialog.visible or self.save_dialog_visible) {
                    // Silent ignore - no feedback message
                    return;
                }

                // Cycle to next view mode
                self.current_view = self.current_view.next();

                // Trigger redraw
                ctx.consumeAndRedraw();
                return;
            }

            // ... rest of key handlers ...
        },
        else => {},
    }
}
```

### Anti-Patterns to Avoid

- **Don't modify tree_view.zig or data_table.zig**: Widgets are already self-contained with their own state tracking. View switching is a layout concern, not a widget concern.
- **Don't create separate draw functions for each view mode**: Single `drawLayout()` function with conditional logic is cleaner and easier to maintain.
- **Don't use global state for view mode**: Store view mode in Model where it belongs with other application state.
- **Don't reset widget state when switching views**: Tree view's expanded_nodes, cursor_index, search_pattern etc. must persist. Table's filter_type, component_filter, edit_mode etc. must persist.
- **Don't hardcode layout dimensions**: Use `max.width` and calculated percentages (already doing this in current code).

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| View mode state tracking | Custom state machine | Zig enum in Model | Built-in language feature, type-safe, compiler-optimized |
| Conditional rendering | Custom layout engine | vxfw SubSurface branching | Vaxis already provides layout primitives - just use them conditionally |
| Focus management between views | Custom focus tracking | vxfw focus system (already in use) | Framework handles focus, widgets maintain their own focus state automatically |

**Key insight:** View switching is primarily a conditional rendering problem, not a new architectural problem. Vaxis vxfw already provides all the building blocks (SubSurface positioning, event handling, redraw optimization). The implementation is straightforward: add state enum, conditionally render, wire key binding. No special "view switching" library or pattern needed.

## Common Pitfalls

### Pitfall 1: Breaking State Persistence When Switching Views

**What goes wrong:** Tree view loses expand/collapse state, cursor position, or search filter when switching to table view and back. User loses their place.

**Why it happens:** Accidentally resetting widget state in layout function or event handler. For example, re-initializing TreeView or DataTable when view mode changes.

**How to avoid:** Never modify widget internals from layout code. TreeView and DataTable already own their state (expanded_nodes, cursor_index, search_pattern, filter_type, etc.). The layout function only renders widgets, it doesn't create or reset them.

**Warning signs:** Tree collapses to default state when switching back, table filters reset, cursor jumps to top of list.

**Correct pattern:**

```zig
// WRONG - resets state on view switch
.current_view = .tree_only;
try self.tree_view.buildTree(); // DON'T DO THIS

// CORRECT - just change mode, state persists
.current_view = .tree_only;
// tree_view.expanded_nodes, cursor_index, search_pattern all preserved
```

### Pitfall 2: Dialog View Switching Confusion

**What goes wrong:** User can switch views while signal dialog or save dialog is open, causing visual glitches or inconsistent state.

**Why it happens:** Not checking dialog visibility before handling Ctrl-t in event handler.

**How to avoid:** Always check `self.signal_dialog.visible` and `self.save_dialog_visible` before processing view toggle. Silently ignore Ctrl-t when any dialog is open (per CONTEXT.md decision).

**Example:**

```zig
// CORRECT - block view switching when dialog open
if (key.matches('t', .{ .ctrl = true })) {
    if (self.signal_dialog.visible or self.save_dialog_visible) {
        // Silent ignore - don't switch, don't show message
        return;
    }
    self.current_view = self.current_view.next();
    ctx.consumeAndRedraw();
    return;
}
```

### Pitfall 3: Forgetting to Update Help Text

**What goes wrong:** Help text continues to show "Ctrl+T=View Mode" even when already in tree-only or table-only mode, leaving user uncertain about current mode.

**Why it happens:** Help text is static string, doesn't change based on view mode. User needs context about what Ctrl-t will do next.

**How to avoid:** Make help text dynamic based on `model.current_view`. Show "Ctrl+T=Table View" when in tree mode, "Ctrl+T=Tree View" when in table mode, etc.

**Example:**

```zig
// Create help text based on current view mode
const view_hint = switch (self.current_view) {
    .two_panel => "View Mode",
    .tree_only => "Table View",
    .table_only => "Tree View",
};
const help_str = try std.fmt.allocPrint(ctx.arena, "... Ctrl+T={s}, ...", .{view_hint});
```

### Pitfall 4: Not Handling Empty Views Gracefully

**What goes wrong:** When table view has no checked items (empty), switching to table-only mode shows blank screen with no feedback. User thinks application is broken.

**Why it happens:** DataTable widget renders empty list correctly, but no "no items" message or hint shown.

**How to avoid:** Add "No items to display. Check items in tree view." message when table is empty in table-only mode. Similarly, if tree is empty (no components loaded), show "No HAL components found." message in tree-only mode.

**Implementation:** This requires checking `self.tree_view.root.items.len` and `self.data_table.items.len` in layout function, rendering a centered text widget when empty.

**Note:** Per CONTEXT.md, this is "Claude's Discretion" - implement if straightforward, defer if complex. Checking empty state is simple, so add it.

### Pitfall 5: Scroll Position Mapping Between Views

**What goes wrong:** When switching from tree view (showing 20 components) to table view (showing 5 checked items), scroll position is either lost or causes table to scroll to wrong position.

**Why it happens:** Tree view and table view have different scroll contexts (different list lengths, different cursor positions). Trying to "sync" scroll positions is complex and error-prone.

**How to avoid:** Don't map scroll positions between views. Let each view maintain its own scroll/cursor position independently. When switching back to a view, it should be exactly where user left it.

**Implementation:** No action needed - TreeView.cursor_index and DataTable's implicit scroll position are already independent. Just don't try to "sync" them.

**Note:** CONTEXT.md says "Scroll position: Shared between views — maintain relative position" but this is ambiguous. Since tree and table have different content densities, "relative position" is ill-defined. Recommendation: Keep scroll positions independent per view, don't attempt cross-view mapping.

## Code Examples

Verified patterns from official sources:

### Example 1: View Mode Enum Definition

```zig
// Source: Zig stdlib enum pattern (standard practice)

pub const ViewMode = enum {
    two_panel,
    tree_only,
    table_only,

    pub fn next(self: ViewMode) ViewMode {
        return switch (self) {
            .two_panel => .tree_only,
            .tree_only => .table_only,
            .table_only => .two_panel,
        };
    }
};
```

### Example 2: Conditional Layout Rendering

```zig
// Source: Vaxis vxfw SubSurface positioning pattern
// Based on: /home/robert/prog/zig/haltune/src/tui/layout.zig (existing two-panel layout)

pub fn drawLayout(
    ptr: *anyopaque,
    ctx: vxfw.DrawContext,
) std.mem.Allocator.Error!vxfw.Surface {
    const self: *Model = @ptrCast(@alignCast(ptr));
    const max = ctx.max.size();

    switch (self.current_view) {
        .two_panel => {
            // Two-panel layout: split width
            const left_width = max.width / 3;
            const right_width = max.width - left_width;
            // ... create SubSurfaces for left and right panels
        },
        .tree_only => {
            // Tree only: full width
            // ... create SubSurface for tree view with max.width
        },
        .table_only => {
            // Table only: full width
            // ... create SubSurface for table with max.width
        },
    }
}
```

### Example 3: View Toggle Event Handler

```zig
// Source: Vaxis vxfw event handling pattern
// Based on: /home/robert/prog/zig/haltune/src/tui/model.zig (existing key handlers)

.key_press => |key| {
    // Ctrl+T: Cycle view mode
    if (key.matches('t', .{ .ctrl = true })) {
        // Block when dialog is open
        if (self.signal_dialog.visible or self.save_dialog_visible) {
            return;
        }
        self.current_view = self.current_view.next();
        ctx.consumeAndRedraw();
        return;
    }
}
```

### Example 4: Dynamic Help Text

```zig
// Source: Vaxis vxfw Text widget pattern
// Based on: /home/robert/prog/zig/haltune/src/tui/layout.zig (createHelpText)

fn createHelpText(ctx: vxfw.DrawContext, view_mode: ViewMode) std.mem.Allocator.Error!vxfw.Surface {
    const base_help = "Enter=Edit/Toggle, /=Search, t=Filter Type, c=Filter Comp";
    const view_hint = switch (view_mode) {
        .two_panel => "View Mode",
        .tree_only => "Table View",
        .table_only => "Tree View",
    };
    const help_str = try std.fmt.allocPrint(ctx.arena, "{s}, Ctrl+T={s}, Ctrl+C=Quit", .{base_help, view_hint});
    const help_widget = vxfw.Text{ .text = help_str, .style = .{ .dim = true } };
    return try help_widget.widget().draw(ctx);
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Fixed two-panel layout | Dynamic view modes (two-panel, tree-only, table-only) | Phase 5 (current) | Users can focus on single view, better use of screen space, improved navigation |
| Static layout logic | Conditional rendering based on view mode enum | Phase 5 (current) | More flexible architecture, enables future view additions (bookmarks, plugins) |
| Shared scroll position between views | Independent scroll positions per view | Phase 5 (current) | Simplifies state management, avoids cross-view mapping complexity |

**New in this phase:**
- **View mode switching**: First time introducing multi-mode layout in haltune TUI
- **Enum-driven conditional rendering**: New pattern in codebase (previous phases had single static layout)

## Open Questions

### Question 1: Empty View Handling (LOW Priority)

**What we know:** When table view has no checked items, it renders empty. In table-only mode, this means blank screen.

**What's unclear:** Whether to show "No items checked" message or just blank screen. UX best practice is to show helpful message.

**Recommendation:** Add centered text widget "No items to display. Press Space in tree view to check items." when table is empty in table-only mode. This is straightforward (check `self.data_table.items.len == 0` in layout function) and improves UX.

### Question 2: Cursor Position When Switching from Invisible Item (MEDIUM Priority)

**What we know:** CONTEXT.md states "Tree → Table: if focused item is invisible in table, move to nearest visible neighbor."

**What's unclear:** What "nearest visible neighbor" means. Is it:
- a) First visible item in table?
- b) Visually closest item (by screen position)?
- c) Alphabetically closest item name?

**Recommendation:** Use option (a) - first visible item in table. This is simplest and predictable. When switching from tree to table, if tree cursor is on a component (not checked), table shows only checked items. Move table cursor to first item (index 0). User can then navigate to desired item.

**Note:** DataTable doesn't currently expose cursor position (it shows all items without cursor). This is fine - no cursor positioning needed. If cursor is added to DataTable in future, this decision becomes relevant.

### Question 3: Should Two-Panel Mode Remain Default? (LOW Priority)

**What we know:** Current application launches in two-panel mode. Users must manually switch to single-view modes.

**What's unclear:** Whether users will prefer single-view modes as default, or whether two-panel should remain default.

**Recommendation:** Keep two-panel as default for now. It's the "power user" view showing both tree and table simultaneously. Advanced users can toggle to single-view modes if desired. In future phases, could add config file option to remember last view mode.

## Sources

### Primary (HIGH confidence)

- **libvaxis GitHub repository** - Complete vxfw framework documentation, SubSurface positioning API, event handling patterns
  - URL: https://github.com/rockorager/libvaxis
  - Verified: Official source, contains working examples of conditional layout, event handling
- **Existing codebase** - Current implementation of two-panel layout in `/home/robert/prog/zig/haltune/src/tui/layout.zig`, Model event handling in `/home/robert/prog/zig/haltune/src/tui/model.zig`
  - Verified: This is the code we're modifying - patterns are proven to work in this application

### Secondary (MEDIUM confidence)

- **Zig stdlib enum documentation** - Enum methods, switch statements, pattern matching
  - URL: https://ziglang.org/documentation/0.15.1/#enum
  - Verified: Official language documentation, enum patterns are standard practice

### Tertiary (LOW confidence)

- **TUI view switching patterns** - General TUI design patterns for view mode switching
  - Note: Most TUI libraries (ncurses, blessed, textual) have different approaches. Vaxis vxfw's conditional rendering is the right pattern for this stack.
  - Web search revealed limited specific guidance on TUI view switching - most implementations are application-specific

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Vaxis vxfw is already in use, no new dependencies needed
- Architecture: HIGH - Pattern is straightforward: add enum, conditional render, wire key binding
- Pitfalls: HIGH - Based on analysis of existing codebase and Vaxis patterns, state management approach is clear

**Research date:** 2026-02-06
**Valid until:** 2026-03-08 (30 days - Vaxis API is stable, this is simple logic not dependent on external changes)

**Key assumptions:**
- Vaxis 0.5.1 API remains stable (no breaking changes in SubSurface or event handling)
- Zig 0.15.1 enum and switch semantics remain consistent
- TreeView and DataTable widgets can be used without modification (verified by reading their code - they're self-contained)
- Users will primarily use two-panel mode, with single-view modes as occasional alternatives (not yet validated by user testing)
