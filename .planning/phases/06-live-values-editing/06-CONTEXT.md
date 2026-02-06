# Phase 6: Live Values & Editing - Context

**Gathered:** 2026-02-07
**Status:** Ready for planning

<domain>
## Phase Boundary

Real-time value display and editing for HAL pins/signals/params in both tree and table views. Values update via pubsub, are editable in-place, and signals support full CRUD operations (create/remove via inline editing, connect/disconnect).

</domain>

<decisions>
## Implementation Decisions

### Value display format
- **Position:** Separate column for values (right-aligned)
- **BIT values:** ● / ○ symbols (filled circle = TRUE, empty circle = FALSE)
- **FLOAT/U32 values:** Full precision, max column width 6-8 characters
- **Status line detail:** When cursor is on a row, status line shows full precision value
- **Type indication:** Implicit by format (symbols for BIT, decimal for FLOAT/U32)

### Editing interaction
- **Trigger:** Enter key on value field opens edit
- **Scope:** Only editable values trigger edit (input pins NOT connected to signals)
- **BIT toggle:** Enter on BIT values simply toggles (● ↔ ○) — no dialog
- **Edit location:** Direct in-place editing (value cell becomes editable)
- **Commit/Cancel:** Esc to cancel, Enter to commit

### Type-specific inputs
- **BIT editing:** Visual toggle — Enter cycles between ● and ○
- **FLOAT/U32 editing:** Free-form text input
- **Input validation:** Allow only sensible keys:
  - `-` for signed/float (at start)
  - `0`-`9` for all numeric types
  - `.` for float (only once)

### Signal CRUD
- **Connect/create:** Ctrl+S on pin opens inline/status line editing
- **Completion:** Inline editing supports completion of existing signals
- **Discovery:** Some way to show available signals for the current pin's type
- **New signal creation:** Name + inferred type from current pin; status line confirms creation
- **Disconnect:** Clear signal name in Ctrl+S editing to disconnect
- **Delete:** If disconnecting last pin using a signal, status line prompts for signal deletion

### Claude's Discretion
- Exact ellipsis/truncation display for overflowing float values
- Signal completion UI design (how to show available signals)
- Status line prompt wording for signal creation/deletion confirmation

</decisions>

<specifics>
## Specific Ideas

- Status line shows full precision when cursor is on the row
- BIT toggle with ● / ○ symbols is cleaner than 1/0 or TRUE/FALSE
- Ctrl+S for signal editing (not "n" for new) - inline flow for both connect and create

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 06-live-values-editing*
*Context gathered: 2026-02-07*
