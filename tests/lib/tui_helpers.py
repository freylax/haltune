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
            self.passed += 1
            return True
        except (pexpect.TIMEOUT, pexpect.EOF):
            self.failed += 1
            return False

    def wait_for_idle(self, idle_ms: int = 100, timeout_ms: int = 2000) -> bool:
        """Wait for screen to become stable."""
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
            self.child.send(chr(ord(ctrl_char) - ord('a') + 1))
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
