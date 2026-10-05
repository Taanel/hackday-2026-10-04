# Build 11 — Gemini 3.8 und getrennte Sprachschlüssel

TTS verwendet ausschließlich `gemini-3.8-flash-lite-tts` und `gemini-3.8-flash-tts`.
3.1-Anfragen und der Legacy-PCM-Decoder sind entfernt. Vier unabhängige lokale
Sprachschlüssel-Plätze können über SecureFields gespeichert, ersetzt und entfernt
werden. Der Reasoning-Store wird dabei nicht geschrieben oder invalidiert.

Zehn gezielte Swift-Tests bestanden. Geprüft: nur 3.8 erlaubt, Schlüssel-Speicherung/Dateirechte, Duplikate und
ungültige Eingaben, Entfernen einzelner Plätze, Schutz des Hauptschlüssels, Leeren
nur des gespeicherten Eingabefelds, Rotation über vier Header-Schlüssel, Weitergabe
bei 429, Überspringen gesperrter Kombinationen und Abbruch vor Wiedergabe.
Mehrere Schlüssel wurden mit einer lokalen URLProtocol-Teststrecke geprüft;
der Nutzer hat noch keine vier realen TTS-Schlüssel hinterlegt. Beide 3.8-Modelle
lieferten beim vorherigen Live-Test mit dem bestehenden Schlüssel HTTP 200 und WAV.
Keine erneuten API-Aufrufe oder unveränderten Swift-/Python-Suiten für diesen Build.

Die Sprachschlüssel liegen unter
`~/Library/Application Support/Friday/Credentials/gemini-tts-api-keys.json`
mit Datei 0600 und Ordner 0700. Sie werden nicht in UserDefaults, im App-Bundle
oder in Git gespeichert. Ohne eigene Sprachschlüssel bleibt der bisherige
Hauptschlüssel der TTS-Fallback für die Konfiguration.

Google-Limits werden pro Projekt berechnet. Der Store überprüft nicht, ob
unterschiedliche Schlüssel zum selben Projekt gehören, und verspricht deshalb
keine Erhöhung der verfügbaren Quote. Quelle:
[Google-Limits](https://ai.google.dev/gemini-api/docs/rate-limits).
