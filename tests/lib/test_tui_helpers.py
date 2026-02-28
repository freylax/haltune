# tests/lib/test_tui_helpers.py
import pytest
from lib.tui_helpers import TUITester

@pytest.mark.skipif(True, reason="TUI test - requires haltune binary")
def test_tui_tester_instantiation():
    tester = TUITester("echo hello")
    assert tester.child is not None
    tester.quit()

def test_tui_tester_with_echo():
    """Test TUITester with simple echo command."""
    tester = TUITester("echo hello")
    assert tester.child is not None

    # Should find the output
    result = tester.wait_for_text("hello")
    assert result is True

    tester.quit()

def test_tui_tester_wait_for_text_timeout():
    """Test TUITester wait_for_text handles missing text."""
    # Use cat to keep process alive
    tester = TUITester("cat")

    # Should not find text that isn't there
    result = tester.wait_for_text("neverappears", timeout=1)
    assert result is False

    # Failed count should increment
    assert tester.failed == 1

    # Send Ctrl+c to quit
    tester.send_key("Ctrl+c")
    tester.quit()

def test_tui_tester_send_key():
    """Test TUITester send_key methods."""
    tester = TUITester("cat")
    assert tester.child is not None

    # Test various key sends
    tester.send_key("Enter")
    tester.send_key("Escape")
    tester.send_key("Tab")
    tester.send_key("Space")
    tester.send_key("a")
    tester.send_key("Ctrl+c")

    tester.quit()

def test_tui_tester_wait_for_idle():
    """Test TUITester wait_for_idle method."""
    tester = TUITester("echo hello")
    assert tester.child is not None

    # Should sleep and return True
    result = tester.wait_for_idle(idle_ms=10)
    assert result is True

    tester.quit()

def test_tui_tester_get_screen():
    """Test TUITester get_screen method."""
    tester = TUITester("echo hello")

    # Wait for something to be in output
    tester.wait_for_text("hello", timeout=2)

    screen = tester.get_screen()
    assert screen is not None

    tester.quit()

def test_tui_tester_report():
    """Test TUITester report method."""
    tester = TUITester("cat")

    # Initial state
    passed, failed = tester.report()
    assert passed == 0
    assert failed == 0

    # After failed wait
    tester.wait_for_text("neverappears", timeout=1)
    passed, failed = tester.report()
    assert passed == 0
    assert failed == 1

    # After successful wait
    tester.send_keys("hello\n")
    tester.wait_for_text("hello", timeout=2)
    passed, failed = tester.report()
    assert passed == 1
    assert failed == 1

    tester.send_key("Ctrl+c")
    tester.quit()
