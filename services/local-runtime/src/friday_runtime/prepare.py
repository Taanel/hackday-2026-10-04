"""The sole network-enabled entry point: prepare both pinned local models."""

from pathlib import Path
from typing import Callable

LAYA_REPOSITORY = "aac6fef/laya-multilingual-coreml"
LAYA_REVISION = "8139e9089273319512c730218903784074133187"
MOONSHINE_REVISION = "quantized_26_08_24"
MOONSHINE_MODEL_URL = "https://download.moonshine.ai/model/small-streaming-de/" + MOONSHINE_REVISION


def prepare_models(
    model_root: Path,
    *,
    snapshot: Callable | None = None,
    download_wake: Callable | None = None,
    model_arch=None,
) -> dict:
    if snapshot is None:
        from huggingface_hub import snapshot_download

        snapshot = snapshot_download
    if download_wake is None or model_arch is None:
        from moonshine_voice import ModelArch, get_model_for_language

        download_wake = download_wake or get_model_for_language
        model_arch = model_arch or ModelArch
    root = model_root.expanduser().resolve()
    root.mkdir(parents=True, exist_ok=True)
    laya_directory = root / "laya"
    snapshot(repo_id=LAYA_REPOSITORY, revision=LAYA_REVISION, local_dir=laya_directory)
    wake_path, arch = download_wake("de", model_arch.SMALL_STREAMING, cache_root=root / "moonshine")
    if arch != model_arch.SMALL_STREAMING:
        raise ValueError("Moonshine returned an unexpected model architecture.")
    if Path(wake_path).name != MOONSHINE_REVISION:
        raise ValueError("Moonshine returned an unexpected model revision.")
    return {
        "layaModelDirectory": str(laya_directory),
        "wakeModelDirectory": str(Path(wake_path).resolve()),
        "revisions": {"laya": LAYA_REVISION, "wake": MOONSHINE_REVISION},
        "licenses": {"laya": "Apache-2.0", "wake": "MIT"},
        "sources": {"laya": "https://huggingface.co/" + LAYA_REPOSITORY, "wake": MOONSHINE_MODEL_URL},
        "packages": {"laya-coreml": "0.2.0", "moonshine-voice": "0.1.5"},
        "wakeArchitecture": "SMALL_STREAMING",
        "wakeLanguage": "de",
    }
