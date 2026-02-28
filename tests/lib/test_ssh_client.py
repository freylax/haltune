# tests/lib/test_ssh_client.py
import pytest

# Handle paramiko not being installed
pytest.importorskip("paramiko", reason="paramiko not installed")

from lib.ssh_client import SSHClient


@pytest.mark.skipif(True, reason="SSH test - requires remote host")
def test_ssh_connect_and_run_command():
    client = SSHClient(hostname="pib", user="cnc")
    client.connect()
    exit_code, stdout, stderr = client.run_command("echo hello")
    assert exit_code == 0
    assert "hello" in stdout
    client.close()


@pytest.mark.skipif(True, reason="SSH test - requires remote host")
def test_ssh_context_manager():
    with SSHClient(hostname="pib", user="cnc") as client:
        exit_code, stdout, stderr = client.run_command("whoami")
        assert exit_code == 0
        assert "cnc" in stdout


@pytest.mark.skipif(True, reason="SSH test - requires remote host")
def test_ssh_file_exists():
    with SSHClient(hostname="pib", user="cnc") as client:
        # Test existing file
        assert client.file_exists("/etc/passwd")
        # Test non-existing file
        assert not client.file_exists("/nonexistent/file/that/does/not/exist")


def test_ssh_client_instantiation():
    """Test that SSHClient can be instantiated without connecting."""
    client = SSHClient(hostname="example.com", user="testuser")
    assert client.hostname == "example.com"
    assert client.user == "testuser"
    assert client._connected is False
