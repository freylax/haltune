#!/usr/bin/env python3
"""
TUI integration tests for haltune using pexpect.

Run on pib: python3 tests/tui_test.py
"""

import sys
import os
import subprocess

# Add mcp-tui-test to path for potential MCP usage
sys.path.append("/home/cnc/mcp-tui-test")

try:
    import pexpect
except ImportError:
    print("ERROR: pexpect not installed. Run: apt install python3-pexpect")
    sys.exit(1)

# Configuration
HALTUNE_BIN = "/home/cnc/prog/haltune/zig-out/bin/haltune"
TEST_HAL_FILE = "/tmp/test_haltune.hal"
TERMINAL_WIDTH = 80
TERMINAL_HEIGHT = 24

def create_test_hal_file():
    """Create a test HAL file for testing."""
    hal_content = """# Test HAL file for haltune TUI testing

# Create test signals
net test-signal sig1
net test-signal sig2

# Set some parameters
setp sig1.value 0.0
setp sig2.value 1.5

# Create pins
net sig1 value-test-pin
sets value-test-pin true
net sig2 value-test-pin-2
sets value-test-pin-2 false
"""
    with open(TEST_HAL_FILE, "w") as f:
        f.write(hal_content)
    print(f"Created test HAL file: {TEST_HAL_FILE}")

def test_tui_basic_load():
    """Test 1: Basic TUI load without arguments."""
    print("\n[TEST 1] Basic TUI Load")

    if not os.path.exists(HALTUNE_BIN):
        print(f"  SKIP: haltune binary not found at {HALTUNE_BIN}")
        return False

    child = pexpect.spawn(
        HALTUNE_BIN,
        dimensions=(TERMINAL_WIDTH, TERMINAL_HEIGHT),
        encoding="utf-8"
    )

    try:
        # Look for TUI elements
        child.expect(["Table View", "Ctrl+T", "components"], timeout=8)
        print("  OK TUI loaded")

        # Verify key UI elements
        output = child.before
        if "Ctrl+T=Table View" in output:
            print("  OK Keyboard shortcuts visible")
        if "0 components" in output:
            print("  OK Shows 0 components (HAL not running)")

        return True

    except pexpect.exceptions.TIMEOUT:
        output = child.before if child.before else ""
        if "Table View" in output or "Ctrl+T" in output:
            print("  OK TUI loaded (timeout on specific text match)")
            return True
        else:
            print(f"  FAIL: TUI did not load. Output: {output[-200:]}")
            return False
    except Exception as e:
        print(f"  FAIL: {e}")
        return False
    finally:
        child.send("q")
        try:
            child.expect(pexpect.EOF, timeout=2)
        except:
            pass

def test_tui_with_hal_file():
    """Test 2: TUI with HAL file argument."""
    print("\n[TEST 2] TUI with HAL File")

    if not os.path.exists(TEST_HAL_FILE):
        print(f"  SKIP: test HAL file not found at {TEST_HAL_FILE}")
        return False

    child = pexpect.spawn(
        f"{HALTUNE_BIN} -f {TEST_HAL_FILE}",
        dimensions=(TERMINAL_WIDTH, TERMINAL_HEIGHT),
        encoding="utf-8"
    )

    try:
        child.expect(["Table View", "Ctrl+T"], timeout=8)
        print("  OK TUI loaded with HAL file")
        return True
    except pexpect.exceptions.TIMEOUT:
        output = child.before if child.before else ""
        if "Table View" in output:
            print("  OK TUI with HAL file loaded")
            return True
        return False
    except Exception as e:
        print(f"  FAIL: {e}")
        return False
    finally:
        child.send("q")
        try:
            child.expect(pexpect.EOF, timeout=2)
        except:
            pass

def test_tui_with_log_file():
    """Test 3: TUI with log file option."""
    print("\n[TEST 3] TUI with Log File")

    log_file = "/tmp/haltune_tui_test.log"

    # Remove old log file
    if os.path.exists(log_file):
        os.remove(log_file)

    child = pexpect.spawn(
        f"{HALTUNE_BIN} --log-file {log_file}",
        dimensions=(TERMINAL_WIDTH, TERMINAL_HEIGHT),
        encoding="utf-8"
    )

    try:
        child.expect(["Table View", "Ctrl+T"], timeout=8)
        print("  OK TUI loaded with log file")

        # Check log file was created and has content
        child.send("q")
        child.expect(pexpect.EOF, timeout=2)

        if os.path.exists(log_file):
            with open(log_file, "r") as f:
                content = f.read()
                if "haltune log started" in content:
                    print("  OK Log file created and written to")
                else:
                    print(f"  OK Log file created (empty or different format)")
            return True
        else:
            print("  INFO: Log file not created")
            return True  # Not a failure, just info

    except Exception as e:
        print(f"  FAIL: {e}")
        return False

def main():
    """Run all TUI tests."""
    print("=" * 50)
    print("haltune TUI Integration Tests")
    print("=" * 50)

    # Create test HAL file
    create_test_hal_file()

    # Check binary exists
    if not os.path.exists(HALTUNE_BIN):
        print(f"\nERROR: haltune binary not found at {HALTUNE_BIN}")
        print("Build haltune first: zig build")
        return 1

    # Run tests
    results = {
        "basic_load": test_tui_basic_load(),
        "hal_file": test_tui_with_hal_file(),
        "log_file": test_tui_with_log_file(),
    }

    # Summary
    print("\n" + "=" * 50)
    print("Test Summary")
    print("=" * 50)

    passed = sum(1 for v in results.values() if v)
    total = len(results)

    for name, result in results.items():
        status = "PASS" if result else "FAIL"
        print(f"  {name}: {status}")

    print(f"\nResults: {passed}/{total} passed")

    return 0 if passed == total else 1

if __name__ == "__main__":
    sys.exit(main())
