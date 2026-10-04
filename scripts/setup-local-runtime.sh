#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
friday_support="$HOME/Library/Application Support/Friday"
command -v uv >/dev/null || { printf 'Bitte uv installieren: https://docs.astral.sh/uv/\n'; exit 1; }
export UV_PROJECT_ENVIRONMENT="$friday_support/runtime/venv"
uv sync --frozen --no-dev --no-install-project --project "$repo_root/services/local-runtime" --python 3.12
export PYTHONPATH="$repo_root/services/local-runtime/src"
"$UV_PROJECT_ENVIRONMENT/bin/python" -m friday_runtime prepare --model-root "$friday_support/models" > "$friday_support/models.json"
"$UV_PROJECT_ENVIRONMENT/bin/python" "$repo_root/scripts/prepare-hex.py" --support "$friday_support"
"$UV_PROJECT_ENVIRONMENT/bin/python" - "$repo_root" "$friday_support" <<'PY'
from pathlib import Path
import json, subprocess, sys
repo, support = map(Path, sys.argv[1:])
models = json.loads((support / 'models.json').read_text())
available = []
try:
    result = subprocess.run(['ollama','list'],capture_output=True,text=True,check=True)
    available = [line.split()[0] for line in result.stdout.splitlines()[1:] if line.split()]
except (OSError, subprocess.CalledProcessError):
    pass
model = 'qwen3:8b' if 'qwen3:8b' in available else (available[0] if available else 'qwen3:8b')
existing = json.loads((support/'runtime.json').read_text()) if (support/'runtime.json').exists() else {}
config = dict(pythonExecutable=str(support/'runtime/venv/bin/python'), workerDirectory=str(repo/'services/local-runtime/src'),
              layaModelDirectory=models['layaModelDirectory'],wakeModelDirectory=models['wakeModelDirectory'],
              hexExecutable=str(support/'tools/Hex.app/Contents/MacOS/hex'),hexSupportDirectory=str(support/'hex'),ollamaModel=model)
for key in ('reasoningProvider', 'geminiModel'):
    if key in existing: config[key] = existing[key]
(support/'runtime.json').write_text(json.dumps(config,indent=2))
print('Lokale Runtime bereit. LLM-Modell: '+model)
if not available: print('Für komplexe Antworten Ollama starten und ollama pull qwen3:8b ausführen.')
PY
printf 'Nächster Schritt: ./scripts/build-macos.sh\n'
