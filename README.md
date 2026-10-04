# Friday — lokaler Assistent für macOS

Erste testbare Version: Thinking-Orb-Overlay oben rechts, native Thinking Orbs,
„Hey Friday“, deutsche Spracheingabe mit Hex, lokale Laya-Entscheidungen und
Computeraktionen. Komplexe Fragen gehen je nach Konfiguration an Gemini 3.8 Flash oder Ollama; nur LLM-Antworten können
optional mit der macOS-Stimme vorgelesen werden.

## Starten

Apple Silicon, macOS 15+, Swift 6, Python 3.12 über [uv](https://docs.astral.sh/uv/).
Das einmalige Setup lädt die offenen Modellgewichte und das offizielle Hex-Binary.
Danach arbeiten Wake, Hex und Laya lokal ohne API-Key.

```bash
./scripts/setup-local-runtime.sh
./scripts/build-macos.sh
open dist/Friday.app
```

Für komplexe Antworten [Ollama](https://ollama.com/) starten und ein Modell installieren,
z.B. `ollama pull qwen3:8b`. Das Setup bevorzugt dieses Modell, ansonsten ein bereits
installiertes Modell. Die Auswahl steht in `~/Library/Application Support/Friday/runtime.json`.

## Gemini-Fallback einrichten

```bash
python3 scripts/configure-gemini.py
```

Der persönliche Schlüssel wird im macOS-Schlüsselbund gespeichert. `runtime.json`
enthält nur Provider/Modell; API-Keys werden nicht in Git gespeichert. Beim ersten
LLM-Aufruf kann macOS nach Schlüsselbundzugriff für Friday fragen. Nur der
Reasoning-Pfad sendet den Anfrage-Text an Google; Hex, Wake und Laya bleiben lokal.
Mit `reasoningProvider: "ollama"` in runtime.json lässt sich wieder lokal antworten.

## Direkt testen

1. Auf den Orb klicken und auf „Bereit · Laya und Hex lokal“ warten.
2. „Hey Friday“ aktivieren und macOS-Mikrofonzugriff erlauben.
3. „Hey Friday, öffne Safari“ sagen; eine kurze Sprechpause beendet die Aufnahme.
4. „Hey Friday, suche nach test auf Safari“ öffnet eine Google-Suche in Safari.
5. „Hey Friday, mach eine Notiz: Milch kaufen“ probieren. „Notizen zeigen“ öffnet den Ordner.

Alternativ „Sprechen“ drücken oder einen Befehl als Text eingeben. „Abbrechen“
stoppt die laufende Verarbeitung; das Overlay hat während der Aufnahme eine Stop-Taste.
Wake ist standardmäßig aus und pausiert während Aufnahme, Verarbeitung und TTS.

Unterstützte erste Aktionen: automatisch erkannte installierte Programme öffnen, Safari-Suchen starten und Markdown-Notizen
unter `~/Library/Application Support/Friday/Notes` speichern. Freie Terminalbefehle,
Klicken in fremden Apps, Einfügen am Cursor und Web-Recherche folgen später.
„Diktat-Vorschau“ zeigt den erkannten Text. „LLM-Antwort vorlesen“ ist optional;
App-Starts und Notizen bleiben stumm.

## Bausteine

| Funktion | Erste Version |
| --- | --- |
| Wake | Moonshine Tiny Streaming, lokaler englischer Detector für „Hey Friday“ |
| Deutsch → Text | Hex 2.1.24, Whisper large-v3-turbo über lokalen API-2-Helper |
| Schnelle Entscheidung | Laya multilingual Core ML, Auswahl aus fünf Intents |
| Computer Use | NSWorkspace-App-Start, Safari-Suche, lokale Markdown-Notizen |
| Komplexe Antwort | Gemini 3.8 Flash über persönliche API; alternativ Ollama lokal |
| Text → Sprache | macOS-Systemstimme; optionaler Cloud-Adapter später |
| Oberfläche | Thinking Orb als SwiftUI/AppKit-Overlay; native MIT-Animationen |

Laya-/Wake-Modelle und Revisionen stehen nach Setup in `models.json`; Hex-Release
und Prüfsumme in `hex-release.json`, beide im Friday-Application-Support-Ordner.
Es gibt keine automatischen Modell-Downloads beim App-Start.

## Mitarbeit und Prüfung

```bash
swift test --package-path apps/macos
PYTHONPATH="$PWD/services/local-runtime/src" uv run --project services/local-runtime --frozen pytest -q
```

`apps/macos/Sources/FridayApp` enthält Oberfläche und Sprachkoordination;
`FridayCore` das Routing; `FridayAdapters` Audio, IPC, Hex, Laya, Tools und Ollama.
Die beiden lokalen Python-Worker liegen unter `services/local-runtime` und werden
mit der `.app` gebündelt. Modelle und Python-Umgebung bleiben außerhalb des Repos.

Geprüft: Swift-/Python-Tests, echte lokale Laya-Inferenz, synthetische Wake-Aufnahme, Audio-Callback auf Hintergrundthread,
deutsches WAV → Hex → Laya und tatsächliches Speichern einer Notiz sowie App-Build/Signatur.
Mikrofon, individuelle Aussprache und sichtbarer App-Start benötigen einen Live-Test auf dem Mac.
Die englische synthetische Wake-Phrase wurde erkannt; die deutsche Anna-Stimme
löste im zweiten Test nicht aus. Bei fehlender Aktivierung „Sprechen“ verwenden.
Die Entwicklungs-App ist lokal ad-hoc signiert und kein notarisiertes Release.

[Architektur](docs/architecture.md) · [Integrationen](docs/integrations.md) ·
[Roadmap](docs/roadmap.md) · [CONTRIBUTING.md](CONTRIBUTING.md)

## Lizenz

Friday-Code, Maskottchen und lokale Worker stehen unter MIT; Laya-Code und die
verwendeten Laya-Gewichte unter Apache-2.0, Moonshine Tiny und Hex/Whisper unter MIT.
Die [Thinking Orbs](https://github.com/Jakubantalik/Libraries.dev) sind mit MIT-Hinweis gebündelt.
macOS-Sprachausgabe ist ein Betriebssystemdienst, keine offene Modellkomponente.
Jedes gewählte Ollama-Modell hat seine eigene Lizenz. `main.py` und `ai.py` bleiben
als ursprünglicher D&D-Starter erhalten; dafür enthielt das Ausgangsrepo keine Lizenz.

Gemini ist ein optionaler Cloud-Dienst mit eigenem Modell und Kontingent, kein
Open-Weight-Modell. Die lokale Ollama-Alternative bleibt verfügbar.
