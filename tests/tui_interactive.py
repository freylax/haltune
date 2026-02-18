#!/usr/bin/env python3
"""
Interactive TUI test wrapper.
Sets up the same HAL environment as the automated tests
but runs haltune interactively for manual exploration.

Run: python3 tests/tui_interactive.py
"""

import sys
import os
import subprocess
import time
import signal
import argparse

# Configuration
HALTUNE_BIN = os.environ.get("HALTUNE_BIN", "./zig-out/bin/haltune")
HAL_FILE = "/tmp/test_interactive.hal"

# Colors
RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
BLUE = "\033[0;34m"
NC = "\033[0m"  # No Color


def print_header(text):
    print(f"{BLUE}{'=' * 50}{NC}")
    print(f"{BLUE}{text}{NC}")
    print(f"{BLUE}{'=' * 50}{NC}")


def print_section(text):
    print(f"\n{GREEN}{text}{NC}")


def print_info(text):
    print(f"  {text}")


def print_warning(text):
    print(f"{YELLOW}  WARNING: {text}{NC}")


def print_error(text):
    print(f"{RED}  ERROR: {text}{NC}")


class HalRunInstance:
    """Manage a halrun process for interactive testing."""

    def __init__(self, hal_file_content):
        self.hal_file = "/tmp/test_interactive_halrun.hal"
        self.process = None
        self.hal_file_content = hal_file_content
        self.python_comp_process = None

    def start(self):
        """Start halrun and the Python test component."""
        # Write the Python component file
        with open("/tmp/haltune_test_comp.py", "w") as f:
            f.write(PYTHON_COMP_CODE)

        # Start the Python component
        self.python_comp_process = subprocess.Popen(
            ["python3", "/tmp/haltune_test_comp.py"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True
        )

        # Give it time to start
        time.sleep(1.0)

        # Write the HAL file
        with open(self.hal_file, "w") as f:
            f.write(self.hal_file_content)

        # Start halrun in interactive mode (-I) to keep it running
        self.process = subprocess.Popen(
            ["halrun", "-I", "-f", self.hal_file],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True
        )

        # Give halrun time to start
        time.sleep(1.5)

        if self.process.poll() is not None:
            _, stderr = self.process.communicate()
            print_error(f"halrun exited with code {self.process.poll()}")
            if stderr:
                print(f"  halrun stderr: {stderr.decode('utf-8', errors='replace')[-200:]}")
            return False

        return True

    def stop(self):
        """Stop the halrun and Python component processes."""
        # Stop Python component first
        if self.python_comp_process:
            try:
                self.python_comp_process.terminate()
                self.python_comp_process.wait(timeout=2)
            except:
                try:
                    os.killpg(os.getpgid(self.python_comp_process.pid), signal.SIGTERM)
                except:
                    pass
            self.python_comp_process = None

        if self.process:
            try:
                self.process.stdin.write(b"exit\n")
                self.process.stdin.flush()
                time.sleep(0.5)
                self.process.wait(timeout=2)
            except:
                try:
                    os.killpg(os.getpgid(self.process.pid), signal.SIGTERM)
                except:
                    pass
            self.process = None

    def list_components(self):
        """List available HAL components."""
        try:
            result = subprocess.run(
                ["halcmd", "list", "comp"],
                capture_output=True,
                text=True,
                timeout=2
            )
            components = result.stdout.strip().split()
            return components
        except:
            return []


def create_hal_script():
    """Create the HAL script (same as automated tests)."""
    return """# Interactive TUI test HAL file
# The test component is started separately via Python
"""


PYTHON_COMP_CODE = '''#!/usr/bin/env python3
import hal
import time

h = hal.component('haltune-test-comp')

# Create different pin types (IN, OUT, IO)
h.newpin('bit-in', hal.HAL_BIT, hal.HAL_IN)
h.newpin('bit-out', hal.HAL_BIT, hal.HAL_OUT)
h.newpin('bit-io', hal.HAL_BIT, hal.HAL_IO)

h.newpin('float-in', hal.HAL_FLOAT, hal.HAL_IN)
h.newpin('float-out', hal.HAL_FLOAT, hal.HAL_OUT)
h.newpin('float-io', hal.HAL_FLOAT, hal.HAL_IO)

h.newpin('u32-in', hal.HAL_U32, hal.HAL_IN)
h.newpin('u32-out', hal.HAL_U32, hal.HAL_OUT)

h.newpin('s32-in', hal.HAL_S32, hal.HAL_IN)
h.newpin('s32-out', hal.HAL_S32, hal.HAL_OUT)

# Create some parameters
h.newparam('float-param', hal.HAL_FLOAT, hal.HAL_RW)
h.newparam('u32-param', hal.HAL_U32, hal.HAL_RW)
h.newparam('s32-param', hal.HAL_S32, hal.HAL_RW)

# Set initial values
h['float-param'] = 3.14159
h['u32-param'] = 42
h['s32-param'] = -10

h.ready()

try:
    while True:
        time.sleep(1)
except:
    pass
finally:
    h.exit()
'''


def show_instructions():
    """Show keyboard instructions for haltune."""
    print_section("Key bindings:")
    print_info("Ctrl+Q     - Quit application")
    print_info("Ctrl+T     - Toggle tree/table view")
    print_info("Enter      - Expand/collapse component, or edit value")
    print_info("Space      - Toggle visibility (mark as visible)")
    print_info("Up/Down    - Navigate items")
    print_info("Page Up/Down - Navigate by page")
    print_info("Backspace  - Collapse parent component")
    print_info("Escape     - Cancel edit mode")
    print_info("/          - Enter search mode")
    print_info("n          - Create new signal (in tree view)")
    print_info("s          - Save configuration")
    print_info("t          - Cycle type filter (in table view)")
    print_info("c          - Enter component filter (in table view)")


def show_test_scenarios():
    """Show suggested test scenarios."""
    print_section("Test Scenarios:")
    print_info("1. Navigate to 'threads' component and press Enter to expand")
    print_info("2. Navigate to a pin and press Space to mark as visible")
    print_info("3. Press Ctrl+T to switch to table view")
    print_info("4. In table view, navigate to a writable value and press Enter to edit")
    print_info("5. Type a new value and press Enter to confirm, or Escape to cancel")
    print_info("6. Press Ctrl+T to switch back to tree view")
    print_info("7. Press Backspace to collapse the parent component")


def main():
    print_header("haltune Interactive TUI Test")

    # Check if haltune binary exists
    if not os.path.exists(HALTUNE_BIN):
        print_error(f"haltune binary not found at {HALTUNE_BIN}")
        print_info("Build haltune first: zig build")
        print_info("Or set HALTUNE_BIN environment variable")
        return 1

    print_info(f"Using haltune: {HALTUNE_BIN}")

    # Create HAL script
    hal_script = create_hal_script()

    print_section("HAL Configuration:")
    print(hal_script)

    # Start halrun
    print_section("Starting halrun...")
    halrun = HalRunInstance(hal_script)
    if not halrun.start():
        print_error("halrun failed to start")
        return 1

    print_info(f"halrun started (PID: {halrun.process.pid})")

    # Show available components
    components = halrun.list_components()
    if components:
        print_info(f"Available components: {', '.join(components)}")
    else:
        print_warning("No components found")

    # Show instructions
    show_instructions()
    show_test_scenarios()

    # Set up cleanup on exit
    def cleanup():
        print()
        print_section("Cleaning up...")
        halrun.stop()
        print_info("Done")

    import atexit
    atexit.register(cleanup)

    # Run haltune
    print_section("Starting haltune...")
    print(f"{YELLOW}Press Ctrl+Q to exit{NC}\n")

    result = subprocess.run([HALTUNE_BIN])

    print(f"\nhaltune exited with code {result.returncode}")
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
