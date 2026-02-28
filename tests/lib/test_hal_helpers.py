# tests/lib/test_hal_helpers.py
import pytest
from lib.hal_helpers import HalRunInstance

@pytest.mark.skipif(True, reason="HAL test - requires halrun")
def test_halrun_start_stop():
    hal = HalRunInstance()
    hal.start()
    assert hal.is_running()
    hal.stop()

@pytest.mark.skipif(True, reason="HAL test - requires halrun")
def test_halrun_send_command():
    hal = HalRunInstance()
    hal.start()
    assert hal.is_running()
    # Send a simple help command - should not raise
    hal.send_command("help")
    hal.stop()

@pytest.mark.skipif(True, reason="HAL test - requires halrun")
def test_halrun_create_signal():
    hal = HalRunInstance()
    hal.start()
    assert hal.is_running()
    # Create a signal - API check only
    result = hal.create_signal("test_signal", "float")
    assert result is True
    hal.stop()

def test_halrun_not_running_error():
    """Test that send_command raises when not running."""
    hal = HalRunInstance()
    with pytest.raises(RuntimeError, match="halrun not running"):
        hal.send_command("help")
