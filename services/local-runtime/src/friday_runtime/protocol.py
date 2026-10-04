"""Bounded JSON-line input and private stdout for the worker wire protocol."""

from array import array
import base64
import binascii
from contextlib import contextmanager, redirect_stdout
import ctypes
import json
import math
import os
from pathlib import Path
import sys
from typing import BinaryIO, Callable, Iterator, TextIO
from uuid import UUID

SAMPLE_RATE = 16000
MAX_AUDIO_SAMPLES = SAMPLE_RATE
MAX_JSON_BYTES = 128 * 1024
MAX_TEXT_BYTES = 32 * 1024
MAX_PCM_BASE64_BYTES = 4 * ((MAX_AUDIO_SAMPLES * 4 + 2) // 3)

Emitter = Callable[[dict], None]
InputStream = BinaryIO | TextIO


class ProtocolError(ValueError):
    """A fixed, non-sensitive explanation of an invalid wire request."""


class JSONWriter:
    def __init__(self, stream: TextIO):
        self.stream = stream

    def __call__(self, message: dict) -> None:
        self.stream.write(json.dumps(message, ensure_ascii=False, allow_nan=False, separators=(",", ":")) + "\n")
        self.stream.flush()


@contextmanager
def protocol_stdout() -> Iterator[JSONWriter]:
    """Route Python and native model output to stderr, reserving stdout for JSON.

    Native libraries can write directly to file descriptor 1. A duplicate of
    the original pipe stays private to JSONWriter while both fd 1 and Python's
    sys.stdout are redirected before any model import or initialization.
    """
    sys.stdout.flush()
    saved_fd = os.dup(1)
    wire = os.fdopen(os.dup(saved_fd), "w", encoding="utf-8", buffering=1)
    try:
        os.dup2(2, 1)
        with redirect_stdout(sys.stderr):
            yield JSONWriter(wire)
    finally:
        try:
            # printf without a newline can remain buffered until process exit;
            # flush it while fd 1 still points at stderr, before restoring it.
            ctypes.CDLL(None).fflush(None)
            wire.close()
        finally:
            os.dup2(saved_fd, 1)
            os.close(saved_fd)


def _reject_json_constant(value: str) -> None:
    raise ValueError("Non-finite JSON number")


def iter_requests(source: InputStream) -> Iterator[dict | ProtocolError]:
    """Read at most one bounded request at a time, recovering after bad lines."""
    while True:
        line = source.readline(MAX_JSON_BYTES + 1)
        if not line:
            return
        encoded = line.encode("utf-8") if isinstance(line, str) else line
        if len(encoded) > MAX_JSON_BYTES:
            # Drain the rest using bounded reads so the next request remains
            # aligned even when an untrusted sender supplies a huge line.
            while not encoded.endswith(b"\n"):
                rest = source.readline(MAX_JSON_BYTES + 1)
                if not rest:
                    break
                encoded = rest.encode("utf-8") if isinstance(rest, str) else rest
            yield ProtocolError("JSON request exceeds the byte limit.")
            continue
        try:
            message = json.loads(encoded.decode("utf-8"), parse_constant=_reject_json_constant)
            if not isinstance(message, dict):
                raise ValueError("Expected an object")
        except (UnicodeError, ValueError, RecursionError):
            yield ProtocolError("Request must be a valid UTF-8 JSON object.")
            continue
        yield message


def correlation_id(request: dict) -> str | None:
    value = request.get("id")
    if not isinstance(value, str) or len(value) > 64:
        return None
    try:
        UUID(value)
    except ValueError:
        return None
    return value


def decision_request(request: dict) -> tuple[str, str]:
    identifier = correlation_id(request)
    try:
        if identifier is None:
            raise ValueError("Missing id")
        UUID(identifier)
    except ValueError:
        raise ProtocolError("Decision id must be a UUID.") from None
    if request.get("op") != "decide":
        raise ProtocolError("Laya supports only the decide operation.")
    text = request.get("text")
    if not isinstance(text, str) or not text.strip():
        raise ProtocolError("Decision text must be a nonempty string.")
    try:
        length = len(text.encode("utf-8"))
    except UnicodeError:
        raise ProtocolError("Decision text must be valid Unicode.") from None
    if length > MAX_TEXT_BYTES:
        raise ProtocolError("Decision text exceeds the byte limit.")
    return identifier, text


def decode_audio(pcm: object) -> list[float]:
    if not isinstance(pcm, str) or not pcm or len(pcm) > MAX_PCM_BASE64_BYTES:
        raise ProtocolError("PCM block must be bounded base64 float32 audio.")
    try:
        raw = base64.b64decode(pcm, validate=True)
    except (ValueError, binascii.Error):
        raise ProtocolError("PCM block must be valid base64.") from None
    if not raw or len(raw) % 4 or len(raw) > MAX_AUDIO_SAMPLES * 4:
        raise ProtocolError("PCM block must contain at most 16000 float32 samples.")
    samples = array("f")
    samples.frombytes(raw)
    if sys.byteorder != "little":
        samples.byteswap()
    if any(not math.isfinite(sample) or abs(sample) > 1.0 for sample in samples):
        raise ProtocolError("PCM samples must be finite values between -1 and 1.")
    return samples.tolist()


def existing_model_directory(path: Path) -> str:
    directory = path.expanduser().resolve()
    if not directory.is_dir():
        raise ProtocolError("Model directory is missing; run prepare first.")
    return str(directory)
