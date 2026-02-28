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
        return True

    def net(self, pin: str, signal: str):
        """Link pin to signal."""
        cmd = f"net {signal} {pin}"
        self.send_command(cmd)

    def setp(self, param: str, value: str):
        """Set parameter value."""
        cmd = f"setp {param} {value}"
        self.send_command(cmd)

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
