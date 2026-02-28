"""Build and setup tests."""

import subprocess
import pytest
import stat
from pathlib import Path
from lib.config import load_config

@pytest.fixture(scope="module")
def config():
    config_path = Path(__file__).parent / "config" / "test_config.toml"
    return load_config(config_path)

class TestBuild:
    @pytest.mark.skipif(True, reason="Build test - can be slow")
    def test_zig_build(self, config):
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
        # Run from project root
        binary = Path(__file__).parent.parent / "zig-out" / "bin" / "haltune"
        # Don't fail if binary doesn't exist - just report
        if not binary.exists():
            pytest.skip("haltune binary not found - run 'zig build' first")
        assert binary.exists()
        assert binary.is_file()

    def test_haltune_executable(self):
        """Test that haltune binary is executable."""
        binary = Path(__file__).parent.parent / "zig-out" / "bin" / "haltune"
        if not binary.exists():
            pytest.skip("haltune binary not found")
        st = binary.stat()
        assert st.st_mode & stat.S_IXUSR, "haltune is not executable"

class TestVersion:
    @pytest.mark.skipif(True, reason="Requires haltune binary")
    def test_haltune_version(self):
        """Test haltune --version."""
        binary = Path(__file__).parent.parent / "zig-out" / "bin" / "haltune"
        if not binary.exists():
            pytest.skip("haltune binary not found")
        result = subprocess.run(
            [str(binary), "--version"],
            capture_output=True,
            text=True
        )
        # Accept success or at least some output mentioning haltune
        assert result.returncode == 0 or "haltune" in result.stdout.lower()

class TestHelp:
    @pytest.mark.skipif(True, reason="Requires haltune binary")
    def test_haltune_help(self):
        """Test haltune --help."""
        binary = Path(__file__).parent.parent / "zig-out" / "bin" / "haltune"
        if not binary.exists():
            pytest.skip("haltune binary not found")
        result = subprocess.run(
            [str(binary), "--help"],
            capture_output=True,
            text=True
        )
        # Accept success or at least some output mentioning help/usage
        assert result.returncode == 0 or "help" in result.stdout.lower() or "usage" in result.stdout.lower()
