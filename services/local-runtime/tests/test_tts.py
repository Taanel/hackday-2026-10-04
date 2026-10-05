import base64
import io
import json
from uuid import uuid4

import pytest


def test_local_tts_returns_wav_without_writing_audio_or_network_downloads(tmp_path):
    from friday_runtime.tts import run_tts

    class Synthesizer:
        closed = False
        def synthesize(self, text):
            assert text == "Hallo Welt."
            return [0.1, -0.1] * 100, 22050
        def close(self): self.closed = True

    synth = Synthesizer()
    identifier = str(uuid4())
    output = []
    request = {"id": identifier, "op": "speak", "text": "Hallo Welt."}
    run_tts(tmp_path, io.StringIO(json.dumps(request) + "\n"), output.append, create=lambda path: synth)
    assert output[0]["type"] == "ready"
    assert output[1]["id"] == identifier
    wav = base64.b64decode(output[1]["wav"], validate=True)
    assert wav[:4] == b"RIFF" and wav[8:12] == b"WAVE"
    assert synth.closed
    assert list(tmp_path.iterdir()) == []


@pytest.mark.parametrize("text", ["", " " * 5, "a" * 401])
def test_local_tts_rejects_empty_or_unbounded_text(tmp_path, text):
    from friday_runtime.tts import run_tts

    class Synthesizer:
        def synthesize(self, text): pytest.fail("Invalid input reached the model")
        def close(self): pass
    output = []
    run_tts(tmp_path, io.StringIO(json.dumps({"id": str(uuid4()), "op": "speak", "text": text}) + "\n"), output.append, create=lambda path: Synthesizer())
    assert "error" in output[1]


@pytest.mark.parametrize("samples,rate", [([float("nan")], 22050), ([0.0] * 800001, 22050), ([0.1], 0)])
def test_local_audio_rejects_nonfinite_or_unbounded_output(samples, rate):
    from friday_runtime.tts import encode_audio
    with pytest.raises(ValueError): encode_audio(samples, rate)
