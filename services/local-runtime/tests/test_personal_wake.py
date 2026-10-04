import wave

import numpy as np
import pytest


def phrase(speed=1.0, gain=0.2, order=(220, 600, 330, 900)):
    parts = []
    for frequency in order:
        t = np.arange(int(0.22 * 16000 / speed)) / 16000
        parts.append(gain * np.sin(2 * np.pi * frequency * t) * np.hanning(len(t)))
    return np.concatenate(parts).astype(np.float32)


def save_wav(path, samples):
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(16000)
        wav.writeframes((samples * 32767).astype("<i2").tobytes())


def profile(tmp_path):
    from friday_runtime.personal_wake import PersonalWakeProfile

    paths = []
    for index, speed in enumerate((0.95, 1.0, 1.05)):
        path = tmp_path / f"sample-{index}.wav"
        save_wav(path, phrase(speed))
        paths.append(path)
    target = tmp_path / "profile.json"
    PersonalWakeProfile.enroll(paths, target)
    return PersonalWakeProfile.load(target)


@pytest.mark.parametrize("speed,gain", [(1.0, 0.2), (1.15, 0.1), (0.85, 0.3)])
def test_personal_phrase_matches_volume_and_speed_changes(tmp_path, speed, gain):
    detector = profile(tmp_path)
    audio = np.concatenate([np.zeros(4000), phrase(speed, gain), np.zeros(1000)])
    match = None
    for offset in range(0, len(audio), 1365):
        match = detector.add_audio(audio[offset:offset + 1365]) or match
    assert match is not None
    assert 2000 <= match <= 6000


def test_unrelated_voiced_audio_and_silence_do_not_wake(tmp_path):
    detector = profile(tmp_path)
    rng = np.random.default_rng(17)
    for audio in (np.zeros(16000), phrase(order=(1600, 2500, 1800, 3000)), rng.normal(0, 0.05, 16000)):
        detector.reset()
        matches = [detector.add_audio(audio[i:i + 1365]) for i in range(0, len(audio), 1365)]
        assert all(match is None for match in matches)


def test_continuous_wake_plus_command_matches_before_command_finishes(tmp_path):
    detector = profile(tmp_path)
    audio = np.concatenate([phrase(), phrase(order=(1700, 1200, 2100, 2600))])
    triggered_at = None
    for offset in range(0, len(audio), 1365):
        if detector.add_audio(audio[offset:offset + 1365]) is not None:
            triggered_at = offset + 1365
            break
    assert triggered_at is not None
    assert triggered_at < len(phrase()) + 6000


def test_invalid_enrollment_keeps_previous_profile(tmp_path):
    from friday_runtime.personal_wake import PersonalWakeProfile

    profile(tmp_path)
    target = tmp_path / "profile.json"
    previous = target.read_bytes()
    bad = tmp_path / "silence.wav"
    save_wav(bad, np.zeros(16000))
    with pytest.raises(ValueError):
        PersonalWakeProfile.enroll([bad] * 3, target)
    assert target.read_bytes() == previous


def test_profile_requires_three_samples_and_reset_forgets_old_pcm(tmp_path):
    from friday_runtime.personal_wake import PersonalWakeProfile

    detector = profile(tmp_path)
    with pytest.raises(ValueError):
        PersonalWakeProfile.enroll([], tmp_path / "unused.json")
    detector.add_audio(phrase()[:5000])
    detector.reset()
    assert detector.add_audio(np.zeros(1000)) is None


def test_worker_enrollment_uses_local_profile_and_can_recover_a_corrupt_one(tmp_path):
    import io
    import json
    from uuid import uuid4
    from friday_runtime.wake import run_wake

    class Stream:
        def add_listener(self, listener): pass
        def start(self): pass
        def stop(self): pass
        def close(self): pass

    class Transcriber:
        def create_stream(self, **kwargs): return Stream()
        def close(self): pass

    target = tmp_path / "profile.json"
    target.write_text("broken JSON")
    paths = []
    for i in range(3):
        path = tmp_path / f"sample-{i}.wav"
        save_wav(path, phrase())
        paths.append(str(path))
    identifier = str(uuid4())
    source = io.StringIO(json.dumps({"id": identifier, "op": "enroll", "paths": paths}) + "\n")
    output = []
    run_wake(tmp_path, source, output.append, create=lambda path: (Transcriber(), object), profile_path=target)
    assert output[0]["type"] == "ready"
    assert output[-1]["id"] == identifier
    assert "error" not in output[-1]
    assert json.loads(target.read_text())["version"] == 1
