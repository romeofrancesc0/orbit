#!/bin/bash
# Installs the optional Powered Notch hooks into ~/.claude/settings.json.
# The app does the same from Settings → Agenti → Hook di Claude Code.
#
# They are optional: without them Powered Notch already works by reading the
# transcripts. They only make a still-pending permission request show up *right away*.
#
#   ./install.sh            -> install
#   ./install.sh --remove   -> uninstall
#
# Hooks that are already there (status line, other tools…) are left alone: the file
# is merged, not rewritten, and a backup copy is saved first.

set -euo pipefail
cd "$(dirname "$0")"

SETTINGS="$HOME/.claude/settings.json"
TARGET_DIR="$HOME/.powered-notch/hooks"
SCRIPT="$TARGET_DIR/powered_notch_hook.py"

MODE="install"
[ "${1:-}" = "--remove" ] && MODE="remove"

if [ "$MODE" = "install" ]; then
  mkdir -p "$TARGET_DIR"
  cp powered_notch_hook.py "$SCRIPT"
  chmod +x "$SCRIPT"
  echo "▸ script copied to $SCRIPT"
fi

MODE="$MODE" SCRIPT="$SCRIPT" SETTINGS="$SETTINGS" /usr/bin/env python3 <<'PY'
import json, os, shutil, sys

settings_path = os.environ["SETTINGS"]
script = os.environ["SCRIPT"]
mode = os.environ["MODE"]

events_raise = ["PermissionRequest", "PermissionDenied", "Notification"]
events_clear = ["PostToolUse", "Stop", "UserPromptSubmit", "SessionEnd"]

settings = {}
if os.path.exists(settings_path):
    shutil.copy2(settings_path, settings_path + ".powered-notch-backup")
    with open(settings_path, encoding="utf-8") as handle:
        settings = json.load(handle)

hooks = settings.setdefault("hooks", {})


def command_for(event):
    return f'/usr/bin/env python3 "{script}" {event}'


def is_ours(entry):
    for hook in entry.get("hooks", []):
        if "powered_notch_hook.py" in str(hook.get("command", "")):
            return True
    return False


changed = 0
for event in events_raise + events_clear:
    entries = hooks.setdefault(event, [])
    entries[:] = [entry for entry in entries if not is_ours(entry)]
    if mode == "install":
        entries.append({
            "hooks": [{
                "type": "command",
                "command": command_for(event),
                "async": True,
                "timeout": 5,
            }]
        })
    changed += 1
    if not entries:
        del hooks[event]

if not hooks:
    settings.pop("hooks", None)

os.makedirs(os.path.dirname(settings_path), exist_ok=True)
with open(settings_path, "w", encoding="utf-8") as handle:
    json.dump(settings, handle, indent=2)
    handle.write("\n")

print(f"▸ {mode}: {changed} events updated in {settings_path}")
print("  (backup: " + settings_path + ".powered-notch-backup)")
PY

if [ "$MODE" = "remove" ]; then
  rm -f "$SCRIPT"
  rm -rf "$HOME/.powered-notch/hints"
  echo "▸ hooks removed"
fi

echo "▸ restart your Claude Code sessions to apply the change"
