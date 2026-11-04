#!/usr/bin/env python3
"""Bridge between Claude Code hooks and Orbit.

Claude Code passes the event JSON on stdin and the event name as the first
argument. The script turns the event into a "hint" that Orbit reads from
~/.orbit/hints/<session_id>.json and layers over the transcript.

It covers states the transcript never records, above all a permission request
that is still pending and would otherwise look like "running".
"""

import json
import os
import sys
import time

HINTS_DIR = os.path.expanduser("~/.orbit/hints")

# Events that raise a state, and how to describe it. The labels are shown as-is in the
# (Italian) interface.
RAISE = {
    "PermissionRequest": ("blocked", "permesso richiesto"),
    "PermissionDenied": ("attention", "permesso negato"),
    "Notification": ("attention", "attende te"),
}

# Any other event means "the block is over": the hint is removed.


def main() -> int:
    event = sys.argv[1] if len(sys.argv) > 1 else ""

    try:
        payload = json.load(sys.stdin)
    except Exception:
        payload = {}

    session_id = payload.get("session_id") or ""
    if not session_id or "/" in session_id:
        return 0

    path = os.path.join(HINTS_DIR, session_id + ".json")

    # Claude Code sends an "idle_prompt" Notification a minute after every finished turn
    # ("Claude is waiting for your input"). It is not a call to action, so it clears the hint.
    if event == "Notification" and payload.get("notification_type") == "idle_prompt":
        event = ""

    if event not in RAISE:
        try:
            os.remove(path)
        except OSError:
            pass
        return 0

    status, default_activity = RAISE[event]
    tool = payload.get("tool_name") or ""
    message = payload.get("message") or ""

    if event == "PermissionRequest" and tool:
        activity = f"permesso: {tool}"
    elif message:
        activity = message[:80]
    else:
        activity = default_activity

    hint = {"status": status, "activity": activity, "at": int(time.time() * 1000)}

    os.makedirs(HINTS_DIR, exist_ok=True)
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(hint, handle)
    os.replace(temporary, path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
