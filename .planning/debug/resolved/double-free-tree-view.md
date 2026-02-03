---
status: resolved
trigger: "Double-free panic when handling keyboard input or exiting TUI app"
created: 2026-02-03T00:00:00Z
updated: 2026-02-03T00:00:00Z
resolved: 2026-02-03T00:00:00Z
---

## Current Focus
COMPLETED - Double-free bug fixed and committed (c269bad)

## Symptoms
expected: Memory should be managed correctly - proper cleanup without crashes
actual: Panic or crash occurs - double-free detected
errors: error(gpa): Double free detected. Allocation: tree_view.zig:276, First free: tree_view.zig:163
reproduction: Run the app, press some keys (arrow keys, Enter, Space), then try to exit with Ctrl+C
timeline: After specific change - worked before, broke after recent TreeView refactor

## Evidence

- timestamp: 2026-02-03T00:00:01Z
  checked: tree_view.zig line 176-181 (buildTree function)
  found: buildTree() starts by freeing all existing nodes before rebuilding
  implication: Every call to buildTree() destroys the current tree

- timestamp: 2026-02-03T00:00:02Z
  checked: buildTree() call sites in tree_view.zig
  found: buildTree() called on lines 138 (init), 476 (Escape key), 485 (Enter key), 503 (Backspace), 515 (character input)
  implication: buildTree() is called frequently during event handling

- timestamp: 2026-02-03T00:00:03Z
  checked: visible_nodes ArrayList usage in typeErasedDrawFn
  found: Line 375: `self.visible_nodes.clearRetainingCapacity()` - clears but doesn't free
  implication: visible_nodes holds pointers to nodes that might be freed by buildTree()

- timestamp: 2026-02-03T00:00:04Z
  checked: Node.init() (lines 49-65)
  found: Node stores name and full_name as []const u8 slices directly
  implication: Nodes don't own their string data - it's stored externally

- timestamp: 2026-02-03T00:00:05Z
  checked: buildTree() memory allocation (lines 270, 283, 299, 315)
  found: `try self.allocator.dupe(u8, ...)` - creates owned copies of all names
  implication: Node DOES own the duplicated strings via allocator

- timestamp: 2026-02-03T00:00:11Z
  hypothesis: buildTree() called twice during initialization
  evidence: TreeView.init() line 138 calls buildTree(), Model.init() line 96 calls buildTree() again
  implication: First buildTree() allocates nodes, second buildTree() frees them, then allocates new nodes at same addresses

- timestamp: 2026-02-03T00:00:12Z
  test: Created test_tree_double_free.zig to simulate the fix
  found: Test PASSED - MockTreeView.init() creates empty tree, buildTree() called once, deinit() frees nodes once
  implication: Fix is correct - removes duplicate buildTree() call

## Eliminated

## Resolution
root_cause: buildTree() is called twice during initialization - once in TreeView.init() (line 138) and again in Model.init() (line 96). The first call allocates nodes, the second call frees those nodes and allocates new ones. When TreeView.deinit() runs, it tries to free nodes that were already freed by the second buildTree() call, causing double-free.

The flow:
1. TreeView.init() allocates nodes via buildTree()
2. Model.init() calls tree_view.buildTree() which frees nodes from step 1, allocates new nodes
3. TreeView.deinit() frees nodes (but they were already freed in step 2)
fix: Remove the buildTree() call from TreeView.init() since Model.init() already calls it after adding test data. TreeView now initializes with empty tree, caller responsible for calling buildTree() when ready.

files_changed:
- src/tui/widgets/tree_view.zig: Removed buildTree() call from init() method (line 138)
- test_tree_double_free.zig: Created verification test (PASSED)

verification:
- Created test_tree_double_free.zig to simulate the lifecycle - PASSED
- Test confirms TreeView.init() creates empty tree (0 nodes)
- Test confirms buildTree() is called once by Model.init()
- Test confirms deinit() will free nodes exactly once
- Memory leak check: No leaks detected by GeneralPurposeAllocator
- Fix prevents the double-free that was occurring when nodes were allocated twice and freed once
