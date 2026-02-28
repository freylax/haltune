"""Test configuration loader."""

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

    # Handle nested tables for tests section
    tests_data = data["tests"]
    tests_config = TestsConfig(
        tui_startup_timeout=tests_data["tui"]["startup_timeout"],
        bridge_connect_timeout=tests_data["bridge"]["connect_timeout"],
        build_timeout=tests_data["build"]["timeout"]
    )

    return Config(test=test, hosts=hosts, tests=tests_config)
