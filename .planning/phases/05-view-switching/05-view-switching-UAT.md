---
status: testing
phase: 05-view-switching
source: 05-01-SUMMARY.md, 05-02-SUMMARY.md
started: 2026-02-06T00:40:00Z
updated: 2026-02-06T00:40:00Z
---

## Current Test

number: 1
name: Launch Application in Tree Mode
expected: |
  Application starts in tree-only view (full width tree component browser)
  Help text at bottom shows "Ctrl+T=Table View" hint
awaiting: user response

## Tests

### 1. Launch Application in Tree Mode
expected: Application starts in tree-only view (full width tree component browser). Help text at bottom shows "Ctrl+T=Table View" hint
result: pending

### 2. Switch to Table View with Ctrl-t
expected: Pressing Ctrl-t switches to table-only view (full width data table). Help text updates to show "Ctrl+T=Tree View"
result: pending

### 3. Switch Back to Tree View with Ctrl-t
expected: Pressing Ctrl-t again returns to tree-only view. Help text updates to show "Ctrl+T=Table View"
result: pending

### 4. Tree View Functionality Preserved
expected: Tree navigation works (arrow keys, Enter to expand/collapse, Space to toggle visibility, / for search). Expanded nodes and filters persist when switching views
result: pending

### 5. Table View Functionality Preserved
expected: Data table shows checked items in full-width layout. Values and editing functionality work the same as before
result: pending

### 6. Ctrl-t Blocked When Dialog Open
expected: When signal dialog or save dialog is open, pressing Ctrl-t does nothing (silent ignore, no message)
result: pending

## Summary

total: 6
passed: 0
issues: 0
pending: 6
skipped: 0

## Gaps

[none yet]
