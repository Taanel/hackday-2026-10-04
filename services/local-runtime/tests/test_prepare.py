from pathlib import Path
from types import SimpleNamespace

import pytest


def test_prepare_downloads_pinned_laya_and_explicit_tiny_streaming(tmp_path):
    from friday_runtime.prepare import LAYA_REVISION, LAYA_REPOSITORY, prepare_models

    calls = []

    def snapshot(**kwargs):
        calls.append(("laya", kwargs))
        Path(kwargs["local_dir"]).mkdir()
        return str(kwargs["local_dir"])

    arch = SimpleNamespace(TINY_STREAMING=2)

    def moonshine(language, model_arch, **kwargs):
        calls.append(("wake", language, model_arch, kwargs))
        directory = kwargs["cache_root"] / "tiny-streaming-en" / "quantized_26_08_21"
        directory.mkdir(parents=True)
        return str(directory), model_arch

    result = prepare_models(tmp_path, snapshot=snapshot, download_wake=moonshine, model_arch=arch)
    assert calls[0] == ("laya", {"repo_id": LAYA_REPOSITORY, "revision": LAYA_REVISION, "local_dir": tmp_path / "laya"})
    assert calls[1] == ("wake", "en", 2, {"cache_root": tmp_path / "moonshine"})
    assert result["layaModelDirectory"] == str(tmp_path / "laya")
    assert result["wakeModelDirectory"] == str(tmp_path / "moonshine" / "tiny-streaming-en" / "quantized_26_08_21")
    assert result["revisions"] == {"laya": "8139e9089273319512c730218903784074133187", "wake": "quantized_26_08_21"}
    assert result["licenses"] == {"laya": "Apache-2.0", "wake": "MIT"}


def test_prepare_cannot_misreport_an_unexpected_wake_revision(tmp_path):
    from friday_runtime.prepare import prepare_models

    with pytest.raises(ValueError, match="revision"):
        prepare_models(tmp_path, snapshot=lambda **kwargs: None, download_wake=lambda *a, **k: (str(tmp_path / "wrong-revision"), 2), model_arch=SimpleNamespace(TINY_STREAMING=2))
