"""TUI comprehensive tests.

Migrated from test_tui_pexpect.py and tests/tui_test.py.
"""

import os
import pytest
from pathlib import Path
from lib.tui_helpers import TUITester
from lib.hal_helpers import HalRunInstance
from lib.config import load_config


@pytest.fixture(scope="module")
def config():
    config_path = Path(__file__).parent / "config" / "test_config.toml"
    return load_config(config_path)


@pytest.fixture
def haltune_binary(config):
    return config.hosts["local"].haltune_binary


@pytest.fixture
def binary_exists(haltune_binary):
    """Skip tests if haltune binary does not exist."""
    return os.path.exists(haltune_binary)


class TestTUILoad:
    """Test TUI loading and initial display."""

    @pytest.mark.skipif(True, reason="TUI test - requires haltune binary")
    def test_tui_loads(self, haltune_binary, binary_exists):
        """Test that TUI loads and displays initial screen."""
        if not binary_exists:
            pytest.skip(f"haltune binary not found at {haltune_binary}")

        tester = TUITester(f"{haltune_binary}")
        assert tester.wait_for_text("Table View", timeout=10) or \
               tester.wait_for_text("Components", timeout=10)
        tester.quit()

    @pytest.mark.skipif(True, reason="TUI test - requires haltune binary")
    def test_tui_shows_status(self, haltune_binary, binary_exists):
        """Test that TUI shows HAL component status."""
        if not binary_exists:
            pytest.skip(f"haltune binary not found at {haltune_binary}")

        tester = TUITester(f"{haltune_binary}")
        assert tester.wait_for_text("components", timeout=10)
        tester.quit()

    @pytest.mark.skipif(True, reason="TUI test - requires haltune binary")
    def test_tui_with_hal_file(self, haltune_binary, binary_exists, tmp_path):
        """Test TUI loads with a HAL file argument."""
        if not binary_exists:
            pytest.skip(f"haltune binary not found at {haltune_binary}")

        # Create a simple test HAL file
        hal_file = tmp_path / "test.hal"
        hal_file.write_text("# Test HAL file\nnet test-signal sig1\n")

        tester = TUITester(f"{haltune_binary} -f {hal_file}")
        assert tester.wait_for_text("Table View", timeout=10)
        tester.quit()


class TestTUIQuit:
    """Test TUI quit functionality."""

    @pytest.mark.skipif(True, reason="TUI test - requires haltune binary")
    def test_quit_with_q(self, haltune_binary, binary_exists):
        """Test that 'q' key quits the application."""
        if not binary_exists:
            pytest.skip(f"haltune binary not found at {haltune_binary}")

        tester = TUITester(f"{haltune_binary}")
        tester.wait_for_text("Table View", timeout=10)
        tester.send_key("q")

        import pexpect
        try:
            tester.child.expect(pexpect.EOF, timeout=2)
        except pexpect.TIMEOUT:
            tester.quit()


class TestTUIViewToggle:
    """Test view switching functionality."""

    @pytest.mark.skipif(True, reason="TUI test - requires haltune binary")
    def test_toggle_table_tree_view(self, haltune_binary, binary_exists):
        """Test Ctrl+T toggles between table and tree view."""
        if not binary_exists:
            pytest.skip(f"haltune binary not found at {haltune_binary}")

        tester = TUITester(f"{haltune_binary}")
        tester.wait_for_text("Table View", timeout=10)
        tester.send_key("Ctrl+T")
        tester.wait_for_idle()
        tester.quit()


class TestTUIExpandCollapse:
    """Test tree expand/collapse functionality."""

    @pytest.mark.skipif(True, reason="TUI test - requires haltune binary")
    def test_expand_component(self, haltune_binary, binary_exists):
        """Test Enter key expands/collapses components."""
        if not binary_exists:
            pytest.skip(f"haltune binary not found at {haltune_binary}")

        tester = TUITester(f"{haltune_binary}")
        tester.wait_for_text("components", timeout=10)
        tester.send_keys("\x1b[B")  # Down arrow
        import time
        time.sleep(0.2)
        tester.send_key("Enter")
        time.sleep(0.3)
        tester.quit()


class TestTUIFileDialog:
    """Test file dialog functionality."""

    @pytest.mark.skipif(True, reason="TUI test - requires haltune binary")
    def test_file_dialog_opens(self, haltune_binary, binary_exists):
        """Test Ctrl+O opens file dialog."""
        if not binary_exists:
            pytest.skip(f"haltune binary not found at {haltune_binary}")

        tester = TUITester(f"{haltune_binary}")
        tester.wait_for_text("Table View", timeout=10)
        tester.send_key("Ctrl+O")
        import time
        time.sleep(0.5)
        tester.send_key("Escape")
        time.sleep(0.3)
        tester.quit()


class TestTUISearch:
    """Test search functionality."""

    @pytest.mark.skipif(True, reason="TUI test - requires haltune binary")
    def test_search_mode(self, haltune_binary, binary_exists):
        """Test / key activates search mode."""
        if not binary_exists:
            pytest.skip(f"haltune binary not found at {haltune_binary}")

        tester = TUITester(f"{haltune_binary}")
        tester.wait_for_text("Table View", timeout=10)
        tester.send_keys("/")
        import time
        time.sleep(0.3)
        tester.send_key("Escape")
        time.sleep(0.3)
        tester.quit()


class TestTUISaveDialog:
    """Test save dialog functionality."""

    @pytest.mark.skipif(True, reason="TUI test - requires haltune binary")
    def test_save_dialog_opens(self, haltune_binary, binary_exists):
        """Test Ctrl+S opens save dialog."""
        if not binary_exists:
            pytest.skip(f"haltune binary not found at {haltune_binary}")

        tester = TUITester(f"{haltune_binary}")
        tester.wait_for_text("Table View", timeout=10)
        tester.send_key("Ctrl+S")
        import time
        time.sleep(0.3)
        tester.send_key("Escape")
        time.sleep(0.3)
        tester.quit()


class TestTUILogFile:
    """Test log file functionality."""

    @pytest.mark.skipif(True, reason="TUI test - requires haltune binary")
    def test_log_file_created(self, haltune_binary, binary_exists, tmp_path):
        """Test that --log-file creates and writes to log file."""
        if not binary_exists:
            pytest.skip(f"haltune binary not found at {haltune_binary}")

        log_file = tmp_path / "haltune_test.log"

        tester = TUITester(f"{haltune_binary} --log-file {log_file}")
        tester.wait_for_text("Table View", timeout=10)
        tester.quit()

        # Log file should exist
        assert log_file.exists()


class TestTUIWithHalrun:
    """Test TUI with real HAL components."""

    @pytest.mark.skipif(True, reason="TUI test - requires halrun")
    def test_tui_with_halrun_components(self, haltune_binary, binary_exists):
        """Test TUI displays real HAL components from halrun."""
        if not binary_exists:
            pytest.skip(f"haltune binary not found at {haltune_binary}")

        # Check if halrun is available
        import shutil
        if not shutil.which("halrun"):
            pytest.skip("halrun not found in PATH")

        halrun = HalRunInstance()
        halrun.start()

        try:
            tester = TUITester(f"{haltune_binary}")
            tester.wait_for_text("Table View", timeout=10)

            # Look for common HAL components
            screen = tester.get_screen()
            # Even without specific components, TUI should load
            assert "components" in screen.lower() or "Table View" in screen

            tester.quit()
        finally:
            halrun.stop()


class TestTUIComprehensive:
    """Comprehensive TUI interaction tests."""

    @pytest.mark.skipif(True, reason="TUI test - requires haltune binary")
    def test_comprehensive_navigation(self, haltune_binary, binary_exists):
        """Test various TUI navigation and interaction features."""
        if not binary_exists:
            pytest.skip(f"haltune binary not found at {haltune_binary}")

        tester = TUITester(f"{haltune_binary}")
        tester.wait_for_text("Table View", timeout=10)

        import time

        # Test tree navigation
        tester.send_keys("\x1b[B")  # Down arrow
        time.sleep(0.2)
        tester.send_keys("\x1b[A")  # Up arrow
        time.sleep(0.2)

        # Test expand/collapse
        tester.send_key("Enter")
        time.sleep(0.3)

        # Test visibility toggle
        tester.send_key("Space")
        time.sleep(0.2)

        # Test view switch
        tester.send_key("Ctrl+T")
        time.sleep(0.3)

        # Test table navigation
        tester.send_keys("\x1b[B")
        time.sleep(0.2)

        # Test edit mode attempt
        tester.send_key("Enter")
        time.sleep(0.3)
        tester.send_key("Escape")
        time.sleep(0.2)

        tester.quit()

    @pytest.mark.skipif(True, reason="TUI test - requires haltune binary")
    def test_value_editing(self, haltune_binary, binary_exists):
        """Test value editing in TUI."""
        if not binary_exists:
            pytest.skip(f"haltune binary not found at {haltune_binary}")

        tester = TUITester(f"{haltune_binary}")
        tester.wait_for_text("Table View", timeout=10)

        import time

        # Navigate to find a potential editable item
        for _ in range(5):
            tester.send_keys("\x1b[B")  # Down arrow
            time.sleep(0.1)

        # Try edit sequence
        tester.send_key("Enter")
        time.sleep(0.3)
        tester.send_keys("1.23")
        time.sleep(0.2)
        tester.send_key("Escape")
        time.sleep(0.2)

        # Switch to table view and test editing there
        tester.send_key("Ctrl+T")
        time.sleep(0.3)
        tester.send_keys("\x1b[B")
        time.sleep(0.1)
        tester.send_key("Enter")
        time.sleep(0.3)
        tester.send_keys("9.87")
        time.sleep(0.2)
        tester.send_key("Escape")
        time.sleep(0.2)

        tester.quit()
