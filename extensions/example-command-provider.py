#!/usr/bin/env python3
"""Example `command` provider: prints sessions as JSON on stdout.

Powered Notch runs this script on every polling round and shows what it prints.
To enable it, add this to the providers in ~/.config/powered-notch/config.json:

    {
      "id": "my-agent",
      "type": "command",
      "name": "My Agent",
      "accent": "#22C55E",
      "command": "/path/to/powered-notch/extensions/example-command-provider.py"
    }

The contract:
  - stdout is a JSON array (or {"sessions": [...]}, or a single object);
  - a non-zero exit code shows the message on stderr as an error in the panel;
  - the script must finish quickly (8 second timeout).

Every field is optional except `id`.
"""

import json
import subprocess
import sys
import time


def running_agents():
    """A real example: finds an agent's processes and turns each into a session.

    It looks for `aider` processes here; replace the filter with your own.
    """
    try:
        output = subprocess.run(
            ["ps", "-axo", "pid=,args="],
            capture_output=True, text=True, timeout=3,
        ).stdout
    except Exception:
        return []

    sessions = []
    for line in output.splitlines():
        line = line.strip()
        if " aider" not in line and not line.endswith("aider"):
            continue
        pid, _, args = line.partition(" ")
        sessions.append({
            "id": f"aider-{pid}",
            "title": args[:70],
            "project": "aider",
            "status": "working",
            "activity": "aider session running",
            "pid": int(pid),
            "updatedAt": int(time.time() * 1000),
        })
    return sessions


def demo_session():
    """Placeholder row: remove it once you plug in real data."""
    return {
        "id": "demo-1",
        "title": "Example session from the command provider",
        "project": "example",
        "path": "~/Projects",
        "branch": "main",
        "model": "gpt-5",
        "status": "attention",
        "activity": "waiting for an answer",
        "updatedAt": int(time.time() * 1000),
        "tokens": {"used": 42000, "limit": 200000},
        "actions": [
            {"label": "Open logs", "command": "open ~/Library/Logs", "symbol": "doc.text"}
        ],
    }


if __name__ == "__main__":
    sessions = running_agents()
    if not sessions:
        sessions = [demo_session()]
    json.dump(sessions, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
