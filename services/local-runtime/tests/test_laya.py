import copy
import io
from uuid import uuid4

import pytest


def test_safari_search_is_an_explicit_local_model_option():
    from friday_runtime.laya import INTENT_QUESTION
    assert "search_web" in INTENT_QUESTION["intent"]["criteria"]


def prediction():
    return {
        "answers": {
            "intent": {
                "type": "choice",
                "choice": "open_app",
                "probabilities": {
                    "open_app": 0.81,
                    "create_note": 0.10,
                    "search_web": 0.0,
                    "switch_desktop": 0.0,
                    "find_project": 0.0,
                    "reasoning": 0.06,
                    "unknown": 0.03,
                },
                "confidence": 0.54,
            }
        },
        "usage": {
            "truncated": False,
            "truncated_questions": [],
            "state_tokens_dropped": 0,
        },
    }


class Agent:
    def __init__(self, result=None):
        self.result = result or prediction()
        self.calls = []
        self.closed = False

    def predict(self, text, questions):
        self.calls.append((text, copy.deepcopy(questions)))
        return self.result

    def close(self):
        self.closed = True


def test_ready_follows_warmup_and_request_uses_choice_probability(tmp_path):
    from friday_runtime.laya import run_laya

    agent = Agent()
    identifier = str(uuid4())
    output = []

    def emit(message):
        if message.get("type") == "ready":
            assert len(agent.calls) == 1
        output.append(message)

    loaded = []

    def load(path, **kwargs):
        loaded.append((path, kwargs))
        return agent

    source = io.StringIO('{"id":"' + identifier + '","op":"decide","text":"Öffne Safari."}\n')
    run_laya(tmp_path, source, emit, load=load)

    assert loaded == [(str(tmp_path), {"local_files_only": True})]
    assert output == [
        {"type": "ready", "provider": "laya"},
        {"id": identifier, "intent": "open_app", "confidence": 0.81, "truncated": False},
    ]
    assert agent.calls[-1][0] == "Öffne Safari."
    question = agent.calls[-1][1]["intent"]
    assert question["type"] == "choice"
    assert set(question["criteria"]) == {"open_app", "search_web", "create_note", "switch_desktop", "find_project", "reasoning", "unknown"}
    assert all(isinstance(value, str) and value for value in question["criteria"].values())
    assert agent.closed


@pytest.mark.parametrize("usage", [
    {"truncated": True},
    {"truncated_questions": ["intent"]},
    {"state_tokens_dropped": 3},
    {"options": {"intent": {"total": 5, "distinct": 4, "tokens_per_option": 2}}},
])
def test_truncated_state_or_collapsed_options_cannot_become_a_decision(usage):
    from friday_runtime.laya import PredictionError, parse_prediction

    result = prediction()
    result["usage"].update(usage)
    with pytest.raises(PredictionError) as caught:
        parse_prediction(result)
    assert caught.value.truncated


@pytest.mark.parametrize("value", [float("nan"), float("inf"), -0.2, 1.2, True, "0.81"])
def test_invalid_probabilities_are_rejected(value):
    from friday_runtime.laya import PredictionError, parse_prediction

    result = prediction()
    result["answers"]["intent"]["probabilities"]["open_app"] = value
    with pytest.raises(PredictionError):
        parse_prediction(result)


@pytest.mark.parametrize("mutation", ["missing", "wrong_sum", "wrong_choice", "wrong_type", "usage"])
def test_malformed_model_results_are_rejected(mutation):
    from friday_runtime.laya import PredictionError, parse_prediction

    result = prediction()
    answer = result["answers"]["intent"]
    if mutation == "missing":
        del answer["probabilities"]["unknown"]
    elif mutation == "wrong_sum":
        answer["probabilities"]["unknown"] = 0.5
    elif mutation == "wrong_choice":
        answer["choice"] = "create_note"
    elif mutation == "wrong_type":
        answer["type"] = "noul"
    else:
        result["usage"] = None
    with pytest.raises(PredictionError):
        parse_prediction(result)


def test_errors_preserve_id_and_do_not_echo_transcript_or_model_exception(tmp_path):
    from friday_runtime.laya import run_laya

    class FailingAfterWarmup(Agent):
        def predict(self, text, questions):
            if self.calls:
                raise ValueError("PRIVATE REQUEST CONTENT")
            return super().predict(text, questions)

    agent = FailingAfterWarmup()
    identifier = str(uuid4())
    output = []
    run_laya(tmp_path, io.StringIO('{"id":"' + identifier + '","op":"decide","text":"PRIVATE TEXT"}\n'), output.append, load=lambda *a, **k: agent)
    assert output[-1]["id"] == identifier
    assert "error" in output[-1]
    assert "PRIVATE" not in str(output)
    assert agent.closed


def test_warmup_failure_never_emits_ready(tmp_path):
    from friday_runtime.laya import PredictionError, run_laya

    agent = Agent()
    agent.result["usage"]["truncated"] = True
    output = []
    with pytest.raises(PredictionError):
        run_laya(tmp_path, io.StringIO(), output.append, load=lambda *a, **k: agent)
    assert output == []
    assert agent.closed


def test_truncation_on_request_is_reported_with_id(tmp_path):
    from friday_runtime.laya import run_laya

    class TruncatesAfterWarmup(Agent):
        def predict(self, text, questions):
            if self.calls:
                self.result["usage"]["truncated_questions"] = ["intent"]
            return super().predict(text, questions)

    identifier = str(uuid4())
    output = []
    run_laya(tmp_path, io.StringIO('{"id":"' + identifier + '","op":"decide","text":"Öffne Safari"}\n'), output.append, load=lambda *a, **k: TruncatesAfterWarmup())
    assert output[-1]["id"] == identifier
    assert output[-1]["truncated"] is True
    assert "intent" not in output[-1]


def test_invalid_id_cannot_leak_text_or_break_next_request(tmp_path):
    import json
    from friday_runtime.laya import run_laya

    identifier = str(uuid4())
    source = io.StringIO(json.dumps({"id": "\ud800", "op": "decide", "text": "Hallo"}) + "\n" + json.dumps({"id": identifier, "op": "decide", "text": "Öffne Safari"}) + "\n")
    output = []
    run_laya(tmp_path, source, output.append, load=lambda *a, **k: Agent())
    assert output[1]["id"] is None
    assert output[2]["id"] == identifier


def test_huge_integer_probability_is_a_prediction_error():
    from friday_runtime.laya import PredictionError, parse_prediction

    result = prediction()
    result["answers"]["intent"]["probabilities"]["open_app"] = 10 ** 400
    with pytest.raises(PredictionError):
        parse_prediction(result)
