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
