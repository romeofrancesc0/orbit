#!/usr/bin/env python3
"""Ponte fra gli hook di Claude Code e Lunetta.

Claude Code passa il JSON dell'evento su stdin; il nome dell'evento arriva come
primo argomento. Lo script traduce l'evento in un "suggerimento" che Lunetta
legge in ~/.lunetta/hints/<session_id>.json e sovrappone al transcript.

Serve per gli stati che nel transcript non compaiono: soprattutto una richiesta
di permesso ancora pendente, che altrimenti si vedrebbe solo come "in esecuzione".
"""

import json
import os
import sys
import time

HINTS_DIR = os.path.expanduser("~/.lunetta/hints")

# Eventi che accendono uno stato, e come descriverlo.
RAISE = {
    "PermissionRequest": ("blocked", "permesso richiesto"),
    "PermissionDenied": ("attention", "permesso negato"),
    "Notification": ("attention", "attende te"),
}

# Tutto il resto significa "il blocco è passato": il suggerimento va rimosso.


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
