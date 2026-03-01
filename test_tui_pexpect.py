#!/usr/bin/env python3
"""Test haltune TUI with pexpect"""
import pexpect
import sys

def test_haltune():
    # Spawn haltune
    child = pexpect.spawn(
        "/home/cnc/prog/haltune/zig-out/bin/haltune",
        encoding="utf-8",
        dimensions=(80, 24)
    )

    # Wait for UI to load (look for common UI elements)
    try:
        # Wait up to 5 seconds for UI elements
        child.expect(["Table View", "Tree View", "Ctrl"], timeout=5)
        print("✓ TUI loaded successfully")

        # Capture screen content
        output = child.before
        print("\nScreen content:")
        print(output[:500])  # First 500 chars

        # Check for component count
        if "0 components" in output:
            print("\n⚠ Showing 0 components - checking debug...")
        elif "component" in output.lower():
            # Count components
            count = output.count("component")
            print(f"\n✓ Found {count} component mentions")

        # Quit
        child.send("q")
        child.expect(pexpect.EOF, timeout=2)
        print("\n✓ Test completed")
        return True

    except pexpect.TIMEOUT:
        print("✗ Timeout waiting for TUI to load")
        print("Output before timeout:")
        print(child.before)
        return False
    except pexpect.EOF:
        print("✗ Process exited")
        print("Output:")
        print(child.before)
        return False
    finally:
        child.close()

if __name__ == "__main__":
    success = test_haltune()
    sys.exit(0 if success else 1)
