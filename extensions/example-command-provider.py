#!/usr/bin/env python3
"""Esempio di provider `command`: stampa su stdout le sessioni in JSON.

AgentBar esegue questo script a ogni giro di polling e mostra ciò che stampa.
Per attivarlo, aggiungi in ~/.config/agentbar/config.json:

    {
      "id": "mio-agent",
      "type": "command",
      "name": "Mio Agent",
      "accent": "#22C55E",
      "command": "/Users/tu/AgentBar/extensions/example-command-provider.py"
    }

Regole del contratto:
  • stdout = un array JSON (oppure {"sessions": [...]}, oppure un solo oggetto);
  • uscita diversa da 0 → il messaggio su stderr compare come errore nel pannello;
  • lo script deve terminare in fretta (timeout 8 secondi).

Ogni campo è opzionale tranne `id`.
"""

import json
import subprocess
import sys
import time


def running_agents():
    """Esempio reale: cerca processi di un agent e ne fa una sessione a testa.

    Qui si cercano processi `aider`; sostituisci il filtro con il tuo.
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
            "activity": "sessione aider attiva",
            "pid": int(pid),
            "updatedAt": int(time.time() * 1000),
        })
    return sessions


def demo_session():
    """Riga dimostrativa: toglila quando colleghi dati veri."""
    return {
        "id": "demo-1",
        "title": "Sessione di esempio del provider command",
        "project": "esempio",
        "path": "~/Projects",
        "branch": "main",
        "model": "gpt-5",
        "status": "attention",
        "activity": "in attesa di una risposta",
        "updatedAt": int(time.time() * 1000),
        "tokens": {"used": 42000, "limit": 200000},
        "actions": [
            {"label": "Apri log", "command": "open ~/Library/Logs", "symbol": "doc.text"}
        ],
    }


if __name__ == "__main__":
    sessions = running_agents()
    if not sessions:
        sessions = [demo_session()]
    json.dump(sessions, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
