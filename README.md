# Friday — dein Assistent für macOS

Hack Day Berlin, 04.10.2026. Ein offenes Grundgerüst für einen Mac-Assistenten
mit einem kleinen PNG-Maskottchen oben rechts, Diktat, „Hey Friday“, schnellen
Computeraktionen und einem LLM für komplexere Aufgaben.

**Stand: startbare Demo und Schnittstellen.** Spracheingabe, Wake-Word, Hex,
Laya und echte Computeraktionen werden im nächsten Schritt angebunden.

## Starten

macOS 15+ und eine Swift-6-Toolchain mit macOS SDK. Keine Modell-Downloads und
keine API-Keys nötig.

```bash
swift test --package-path apps/macos
./scripts/build-macos.sh
open dist/Friday.app
```

Alternativ `apps/macos/Package.swift` in Xcode öffnen und das Produkt `Friday` starten.
Das Build-Skript erstellt eine lokal ad-hoc signierte Entwicklungs-App, kein
notarisiertes Release für die Verteilung.

Die App hat eine Menüleiste, ein schwebendes Maskottchen und eine Texteingabe.
Probiere `Öffne Safari`, `Notiz: Milch kaufen` oder `Plane einen Wochenendtrip`.
Aktionen erscheinen als Vorschau; komplexe Anfragen zeigen den LLM-Platzhalter.
„Diktat-Vorschau“ gibt den Text unverändert zurück. „Antwort vorlesen“ verwendet
die macOS-Systemstimme und ist standardmäßig ausgeschaltet.

## Struktur

```text
apps/macos/
  Package.swift
  Sources/
    FridayApp/            SwiftUI, Menüleiste, Maskottchen, Demo-Eingabe
      Resources/          mascot.png hier ablegen
    FridayCore/           gemeinsame Verträge und AssistantRouter
    FridayAdapters/       Demo, Hex/Laya/ElevenLabs-Slots, System-TTS
  Tests/FridayCoreTests/  Routing und Fehlerpfade
  packaging/             Info.plist für Friday.app
docs/
  architecture.md        Datenfluss und Modulgrenzen
  integrations.md        Anschlusspunkte und geprüfte Projektlinks
  roadmap.md             nächste Schritte und Abnahmekriterien
scripts/build-macos.sh   lokale .app bauen
.github/workflows/       macOS-Build und Tests
main.py, ai.py           ursprüngliches Python/Ollama-Beispiel
```

## Geplanter Sprachfluss

„Hey Friday“ oder Taste → Aufnahme → Hex/STT → Text → Laya → schnelle Aktion
oder Reasoning-LLM → Antwort → optionale Sprachausgabe.
Der separate Diktiermodus führt den Text direkt zur Texteingabe in der aktiven App.

| Baustein | Im Grundgerüst | Nächster Schritt |
| --- | --- | --- |
| Maskottchen | schwebendes Panel mit Symbol | eigenes `mascot.png` hinzufügen |
| Diktat / Hex | Capture-, STT- und TextOutput-Verträge | Mikrofon, Hex-Helper, Einfügen am Cursor |
| „Hey Friday“ | WakeWordDetector-Vertrag und Provider-Slot | lokalen Detector anbinden |
| Laya | Decision-Vertrag, Router, Demo-Klassifikation | echte Inferenz und Argumentvalidierung |
| LLM-Fallback | Reasoning-Vertrag, Demo-Antwort | Ollama oder anderen Provider anbinden |
| Computer Use | typisierte App-, Notiz- und Terminalaktionen | echten Executor und macOS-Berechtigungen |
| Text-to-Speech | macOS-Systemstimme | optional ElevenLabs oder lokale Engine |

Details stehen in der [Architektur](docs/architecture.md), den
[Integrationshinweisen](docs/integrations.md) und der [Roadmap](docs/roadmap.md).
Beitragende starten mit [CONTRIBUTING.md](CONTRIBUTING.md).

## Ursprünglicher Starter

`main.py` und `ai.py` stammen aus dem Veranstalter-Starter und bleiben als
separates Dungeons-&-Dragons-Beispiel erhalten: Python + `requests`, Ollama auf
`localhost:11434`, Modell `llama3.2`. Sie werden von der macOS-App noch nicht aufgerufen.

## Lizenz

Der neue macOS-Code unter `apps/macos/` steht unter [MIT](apps/macos/LICENSE).
Für das übernommene Veranstalter-Beispiel wurde im Ausgangsrepository keine
Lizenz angegeben. Externe Modelle, Plattform-APIs und optionale Dienste haben
ihre eigenen Bedingungen; im Grundgerüst wird kein Fremdcode mitgeliefert.
