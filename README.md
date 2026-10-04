# Friday — lokaler Assistent für macOS

Erste testbare Version: Thinking-Orb-Overlay oben rechts, native Thinking Orbs,
„Friday“ und „Hey Friday“, deutsche Spracheingabe mit Hex, lokale Laya-Entscheidungen und
Computeraktionen. Komplexe Fragen gehen je nach Konfiguration an Gemini Flash oder Ollama; nur LLM-Antworten können
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
LLM-Aufruf kann macOS nach Schlüsselbundzugriff für Friday fragen. Mit dem Mac-
Anmeldepasswort „Immer erlauben“ wählen. Der Schlüssel wird danach nur im Arbeitsspeicher
dieser App-Sitzung gehalten. Ad-hoc signierte Test-Builds können nach jedem Update
erneut fragen. Für dauerhafte Wiedererkennung eine vorhandene Apple-Code-Signing-
Identität mit `FRIDAY_SIGNING_IDENTITY` beim Bauen auswählen oder deren Namen/Hash
in `~/Library/Application Support/Friday/signing-identity` speichern. Nur der
Reasoning-Pfad sendet den Anfrage-Text an Google; Hex, Wake und Laya bleiben lokal.
Mit `reasoningProvider: "ollama"` in runtime.json lässt sich wieder lokal antworten.

## Direkt testen

1. Auf den Orb klicken und auf „Bereit · Laya und Hex lokal“ warten.
2. „Friday / Hey Friday aktivieren“ und macOS-Mikrofonzugriff erlauben.
   Wenn die Standard-Erkennung die Aussprache nicht versteht: „Hey Friday anlernen“
   anklicken und dreimal nur die Phrase einsprechen, jeweils kurz still sein.
   Nach jeder Probe den Button für die nächste Aufnahme verwenden. Das persönliche
   Klangmuster wird lokal gespeichert und anschließend automatisch aktiviert.
   „Zurücksetzen“ entfernt das Profil. Die Anlernfunktion ist ein Prototyp;
   ihre Zuverlässigkeit mit der eigenen Stimme muss live geprüft werden.
3. „Friday, öffne Safari“ oder „Hey Friday, öffne Safari“ sagen; etwa 0,75 Sekunden
   Stille beenden die Aufnahme. Das persönliche Hey-Friday-Profil bleibt zusätzlich aktiv.
4. „Hey Friday, suche nach test auf Safari“ öffnet eine Google-Suche in Safari.
   Auch „Öffne Safari und suche nach Test“ und „Suche nach Test“ funktionieren als direkte Safari-Aktion.
   „Kannst du Shaper 3D öffnen?“ erkennt die installierte App Shapr3D auch mit dieser
   Schreibweise. Leerzeichen und eindeutige kleine Schreibfehler in App-Namen sind erlaubt.
5. „Hey Friday, mach eine Notiz: Milch kaufen“ probieren. „Notizen zeigen“ öffnet den Ordner.

Alternativ „Sprechen“ drücken oder einen Befehl als Text eingeben. „Abbrechen“
stoppt die laufende Verarbeitung; das Overlay hat während der Aufnahme eine Stop-Taste.
Wake ist standardmäßig aus und pausiert während Aufnahme, Verarbeitung und TTS.
LLM-Antworten werden standardmäßig mit der kostenlosen lokalen macOS-Sprach-API
vorgelesen und direkt im Fenster angezeigt; der Schalter kann die Sprachausgabe
ausschalten. Gemini 3.5 Flash-Lite mit minimalem Thinking ist der Standard.
Bei Überlastung übernimmt Gemini 3.8 Flash mit niedrigem Thinking. Das
überlastete Modell wird danach zwei Minuten lang nicht erneut angefragt.

„Wechsel Schreibtisch“, „Wechsle zum nächsten Schreibtisch“ und „Wechsel Schreibtisch
nach links“ senden Control + Pfeiltaste. Dafür „Computersteuerung erlauben“ anklicken
und Friday in den macOS-Bedienungshilfen freigeben. Die entsprechende macOS-
Tastenkombination muss aktiviert sein; ein benachbarter Schreibtisch muss existieren.
Gemini kann App-Start, Safari-Suche, Notiz und Schreibtischwechsel als typisierte
Aufträge zurückgeben. Friday prüft diese vor der Ausführung (höchstens drei,
keine freien Terminalbefehle, keine doppelten Aktionen). Ein Toolfehler wird nicht
erneut über Gemini ausgeführt. Das ist noch kein allgemeiner Klick-Agent.

Unterstützte erste Aktionen: automatisch erkannte installierte Programme öffnen, Safari-Suchen starten und Markdown-Notizen
unter `~/Library/Application Support/Friday/Notes` speichern. Freie Terminalbefehle,
Klicken in fremden Apps, Einfügen am Cursor und Web-Recherche folgen später.
„Diktat-Vorschau“ zeigt den erkannten Text. „LLM-Antwort vorlesen“ ist optional;
App-Starts und Notizen bleiben stumm.

## Bausteine

| Funktion | Erste Version |
| --- | --- |
| Wake | Moonshine Tiny Streaming für Friday / Hey Friday; zusätzlich persönliche lokale Klangmuster (3 Sprachproben, DTW) |
| Deutsch → Text | Hex 2.1.24, Whisper large-v3-turbo über lokalen API-2-Helper |
| Schnelle Entscheidung | Laya multilingual Core ML, Auswahl aus sechs Intents |
| Computer Use | Installierte Apps starten, Safari-Suche, lokale Notizen, Schreibtischwechsel |
| Komplexe Antwort | Gemini 3.5 Flash-Lite (minimal), Ersatz 3.8 Flash (low); alternativ Ollama lokal |
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
Die Moonshine-Standarderkennung hat Schwierigkeiten mit der deutschen Anna-Stimme.
Mit drei persönlichen Anna-Sprachproben erkennt der neue Klangmuster-Prototyp
auch „Hey Friday“ direkt vor einem Befehl; getestete andere Sätze lösen nicht aus.
Bei fehlender Aktivierung neu anlernen oder „Sprechen“ verwenden.
Ohne konfigurierte Apple-Signatur wird ad-hoc signiert. Die Entwicklungs-App ist
kein notarisiertes Release. Bereits laufende Apps werden direkt aktiviert; der
Kaltstart einer App hängt von deren eigener Startzeit ab.

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
