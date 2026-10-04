"""Local Laya Core ML decisions; no heuristic fallback or downloads."""

import math
from pathlib import Path
from typing import Callable

from .protocol import (
    Emitter,
    InputStream,
    ProtocolError,
    correlation_id,
    decision_request,
    existing_model_directory,
    iter_requests,
)

# Descriptions are part of the model question, rather than postprocessing rules.
# Keep the four options distinct and short enough for the model's head budget.
INTENT_QUESTION = {
    "intent": {
        "type": "choice",
        "instructions": "Welche einzelne Absicht hat die deutsche Nutzeranfrage? Wähle die passendste Aktion.",
        "criteria": {
            "open_app": "Eine genannte Mac-App öffnen oder starten, z. B. Öffne Safari.",
            "create_note": "Eine Notiz mit diktiertem Inhalt erstellen oder speichern, z. B. Notiere den Termin.",
            "reasoning": "Eine Frage beantworten, etwas erklären, planen, berechnen oder ausführlich analysieren.",
            "unknown": "Unklar, keine Anfrage, mehrere Aktionen oder keine der unterstützten Absichten.",
        },
    }
}
INTENTS = frozenset(INTENT_QUESTION["intent"]["criteria"])


class PredictionError(ValueError):
    def __init__(self, message: str, *, truncated: bool = False):
        super().__init__(message)
        self.truncated = truncated


def parse_prediction(result: object) -> dict:
    """Validate model metadata before using its chosen probability."""
    if not isinstance(result, dict) or not isinstance(result.get("usage"), dict):
        raise PredictionError("Laya returned invalid usage metadata.")
    usage = result["usage"]
    truncated = usage.get("truncated")
    questions = usage.get("truncated_questions")
    dropped = usage.get("state_tokens_dropped")
    if (
        type(truncated) is not bool
        or not isinstance(questions, list)
        or not all(isinstance(question, str) for question in questions)
        or type(dropped) is not int
        or dropped < 0
    ):
        raise PredictionError("Laya returned invalid truncation metadata.")
    if truncated or questions or dropped:
        raise PredictionError("Laya truncated the request; no decision was accepted.", truncated=True)
    options = usage.get("options", {})
    if not isinstance(options, dict):
        raise PredictionError("Laya returned invalid option metadata.")
    if options:
        # v0.2.0 reports this field only for collapsed token spans. Such a
        # result cannot distinguish all four intents and must be rejected.
        raise PredictionError("Laya collapsed the options; no decision was accepted.", truncated=True)
    answers = result.get("answers")
    answer = answers.get("intent") if isinstance(answers, dict) else None
    if not isinstance(answer, dict) or answer.get("type") != "choice":
        raise PredictionError("Laya returned an invalid intent answer.")
    choice, probabilities = answer.get("choice"), answer.get("probabilities")
    if not isinstance(choice, str) or choice not in INTENTS:
        raise PredictionError("Laya returned an unsupported intent.")
    if not isinstance(probabilities, dict) or set(probabilities) != INTENTS:
        raise PredictionError("Laya returned an incomplete probability distribution.")
    if any(
        type(value) not in (int, float) or not 0 <= value <= 1 or not math.isfinite(value)
        for value in probabilities.values()
    ):
        raise PredictionError("Laya returned invalid probabilities.")
    # The upstream runtime rounds each of four probabilities to four decimal
    # places, so the sum can differ from one by up to 0.0002.
    if not math.isclose(sum(probabilities.values()), 1.0, abs_tol=0.001):
        raise PredictionError("Laya probabilities do not sum to one.")
    if probabilities[choice] < max(probabilities.values()):
        raise PredictionError("Laya choice does not match its probabilities.")
    return {"intent": choice, "confidence": float(probabilities[choice]), "truncated": False}


def _load_agent(path: str, **kwargs):
    import laya_coreml

    return laya_coreml.load(path, **kwargs)


def run_laya(model_dir: Path, source: InputStream, emit: Emitter, *, load: Callable = _load_agent) -> None:
    directory = existing_model_directory(model_dir)
    agent = load(directory, local_files_only=True)
    try:
        parse_prediction(agent.predict("Öffne Safari.", INTENT_QUESTION))
        emit({"type": "ready", "provider": "laya"})
        for request in iter_requests(source):
            identifier = None if isinstance(request, ProtocolError) else correlation_id(request)
            try:
                if isinstance(request, ProtocolError):
                    raise request
                identifier, text = decision_request(request)
                result = parse_prediction(agent.predict(text, INTENT_QUESTION))
            except PredictionError as error:
                response = {"id": identifier, "error": str(error)}
                if error.truncated:
                    response["truncated"] = True
                emit(response)
            except ProtocolError as error:
                emit({"id": identifier, "error": str(error)})
            except Exception:
                # Never copy model exception text: it may contain request data.
                emit({"id": identifier, "error": "Local Laya prediction failed."})
            else:
                emit({"id": identifier, **result})
    finally:
        close = getattr(agent, "close", None)
        if callable(close):
            close()
