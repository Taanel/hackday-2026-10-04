# Deutsche Stimme und Kosten, Stand 4. Oktober 2026

Friday verwendet Gemini 3.8 Flash-Lite TTS mit Kore (optional Aoede oder Charon).
Ein echter API-Test mit dem bestehenden Schlüssel lieferte WAV-Audio in ca. drei
Sekunden. Die integrierte Wiedergabe wurde bis zum AVAudioPlayer-Abschluss geprüft.
Die subjektive Stimme lässt sich im Friday-Fenster wechseln.

[Google-Preise](https://ai.google.dev/gemini-api/docs/pricing): Free Tier kostenlos
innerhalb des jeweiligen Kontingents. Im bezahlten Standard-Tarif bis 31.12.2026
0,50 USD pro Million Text-Eingabetokens und 6 USD pro Million Audio-Ausgabetokens;
25 Audiotokens pro Sekunde, also etwa 0,54 USD pro Stunde erzeugtem Audio.
Beispiel: 100 Antworten täglich zu je zehn Sekunden, 30 Tage: 4,50 USD Audio,
zuzüglich Text-Eingabe und der separat berechneten Gemini-Antworten. Ab 01.01.2027
verdoppeln sich die hier genannten TTS-Tokenpreise laut aktueller Preisseite.
Friday aktiviert keine Abrechnung oder Buchung.

[ElevenLabs-API-Preise](https://elevenlabs.io/pricing/api): Eleven v4 Turbo
0,011 USD pro 1.000 Zeichen bis 12.10.2026; regulär 0,04 USD. Bei 100 Antworten
täglich à 200 Zeichen (600.000 im Monat) wären das 6,60 USD zum Aktionspreis bzw.
24 USD regulär. Eleven v4: 0,022 bzw. 0,08 USD, also 13,20 bzw. 48 USD für dasselbe
Zeichenvolumen. Kontingente, Steuern und Vertragsbedingungen sind gesondert zu prüfen.
ElevenLabs ist nicht eingebaut, da die natürliche Gemini-Stimme mit dem vorhandenen
Schlüssel bereits funktioniert.

DuckDuckGo Lite und die nichtkommerzielle Open-Meteo-API benötigen in diesem
privaten Prototyp keinen zusätzlichen Schlüssel. Googles native Grounding-Suche
ist für die verwendeten Gemini-Textmodelle laut Preisliste im Free Tier nicht
verfügbar; echte Aufrufe wurden mit HTTP 429 abgelehnt.
