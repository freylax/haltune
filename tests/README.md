# Test Suite

This directory contains the Python test suite for haltune.

## Running Tests

### All tests
```bash
cd tests
pytest
```

### Specific test file
```bash
pytest test_bridge.py
```

### Skip slow tests
```bash
pytest -m "not slow"
```

### Run only local tests
```bash
pytest -m "not bridge and not tui and not hal and not ssh"
```

## Test Organization

- `lib/` - Helper modules
  - `bridge_client.py` - HAL bridge server communication
  - `ssh_client.py` - SSH operations for remote testing
  - `tui_helpers.py` - TUI testing with pexpect
  - `hal_helpers.py` - HAL component creation
  - `config.py` - Configuration loading

- `test_bridge.py` - Bridge server tests
- `test_tui.py` - TUI interaction tests
- `test_build.py` - Build verification tests

## Configuration

Edit `config/test_config.toml` to customize:
- Hostnames and paths
- Timeout values
- SSH settings

## Remote Testing

To run tests on remote host (pib):
```bash
pytest -m ssh
```

Requires SSH key authentication configured.
