// Haltune TUI Test Script
// Run with: mcp-tui-driver run-script test_tui.js
// or via the MCP tools in Claude Code

async function testHaltuneTUI() {
    console.log("=== Haltune TUI Test ===");

    // Launch haltune
    const launchResult = await tui.launch({
        command: "/home/robert/prog/zig/haltune/zig-out/bin/haltune",
        cols: 120,
        rows: 40,
        cwd: "/home/robert/prog/zig/haltune"
    });
    const sessionId = launchResult.session_id;
    console.log("Session ID:", sessionId);

    // Wait for UI to load
    await tui.waitForText(sessionId, "Table View", 5000);
    const text = await tui.text(sessionId);
    console.log("Screen text:", text.substring(0, 500) + "...");

    // Verify components are shown
    if (text.includes("components") || text.includes("0 components")) {
        console.log("OK: UI shows components");
    }

    // Take screenshot
    const screenshot = await tui.screenshot(sessionId);
    console.log("Screenshot taken:", screenshot.width + "x" + screenshot.height);

    // Test navigation - press Down key
    await tui.pressKey(sessionId, "Down");
    await tui.waitForIdle(sessionId, 100, 2000);

    // Test Ctrl+O to open file dialog
    await tui.pressKeys(sessionId, ["Ctrl+o", "Escape"]);
    await tui.waitForIdle(sessionId, 100, 2000);

    // Quit
    await tui.pressKey(sessionId, "q");
    await tui.close(sessionId);

    console.log("=== TUI Test Complete ===");
}

// Run the test
testHaltuneTUI().catch(console.error);
