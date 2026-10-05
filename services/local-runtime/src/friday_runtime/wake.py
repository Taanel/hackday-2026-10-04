"""Moonshine streaming wake detection using audio supplied by the app."""

import math
from pathlib import Path
import re
from typing import Callable
import unicodedata

from .protocol import (
    Emitter,
    InputStream,
    MAX_TEXT_BYTES,
    ProtocolError,
    SAMPLE_RATE,
    correlation_id,
    decode_audio,
    existing_model_directory,
    iter_requests,
)


def has_wake_prefix(text: str, *, allow_bare: bool = False) -> bool:
    normalized = unicodedata.normalize("NFKC", text).casefold()
    words = re.findall(r"[^\W_]+", normalized)
    # Fixed spellings observed in German ASR for the spoken English name.
    # Still require the complete two-word prefix; no substring/fuzzy match.
    names = {"friday", "frida", "freda", "freidei", "fridey", "freitag", "fida", "fidder"}
    return (len(words) >= 2 and words[0] in {"hey", "hi"} and words[1] in names) or (allow_bare and words[:1] == ["friday"])


def _listener(worker, generation: int, base: type):
    class WakeListener(base):
        def on_line_text_changed(self, event):
            worker.accept_line(generation, event.line)

        def on_line_completed(self, event):
            worker.accept_line(generation, event.line)

        def on_error(self, event):
            worker.stream_error(generation)

    return WakeListener()


class WakeWorker:
    def __init__(self, transcriber, emit: Emitter, *, listener_base: type, personal=None, allow_bare=False, allow_personal=False):
        self.transcriber = transcriber
        self.emit = emit
        self.listener_base = listener_base
        self.stream = None
        self.generation = 0
        self.audio_samples = 0
        self.active = False
        self.fired = False
        self.personal = personal
        self.allow_bare = allow_bare
        self.allow_personal = allow_personal
        self.diagnostics = False
        self.last_diagnostic = -SAMPLE_RATE

    def accept_line(self, generation: int, line) -> None:
        if generation != self.generation or not self.active or self.fired:
            return
        text = getattr(line, "text", None)
        if not isinstance(text, str):
            return
        try:
            if len(text.encode("utf-8")) > MAX_TEXT_BYTES:
                return
            if self.diagnostics and self.audio_samples - self.last_diagnostic >= SAMPLE_RATE:
                self.last_diagnostic = self.audio_samples
                self.emit({"type": "transcript", "text": text[:160], "generation": self.generation})
            if not has_wake_prefix(text, allow_bare=self.allow_bare): return
        except UnicodeError:
            return
        # Moonshine's transcript_line_t.start_time is seconds relative to the
        # start of this stream (core/moonshine-c-api.h), with float precision.
        start_time = getattr(line, "start_time", None)
        if (
            type(start_time) not in (int, float)
            or not math.isfinite(start_time)
            or start_time < 0
            or start_time > self.audio_samples / SAMPLE_RATE
        ):
            self.stream_error(generation, "Wake transcript had an invalid audio timestamp.")
            return
        self.fired = True  # Set before emit: completed/text-changed may repeat.
        self.emit({
            "type": "wake",
            "text": text.strip(),
            "startSample": math.floor(start_time * SAMPLE_RATE),
            "audioSamples": self.audio_samples,
            "generation": self.generation,
        })

    def stream_error(self, generation: int, message: str = "Local wake transcription failed.") -> None:
        if generation == self.generation and self.active:
            self.active = False
            self.emit({"type": "error", "error": message, "generation": generation})

    def add_audio(self, samples: list[float]) -> None:
        if not self.active:
            return
        # Events are emitted synchronously inside add_audio; their offset must
        # include the current block, rather than only preceding blocks.
        self.audio_samples += len(samples)
        if self.personal is not None and self.allow_personal:
            start = self.personal.add_audio(samples)
            if start is not None and not self.fired:
                self.fired = True
                self.emit({"type": "wake", "text": "Hey Friday", "startSample": start,
                           "audioSamples": self.audio_samples, "generation": self.generation})
        # The personal profile was trained with "Hey Friday". Keep transcript
        # wake detection alongside it so "Friday" alone also works. fired
        # prevents the two detectors from emitting the same wake twice.
        if self.stream is not None and not self.fired:
            self.stream.add_audio(samples, SAMPLE_RATE)

    def pause(self) -> None:
        self.active = False
        stream, self.stream = self.stream, None
        if stream is not None:
            try:
                # stop() performs a final decode. Disable callbacks first so
                # stale transcripts cannot wake a paused/new generation.
                stream.stop()
            finally:
                stream.close()

    def resume(self) -> None:
        self.pause()
        self.generation += 1
        self.audio_samples = 0
        self.fired = False
        self.last_diagnostic = -SAMPLE_RATE
        if self.personal is not None:
            self.personal.reset()
        stream = self.transcriber.create_stream(update_interval=0.25)
        self.stream = stream
        stream.add_listener(_listener(self, self.generation, self.listener_base))
        stream.start()
        self.active = True

    def reset(self) -> None:
        self.resume()

    def close(self) -> None:
        try:
            self.pause()
        finally:
            self.transcriber.close()


def _create_transcriber(path: str, *, architecture: str = "tiny"):
    from moonshine_voice import ModelArch, TranscriptEventListener, Transcriber

    arch = ModelArch.SMALL_STREAMING if architecture == "small" else ModelArch.TINY_STREAMING
    return Transcriber(model_path=path, model_arch=arch,
                       options={"keyterms": "Hey Friday,Hi Friday", "keyterm_boost": "2.0", "vad_threshold": "0.35", "return_audio_data": "false"}), TranscriptEventListener


def run_wake(model_dir: Path, source: InputStream, emit: Emitter, *, create: Callable | None = None, profile_path: Path | None = None, architecture: str = "tiny") -> None:
    from .personal_wake import PROFILE_PATH, PersonalWakeProfile

    directory = existing_model_directory(model_dir)
    profile_path = profile_path if profile_path is not None else PROFILE_PATH
    transcriber, listener_base = create(directory) if create is not None else _create_transcriber(directory, architecture=architecture)
    try:
        personal = PersonalWakeProfile.load(profile_path)
    except (ValueError, OSError):
        # A broken profile must not block reset or a new enrollment.
        personal = None
    worker = WakeWorker(transcriber, emit, listener_base=listener_base, personal=personal)
    try:
        worker.resume()
        emit({"type": "ready", "provider": "wake", "generation": worker.generation})
        for request in iter_requests(source):
            identifier = None if isinstance(request, ProtocolError) else correlation_id(request)
            try:
                if isinstance(request, ProtocolError):
                    raise request
                operation = request.get("op")
                if operation == "audio":
                    worker.add_audio(decode_audio(request.get("pcm")))
                elif operation == "reset":
                    worker.reset()
                elif operation == "pause":
                    worker.pause()
                elif operation == "resume":
                    for key in ("allowBare", "allowPersonal", "diagnostics"):
                        if key in request and type(request[key]) is not bool:
                            raise ProtocolError("Invalid wake setting.")
                    worker.allow_bare = request.get("allowBare", False)
                    worker.allow_personal = request.get("allowPersonal", False)
                    worker.diagnostics = request.get("diagnostics", False)
                    worker.resume()
                elif operation == "enroll":
                    paths = request.get("paths")
                    if not isinstance(paths, list) or len(paths) != 3 or not all(isinstance(path, str) for path in paths):
                        raise ProtocolError("Bitte drei Sprachproben aufnehmen.")
                    PersonalWakeProfile.enroll(paths, profile_path)
                    worker.pause()
                    worker.personal = PersonalWakeProfile.load(profile_path)
                elif operation == "clear_profile":
                    profile_path.unlink(missing_ok=True)
                    worker.pause()
                    worker.personal = None
                else:
                    raise ProtocolError("Unsupported wake operation.")
                if operation in ("reset", "pause", "resume", "enroll", "clear_profile") and identifier is not None:
                    # The app awaits this acknowledgment before accepting the
                    # new generation, rejecting old events already in its pipe.
                    emit({"id": identifier, "generation": worker.generation})
            except ProtocolError as error:
                response = {"type": "error", "error": str(error)}
                if identifier is not None:
                    response["id"] = identifier
                emit(response)
            except ValueError as error:
                # Enrollment validation uses fixed messages, never audio/path contents.
                response = {"type": "error", "error": str(error), "generation": worker.generation}
                if identifier is not None:
                    response["id"] = identifier
                emit(response)
            except Exception:
                worker.active = False
                response = {"type": "error", "error": "Local wake operation failed.", "generation": worker.generation}
                if identifier is not None:
                    response["id"] = identifier
                emit(response)
    finally:
        worker.close()
