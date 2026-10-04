import json
import subprocess
import sys

import pytest


def run_python(script, *arguments, stdin=""):
    return subprocess.run([sys.executable, "-c", script, *arguments], input=stdin, text=True, capture_output=True, timeout=10)


def test_protocol_stdout_redirects_python_and_native_writes():
    result = run_python('''
import ctypes, os
from friday_runtime.protocol import protocol_stdout
with protocol_stdout() as emit:
    print("python model diagnostic")
    os.write(1, b"native model diagnostic\\n")
    ctypes.CDLL(None).printf(b"buffered native diagnostic")
    emit({"type":"ok"})
''')
    assert result.returncode == 0
    assert result.stdout == '{"type":"ok"}\n'
    assert "python model diagnostic" in result.stderr
    assert "native model diagnostic" in result.stderr
    assert "buffered native diagnostic" in result.stderr


@pytest.mark.parametrize("provider", ["laya", "wake"])
def test_cli_missing_model_fails_with_only_json_on_stdout(tmp_path, provider):
    result = subprocess.run([sys.executable, "-m", "friday_runtime", provider, "--model-dir", str(tmp_path / "missing")], input="", text=True, capture_output=True, timeout=10)
    assert result.returncode == 1
    assert json.loads(result.stdout) == {"type": "error", "provider": provider, "error": "Model directory is missing; run prepare first."}
    assert result.stderr == ""


def test_cli_laya_filters_noisy_model_output_and_preserves_wire(tmp_path):
    result = run_python('''
import os, sys, types
package = types.ModuleType("laya_coreml")
class Agent:
    def predict(self, text, questions):
        print("prediction diagnostic")
        os.write(1, b"native prediction diagnostic\\n")
        return {"answers":{"intent":{"type":"choice","choice":"unknown","probabilities":{"open_app":0.1,"search_web":0.0,"create_note":0.1,"switch_desktop":0.0,"reasoning":0.2,"unknown":0.6}}},"usage":{"truncated":False,"truncated_questions":[],"state_tokens_dropped":0}}
def load(path, **kwargs):
    assert kwargs == {"local_files_only":True}
    print("load diagnostic")
    return Agent()
package.load = load
sys.modules["laya_coreml"] = package
sys.argv = ["friday_runtime", "laya", "--model-dir", sys.argv[1]]
from friday_runtime.__main__ import main
raise SystemExit(main())
''', str(tmp_path), stdin='{"id":"5c22cb53-09d0-40e9-91ca-1f17c2a1b540","op":"decide","text":"Hallo"}\n')
    assert result.returncode == 0
    messages = [json.loads(line) for line in result.stdout.splitlines()]
    assert messages == [{"type": "ready", "provider": "laya"}, {"id": "5c22cb53-09d0-40e9-91ca-1f17c2a1b540", "intent": "unknown", "confidence": 0.6, "truncated": False}]
    assert "diagnostic" in result.stderr


def test_cli_fatal_model_failure_is_sanitized(tmp_path):
    result = run_python('''
import sys, types
package = types.ModuleType("laya_coreml")
def load(*a, **kw):
    raise RuntimeError("PRIVATE DATA FROM MODEL")
package.load = load
sys.modules["laya_coreml"] = package
sys.argv = ["friday_runtime", "laya", "--model-dir", sys.argv[1]]
from friday_runtime.__main__ import main
raise SystemExit(main())
''', str(tmp_path))
    assert result.returncode == 1
    assert json.loads(result.stdout) == {"type": "error", "provider": "laya", "error": "Local runtime failed (RuntimeError)."}
    assert "PRIVATE" not in result.stdout + result.stderr


def test_cli_prepare_reports_metadata_as_single_json_object(tmp_path):
    result = run_python('''
import sys, types
from pathlib import Path
hub = types.ModuleType("huggingface_hub")
def snapshot_download(**kwargs):
    print("download diagnostic")
    assert kwargs["revision"] == "8139e9089273319512c730218903784074133187"
hub.snapshot_download = snapshot_download
moonshine = types.ModuleType("moonshine_voice")
moonshine.ModelArch = types.SimpleNamespace(TINY_STREAMING=2)
def download(language, arch, **kwargs):
    assert (language, arch) == ("en", 2)
    return str(kwargs["cache_root"] / "quantized_26_08_21"), 2
moonshine.get_model_for_language = download
sys.modules["huggingface_hub"] = hub
sys.modules["moonshine_voice"] = moonshine
sys.argv = ["friday_runtime", "prepare", "--model-root", sys.argv[1]]
from friday_runtime.__main__ import main
raise SystemExit(main())
''', str(tmp_path))
    assert result.returncode == 0
    metadata = json.loads(result.stdout)
    assert metadata["layaModelDirectory"] == str(tmp_path / "laya")
    assert metadata["wakeArchitecture"] == "TINY_STREAMING"
    assert "download diagnostic" in result.stderr
