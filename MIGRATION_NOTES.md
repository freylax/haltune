# Test Migration Notes

Bash scripts migrated to Python:

- `test_bridge_comprehensive.sh` → `tests/test_bridge.py`
- `test_tui_comprehensive.js` → `tests/test_tui.py`
- `test_tui_pexpect.py` → `tests/test_tui.py`
- `tests/tui_test.py` → `tests/test_tui.py`
- `test_remote_hal.py` → `tests/test_bridge.py`

## New Test Infrastructure

- **Helper modules**: `tests/lib/` (bridge_client, ssh_client, tui_helpers, hal_helpers, config)
- **Test files**: `tests/test_bridge.py`, `tests/test_tui.py`, `tests/test_build.py`
- **Configuration**: `tests/config/test_config.toml`
- **Requirements**: `tests/requirements.txt`, `tests/requirements-dev.txt`
- **Pytest configuration**: `tests/pytest.ini`, `tests/conftest.py`

## Running Tests

```bash
cd tests
pytest
```

See `tests/README.md` for detailed documentation.

## Removed Scripts

The following deprecated scripts have been removed after migration:

- `test_bridge_comprehensive.sh` - Bash script for bridge server testing
- `test_tui_comprehensive.js` - Node.js script for TUI testing
- `test_tui_pexpect.py` - Standalone pexpect-based TUI test script
- `test_remote_hal.py` - Standalone remote HAL testing script

## Retained Scripts

The following development helper scripts are retained in `tests/`:

- `tui_dev.sh`, `tui_dev_shell.sh`, `tui_dev_hal.sh` - TUI development helpers
- `tui_interactive.py`, `tui_interactive.sh` - Interactive TUI testing tools
- `test_haltune_components.sh` - Component testing script
- `test_component_pin.py` - Remote pin testing script (for pib/cnc)
