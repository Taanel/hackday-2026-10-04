#!/usr/bin/env python3
"""Store a personal Gemini key locally and select Friday's cloud fallback."""
import getpass
import json
from pathlib import Path
import os
import tempfile

config_path = Path.home() / "Library/Application Support/Friday/runtime.json"
if not config_path.exists():
    raise SystemExit("Bitte zuerst scripts/setup-local-runtime.sh ausführen.")
key = getpass.getpass("Gemini API-Key (wird nicht angezeigt): ").strip()
if not key or len(key) > 512 or any(ord(c) <= 32 or ord(c) >= 127 for c in key):
    raise SystemExit("Bitte einen API-Schlüssel ohne Leerzeichen oder Zeilenumbrüche eingeben.")
credentials = config_path.parent / "Credentials"
credentials.mkdir(mode=0o700, parents=True, exist_ok=True)
credentials.chmod(0o700)
descriptor, temporary = tempfile.mkstemp(dir=credentials)
try:
    with os.fdopen(descriptor, "w") as output:
        output.write(key)
    os.replace(temporary, credentials / "gemini-api-key.txt")
finally:
    if os.path.exists(temporary): os.unlink(temporary)
config = json.loads(config_path.read_text())
config.update(reasoningProvider="gemini", geminiModel="gemini-3.5-flash-lite")
config_path.write_text(json.dumps(config, indent=2))
print("Gemini Flash-Lite eingerichtet. Schlüssel nur lokal gespeichert. Friday neu starten.")
