# Build 10 — Gemini-TTS wieder bevorzugt

Google lieferte beim erneuten Live-Test mit dem vorhandenen privaten Schlüssel
wieder HTTP 200 und Audio. Je ein kurzer Testsatz wurde erfolgreich mit
`gemini-3.8-flash-lite-tts`, `gemini-3.8-flash-tts` und
`gemini-3.1-flash-tts-preview` angefragt. Die GA-Modelle lieferten WAV, Preview
lieferte `audio/l16; rate=24000; channels=1`. Das sind erfolgreiche API-Tests;
sie beweisen weder ein festes Kontingent noch identische Klangqualität aller Modelle.

Der bevorzugte Provider ist wieder Gemini. Drei Modelle rotieren; Kore/Aoede/Charon
bleiben je nach Auswahl gleich. Erreichte Limits sperren einzelne Modelle bis zum
Retry-Zeitpunkt bzw. dem Tagesreset. Alle Versuche teilen 20 Sekunden. Bei Cloud-
Fehlern übernimmt Piper für mindestens zwei Minuten, danach darf die Cloud wieder
versucht werden. Modell-Sperren bleiben dabei erhalten; es werden keine zusätzlichen
API-Schlüssel oder Google-Projekte angelegt und keine Abrechnung aktiviert.

12 gezielte Swift-Tests bestanden. Sie prüfen Rotation, Cooldown-Erholung, private
Header, beide Audioformate, Ablehnung ungültiger PCM-Formate, Modellwechsel nach 429,
keine wiederholten Requests an gesperrte Modelle, lokalen Ersatz mit sichtbarem
Fehlergrund und Abbruch vor Wiedergabe. Neue Pool-/Schema- und Erholungstests
scheiterten vor der Implementierung. Unveränderte Swift-/Python-Suiten wurden
nicht erneut ausgeführt.

Quellen: [Google TTS](https://ai.google.dev/gemini-api/docs/speech-generation),
[Limits je Projekt und Modell](https://ai.google.dev/gemini-api/docs/rate-limits).
Die Quota gilt pro Projekt; Stimmen oder weitere Schlüssel desselben Projekts
erhöhen sie nicht. Tageslimits werden um Mitternacht Pacific zurückgesetzt.
