# Python Test Migration Design

**Date:** 2025-02-28
**Status:** Approved
**Author:** Claude Code

## Overview

Migrate all bash test scripts to Python for improved reliability, portability, and code reusability. The new infrastructure will support both local and remote testing scenarios with modular helper libraries.

## Goals

1. **Reliability**: Python's structured error handling and type safety reduce flaky tests
2. **Portability**: Tests run on local machine and remote (pib) via SSH
3. **Reusability**: Common functionality extracted into modules
4. **Maintainability**: Single language (Python) for all test infrastructure

## Directory Structure

```
tests/
├── config/
│   └── test_config.toml          # Test configuration (hosts, paths, timeouts)
├── lib/
│   ├── __init__.py
│   ├── bridge_client.py          # HAL bridge server communication
│   ├── ssh_client.py             # SSH operations for remote testing
│   ├── tui_helpers.py            # TUI testing utilities (pexpect)
│   └── hal_helpers.py            # HAL component/signal creation helpers
├── test_bridge.py                # HAL bridge server tests
├── test_tui.py                   # TUI interaction tests
└── test_build.py                 # Build and setup tests
```

## Configuration Module

**File:** `tests/config/test_config.toml`

```toml
[test]
# Default timeout for test operations (seconds)
timeout = 30
# Enable debug output
verbose = true

[hosts.local]
# Local machine settings
haltune_binary = "./zig-out/bin/haltune"
bridge_host = "localhost"
bridge_port = 8765

[hosts.pib]
# Remote pib settings
hostname = "pib"
user = "cnc"
haltune_binary = "/home/cnc/prog/haltune/zig-out/bin/haltune"
bridge_host = "localhost"
bridge_port = 8765
# SSH key path (null = use default agent)
ssh_key = null

[tests]
# Specific test configurations
tui.startup_timeout = 10
bridge.connect_timeout = 5
build.timeout = 120
```

## Core Helper Modules

### Bridge Client (`tests/lib/bridge_client.py`)

```python
"""HAL bridge server communication client."""

import socket
import json
from dataclasses import dataclass
from typing import Any, Optional

@dataclass
class BridgeResponse:
    success: bool
    data: dict[str, Any]
    error: Optional[str] = None

class BridgeClient:
    def __init__(self, host: str, port: int, timeout: float = 5.0):
        self.host = host
        self.port = port
        self.timeout = timeout

    def send_request(self, request: dict[str, Any]) -> BridgeResponse:
        """Send JSON request and parse response."""
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(self.timeout)
            s.connect((self.host, self.port))
            s.sendall(json.dumps(request).encode() + b"\n")
            response = json.loads(s.recv(65536).decode())
        return BridgeResponse(
            success=response.get("type") != "error",
            data=response,
            error=response.get("error")
        )

    def ping(self) -> bool:
        return self.send_request({"type": "ping"}).success

    def list_pins(self) -> list[dict]:
        return self.send_request({"type": "list_pins"}).data.get("pins", [])
```

### SSH Client (`tests/lib/ssh_client.py`)

```python
"""SSH operations for remote testing."""

import paramiko
from typing import Optional

class SSHClient:
    def __init__(self, hostname: str, user: str, key_path: Optional[str] = None):
        self.client = paramiko.SSHClient()
        self.client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        self.hostname = hostname
        self.user = user
        self.key_path = key_path

    def connect(self):
        self.client.connect(
            self.hostname,
            username=self.user,
            key_filename=self.key_path
        )

    def run_command(self, command: str) -> tuple[int, str, str]:
        stdin, stdout, stderr = self.client.exec_command(command)
        exit_code = stdout.channel.recv_exit_status()
        return exit_code, stdout.read().decode(), stderr.read().decode()

    def close(self):
        self.client.close()
```

### TUI Helpers (`tests/lib/tui_helpers.py`)

```python
"""TUI testing utilities using pexpect."""

import pexpect
from typing import Optional

class TUITester:
    def __init__(self, command: str, dimensions: tuple[int, int] = (80, 24)):
        self.child = pexpect.spawn(command, dimensions=dimensions, encoding="utf-8")
        self.passed = 0
        self.failed = 0

    def wait_for_text(self, text: str, timeout: int = 5) -> bool:
        try:
            self.child.expect(text, timeout=timeout)
            return True
        except pexpect.TIMEOUT:
            return False

    def send_keys(self, keys: str):
        self.child.send(keys)

    def quit(self):
        self.child.send("q")
        self.child.expect(pexpect.EOF, timeout=2)

    def report(self) -> tuple[int, int]:
        return self.passed, self.failed
```

### HAL Helpers (`tests/lib/hal_helpers.py`)

```python
"""HAL component and signal creation helpers."""

import subprocess
import time

class HalRunInstance:
    def __init__(self):
        self.proc: Optional[subprocess.Popen] = None

    def start(self):
        self.proc = subprocess.Popen(
            ["halrun", "-s"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        time.sleep(0.5)  # Wait for startup

    def loadrt(self, component: str, args: str = ""):
        cmd = f"loadrt {component}"
        if args:
            cmd += f" {args}"
        self.proc.stdin.write(cmd + "\n")
        self.proc.stdin.flush()

    def create_signal(self, name: str, pin_type: str) -> bool:
        cmd = f"newsig {name} {pin_type}"
        self.proc.stdin.write(cmd + "\n")
        self.proc.stdin.flush()
        return self.check_success()

    def check_success(self) -> bool:
        # Check last command output for errors
        return True

    def stop(self):
        if self.proc:
            self.proc.stdin.write("exit\n")
            self.proc.stdin.flush()
            self.proc.wait(timeout=2)
```

## Test File Structure Pattern

```python
"""Test suite example using pytest."""

import pytest
from pathlib import Path
from lib.bridge_client import BridgeClient
from lib.config import load_config

@pytest.fixture
def config():
    return load_config(Path(__file__).parent / "config" / "test_config.toml")

@pytest.fixture
def bridge_client(config):
    client = BridgeClient(
        host=config.hosts["local"].bridge_host,
        port=config.hosts["local"].bridge_port
    )
    yield client

class TestBridgeServer:
    def test_ping(self, bridge_client):
        assert bridge_client.ping() == True

    @pytest.mark.parametrize("pin_name", ["pid.Pgain", "pid.enable"])
    def test_get_pin_value(self, bridge_client, pin_name):
        pins = bridge_client.list_pins()
        pin = next((p for p in pins if p["name"] == pin_name), None)
        assert pin is not None

    def test_set_pin_value(self, bridge_client):
        result = bridge_client.set_pin("pid.Pgain", 2.0)
        assert result.success
```

## Local vs Remote Testing

Tests detect environment and route accordingly:

```python
def get_test_mode() -> str:
    """Detect if running on local machine or pib."""
    import socket
    return socket.gethostname()

def run_test_on_host(test_func, host: str):
    """Run test locally or via SSH based on host."""
    if host == "local" or get_test_mode() == host:
        return test_func()
    else:
        # Use SSH to run on remote host
        with SSHClient(host) as ssh:
            return ssh.run_remote_test(test_func)
```

## Test Migration Mapping

| Bash Script | Python Test | Description |
|-------------|-------------|-------------|
| `test_bridge_comprehensive.sh` | `tests/test_bridge.py` | 14 test cases for bridge server |
| `test_tui_comprehensive.js` | `tests/test_tui.py` | TUI navigation and interaction |
| `test_tui_pexpect.py` | `tests/test_tui.py` | Merge with comprehensive |
| `tests/tui_test.py` | `tests/test_tui.py` | Merge with comprehensive |
| `test_remote_hal.py` | `tests/test_bridge.py` | Merge remote bridge tests |
| Build/deploy scripts | `tests/test_build.py` | New build verification tests |

## Implementation Order

1. Configuration module and TOML
2. Core helper modules (bridge, ssh, tui, hal)
3. Bridge server test migration
4. TUI test migration
5. Build test creation
6. Documentation updates
7. Remove deprecated bash scripts

## Success Criteria

- All bash scripts migrated to Python
- Tests pass on both local and pib
- Code coverage maintained or improved
- Documentation updated
- CI/CD integration working
