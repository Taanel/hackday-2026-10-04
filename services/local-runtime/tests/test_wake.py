import base64
import io
import json
from types import SimpleNamespace

import pytest


class Stream:
    def __init__(self):
        self.listener = None
        self.started = False
        self.closed = False
        self.stop_event = None
        self.audio_event = None
        self.audio = []

    def add_listener(self, listener):
        self.listener = listener

    def start(self):
        self.started = True

    def add_audio(self, audio, sample_rate):
        self.audio.append((audio, sample_rate))
        if self.audio_event:
            self.listener.on_line_text_changed(self.audio_event)

    def stop(self):
        if self.stop_event:
            self.listener.on_line_completed(self.stop_event)
        self.started = False

    def close(self):
        self.closed = True


class Transcriber:
    def __init__(self):
        self.streams = []
        self.closed = False

    def create_stream(self, *, update_interval):
        assert update_interval == 0.25
        stream = Stream()
        self.streams.append(stream)
        return stream

    def close(self):
        self.closed = True


def event(text="Hey Friday, öffne Safari.", *, start=0.125, line_id=7):
    return SimpleNamespace(line=SimpleNamespace(text=text, start_time=start, line_id=line_id))


@pytest.mark.parametrize("text", ["Hey Friday", " HEY, FRIDAY! ", "Hey—Friday, öffne Safari", "\"hey friday\" please", "Hey Frida, Licht an", "Hey Freidei", "Hey Freitag", "Hi Friday", "HI, FRIDA! Öffne Safari", "Hi Freidei, Licht an", "Hi Fida, öffne Safari", "Hi Fidder, öffne Safari"])
def test_normalized_whole_wake_prefix_matches(text):
    from friday_runtime.wake import has_wake_prefix

    assert has_wake_prefix(text)


@pytest.mark.parametrize("text", ["hey", "hi", "say hey friday", "Sag Hi Friday", "hey fridaynight", "hi fridaynight", "heyfriday", "hifriday", "hey friday2", "hi friday2", "where is Friday?", "Fridaynight", "Friday2", "Friday", "Friday, open Blender", "FRIDAY!", "Wir treffen uns am Freitag", "Frida", "Hey Freunde", "Hey freitagabend", "Hi Freunde"])
def test_substrings_and_mid_sentence_mentions_do_not_match(text):
    from friday_runtime.wake import has_wake_prefix

    assert not has_wake_prefix(text)


def test_friday_still_works_with_a_personal_hey_friday_profile():
    from friday_runtime.wake import WakeWorker

    class Personal:
        def reset(self): pass
        def add_audio(self, samples): return None

    transcriber = Transcriber()
    output = []
    worker = WakeWorker(transcriber, output.append, listener_base=object, personal=Personal(), allow_bare=True)
    worker.resume()
    assert len(transcriber.streams) == 1
    transcriber.streams[-1].audio_event = event("Friday, open Blender", start=0.0)
    worker.add_audio([0.0] * 4000)
    assert output == [{"type": "wake", "text": "Friday, open Blender", "startSample": 0,
                       "audioSamples": 4000, "generation": 1}]
    worker.close()


def test_local_transcript_diagnostics_are_bounded_and_do_not_trigger_a_wake():
    from friday_runtime.wake import WakeWorker
    transcriber = Transcriber()
    output = []
    worker = WakeWorker(transcriber, output.append, listener_base=object)
    worker.diagnostics = True
    worker.resume()
    transcriber.streams[-1].audio_event = event("Wir treffen uns am Freitag", start=0)
    worker.add_audio([0.0] * 4000)
    worker.add_audio([0.0] * 4000)
    assert output == [{"type": "transcript", "text": "Wir treffen uns am Freitag", "generation": 1}]
    assert not worker.fired
    worker.close()


def test_german_small_constructor_biases_only_the_wake_phrase(monkeypatch):
    import sys
    from friday_runtime.wake import _create_transcriber
    calls = []
    def create(**kwargs): calls.append(kwargs); return object()
    monkeypatch.setitem(sys.modules, "moonshine_voice", SimpleNamespace(ModelArch=SimpleNamespace(SMALL_STREAMING=4,TINY_STREAMING=2),Transcriber=create,TranscriptEventListener=object))
    _create_transcriber("/prepared/model", architecture="small")
    assert calls[0]["model_arch"] == 4
    assert calls[0]["options"]["keyterms"] == "Hey Friday,Hi Friday"
    assert calls[0]["options"]["return_audio_data"] == "false"


def test_one_wake_per_generation_reports_sample_offsets():
    from friday_runtime.wake import WakeWorker

    transcriber = Transcriber()
    output = []
    worker = WakeWorker(transcriber, output.append, listener_base=object)
    worker.resume()
    stream = transcriber.streams[-1]
    stream.audio_event = event()
    worker.add_audio([0.0] * 8000)
    stream.listener.on_line_completed(event())
    stream.listener.on_line_text_changed(event(line_id=8))
    assert output == [{"type": "wake", "text": "Hey Friday, öffne Safari.", "startSample": 2000, "audioSamples": 8000, "generation": 1}]
    assert stream.audio[0][1] == 16000
    worker.close()
    assert stream.closed and transcriber.closed


def test_reset_ignores_old_stop_decode_and_resets_sample_counter():
    from friday_runtime.wake import WakeWorker

    transcriber = Transcriber()
    output = []
    worker = WakeWorker(transcriber, output.append, listener_base=object)
    worker.resume()
    old = transcriber.streams[-1]
    worker.add_audio([0.0] * 10000)
    old.stop_event = event()
    worker.reset()
    old.listener.on_line_text_changed(event())
    new = transcriber.streams[-1]
    new.audio_event = event(start=0.0)
    worker.add_audio([0.0] * 4000)
    assert old.closed
    assert output == [{"type": "wake", "text": "Hey Friday, öffne Safari.", "startSample": 0, "audioSamples": 4000, "generation": 2}]
    worker.close()


def test_pause_discards_audio_and_resume_starts_fresh_generation():
    from friday_runtime.wake import WakeWorker

    transcriber = Transcriber()
    output = []
    worker = WakeWorker(transcriber, output.append, listener_base=object)
    worker.resume()
    old = transcriber.streams[-1]
    old.stop_event = event()
    worker.pause()
    worker.add_audio([0.0] * 1000)
    assert output == []
    assert old.audio == []
    worker.resume()
    new = transcriber.streams[-1]
    new.audio_event = event(start=0.0)
    worker.add_audio([0.0] * 500)
    assert output[-1]["audioSamples"] == 500
    worker.close()


@pytest.mark.parametrize("start", [None, -1.0, float("nan"), float("inf"), 100.0])
def test_invalid_timestamps_never_fabricate_an_audio_offset(start):
    from friday_runtime.wake import WakeWorker

    transcriber = Transcriber()
    output = []
    worker = WakeWorker(transcriber, output.append, listener_base=object)
    worker.resume()
    transcriber.streams[-1].audio_event = event(start=start)
    worker.add_audio([0.0] * 1600)
    assert not any(message.get("type") == "wake" for message in output)
    assert output[-1]["type"] == "error"
    worker.close()


def test_worker_wire_starts_ready_and_shuts_down_at_eof(tmp_path):
    from friday_runtime.wake import run_wake

    transcriber = Transcriber()
    loaded = []
    output = []

    def create(path):
        loaded.append(path)
        return transcriber, object

    source = io.StringIO(json.dumps({"op": "audio", "pcm": base64.b64encode(b"\0" * 1600).decode()}) + '\n{"op":"pause"}\n{"op":"resume"}\n{"op":"reset"}\n')
    run_wake(tmp_path, source, output.append, create=create, profile_path=tmp_path / "profile.json")
    assert loaded == [str(tmp_path)]
    assert output == [{"type": "ready", "provider": "wake", "generation": 1}]
    assert len(transcriber.streams) == 3
    assert all(stream.closed for stream in transcriber.streams)
    assert transcriber.closed


def test_control_acknowledgments_follow_operations_and_report_generation(tmp_path):
    from friday_runtime.wake import run_wake

    transcriber = Transcriber()
    output = []
    identifiers = ["e0d7c808-a0d3-4130-a2b8-2dbd19b3b6e1", "3f4c9a8b-8b32-4aa4-9092-5e35be14c9ad", "7ec15a40-d6d4-43bb-b71d-cf8d32e44564"]

    def emit(message):
        if message.get("id") == identifiers[0]:
            assert transcriber.streams[-1].closed
        elif message.get("id") in identifiers[1:]:
            assert transcriber.streams[-1].started
        output.append(message)

    source = io.StringIO("\n".join(json.dumps({"id": identifier, "op": operation}) for identifier, operation in zip(identifiers, ["pause", "resume", "reset"])) + "\n")
    run_wake(tmp_path, source, emit, create=lambda path: (transcriber, object), profile_path=tmp_path / "profile.json")
    assert output == [
        {"type": "ready", "provider": "wake", "generation": 1},
        {"id": identifiers[0], "generation": 1},
        {"id": identifiers[1], "generation": 2},
        {"id": identifiers[2], "generation": 3},
    ]
