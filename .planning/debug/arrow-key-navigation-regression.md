---
status: verifying
trigger: "arrow-key-navigation-regression"
created: 2026-02-04T00:00:00Z
updated: 2026-02-04T00:00:00Z
---

## Current Focus
next_action: User needs to test on pib with proper TTY to verify arrow key navigation works

## Symptoms
expected: Arrow keys should move selection through tree nodes, Enter should expand/collapse, Space should toggle checkboxes
actual: User reports keyboard input not responding - same as the original issue
errors: None explicitly reported - just no response to keypresses
reproduction: Run haltune on pib with proper TTY, press arrow keys
started: Originally fixed in commit 2ffdc49. Latest commit 026e01c changed TreeView rendering significantly. User reports issues again after this commit.

## Eliminated

## Evidence
- timestamp: 2026-02-04T00:00:00Z
  checked: Commit 026e01c diff, tree_view.zig typeErasedDrawFn
  found: Before fix: Surface had .widget = self.widget() (TreeView with eventHandler). After fix: delegates to vxfw.Text.widget().draw() which returns Surface with .widget pointing to Text widget (no eventHandler)
  implication: Events routed to Text widget's eventHandler (null) instead of TreeView's eventHandler

## Resolution
root_cause: typeErasedDrawFn delegates to vxfw.Text.widget().draw(), returning a Surface whose widget reference points to Text instead of TreeView. Vaxis event routing uses Surface.widget.eventHandler, so events never reach TreeView's handler.
fix: Capture the Surface from Text.widget().draw(), then create a new Surface with same buffer but .widget = self.widget()
verification: Pending user testing on pib
files_changed: ["src/tui/widgets/tree_view.zig"]
