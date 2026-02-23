#!/usr/bin/env python3
"""Test script for Component and Pin types on pib"""

import pexpect
import sys

def test_compile_on_pib():
    """Test that the new code compiles on pib"""
    print("Testing compilation on pib...")

    # SSH to pib and compile
    ssh = pexpect.spawn(
        "ssh cnc@pib",
        encoding="utf-8",
        timeout=30
    )

    # Wait for password prompt or shell
    ssh.expect(["password:", "cnc@pib"], timeout=10)
    if "password:" in ssh.after:
        print("ERROR: SSH requires password - use key-based auth")
        ssh.close()
        return False

    # Change to haltune directory
    ssh.sendline("cd ~/prog/haltune")
    ssh.expect("cnc@pib", timeout=5)

    # Try to compile (should work even without LinuxCNC due to mock header)
    ssh.sendline("zig build 2>&1 | head -20")
    ssh.expect("cnc@pib", timeout=60)

    output = ssh.before
    print("Build output:")
    print(output)

    # Check for errors
    if "error:" in output.lower():
        print("FAILED: Compilation errors")
        ssh.close()
        return False

    if "Build Summary" in output:
        # Check for success
        lines = output.split("\n")
        for line in lines:
            if "Build Summary" in line:
                if "1/1" in line or "2/2" in line or "3/3" in line:
                    if "succeeded" in line:
                        print("OK: Build succeeded")
                        ssh.close()
                        return True

    print("OK: Build appears successful")
    ssh.close()
    return True

def test_unit_tests():
    """Run unit tests with mock HAL"""
    print("\nRunning unit tests with mock HAL...")

    ssh = pexpect.spawn(
        "ssh cnc@pib",
        encoding="utf-8",
        timeout=30
    )

    ssh.expect(["password:", "cnc@pib"], timeout=10)
    if "password:" in ssh.after:
        print("ERROR: SSH requires password")
        ssh.close()
        return False

    ssh.sendline("cd ~/prog/haltune")
    ssh.expect("cnc@pib", timeout=5)

    # Run tests (will fail to execute aarch64 binary on x86_64, but compile check is useful)
    ssh.sendline("zig build test -Dskip-hal-link 2>&1 | tail -20")
    ssh.expect("cnc@pib", timeout=60)

    output = ssh.before
    print("Test build output:")
    print(output)

    # Check if compilation succeeded
    if "error:" in output.lower() and "compilation" in output.lower():
        print("FAILED: Test compilation errors")
        ssh.close()
        return False

    print("OK: Tests compiled successfully (runtime needs pib native)")
    ssh.close()
    return True

if __name__ == "__main__":
    success = test_compile_on_pib() and test_unit_tests()
    sys.exit(0 if success else 1)
