# Integrationen

Projektquellen am 04.10.2026 geprüft. Alle echten Adapter sind noch offen.
Die App verdrahtet derzeit die Demo-Provider in `AssistantViewModel.swift`.

Die jetzt ausgewählten lokalen Modelle und Laufzeiten stehen im
[Integrationsplan](superpowers/plans/2026-10-04-local-voice-stack.md).
Die Hinweise unten beschreiben weiterhin die vorhandenen Anschlusspunkte.

## Hex: Diktat / Speech-to-Text

Quelle: [anomalyco/hex](https://github.com/anomalyco/hex), MIT;
[SDK-Dokumentation](https://github.com/anomalyco/hex/blob/main/sdk/typescript/README.md).
Hex unterstützt lokales Diktat. Das TypeScript-SDK nutzt einen nativen Helper;
es ist keine direkt importierbare Swift-Bibliothek. Laut SDK-Dokumentation muss
der einbettende Consumer den kompatiblen nativen Helper derzeit selbst bereitstellen.

Anschlusspunkt: `HexSpeechToText.transcribe(audioFile:)`.
Für die native App planen wir eine kleine Swift-Bridge zum lokalen Helper und
dessen IPC/Loopback-Protokoll. Eine TypeScript-Sidecar wäre eine Alternative,
falls wir das bestehende SDK direkt nutzen möchten. Vor der Wahl die konkrete
Upstream-Version und das [Service-Protokoll](https://github.com/anomalyco/hex/blob/main/docs/specs/local-transcription-service.md) prüfen.
Aufnahme, Deutsch-Modellwahl, Berechtigungen und temporäre Dateien gehören zur
Friday-Integration. Noch kein Helper wird heruntergeladen oder gestartet.

## „Hey Friday“

Anschlusspunkt: `WakeWordDetector.start(phrase:)` liefert Aktivierungsereignisse.
Die Erkennung braucht einen echten lokalen Audio-Detector; ein Textvergleich
nach STT wäre kein dauerhaftes Wake-Word-System. Hex dokumentiert eigene
[Voice Commands](https://github.com/anomalyco/hex/blob/main/docs/features/commands.md);
ob wir sie verwenden oder einen unabhängigen Detector anschließen, bleibt offen.
Abnahme: „Hey Friday“ aktiviert den Assistenten, Stille/andere Phrasen nicht;
Erkennung pausiert beim Antworten und kann vollständig abgeschaltet werden.

## Laya: schnelle Entscheidungen

Quelle: [NandhaKishorM/laya](https://github.com/NandhaKishorM/laya).
Laya liefert typisierte Auswahl-, Score- und Ja/Nein-Entscheidungen statt
generiertem Antworttext. Es passt damit zum Routing zwischen vordefinierten Aktionen.

Anschlusspunkt: `LayaDecisionEngine.decide(text:)`.
Kandidaten: Programm öffnen, Notiz erstellen, Reasoning, unbekannt.
Die lokale Laufzeit (Python-Service, Core ML oder andere Bridge) wird später festgelegt.
Deutschqualität, Konfidenz und Latenz mit realen Mac-Befehlen messen.
Argumente separat extrahieren und erlaubte App-IDs/Tool-Schemata validieren;
ein ausgewählter Intent ist noch kein ausführbarer Terminalbefehl.

## Reasoning-LLM

Anschlusspunkt: `ReasoningEngine.respond(to:)`.
`ai.py` zeigt den vorhandenen Ollama-Aufruf mit `llama3.2` als Startpunkt.
Für die macOS-App folgt ein Swift-Adapter mit Fehlerbehandlung, Deadline und
Abbruch. Ein anderer lokaler oder gehosteter Provider lässt sich dahinter austauschen.
Recherchen benötigen zusätzlich Such-/Browserwerkzeuge und Quellen.

## Computer Use

Anschlusspunkte: `ToolExecutor.execute(_:)` und `TextOutput.insertAtCursor(_:)`.
Geplant: App-Start per Bundle-ID, Notizablage, Terminal-Prozesse und später
Accessibility-basierte UI-Aktionen. Das Terminal erhält ausführbaren Pfad,
Argumente und Arbeitsverzeichnis als getrennte Felder. Die Vorschau ist kein
echter Executor und vergibt keine Systemberechtigungen.

## Sprachausgabe

`SystemSpeechOutput` verwendet AVFoundation und die installierte macOS-Stimme;
dafür braucht die Demo keinen externen TTS-Account. Die Ausgabe ist optional
und ausschließlich für finale LLM-Antworten vorgesehen; Computeraktionen und
Diktat bleiben stumm. `speak` wartet auf Wiedergabeende; Stop/Abbruch beendet
die wartende Anfrage mit `CancellationError`.
`ElevenLabsSpeechOutput` ist ein späterer Anbieter-Slot, ohne API-Aufruf oder
Key. Alternativ kann eine lokale TTS-Engine denselben Vertrag implementieren.
Cloud-Schlüssel gehören später in die Keychain, nicht ins Repository.

## Thinking Orbs

[Libraries.dev](https://libraries.dev/orbs) bietet einen nativen SwiftUI-Port
mit neun Animationen. Die MIT-Quellen sind unter `Vendor/ThinkingOrbsKit`
auf Revision `d06640864eb4adc2fe240f899a44ee6210779782` gepinnt.
`AssistantOrb` ist der app-eigene Wrapper; die Oberfläche benötigt kein npm,
React oder WebView. Der Upstream-Copyright-Hinweis liegt auch in den App-Ressourcen.
