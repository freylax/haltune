# Bookmarks Feature - Detailed Design

**Purpose:** Quick access to frequently monitored HAL items (pins, signals, parameters)

## User Workflow

### Adding Bookmarks

1. Navigate to any item in tree view (pin, signal, or parameter)
2. Press **'b'** key to bookmark the current selection
3. Visual feedback:
   - **[B]** indicator appears next to item name in tree view
   - Confirmation message (via stderr): `Bookmarked: stepgen.0.enable`
4. Item is now in bookmark list

### Viewing Bookmarks

1. Press **'B'** (Shift+b) to open bookmark list dialog
2. Dialog shows:
   ```
   ┌──────────── Bookmarks ────────────┐
   │ [B] stepgen.0.enable   PIN      │
   │ [B] pid.0.Pgain         PARAM    │
   │ [B] X-vel               SIGNAL    │
   │                                     │
   │ Enter=Jump  Del=Remove  Esc=Close │
   └──────────────────────────────────────┘
   ```
3. Use **↑/↓** arrows to navigate list
4. Press **Enter** to jump to selected item
5. Press **Delete** or **'d'** to remove selected bookmark

### Removing Bookmarks

Two ways to remove:

**Method 1: From bookmark list**
1. Open bookmark list with 'B'
2. Navigate to item
3. Press Delete or 'd'
4. Item removed immediately

**Method 2: From tree view** (future enhancement)
1. Navigate to bookmarked item
2. Press 'b' again to toggle bookmark off
3. [B] indicator disappears

### Jumping to Bookmarks

1. Open bookmark list with 'B'
2. Navigate to item
3. Press Enter
4. Dialog closes, tree view navigates to that item
5. Cursor positioned on the item
6. View switched to appropriate mode (tree if not already)

## Data Structure

### Bookmark Entry

```zig
pub const Bookmark = struct {
    name: []const u8,      // HAL item name (e.g., "stepgen.0.enable")
    item_type: BookmarkType, // pin, signal, or param
    added_at: i64,          // Unix timestamp
};
```

### Storage Format (JSON)

**File:** `~/.config/haltune/bookmarks.json`

```json
[
    {"name":"stepgen.0.enable","type":"pin","added":1739434200},
    {"name":"pid.0.Pgain","type":"param","added":1739434260},
    {"name":"X-vel","type":"signal","added":1739434300},
    {"name":"stepgen.0.position-scale","type":"param","added":1739434400}
]
```

### Why JSON?

- **Human editable** - Users can manually edit bookmark list
- **Version control friendly** - Easy to diff changes
- **Language agnostic** - Other tools can read/write
- **Simple** - No complex parsing needed
- **Expandable** - Easy to add new fields later

## UI Details

### Tree View Bookmark Indicator

In `src/tui/widgets/tree_view.zig`, bookmarked items show:

```
>component *                    ← Normal item
>[B] motion *                 ← Bookmarked item
>  [B] servo-thread *         ← Bookmarked child item
```

- **[B]** appears before item name (similar to visibility symbols)
- Only shown in tree view, not data table
- Uses standard color (no special highlighting)

### Bookmark List Dialog

**Dialog dimensions:**
- Width: 60 chars (or terminal width - 4, whichever is less)
- Height: 20 chars (or terminal height - 4, whichever is less)
- Centered on screen

**Dialog layout:**
```
┌───────────────────────────── Bookmarks ───────────────────────┐
│ > [B] stepgen.0.enable   PIN                                  │
│   [B] pid.0.Pgain         PARAM                                │
│   [B] X-vel               SIGNAL                               │
│   [B] stepgen.0.position-scale  PARAM                            │
│   [B] motion.command      PIN                                     │
│                                                                 │
│ Enter=Jump  Del=Remove  Esc=Close                                  │
└─────────────────────────────────────────────────────────────────────────┘
```

**Column layout:**
- Cursor: `>` or space
- Bookmark indicator: `[B]` (always shown in list)
- Name: Item name (truncated if too long)
- Type: PIN/SIGNAL/PARAM (right-aligned, fixed width)

**Navigation:**
- **↑/k** - Move up
- **↓/j** - Move down
- **Enter** - Jump to selected item
- **Delete/d** - Remove selected bookmark
- **Escape/q** - Close dialog

**Scrolling:**
- If >20 items, dialog scrolls
- Cursor stays visible
- Scroll indicator: `[1/25]` in title (future enhancement)

### Help Text

Updated help line shows bookmark count:

```
Ctrl+T=Table View  B=Bookmarks(5)  Ctrl+C=Quit
```

- Shows `B=Bookmarks` when no bookmarks
- Shows `B=Bookmarks(5)` with count when bookmarks exist

## Implementation Notes

### When Tree Rebuilds

Tree view is rebuilt when:
- Components load/unload
- Search pattern changes
- Visibility filter changes

**Problem:** Node pointers are invalidated on rebuild

**Solution:** Bookmark storage uses item **names**, not pointers
- On rebuild, check if item is bookmarked by name lookup
- Re-apply [B] indicator to new node

### Missing/Crashed Bookmarks

If user has bookmarked `stepgen.0.enable` but that component is no longer loaded:

1. Item still in bookmark list (preserved across restarts)
2. Attempting to jump to it shows error: "Item not found: stepgen.0.enable"
3. No crash - graceful handling
4. User can manually remove from list

**Future enhancement:** Auto-cleanup of stale bookmarks

### Bookmarks vs Tree Selection

Bookmarks are **independent** from tree selection:
- Tree cursor can be on any item
- Bookmark list is separate
- Jumping to bookmark moves tree cursor to that item

## Key Bindings Summary

| Key | Action | Mode |
|-----|--------|------|
| **b** | Add current selection to bookmarks | Tree view |
| **B** | Open bookmark list dialog | Any |
| **↑/↓** | Navigate bookmark list | Bookmark dialog |
| **Enter** | Jump to selected bookmark | Bookmark dialog |
| **Delete/d** | Remove selected bookmark | Bookmark dialog |
| **Escape** | Close bookmark list | Bookmark dialog |

## Example Session

```
1. User navigates to stepgen.0.enable in tree
2. Press 'b'
   → Tree shows: >[B] stepgen.0.enable *
   → stderr: Bookmarked: stepgen.0.enable

3. User navigates to pid.0.Pgain
4. Press 'b'
   → Tree shows: >[B] pid.0.Pgain

5. User navigates away to other items...

6. Later, press 'B' (Shift+b)
   → Bookmark dialog opens:
     > [B] stepgen.0.enable   PIN
       [B] pid.0.Pgain         PARAM

7. Press Enter on stepgen.0.enable
   → Dialog closes
   → Tree view navigates to stepgen.0.enable
   → Cursor positioned on item

8. Press 'B' again, press Delete on pid.0.Pgain
   → Removed from bookmarks

9. Restart haltune
   → Bookmarks still there (loaded from JSON)
   → Tree shows [B] indicators
```

## Future Enhancements (Post-MVP)

### 1. Bookmark Categories/Folders

```
┌──────────── Bookmarks ────────────┐
│ [+] X-Axis /                     │
│   [B] stepgen.0.enable         │
│   [B] pid.0.Pgain             │
│ [+] Y-Axis /                     │
│   [B] stepgen.1.enable         │
│                                 │
│ Enter=Jump  Del=Remove  Esc=Close │
└───────────────────────────────────┘
```

### 2. Bookmark Notes

Add user notes to bookmarks:
```json
{"name":"pid.0.Pgain","type":"param","added":1739434260,"note":"Heavy gantry setting"}
```

### 3. Quick Access Keys

Number bookmarks 1-9 for quick access:
- Press '1' to jump to first bookmark
- Press '2' for second, etc.

### 4. Export/Import Bookmarks

- Export bookmarks to file for sharing
- Import bookmarks from file

### 5. Toggle Bookmark in Tree

Press 'b' on already-bookmarked item to remove it
(no need to open dialog)

### 6. Bookmark Search

Search within bookmark list:
- Press '/' in dialog to filter bookmarks
- Useful with many bookmarks

## Testing Checklist

After implementation, verify:

- [ ] Add pin to bookmark
- [ ] Add signal to bookmark
- [ ] Add param to bookmark
- [ ] [B] indicator shows in tree
- [ ] Open bookmark list with 'B'
- [ ] Navigate list with arrow keys
- [ ] Jump to bookmark with Enter
- [ ] Remove bookmark with Delete
- [ ] Bookmarks persist across restart
- [ ] JSON file created correctly
- [ ] Help text shows bookmark count
- [ ] Missing bookmark shows error
- [ ] Can add duplicate (just updates, no error)
- [ ] Dialog closes on Escape
- [ ] Dialog shows empty state
