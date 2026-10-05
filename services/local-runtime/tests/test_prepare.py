from pathlib import Path
from types import SimpleNamespace

import pytest


def test_prepare_downloads_pinned_laya_and_german_small_streaming(tmp_path):
    from friday_runtime.prepare import LAYA_REVISION, LAYA_REPOSITORY, prepare_models

    calls = []

    def snapshot(**kwargs):
        calls.append(("laya", kwargs))
        Path(kwargs["local_dir"]).mkdir()
        return str(kwargs["local_dir"])

    arch = SimpleNamespace(SMALL_STREAMING=4)

    def moonshine(language, model_arch, **kwargs):
        calls.append(("wake", language, model_arch, kwargs))
        directory = kwargs["cache_root"] / "small-streaming-de" / "quantized_26_08_24"
        directory.mkdir(parents=True)
        return str(directory), model_arch

    result = prepare_models(tmp_path, snapshot=snapshot, download_wake=moonshine, model_arch=arch)
    assert calls[0] == ("laya", {"repo_id": LAYA_REPOSITORY, "revision": LAYA_REVISION, "local_dir": tmp_path / "laya"})
    assert calls[1] == ("wake", "de", 4, {"cache_root": tmp_path / "moonshine"})
    assert result["layaModelDirectory"] == str(tmp_path / "laya")
    assert result["wakeModelDirectory"] == str(tmp_path / "moonshine" / "small-streaming-de" / "quantized_26_08_24")
    assert result["revisions"] == {"laya": "8139e9089273319512c730218903784074133187", "wake": "quantized_26_08_24"}
    assert result["licenses"] == {"laya": "Apache-2.0", "wake": "MIT"}


def test_prepare_cannot_misreport_an_unexpected_wake_revision(tmp_path):
    from friday_runtime.prepare import prepare_models

    with pytest.raises(ValueError, match="revision"):
        prepare_models(tmp_path, snapshot=lambda **kwargs: None, download_wake=lambda *a, **k: (str(tmp_path / "wrong-revision"), 4), model_arch=SimpleNamespace(SMALL_STREAMING=4))
