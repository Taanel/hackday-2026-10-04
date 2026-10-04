import base64
import io
import json
import struct
from uuid import uuid4

import pytest


def test_bad_json_is_reported_and_next_line_is_read():
    from friday_runtime.protocol import ProtocolError, iter_requests

    requests = list(iter_requests(io.BytesIO(b'{oops}\n{"op":"reset"}\n')))
    assert isinstance(requests[0], ProtocolError)
    assert requests[1] == {"op": "reset"}


@pytest.mark.parametrize("payload", [b'[]\n', b'null\n', b'{"v":NaN}\n', b'\xff\n'])
def test_only_json_objects_and_utf8_are_accepted(payload):
    from friday_runtime.protocol import ProtocolError, iter_requests

    assert isinstance(list(iter_requests(io.BytesIO(payload)))[0], ProtocolError)


def test_oversize_line_is_bounded_and_drained_before_next_request():
    from friday_runtime.protocol import MAX_JSON_BYTES, ProtocolError, iter_requests

    source = io.BytesIO(b'x' * (MAX_JSON_BYTES * 2) + b'\n{"op":"pause"}\n')
    requests = list(iter_requests(source))
    assert len(requests) == 2
    assert isinstance(requests[0], ProtocolError)
    assert requests[1] == {"op": "pause"}


def test_wire_json_is_single_line_flushed_and_unicode_safe():
    from friday_runtime.protocol import JSONWriter

    stream = io.StringIO()
    JSONWriter(stream)({"text": "Öffne\nSafari"})
    assert len(stream.getvalue().splitlines()) == 1
    assert json.loads(stream.getvalue()) == {"text": "Öffne\nSafari"}


@pytest.mark.parametrize("text", ["", "   ", 4, None])
def test_decision_text_is_required(text):
    from friday_runtime.protocol import ProtocolError, decision_request

    with pytest.raises(ProtocolError):
        decision_request({"id": str(uuid4()), "op": "decide", "text": text})


def test_decision_text_has_a_byte_limit():
    from friday_runtime.protocol import MAX_TEXT_BYTES, ProtocolError, decision_request

    with pytest.raises(ProtocolError):
        decision_request({"id": str(uuid4()), "op": "decide", "text": "ö" * MAX_TEXT_BYTES})


def test_decision_id_is_a_uuid():
    from friday_runtime.protocol import ProtocolError, decision_request

    with pytest.raises(ProtocolError):
        decision_request({"id": "unexpected", "op": "decide", "text": "Öffne Safari"})


def test_audio_is_little_endian_float32():
    from friday_runtime.protocol import decode_audio

    pcm = base64.b64encode(struct.pack("<3f", -0.5, 0.0, 0.25)).decode()
    assert decode_audio(pcm) == [-0.5, 0.0, 0.25]


@pytest.mark.parametrize("raw", [b"", b"abc", struct.pack("<f", float("nan")), struct.pack("<f", float("inf")), struct.pack("<f", 1.5)])
def test_invalid_pcm_is_rejected(raw):
    from friday_runtime.protocol import ProtocolError, decode_audio

    with pytest.raises(ProtocolError):
        decode_audio(base64.b64encode(raw).decode())


def test_audio_blocks_are_bounded_before_decoding():
    from friday_runtime.protocol import MAX_AUDIO_SAMPLES, ProtocolError, decode_audio

    raw = b"\0" * ((MAX_AUDIO_SAMPLES + 1) * 4)
    with pytest.raises(ProtocolError):
        decode_audio(base64.b64encode(raw).decode())


def test_invalid_base64_is_rejected():
    from friday_runtime.protocol import ProtocolError, decode_audio

    with pytest.raises(ProtocolError):
        decode_audio("not*base64")
