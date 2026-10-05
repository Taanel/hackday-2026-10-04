# Build 9 — Prüfung vom 2026-10-05

## Home Assistant

- Reale Discovery mit dem lokal gespeicherten Token: 402 unterstützte Geräte/Entitäten.
- Echter lokaler Laya-Worker: sechs kurze und vollständige Hausbefehle als
  `home_control`, ca. 150–160 ms Klassifikation, Konfidenz 0,9995–0,9999.
- Direkter Service-Test schaltete die Wohnzimmer-Gruppe ein. Unmittelbar nach
  HTTP 200 meldete HA noch „aus“, nach etwa einer Sekunde Gruppe und beide Lampen „an“.
  Der Nutzer bestätigte das tatsächlich eingeschaltete Licht.
- Der neue Swift-Client bestätigte den bereits gewünschten Zustand nach seinem
  Service-Aufruf über denselben realen Gerätekatalog. Weitere Tests zu Parser,
  Mehrdeutigkeit, Gruppen, Readback und ausbleibender Bestätigung liefen mit Mocks.
- Kein Live-Test von Dimmen, Steckdosen, Szenen oder Thermostaten. Temperatur-
  Steuerung verlangt derzeit Celsius; die reale Instanz meldete Fahrenheit.

## Vorlesen

- Ein realer Gemini-TTS-Aufruf meldete HTTP 429: für diesen Schlüssel/Modell
  10 Anfragen pro Tag im Free Tier ausgeschöpft. Diese Antwort erklärt die
  ausgefallene Cloud-Stimme; Kontingente können sich ändern.
- Piper Thorsten High wurde lokal vorbereitet und erzeugte deutsches WAV-Audio.
- Native Swift-Probe verwendete den tatsächlichen TTS-Worker und
  `LocalPiperSpeechOutput`. AVAudioPlayer spielte den Testsatz ab und meldete
  erfolgreichen Abschluss; initiales Laden der Stimme etwa 1,1 Sekunden.
- Chunk-Grenzen, lokaler Standard, Cloud-Fallback ohne wiederholte Cloud-Anfrage
  und Abbruch wurden gezielt getestet. Kein ElevenLabs- oder kostenpflichtiger Aufruf.

## Wake und leise Sprache

- Das bisherige englische Tiny-Modell transkribierte deutsches „Hey Friday“ oft falsch.
- German Small Streaming plus Keyword-Bias erkannte die Phrase in synthetischen
  deutschen Aufnahmen bei Skalierung 0,1, 0,03 und 0,01. Normale Sätze ohne
  Wake-Phrase aktivierten nicht. Dies ersetzt keinen Live-Test mit dem Nutzer.
- Regression für durchgehende leise Sprache mit RMS 0,003 scheiterte an der alten
  festen Sprachschwelle und besteht mit der neuen Ruhepegel-Anpassung.
- Wake-Diagnosen und reine Wake-Phrase wurden gezielt geprüft. Bare Friday und
  Acoustic-only bleiben standardmäßig aus. Audio-/Diagnosehistorie wird nicht gespeichert.
- Energieverbrauch des deutschen Small-Modells am echten Mikrofon noch nicht
  vermessen. Daraus folgt noch keine Zusicherung eines geringeren Gesamtverbrauchs.

## Installation

Nur die betroffenen Swift-/Python-Tests wurden ausgeführt; keine erneute komplette
Swift-Suite. Release-Build 9 wurde erstellt und Signatur, unveränderte Signing-
Identität, Release-UUID und gebündelte Worker geprüft. Tatsächliche lokale Gemini-
und HA-Schlüssel kommen weder in versionierten Dateien noch im App-Bundle vor.
Die App liegt unter `~/Applications/Friday.app`; Build 8 ist im privaten
Application-Support-Ordner gesichert. Der laufende Prozess wurde nicht automatisch
beendet oder gestartet. Die Mikrofonabnahme setzt das manuelle Neuöffnen voraus.
