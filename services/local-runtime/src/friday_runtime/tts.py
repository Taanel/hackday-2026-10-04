"""Offline German Piper synthesis. Voice assets are prepared separately."""

import base64
import io
from pathlib import Path
from typing import Callable
import wave

from .protocol import ProtocolError, correlation_id, existing_model_directory, iter_requests

VOICE = "piper_de_DE-thorsten-high"


def prepare_tts(model_dir: Path) -> dict:
    from moonshine_voice import TextToSpeech

    root = model_dir.expanduser().resolve()
    root.mkdir(parents=True, exist_ok=True)
    voice = TextToSpeech().language("de").voice(VOICE).models_from(root, download=True).load()
    voice.close()
    return {"ttsModelDirectory": str(root), "voice": VOICE, "language": "de"}


def encode_audio(samples, rate: int) -> bytes:
    import numpy as np

    if type(rate) is not int or not 8000 <= rate <= 48000 or not 1 <= len(samples) <= 700000:
        raise ValueError("Invalid local speech audio.")
    audio = np.asarray(samples, dtype=np.float32)
    if audio.ndim != 1 or not np.isfinite(audio).all():
        raise ValueError("Invalid local speech audio.")
    output = io.BytesIO()
    with wave.open(output, "wb") as wav:
        wav.setnchannels(1); wav.setsampwidth(2); wav.setframerate(rate)
        wav.writeframes((np.clip(audio, -1, 1) * 32767).astype("<i2").tobytes())
    return output.getvalue()


def _create_synthesizer(path: str):
    from moonshine_voice import TextToSpeech

    return TextToSpeech().language("de").voice(VOICE).models_from(path, download=False).load()


def run_tts(model_dir: Path, source, emit, *, create: Callable = _create_synthesizer) -> None:
    synthesizer = create(existing_model_directory(model_dir))
    try:
        emit({"type": "ready", "provider": "tts", "voice": VOICE})
        for request in iter_requests(source):
            identifier = None if isinstance(request, ProtocolError) else correlation_id(request)
            try:
                if isinstance(request, ProtocolError): raise request
                text = request.get("text")
                if identifier is None or request.get("op") != "speak" or not isinstance(text, str) or not text.strip() or len(text) > 400:
                    raise ProtocolError("Speech request must have a UUID and 1–400 text characters.")
                samples, rate = synthesizer.synthesize(text)
                audio = encode_audio(samples, rate)
            except ProtocolError as error:
                emit({"id": identifier, "error": str(error)})
            except Exception:
                emit({"id": identifier, "error": "Local German speech synthesis failed."})
            else:
                emit({"id": identifier, "wav": base64.b64encode(audio).decode("ascii")})
    finally:
        synthesizer.close()
