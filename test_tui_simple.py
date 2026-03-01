#!/usr/bin/env python3
"""Simple test to check haltune output"""
import subprocess
import time

def main():
    # Start haltune in background
    proc = subprocess.Popen(
        ["/home/cnc/prog/haltune/zig-out/bin/haltune"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )

    # Wait a bit for it to start
    time.sleep(2)

    # Terminate
    proc.terminate()

    # Get output
    stdout, stderr = proc.communicate(timeout=2)

    print("=== STDOUT ===")
    print(stdout[:1000] if stdout else "(empty)")
    print("\n=== STDERR ===")
    print(stderr[-2000:] if stderr else "(empty)")

    # Check for errors
    if "error" in stderr.lower() or errno in stderr.lower():
        print("\n⚠ Errors detected in output")

if __name__ == "__main__":
    main()
