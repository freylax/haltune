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
