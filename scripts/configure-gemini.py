#!/usr/bin/env python3
"""Store a personal Gemini key in Keychain and select Friday's cloud fallback."""
import getpass
import json
from pathlib import Path
import subprocess

config_path = Path.home() / "Library/Application Support/Friday/runtime.json"
if not config_path.exists():
    raise SystemExit("Bitte zuerst scripts/setup-local-runtime.sh ausführen.")
key = getpass.getpass("Gemini API-Key (wird nicht angezeigt): ").strip()
if not key:
    raise SystemExit("Kein Schlüssel eingegeben.")
result = subprocess.run(["security", "add-generic-password", "-U", "-a", "Friday", "-s",
                         "dev.hackday.friday.gemini", "-w", key], capture_output=True)
if result.returncode:
    raise SystemExit("Schlüsselbund konnte nicht aktualisiert werden.")
config = json.loads(config_path.read_text())
config.update(reasoningProvider="gemini", geminiModel="gemini-3.5-flash-lite")
config_path.write_text(json.dumps(config, indent=2))
print("Gemini Flash-Lite mit minimalem Thinking eingerichtet. Friday neu starten.")
