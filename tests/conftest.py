"""Pytest configuration and shared fixtures."""

import pytest
import socket
from pathlib import Path

def pytest_configure(config):
    """Configure pytest markers."""
    config.addinivalue_line("markers", "slow: marks tests as slow")
    config.addinivalue_line("markers", "bridge: tests requiring bridge server")
    config.addinivalue_line("markers", "tui: tests requiring TUI")
    config.addinivalue_line("markers", "hal: tests requiring HAL")
    config.addinivalue_line("markers", "ssh: tests requiring SSH")

def pytest_collection_modifyitems(config, items):
    """Add markers based on test requirements."""

    def is_bridge_available():
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.settimeout(1.0)
                s.connect(("localhost", 8765))
            return True
        except (socket.timeout, ConnectionRefusedError):
            return False

    def is_halrun_available():
        import shutil
        return shutil.which("halrun") is not None

    def is_haltune_built():
        # Check in both project root and tests directory
        project_root = Path(__file__).parent.parent
        paths = [
            project_root / "zig-out" / "bin" / "haltune",
            Path("./zig-out/bin/haltune"),
        ]
        return any(p.exists() for p in paths)

    for item in items:
        # Auto-detect bridge tests
        if "bridge_client" in str(item.fspath) or "test_bridge.py" in str(item.fspath):
            item.add_marker(pytest.mark.bridge)
            if not is_bridge_available():
                item.add_marker(pytest.mark.skip(reason="Bridge server not running"))

        # Auto-detect TUI tests
        if "tui" in str(item.fspath) or "tui_helpers" in str(item.fspath):
            item.add_marker(pytest.mark.tui)
            if not is_haltune_built():
                item.add_marker(pytest.mark.skip(reason="haltune not built"))

        # Auto-detect HAL tests
        if "hal_helpers" in str(item.fspath):
            item.add_marker(pytest.mark.hal)
            if not is_halrun_available():
                item.add_marker(pytest.mark.skip(reason="halrun not available"))
