#!/bin/bash
# Installa gli hook opzionali di Lunetta in ~/.claude/settings.json.
# Lo stesso lo fa l'app: Impostazioni → Agenti → Hook di Claude Code.
#
# Sono facoltativi: senza di essi Lunetta funziona già leggendo i transcript.
# Servono a vedere *subito* una richiesta di permesso ancora pendente.
#
#   ./install.sh            → installa
#   ./install.sh --remove   → disinstalla
#
# Gli hook già presenti (statusline, altri strumenti…) non vengono toccati:
# il file viene fuso, non riscritto, e ne viene salvata una copia.

set -euo pipefail
cd "$(dirname "$0")"

SETTINGS="$HOME/.claude/settings.json"
TARGET_DIR="$HOME/.lunetta/hooks"
SCRIPT="$TARGET_DIR/lunetta_hook.py"

MODE="install"
[ "${1:-}" = "--remove" ] && MODE="remove"

if [ "$MODE" = "install" ]; then
  mkdir -p "$TARGET_DIR"
  cp lunetta_hook.py "$SCRIPT"
  chmod +x "$SCRIPT"
  echo "▸ script copiato in $SCRIPT"
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
    shutil.copy2(settings_path, settings_path + ".lunetta-backup")
    with open(settings_path, encoding="utf-8") as handle:
        settings = json.load(handle)

hooks = settings.setdefault("hooks", {})


def command_for(event):
    return f'/usr/bin/env python3 "{script}" {event}'


def is_ours(entry):
    for hook in entry.get("hooks", []):
        if "lunetta_hook.py" in str(hook.get("command", "")):
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

print(f"▸ {mode}: {changed} eventi aggiornati in {settings_path}")
print("  (copia di sicurezza: " + settings_path + ".lunetta-backup)")
PY

if [ "$MODE" = "remove" ]; then
  rm -f "$SCRIPT"
  rm -rf "$HOME/.lunetta/hints"
  echo "▸ hook rimossi"
fi

echo "▸ riavvia le sessioni di Claude Code per applicare la modifica"
