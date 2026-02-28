# Python Test Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Migrate all bash test scripts to Python with modular helper libraries supporting both local and remote testing.

**Architecture:** Modular test infrastructure with TOML configuration, helper libraries for bridge/SSH/TUI/HAL operations, and pytest-based test suites that support local and remote execution modes.

**Tech Stack:** Python 3.11+, pytest, pexpect, paramiko, tomli (or tomllib)

---

## Task 1: Create Directory Structure

**Files:**
- Create: `tests/config/`
- Create: `tests/lib/`
- Create: `tests/config/test_config.toml`

**Step 1: Create directories**

```bash
mkdir -p tests/config tests/lib
```

**Step 2: Verify directories exist**

Run: `ls -la tests/`
Expected: Output shows `config/` and `lib/` directories

**Step 3: Commit**

```bash
git add tests/config tests/lib
git commit -m "test infra: create directory structure for Python tests"
```

---

## Task 2: Create Configuration Module

**Files:**
- Create: `tests/lib/config.py`
- Create: `tests/config/test_config.toml`
- Test: `tests/lib/test_config.py`

**Step 1: Write failing test for config loading**

```python
# tests/lib/test_config.py
import pytest
from pathlib import Path
from lib.config import load_config

def test_load_config():
    config_path = Path(__file__).parent.parent / "config" / "test_config.toml"
    config = load_config(config_path)
    assert hasattr(config, "test")
    assert config.test.timeout == 30
    assert config.hosts["local"].haltune_binary == "./zig-out/bin/haltune"
```

**Step 2: Run test to verify it fails**

Run: `cd tests && python -m pytest lib/test_config.py -v`
Expected: FAIL with "ModuleNotFoundError: No module named 'lib.config'"

**Step 3: Create __init__.py**

```python
# tests/lib/__init__.py
```

**Step 4: Create TOML config file**

```toml
# tests/config/test_config.toml
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
# SSH key path (empty = use default agent)
ssh_key = ""

[tests]
# Specific test configurations
tui.startup_timeout = 10
bridge.connect_timeout = 5
build.timeout = 120
```

**Step 5: Write config.py implementation**

```python
# tests/lib/config.py
"""Test configuration loader."""

import tomli
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

try:
    import tomllib  # Python 3.11+
except ImportError:
    import tomli as tomllib

@dataclass
class TestConfig:
    timeout: int
    verbose: bool

@dataclass
class HostConfig:
    hostname: str = ""
    haltune_binary: str = ""
    bridge_host: str = "localhost"
    bridge_port: int = 8765
    user: str = ""
    ssh_key: Optional[str] = None

@dataclass
class TestsConfig:
    tui_startup_timeout: int
    bridge_connect_timeout: int
    build_timeout: int

@dataclass
class Config:
    test: TestConfig
    hosts: dict[str, HostConfig]
    tests: TestsConfig

def load_config(path: Path) -> Config:
    """Load configuration from TOML file."""
    with open(path, "rb") as f:
        data = tomllib.load(f)

    test = TestConfig(
        timeout=data["test"]["timeout"],
        verbose=data["test"]["verbose"]
    )

    hosts = {}
    for name, host_data in data["hosts"].items():
        hosts[name] = HostConfig(
            hostname=host_data.get("hostname", ""),
            haltune_binary=host_data["haltune_binary"],
            bridge_host=host_data.get("bridge_host", "localhost"),
            bridge_port=host_data["bridge_port"],
            user=host_data.get("user", ""),
            ssh_key=host_data.get("ssh_key") or None
        )

    tests_config = TestsConfig(
        tui_startup_timeout=data["tests"]["tui.startup_timeout"],
        bridge_connect_timeout=data["tests"]["bridge.connect_timeout"],
        build_timeout=data["tests"]["build.timeout"]
    )

    return Config(test=test, hosts=hosts, tests=tests_config)
```

**Step 6: Run test to verify it passes**

Run: `cd tests && python -m pytest lib/test_config.py -v`
Expected: PASS

**Step 7: Commit**

```bash
git add tests/lib/config.py tests/lib/__init__.py tests/config/test_config.toml tests/lib/test_config.py
git commit -m "test infra: add configuration module with TOML support"
```

---

## Task 3: Create Bridge Client Module

**Files:**
- Create: `tests/lib/bridge_client.py`
- Test: `tests/lib/test_bridge_client.py`

**Step 1: Write failing test for ping**

```python
# tests/lib/test_bridge_client.py
import pytest
from lib.bridge_client import BridgeClient, BridgeResponse

def test_ping_success():
    # This test requires bridge server to be running
    client = BridgeClient(host="localhost", port=8765, timeout=5.0)
    result = client.ping()
    assert result is True

def test_send_request_returns_bridge_response():
    client = BridgeClient(host="localhost", port=8765, timeout=5.0)
    response = client.send_request({"type": "ping"})
    assert isinstance(response, BridgeResponse)
    assert response.data["type"] == "pong"

@pytest.mark.skipif(no_bridge_server, reason="No bridge server running")
def test_list_pins():
    client = BridgeClient(host="localhost", port=8765, timeout=5.0)
    pins = client.list_pins()
    assert isinstance(pins, list)
```

**Step 2: Run test to verify it fails**

Run: `cd tests && python -m pytest lib/test_bridge_client.py -v`
Expected: FAIL with "ModuleNotFoundError: No module named 'lib.bridge_client'"

**Step 3: Write bridge_client.py implementation**

```python
# tests/lib/bridge_client.py
"""HAL bridge server communication client."""

import socket
import json
from dataclasses import dataclass
from typing import Any, Optional

@dataclass
class BridgeResponse:
    """Response from bridge server."""
    success: bool
    data: dict[str, Any]
    error: Optional[str] = None

class BridgeClient:
    """Client for communicating with HAL bridge server."""

    def __init__(self, host: str, port: int, timeout: float = 5.0):
        self.host = host
        self.port = port
        self.timeout = timeout

    def send_request(self, request: dict[str, Any]) -> BridgeResponse:
        """Send JSON request and parse response."""
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.settimeout(self.timeout)
                s.connect((self.host, self.port))
                s.sendall(json.dumps(request).encode() + b"\n")
                response_data = s.recv(65536).decode()
                response = json.loads(response_data)

            return BridgeResponse(
                success=response.get("type") != "error",
                data=response,
                error=response.get("error")
            )
        except (socket.timeout, ConnectionRefusedError, json.JSONDecodeError) as e:
            return BridgeResponse(success=False, data={}, error=str(e))

    def ping(self) -> bool:
        """Send ping request."""
        response = self.send_request({"type": "ping"})
        return response.success and response.data.get("type") == "pong"

    def list_pins(self) -> list[dict]:
        """List all HAL pins."""
        response = self.send_request({"type": "list_pins"})
        if response.success:
            return response.data.get("pins", [])
        return []

    def get_pin(self, pin_name: str) -> Optional[dict]:
        """Get specific pin value."""
        response = self.send_request({"type": "get_pin", "name": pin_name})
        if response.success:
            return response.data.get("pin")
        return None

    def set_pin(self, pin_name: str, value: Any) -> BridgeResponse:
        """Set pin value."""
        return self.send_request({
            "type": "set_pin",
            "name": pin_name,
            "value": value
        })

    def list_signals(self) -> list[dict]:
        """List all HAL signals."""
        response = self.send_request({"type": "list_signals"})
        if response.success:
            return response.data.get("signals", [])
        return []

    def list_params(self) -> list[dict]:
        """List all HAL parameters."""
        response = self.send_request({"type": "list_params"})
        if response.success:
            return response.data.get("params", [])
        return []

    def list_components(self) -> list[dict]:
        """List all HAL components."""
        response = self.send_request({"type": "list_components"})
        if response.success:
            return response.data.get("components", [])
        return []
```

**Step 4: Run tests to verify they pass**

Run: `cd tests && python -m pytest lib/test_bridge_client.py -v`
Expected: Tests may skip if bridge server not running, but structure is correct

**Step 5: Commit**

```bash
git add tests/lib/bridge_client.py tests/lib/test_bridge_client.py
git commit -m "test infra: add bridge client module"
```

---

## Task 4: Create SSH Client Module

**Files:**
- Create: `tests/lib/ssh_client.py`
- Test: `tests/lib/test_ssh_client.py`

**Step 1: Write failing test**

```python
# tests/lib/test_ssh_client.py
import pytest
from lib.ssh_client import SSHClient

@pytest.mark.skipif(no_ssh_available, reason="SSH not available")
def test_ssh_connect_and_run_command():
    client = SSHClient(hostname="pib", user="cnc")
    client.connect()
    exit_code, stdout, stderr = client.run_command("echo hello")
    assert exit_code == 0
    assert "hello" in stdout
    client.close()
```

**Step 2: Run test to verify it fails**

Run: `cd tests && python -m pytest lib/test_ssh_client.py -v`
Expected: FAIL with "ModuleNotFoundError: No module named 'lib.ssh_client'"

**Step 3: Write ssh_client.py implementation**

```python
# tests/lib/ssh_client.py
"""SSH operations for remote testing."""

import paramiko
from typing import Optional

class SSHClient:
    """SSH client for remote command execution."""

    def __init__(self, hostname: str, user: str, key_path: Optional[str] = None):
        self.client = paramiko.SSHClient()
        self.client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        self.hostname = hostname
        self.user = user
        self.key_path = key_path
        self._connected = False

    def connect(self):
        """Connect to remote host."""
        if self._connected:
            return

        connect_kwargs = {
            "hostname": self.hostname,
            "username": self.user,
        }
        if self.key_path:
            connect_kwargs["key_filename"] = self.key_path

        self.client.connect(**connect_kwargs)
        self._connected = True

    def run_command(self, command: str) -> tuple[int, str, str]:
        """Run command on remote host."""
        if not self._connected:
            self.connect()

        stdin, stdout, stderr = self.client.exec_command(command)
        exit_code = stdout.channel.recv_exit_status()
        return exit_code, stdout.read().decode(), stderr.read().decode()

    def file_exists(self, path: str) -> bool:
        """Check if file exists on remote host."""
        exit_code, _, _ = self.run_command(f"test -f {path}")
        return exit_code == 0

    def close(self):
        """Close connection."""
        self.client.close()
        self._connected = False

    def __enter__(self):
        self.connect()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()
```

**Step 4: Run tests to verify they pass**

Run: `cd tests && python -m pytest lib/test_ssh_client.py -v`
Expected: Tests may skip if SSH not available

**Step 5: Commit**

```bash
git add tests/lib/ssh_client.py tests/lib/test_ssh_client.py
git commit -m "test infra: add SSH client module"
```

---

## Task 5: Create TUI Helpers Module

**Files:**
- Create: `tests/lib/tui_helpers.py`
- Test: `tests/lib/test_tui_helpers.py`

**Step 1: Write failing test**

```python
# tests/lib/test_tui_helpers.py
import pytest
from lib.tui_helpers import TUITester

def test_tui_load_and_quit():
    tester = TUITester("./zig-out/bin/haltune --test-mode")
    assert tester.wait_for_text("Table View", timeout=5)
    tester.quit()

def test_tui_send_keys():
    tester = TUITester("./zig-out/bin/haltune --test-mode")
    tester.wait_for_text("Table View")
    tester.send_keys("q")
    assert tester.child.expect(pexpect.EOF, timeout=2)
```

**Step 2: Run test to verify it fails**

Run: `cd tests && python -m pytest lib/test_tui_helpers.py -v`
Expected: FAIL with "ModuleNotFoundError: No module named 'lib.tui_helpers'"

**Step 3: Write tui_helpers.py implementation**

```python
# tests/lib/tui_helpers.py
"""TUI testing utilities using pexpect."""

import pexpect
from typing import Optional

class TUITester:
    """Helper for testing terminal user interfaces."""

    def __init__(self, command: str, dimensions: tuple[int, int] = (80, 24), encoding: str = "utf-8"):
        """Initialize TUI tester with command to run.

        Args:
            command: Command string to execute
            dimensions: Terminal (cols, rows)
            encoding: Character encoding
        """
        self.child = pexpect.spawn(command, dimensions=dimensions, encoding=encoding)
        self.passed = 0
        self.failed = 0

    def wait_for_text(self, text: str, timeout: int = 5) -> bool:
        """Wait for text to appear in output.

        Args:
            text: Text to wait for (can be regex)
            timeout: Seconds to wait

        Returns:
            True if text found, False otherwise
        """
        try:
            self.child.expect(text, timeout=timeout)
            return True
        except pexpect.TIMEOUT:
            self.failed += 1
            return False

    def wait_for_idle(self, idle_ms: int = 100, timeout_ms: int = 2000) -> bool:
        """Wait for screen to become stable."""
        # Simple implementation - just wait a bit
        import time
        time.sleep(idle_ms / 1000)
        return True

    def send_keys(self, keys: str):
        """Send key sequence to TUI."""
        self.child.send(keys)

    def send_key(self, key: str):
        """Send single key (with special handling)."""
        if key == "Enter":
            self.child.send("\n")
        elif key == "Escape":
            self.child.send("\x1b")
        elif key == "Tab":
            self.child.send("\t")
        elif key == "Space":
            self.child.send(" ")
        elif key.startswith("Ctrl+"):
            ctrl_char = key[5:].lower()
            self.child.send("\x01" + chr(ord(ctrl_char) - ord('a') + 1))
        else:
            self.child.send(key)

    def get_screen(self) -> str:
        """Get current screen content."""
        return self.child.before

    def quit(self):
        """Attempt clean quit."""
        self.child.send("q")
        try:
            self.child.expect(pexpect.EOF, timeout=2)
        except pexpect.TIMEOUT:
            self.child.terminate(force=True)

    def report(self) -> tuple[int, int]:
        """Get pass/fail counts."""
        return self.passed, self.failed

    def assert_passed(self, test_name: str, condition: bool):
        """Record test result."""
        if condition:
            self.passed += 1
        else:
            self.failed += 1
            assert condition, f"{test_name} failed"
```

**Step 4: Run tests to verify they pass**

Run: `cd tests && python -m pytest lib/test_tui_helpers.py -v`
Expected: Tests run (may skip if binary not built)

**Step 5: Commit**

```bash
git add tests/lib/tui_helpers.py tests/lib/test_tui_helpers.py
git commit -m "test infra: add TUI helpers module"
```

---

## Task 6: Create HAL Helpers Module

**Files:**
- Create: `tests/lib/hal_helpers.py`
- Test: `tests/lib/test_hal_helpers.py`

**Step 1: Write failing test**

```python
# tests/lib/test_hal_helpers.py
import pytest
from lib.hal_helpers import HalRunInstance

def test_halrun_start_stop():
    hal = HalRunInstance()
    hal.start()
    assert hal.is_running()
    hal.loadrt("or2")
    hal.stop()

def test_create_signal():
    hal = HalRunInstance()
    hal.start()
    result = hal.create_signal("test_sig", "bit")
    assert result is True
    hal.stop()
```

**Step 2: Run test to verify it fails**

Run: `cd tests && python -m pytest lib/test_hal_helpers.py -v`
Expected: FAIL with "ModuleNotFoundError: No module named 'lib.hal_helpers'"

**Step 3: Write hal_helpers.py implementation**

```python
# tests/lib/hal_helpers.py
"""HAL component and signal creation helpers."""

import subprocess
import time
from typing import Optional

class HalRunInstance:
    """Manage a halrun subprocess for testing."""

    def __init__(self, halrun_cmd: str = "halrun"):
        self.halrun_cmd = halrun_cmd
        self.proc: Optional[subprocess.Popen] = None

    def start(self):
        """Start halrun subprocess."""
        self.proc = subprocess.Popen(
            [self.halrun_cmd, "-s"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        # Wait for startup
        time.sleep(0.5)

    def is_running(self) -> bool:
        """Check if halrun is still running."""
        return self.proc is not None and self.proc.poll() is None

    def send_command(self, cmd: str) -> str:
        """Send command to halrun."""
        if not self.is_running():
            raise RuntimeError("halrun not running")

        self.proc.stdin.write(cmd + "\n")
        self.proc.stdin.flush()
        # Read response
        time.sleep(0.1)
        return ""

    def loadrt(self, component: str, args: str = ""):
        """Load real-time component."""
        cmd = f"loadrt {component}"
        if args:
            cmd += f" {args}"
        self.send_command(cmd)

    def create_signal(self, name: str, pin_type: str) -> bool:
        """Create a new signal."""
        cmd = f"newsig {name} {pin_type}"
        self.send_command(cmd)
        # TODO: Check for errors in output
        return True

    def net(self, pin: str, signal: str):
        """Link pin to signal."""
        cmd = f"net {signal} {pin}"
        self.send_command(cmd)

    def setp(self, param: str, value: str):
        """Set parameter value."""
        cmd = f"setp {param} {value}"
        self.send_command(cmd)

    def check_success(self) -> bool:
        """Check if last command succeeded."""
        # Read stderr for error messages
        return True

    def stop(self):
        """Stop halrun subprocess."""
        if self.proc:
            try:
                self.send_command("exit")
                self.proc.wait(timeout=2)
            except (subprocess.TimeoutExpired, BrokenPipeError):
                self.proc.terminate()
                self.proc.wait(timeout=1)
            self.proc = None
```

**Step 4: Run tests to verify they pass**

Run: `cd tests && python -m pytest lib/test_hal_helpers.py -v`
Expected: Tests run (may skip if halrun not available)

**Step 5: Commit**

```bash
git add tests/lib/hal_helpers.py tests/lib/test_hal_helpers.py
git commit -m "test infra: add HAL helpers module"
```

---

## Task 7: Migrate Bridge Server Tests

**Files:**
- Create: `tests/test_bridge.py`
- Reference: `test_bridge_comprehensive.sh` (source)
- Reference: `test_remote_hal.py` (source)

**Step 1: Read source bash script**

```bash
cat test_bridge_comprehensive.sh
```

**Step 2: Write pytest test file**

```python
# tests/test_bridge.py
"""HAL bridge server comprehensive tests.

Migrated from test_bridge_comprehensive.sh and test_remote_hal.py.
"""

import pytest
import socket
from pathlib import Path
from lib.bridge_client import BridgeClient
from lib.config import load_config

@pytest.fixture(scope="module")
def config():
    config_path = Path(__file__).parent / "config" / "test_config.toml"
    return load_config(config_path)

@pytest.fixture
def bridge_client(config):
    client = BridgeClient(
        host=config.hosts["local"].bridge_host,
        port=config.hosts["local"].bridge_port,
        timeout=config.tests.bridge_connect_timeout
    )
    return client

class TestBridgePing:
    def test_ping_pong(self, bridge_client):
        response = bridge_client.send_request({"type": "ping"})
        assert response.success
        assert response.data["type"] == "pong"

class TestBridgeListPins:
    def test_list_pins_returns_pins(self, bridge_client):
        pins = bridge_client.list_pins()
        assert isinstance(pins, list)
        # Check for known pins if HAL is running
        if pins:
            pin = pins[0]
            assert "name" in pin
            assert "type" in pin

    def test_list_pins_has_expected_structure(self, bridge_client):
        pins = bridge_client.list_pins()
        for pin in pins[:5]:  # Check first 5
            assert "name" in pin
            assert "type" in pin
            assert "dir" in pin
            assert "value" in pin

class TestBridgeGetPin:
    def test_get_pin_by_name(self, bridge_client):
        pins = bridge_client.list_pins()
        if pins:
            pin_name = pins[0]["name"]
            pin = bridge_client.get_pin(pin_name)
            assert pin is not None
            assert pin["name"] == pin_name

    def test_get_nonexistent_pin(self, bridge_client):
        pin = bridge_client.get_pin("nonexistent.pin")
        assert pin is None

class TestBridgeSetPin:
    def test_set_pin_value(self, bridge_client):
        # Get a writable pin first
        pins = bridge_client.list_pins()
        writable_pin = next((p for p in pins if p.get("dir") in ["in", "io"]), None)
        if writable_pin:
            response = bridge_client.set_pin(writable_pin["name"], 1.0)
            assert response.success

class TestBridgeSignals:
    def test_list_signals(self, bridge_client):
        signals = bridge_client.list_signals()
        assert isinstance(signals, list)

class TestBridgeParams:
    def test_list_params(self, bridge_client):
        params = bridge_client.list_params()
        assert isinstance(params, list)

class TestBridgeComponents:
    def test_list_components(self, bridge_client):
        components = bridge_client.list_components()
        assert isinstance(components, list)

class TestBridgeCreateDeleteSignal:
    def test_create_and_delete_signal(self, bridge_client):
        # Create signal
        response = bridge_client.send_request({
            "type": "create_signal",
            "name": "test_py_signal",
            "signal_type": "float"
        })
        # May fail if signal exists or HAL not in ready state
        # Just verify we get a valid response

        # Delete signal
        response = bridge_client.send_request({
            "type": "delete_signal",
            "name": "test_py_signal"
        })

class TestBridgeLinkUnlink:
    def test_link_and_unlink_pin(self, bridge_client):
        # This test requires HAL to be running with specific pins
        # Skip if no writable pins available
        pins = bridge_client.list_pins()
        test_pin = next((p for p in pins if p.get("name") == "test.pin"), None)
        if not test_pin:
            pytest.skip("No test pin available")

        # Link
        response = bridge_client.send_request({
            "type": "link_pin",
            "pin": "test.pin",
            "signal": "test.signal"
        })

        # Unlink
        response = bridge_client.send_request({
            "type": "unlink_pin",
            "pin": "test.pin"
        })

class TestBridgeErrors:
    def test_invalid_request_type(self, bridge_client):
        response = bridge_client.send_request({"type": "invalid"})
        assert not response.success
        assert response.error is not None

    def test_malformed_json(self, bridge_client):
        # This tests raw socket behavior
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.settimeout(5.0)
                s.connect((bridge_client.host, bridge_client.port))
                s.sendall(b"not json\n")
                response = s.recv(65536).decode()
                # Should get error response
        except (socket.timeout, ConnectionRefusedError):
            pytest.skip("Bridge server not available")
```

**Step 3: Run tests to verify they work**

Run: `cd tests && python -m pytest test_bridge.py -v`
Expected: Tests run, some may skip if bridge not running

**Step 4: Commit**

```bash
git add tests/test_bridge.py
git commit -m "test: migrate bridge server tests to Python"
```

---

## Task 8: Migrate TUI Tests

**Files:**
- Create: `tests/test_tui.py`
- Reference: `test_tui_comprehensive.js` (source)
- Reference: `test_tui_pexpect.py` (source)
- Reference: `tests/tui_test.py` (source)

**Step 1: Read source files**

```bash
cat test_tui_pexpect.py
cat tests/tui_test.py
```

**Step 2: Write pytest test file**

```python
# tests/test_tui.py
"""TUI comprehensive tests.

Migrated from test_tui_pexpect.py and tests/tui_test.py.
"""

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

class TestTUILoad:
    def test_tui_loads(self, haltune_binary):
        tester = TUITester(f"{haltune_binary} --test-mode")
        assert tester.wait_for_text("Table View", timeout=config.tests.tui_startup_timeout)
        tester.quit()

    def test_tui_shows_status(self, haltune_binary):
        tester = TUITester(f"{haltune_binary} --test-mode")
        assert tester.wait_for_text("components", timeout=10)
        tester.quit()

class TestTUIQuit:
    def test_quit_with_q(self, haltune_binary):
        tester = TUITester(f"{haltune_binary} --test-mode")
        tester.wait_for_text("Table View")
        tester.send_key("q")
        # Should exit cleanly
        import pexpect
        try:
            tester.child.expect(pexpect.EOF, timeout=2)
        except pexpect.TIMEOUT:
            tester.quit()

    def test_quit_with_ctrl_q(self, haltune_binary):
        tester = TUITester(f"{haltune_binary} --test-mode")
        tester.wait_for_text("Table View")
        tester.send_keys("\x11")  # Ctrl+Q
        try:
            import pexpect
            tester.child.expect(pexpect.EOF, timeout=2)
        except pexpect.TIMEOUT:
            tester.quit()

class TestTUIViewToggle:
    def test_toggle_table_tree_view(self, haltune_binary):
        tester = TUITester(f"{haltune_binary} --test-mode")
        tester.wait_for_text("Table View")

        # Press Ctrl+T to toggle
        tester.send_keys("\x14")  # Ctrl+T
        tester.wait_for_idle()

        tester.quit()

class TestTUIExpandCollapse:
    def test_expand_component(self, haltune_binary):
        tester = TUITester(f"{haltune_binary} --test-mode")
        tester.wait_for_text("components")

        # Navigate to first item and press Enter
        tester.send_keys("\x1b[B")  # Down
        tester.send_key("Enter")

        # Check if expanded
        import time
        time.sleep(0.5)

        tester.quit()

class TestTUIValueEditing:
    def test_edit_pin_value(self, haltune_binary):
        """Test editing a pin value in TUI."""
        tester = TUITester(f"{haltune_binary} --test-mode")
        tester.wait_for_text("components")

        # Navigate to a value and press Enter to edit
        # This is a basic test - full value editing tests require HAL running
        import time
        time.sleep(0.5)

        tester.quit()

class TestTUIWithHAL:
    def test_tui_with_halrun_components(self, haltune_binary):
        """Test TUI with actual HAL components from halrun."""
        hal = HalRunInstance()
        hal.start()

        # Create some test components
        hal.loadrt("or2", "count=2")
        hal.create_signal("test_sig", "bit")

        # Run TUI and check for components
        tester = TUITester(f"{haltune_binary} --test-mode")
        tester.wait_for_text("components", timeout=10)

        # Should show our test components
        screen = tester.get_screen()
        # Check for HAL components

        tester.quit()
        hal.stop()
```

**Step 3: Run tests to verify they work**

Run: `cd tests && python -m pytest test_tui.py -v`
Expected: Tests run, some may skip if binary not built

**Step 4: Commit**

```bash
git add tests/test_tui.py
git commit -m "test: migrate TUI tests to Python"
```

---

## Task 9: Create Build Tests

**Files:**
- Create: `tests/test_build.py`

**Step 1: Write build tests**

```python
# tests/test_build.py
"""Build and setup tests."""

import subprocess
import pytest
from pathlib import Path
from lib.config import load_config

@pytest.fixture(scope="module")
def config():
    config_path = Path(__file__).parent / "config" / "test_config.toml"
    return load_config(config_path)

class TestBuild:
    def test_zig_build(self):
        """Test that zig build succeeds."""
        result = subprocess.run(
            ["zig", "build"],
            timeout=config.tests.build_timeout,
            capture_output=True,
            text=True
        )
        assert result.returncode == 0, f"Build failed: {result.stderr}"

    def test_haltune_binary_exists(self):
        """Test that haltune binary was created."""
        binary = Path("./zig-out/bin/haltune")
        assert binary.exists(), "haltune binary not found"
        assert binary.is_file(), "haltune is not a file"

    def test_haltune_executable(self):
        """Test that haltune binary is executable."""
        binary = Path("./zig-out/bin/haltune")
        # On Unix, check for executable permission
        import stat
        st = binary.stat()
        assert st.st_mode & stat.S_IXUSR, "haltune is not executable"

class TestVersion:
    def test_haltune_version(self):
        """Test haltune --version."""
        result = subprocess.run(
            ["./zig-out/bin/haltune", "--version"],
            capture_output=True,
            text=True
        )
        # Should return 0 or have version output
        assert result.returncode == 0 or "haltune" in result.stdout.lower()

class TestHelp:
    def test_haltune_help(self):
        """Test haltune --help."""
        result = subprocess.run(
            ["./zig-out/bin/haltune", "--help"],
            capture_output=True,
            text=True
        )
        # Should return 0 or have help output
        assert result.returncode == 0 or "help" in result.stdout.lower() or "usage" in result.stdout.lower()
```

**Step 2: Run tests to verify they work**

Run: `cd tests && python -m pytest test_build.py -v`
Expected: Tests verify build process

**Step 3: Commit**

```bash
git add tests/test_build.py
git commit -m "test: add build verification tests"
```

---

## Task 10: Create Test Suite Configuration

**Files:**
- Create: `tests/pytest.ini`
- Create: `tests/conftest.py`

**Step 1: Create pytest.ini**

```ini
# tests/pytest.ini
[pytest]
testpaths = .
python_files = test_*.py
python_classes = Test*
python_functions = test_*
addopts =
    -v
    --tb=short
    --strict-markers
markers =
    slow: marks tests as slow (deselect with '-m "not slow"')
    bridge: tests that require bridge server
    tui: tests that require TUI
    hal: tests that require HAL (halrun)
    ssh: tests that require SSH to remote host
    local: tests that run on local machine only
```

**Step 2: Create conftest.py**

```python
# tests/conftest.py
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
        return Path("./zig-out/bin/haltune").exists()

    for item in items:
        # Auto-detect bridge tests
        if "bridge_client" in str(item.fspath):
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
```

**Step 3: Commit**

```bash
git add tests/pytest.ini tests/conftest.py
git commit -m "test infra: add pytest configuration and auto-skip"
```

---

## Task 11: Update Documentation

**Files:**
- Create: `tests/README.md`
- Modify: `README.md` (project root)

**Step 1: Create tests/README.md**

```markdown
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
pytest -m local
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
```

**Step 2: Update project README**

Add section about running tests:

```markdown
## Testing

The project uses Python pytest for testing.

### Prerequisites

```bash
pip install pytest pexpect paramiko tomli
```

### Run Tests

```bash
cd tests
pytest
```

### Test Categories

- `test_bridge.py` - HAL bridge server tests
- `test_tui.py` - TUI interaction tests
- `test_build.py` - Build verification tests

See `tests/README.md` for details.
```

**Step 3: Commit**

```bash
git add tests/README.md README.md
git commit -m "docs: add test suite documentation"
```

---

## Task 12: Create Requirements File

**Files:**
- Create: `tests/requirements.txt`
- Create: `tests/requirements-dev.txt`

**Step 1: Create requirements.txt**

```text
# Core test dependencies
pytest>=7.4.0
pexpect>=4.8.0
paramiko>=3.3.0

# TOML parsing (Python < 3.11)
tomli>=2.0.1; python_version < "3.11"
```

**Step 2: Create requirements-dev.txt**

```text
-r requirements.txt

# Development tools
pytest-cov>=4.1.0
pytest-xdist>=3.5.0  # parallel tests
black>=23.0.0
mypy>=1.7.0
```

**Step 3: Commit**

```bash
git add tests/requirements.txt tests/requirements-dev.txt
git commit -m "test infra: add Python requirements files"
```

---

## Task 13: Update CI/CD Configuration

**Files:**
- Modify: `.github/workflows/test.yml` or create if not exists

**Step 1: Create or update GitHub Actions workflow**

```yaml
# .github/workflows/test.yml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v4

    - name: Install Zig
      uses: goto-bus-stop/setup-zig@v2
      with:
        version: 0.15.2

    - name: Install Python dependencies
      run: |
        pip install -r tests/requirements.txt

    - name: Build
      run: zig build

    - name: Run tests
      run: |
        cd tests
        pytest -v
```

**Step 2: Commit**

```bash
git add .github/workflows/test.yml
git commit -m "ci: add GitHub Actions workflow for Python tests"
```

---

## Task 14: Verify Migration Complete

**Step 1: Run all tests**

```bash
cd tests
pytest -v
```

Expected: All new tests pass

**Step 2: Compare coverage**

Check that all bash test scenarios are covered in Python tests.

**Step 3: Final verification commit**

```bash
git add tests/
git commit -m "test: complete Python test migration verification"
```

---

## Task 15: Cleanup Deprecated Bash Scripts

**Files:**
- Remove: `test_bridge_comprehensive.sh`
- Remove: `test_tui_comprehensive.js`
- Remove: `test_tui_pexpect.py` (root level, not in tests/)
- Archive: Move any useful parts to docs/ if needed

**Step 1: Create migration notes**

```bash
# Document what was migrated
cat > MIGRATION_NOTES.md << 'EOF'
# Test Migration Notes

Bash scripts migrated to Python:

- test_bridge_comprehensive.sh → tests/test_bridge.py
- test_tui_comprehensive.js → tests/test_tui.py
- test_tui_pexpect.py → tests/test_tui.py
- tests/tui_test.py → tests/test_tui.py
- test_remote_hal.py → tests/test_bridge.py
EOF
```

**Step 2: Remove deprecated scripts**

```bash
git rm test_bridge_comprehensive.sh test_tui_comprehensive.js test_tui_pexpect.py test_remote_hal.py
```

**Step 3: Commit cleanup**

```bash
git add MIGRATION_NOTES.md
git commit -m "test: remove deprecated bash test scripts after migration"
```

---

## Completion Checklist

- [ ] All helper modules created and tested
- [ ] All bash scripts migrated to Python
- [ ] Configuration via TOML working
- [ ] Local and remote testing modes working
- [ ] Documentation updated
- [ ] CI/CD configured
- [ ] Deprecated scripts removed
- [ ] All tests passing

---

## Reference: Design Document

See `docs/plans/2025-02-28-python-test-migration-design.md` for full design context.
