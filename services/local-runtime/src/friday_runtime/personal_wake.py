"""Local acoustic wake prototype: normalized mel features and subsequence DTW.

This recognizes an enrolled sound pattern, not a person's identity. Raw voice
recordings are temporary; only bounded spectral templates are persisted.
"""

import json
import os
from pathlib import Path
import wave

import numpy as np

RATE = 16000
HOP = 320
FRAME = 400
MAX_SAMPLES = RATE * 4
PROFILE_PATH = Path.home() / "Library/Application Support/Friday/VoiceProfile/profile.json"


def _filters():
    frequencies = np.fft.rfftfreq(512, 1 / RATE)
    mel = np.linspace(2595 * np.log10(1 + 80 / 700), 2595 * np.log10(1 + 7600 / 700), 34)
    edges = 700 * (10 ** (mel / 2595) - 1)
    return np.maximum(0, np.minimum(
        (frequencies[None, :] - edges[:-2, None]) / (edges[1:-1] - edges[:-2])[:, None],
        (edges[2:, None] - frequencies[None, :]) / (edges[2:] - edges[1:-1])[:, None],
    ))


MEL_FILTERS = _filters()
DCT = np.cos(np.pi / 32 * np.arange(1, 14)[:, None] * (np.arange(32)[None, :] + 0.5))


def features(samples):
    samples = np.asarray(samples, dtype=np.float32)
    if len(samples) < FRAME:
        return np.empty((0, 13), dtype=np.float32)
    frames = np.lib.stride_tricks.sliding_window_view(samples, FRAME)[::HOP]
    energy = np.sqrt(np.mean(frames ** 2, axis=1))
    spectrum = abs(np.fft.rfft(frames * np.hanning(FRAME), n=512)) ** 2
    cepstra = np.log(np.maximum(spectrum @ MEL_FILTERS.T, 1e-10)) @ DCT.T
    norms = np.linalg.norm(cepstra, axis=1, keepdims=True)
    result = cepstra / np.maximum(norms, 1e-8)
    result[energy < 0.003] = 0
    return result.astype(np.float32)


def _match(template, live):
    """Return average cost and span, allowing bounded speed differences."""
    n, m = len(template), len(live)
    if m < n * 0.6:
        return 1.0, 0, 0
    distances = np.maximum(0, 1 - template @ live.T)
    previous = np.zeros(m + 1)
    starts = np.arange(m + 1)
    lengths = np.zeros(m + 1, dtype=int)
    for row in distances:
        current = np.full(m + 1, np.inf)
        current_starts = np.zeros(m + 1, dtype=int)
        current_lengths = np.zeros(m + 1, dtype=int)
        for j in range(1, m + 1):
            options = (previous[j - 1], previous[j], current[j - 1])
            # Scalar minimum with the same first-index tie behavior as argmin.
            # Avoid allocating a NumPy array for every DTW cell.
            k = 0 if options[0] <= options[1] and options[0] <= options[2] else (1 if options[1] <= options[2] else 2)
            if k == 0:
                start, length = starts[j - 1], lengths[j - 1]
            elif k == 1:
                start, length = starts[j], lengths[j]
            else:
                start, length = current_starts[j - 1], current_lengths[j - 1]
            current[j] = row[j - 1] + options[k]
            current_starts[j] = start
            current_lengths[j] = length + 1
        previous, starts, lengths = current, current_starts, current_lengths
    best = (1.0, 0, 0)
    # Only a recent endpoint may trigger; old phrases must not reappear.
    for end in range(max(1, m - 4), m + 1):
        start = int(starts[end])
        duration = end - start
        if not n * 0.6 <= duration <= n * 1.6:
            continue
        if np.mean(np.linalg.norm(live[start:end], axis=1) > 0.5) < 0.6:
            continue
        score = float(previous[end] / max(1, lengths[end]))
        if score < best[0]:
            best = score, start, end
    return best


def _read_sample(path):
    with wave.open(str(path)) as wav:
        if wav.getnchannels() != 1 or wav.getsampwidth() != 2 or wav.getframerate() != RATE or wav.getnframes() > RATE * 6:
            raise ValueError("Bitte nur kurz Hey Friday einsprechen (maximal drei Sekunden).")
        samples = np.frombuffer(wav.readframes(wav.getnframes()), dtype="<i2").astype(np.float32) / 32768
    if len(samples) < FRAME:
        raise ValueError("Die Sprachprobe ist zu kurz.")
    blocks = np.array([np.sqrt(np.mean(block ** 2)) for block in np.array_split(samples, max(1, len(samples) // 160))])
    voiced = np.flatnonzero(blocks > max(0.004, float(blocks.max()) * 0.06))
    if not len(voiced):
        raise ValueError("Kein Sprachsignal erkannt. Bitte näher am Mikrofon sprechen.")
    block_size = len(samples) / len(blocks)
    start = max(0, int((voiced[0] - 1) * block_size))
    end = min(len(samples), int((voiced[-1] + 2) * block_size))
    samples = samples[start:end]
    if not RATE * 0.35 <= len(samples) <= RATE * 3:
        raise ValueError("Bitte nur Hey Friday sagen, ohne anschließenden Befehl.")
    return features(samples)


class PersonalWakeProfile:
    def __init__(self, templates):
        self.templates = templates
        self.reset()

    @classmethod
    def enroll(cls, paths, target=PROFILE_PATH):
        if len(paths) != 3:
            raise ValueError("Bitte Hey Friday dreimal einsprechen.")
        templates = [_read_sample(path) for path in paths]
        # A bad recording must not overwrite a previously working profile.
        sizes = [len(template) for template in templates]
        if min(sizes) / max(sizes) < 0.5:
            raise ValueError("Die Sprachproben sind zu unterschiedlich. Bitte erneut einsprechen.")
        target = Path(target)
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.with_suffix(".tmp")
        temporary.write_text(json.dumps({"version": 1, "templates": [t.tolist() for t in templates]}))
        os.chmod(temporary, 0o600)
        os.replace(temporary, target)

    @classmethod
    def load(cls, path=PROFILE_PATH):
        path = Path(path)
        if not path.exists():
            return None
        if path.stat().st_size > 300_000:
            raise ValueError("Ungültiges persönliches Wake-Profil. Bitte neu anlernen.")
        data = json.loads(path.read_text())
        if data.get("version") != 1 or len(data.get("templates", [])) != 3:
            raise ValueError("Ungültiges persönliches Wake-Profil. Bitte neu anlernen.")
        templates = [np.asarray(t, dtype=np.float32) for t in data["templates"]]
        if any(t.ndim != 2 or t.shape[1] != 13 or not 15 <= len(t) <= 150 or not np.isfinite(t).all() for t in templates):
            raise ValueError("Ungültiges persönliches Wake-Profil. Bitte neu anlernen.")
        return cls(templates)

    def reset(self):
        self.samples = np.empty(0, dtype=np.float32)
        self.total = 0
        self.last_check = 0
        self.fired = False

    def add_audio(self, samples):
        self.total += len(samples)
        self.samples = np.concatenate([self.samples, np.asarray(samples, dtype=np.float32)])[-MAX_SAMPLES:]
        if self.fired or self.total - self.last_check < 1600:
            return None
        self.last_check = self.total
        if len(self.samples) < FRAME or np.sqrt(np.mean(self.samples[-1600:] ** 2)) < 0.003:
            return None
        live = features(self.samples)
        matches = sorted(_match(template, live) for template in self.templates)
        # Two separate recordings must agree on a recent phrase.
        if matches[1][0] > 0.16 or abs(matches[0][1] - matches[1][1]) > 12:
            return None
        self.fired = True
        # Preserve a short lead-in so a flexible alignment cannot clip "Hey".
        return max(0, self.total - len(self.samples) + matches[0][1] * HOP - 3200)
