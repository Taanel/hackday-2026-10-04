# Integrationen

V1 nutzt reale lokale Adapter. Das Setup und die konkreten Versionen stehen in
[README](../README.md); Modellrevisionen werden lokal in models.json gespeichert.

## Hex: Diktat / Speech-to-Text

Quelle: [anomalyco/hex](https://github.com/anomalyco/hex), MIT;
[SDK-Dokumentation](https://github.com/anomalyco/hex/blob/main/sdk/typescript/README.md).
Hex unterstützt lokales Diktat. Das TypeScript-SDK nutzt einen nativen Helper;
es ist keine direkt importierbare Swift-Bibliothek. Laut SDK-Dokumentation muss
der einbettende Consumer den kompatiblen nativen Helper derzeit selbst bereitstellen.

HexService startet das originale ARM64-Release 2.1.24 mit `service --embedded`,
prüft API 2 und verwendet den lokalen Bearer-authentifizierten HTTP-Service.
Das Setup installiert Whisper large-v3-turbo für Deutsch; Runtime-Downloads sind aus.

## „Hey Friday“

Optionales lokales Anlernen: dreimal die Phrase aufnehmen. Der Worker speichert
normalisierte spektrale Merkmale in `~/Library/Application Support/Friday/VoiceProfile/profile.json`.
Temporäre WAVs werden anschließend gelöscht. Subsequence-DTW sucht das Klangmuster
in rollierenden PCM-Fenstern; Lautstärke und Sprechtempo dürfen sich ändern.
Das ist eine Testfunktion, keine Sprecheridentifikation. Mit einem Profil ersetzt
sie Moonshine für die Aktivierung; „Zurücksetzen“ wechselt zur Standarderkennung.

Moonshine Tiny Streaming verarbeitet kontinuierlich lokale AudioInput-Samples
und meldet die vollständige Phrase „Hey Friday“. Die englischen offenen Tiny-Gewichte
werden einmalig vorbereitet; das Mikrofon bleibt unter Kontrolle der nativen App.
Abnahme: „Hey Friday“ aktiviert den Assistenten, Stille/andere Phrasen nicht;
Erkennung pausiert beim Antworten und kann vollständig abgeschaltet werden.
Wake-Fehler starten nur den Wake-Helper neu. Transport-Sitzung und Stream-Generation
verhindern, dass alte Ereignisse nach einem Neustart erneut aktivieren. Audiosamples
werden vor dem IPC auf gültiges PCM begrenzt. Hex wird vor „Bereit“ einmal geladen
und vorgewärmt; seine Modellprüfung läuft nicht bei jedem Befehl erneut.

## Laya: schnelle Entscheidungen

Quelle: [NandhaKishorM/laya](https://github.com/NandhaKishorM/laya).
Laya liefert typisierte Auswahl-, Score- und Ja/Nein-Entscheidungen statt
generiertem Antworttext. Es passt damit zum Routing zwischen vordefinierten Aktionen.

Anschlusspunkt: `LayaDecisionEngine.decide(text:)`.
Kandidaten: Programm öffnen, Safari-Suche, Notiz erstellen, Reasoning, unbekannt.
Der Python-Worker verwendet [laya-coreml](https://github.com/mizorewww/laya-coreml) 0.2.0
und die gepinnten multilingual Core-ML-Gewichte. Swift kommuniziert über JSON-Zeilen.
Deutschqualität, Konfidenz und Latenz mit realen Mac-Befehlen messen.
Argumente separat extrahieren und erlaubte App-IDs/Tool-Schemata validieren;
ein ausgewählter Intent ist noch kein ausführbarer Terminalbefehl.

## Reasoning-LLM

Anschlusspunkt: `ReasoningEngine.respond(to:)`.
`ai.py` zeigt den vorhandenen Ollama-Aufruf mit `llama3.2` als Startpunkt.
OllamaReasoningEngine verwendet die lokale Chat-API mit Fehlerbehandlung, Deadline und Abbruch. Ein anderer lokaler oder gehosteter Provider lässt sich dahinter austauschen.
Recherchen benötigen zusätzlich Such-/Browserwerkzeuge und Quellen.

## Computer Use

Anschlusspunkte: `ToolExecutor.execute(_:)` und `TextOutput.insertAtCursor(_:)`.
Umgesetzt: automatisch erkannte App-Starts per Bundle-ID, Safari-Websuche und Markdown-Notizablage.
Offen: Terminal-Prozesse und Accessibility-basierte UI-Aktionen. Das Terminal erhält ausführbaren Pfad,
Argumente und Arbeitsverzeichnis als getrennte Felder. MacToolExecutor führt App- und Notizaktionen aus; freie Terminalbefehle lehnt V1 ab.

## Sprachausgabe

`SystemSpeechOutput` verwendet AVFoundation und die installierte macOS-Stimme;
dafür braucht die App keinen externen TTS-Account oder API-Key. Die Ausgabe ist
standardmäßig aktiv und abschaltbar, für finale LLM-Antworten und LLM-Fehler; Computeraktionen und
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

## Gemini 3.8 Flash

Optionaler Antwort-Provider über Googles GenerateContent-API. Der persönliche
API-Schlüssel wird im macOS-Schlüsselbund unter dev.hackday.friday.gemini gespeichert.
`python3 scripts/configure-gemini.py` wählt das Cloud-Fallback; das normale lokale
Setup behält die gewählte Fallback-Konfiguration bei. Googles
[Modell-Dokumentation](https://ai.google.dev/gemini-api/docs/models/gemini-3.8-flash)
beschreibt den geprüften Modellnamen. Bei 503 und anderen vorübergehenden Fehlern
übernimmt Gemini 3.5 Flash Lite. Ein erfolgreicher Modelltest bestätigt Antworten
und Function Calling. App-Starts, Safari-Suche, Notizen und Schreibtischwechsel
bleiben lokale Toolaktionen. Gemini kann diese als typisierte Aufträge an Friday
zurückgeben; unbekannte Funktionen oder nicht installierte App-Namen werden
abgelehnt. Finale Antworten werden standardmäßig lokal vorgelesen.
