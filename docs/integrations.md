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

## „Hey Friday“ / „Hi Friday“ / optional „Friday“

Optionales lokales Anlernen: dreimal die Phrase aufnehmen. Der Worker speichert
normalisierte spektrale Merkmale in `~/Library/Application Support/Friday/VoiceProfile/profile.json`.
Temporäre WAVs werden anschließend gelöscht. Subsequence-DTW sucht das Klangmuster
in rollierenden PCM-Fenstern; Lautstärke und Sprechtempo dürfen sich ändern.
Das ist eine Testfunktion, keine Sprecheridentifikation. Das persönliche Profil
ist nur nach ausdrücklichem Opt-in aktiv. Standardmäßig lösen „Hey Friday“ und „Hi Friday“ am Anfang einer Äußerung aus; „Friday“ allein ist separat optional.
„Zurücksetzen“ entfernt nur das persönliche Profil.

Moonshine Small Streaming Deutsch (123M) verarbeitet kontinuierlich lokale AudioInput-Samples
und meldet standardmäßig die vollständigen Phrasen „Hey Friday“ und „Hi Friday“ am Beginn
einer Äußerung. „Friday“ allein erfordert das separate Opt-in. Die deutschen offenen
Small-Gewichte werden einmalig vorbereitet; das Mikrofon bleibt unter Kontrolle der
nativen App. Die Schlüsselphrase wird dem Modell mitgegeben. Feste ASR-Schreibvarianten
wie „Hey Freidei“ und die in deutschen Sprachproben beobachteten „Hi Fida/Fidder“ werden ebenfalls erkannt; „hey“ oder „hi“ als erstes Wort bleibt erforderlich.
Das Setup verwendet `SMALL_STREAMING` und Revision `quantized_26_08_24`.
Die alte Tiny-Konfiguration bleibt über `wakeArchitecture` kompatibel.
Ruhepegel-basierte Sprachgrenzen verhindern den vorzeitigen Abschluss leiser Befehle.
Eine Wake-Phrase ohne Befehl öffnet eine Aufnahme mit acht Sekunden Sprachbeginn-Timeout.
Die Mikrofon-Diagnose zeigt einen begrenzten Text im aktiven Einstellungsfenster;
sie aktiviert keinen Befehl und speichert weder Audio noch Transkripte auf Disk.
Ein Overlay-Klick startet dieselbe native Aufnahme, benötigt aber keinen Wake-Worker.
Die Aufnahme beginnt vor dem Pause-Acknowledgement; doppelte Klicks starten sie nicht neu.
Abnahme: „Hey Friday“ oder „Hi Friday“ aktiviert den Assistenten; „Friday“ allein, Stille und
Erwähnungen mitten in einem Satz lösen in der Standardeinstellung nicht aus;
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
Kandidaten: Programm öffnen, Safari-Suche, Notiz erstellen, Schreibtisch wechseln,
offenes Projekt finden, Reasoning, unbekannt.
Der Python-Worker verwendet [laya-coreml](https://github.com/mizorewww/laya-coreml) 0.2.0
und die gepinnten multilingual Core-ML-Gewichte. Swift kommuniziert über JSON-Zeilen.
Deutschqualität, Konfidenz und Latenz mit realen Mac-Befehlen messen.
Argumente separat extrahieren und erlaubte App-IDs/Tool-Schemata validieren;
ein ausgewählter Intent ist noch kein ausführbarer Terminalbefehl.

## Reasoning-LLM

Anschlusspunkt: `ReasoningEngine.respond(to:)`.
`ai.py` zeigt den vorhandenen Ollama-Aufruf mit `llama3.2` als Startpunkt.
OllamaReasoningEngine verwendet die lokale Chat-API mit Fehlerbehandlung, Deadline und Abbruch. Ein anderer lokaler oder gehosteter Provider lässt sich dahinter austauschen.
Gemini kann `search_web(query)` oder `weather_forecast(location)` anfordern.
`WebResearchService` liefert DuckDuckGo-Lite-Snippets (höchstens fünf) bzw. aktuelle
Open-Meteo-Tagesprognosen für maximal 16 Tage. Ein zweiter Modellaufruf erhält
die Daten ohne Computerfunktionen. Quellen stammen ausschließlich aus dem Adapter,
werden getrennt angezeigt und nicht gesprochen. Ohne Wetter-Ort fragt Friday nach;
die letzten acht Frage-/Antwortpaare bleiben nur im Arbeitsspeicher. Fehlende Daten
und Captchas erzeugen klare Fehler. Suchseiten werden nicht vollständig abgerufen.

## Computer Use

Anschlusspunkte: `ToolExecutor.execute(_:)` und `TextOutput.insertAtCursor(_:)`.
Umgesetzt: automatisch erkannte App-Starts per Bundle-ID, Safari-Websuche und Markdown-Notizablage.
Zusätzlich: Schreibtischwechsel und lokale Projektsuche über AX-Fenstertitel und
sichtbare Terminal.app-Tab-Inhalte. Dafür benötigt Friday Bedienungshilfen und
Terminal-Automation. Mehrere Treffer werden lokal zur Auswahl angezeigt. Gelesene
Inhalte bleiben auf dem Mac; Gemini und TTS erhalten keine Ergebnisse dieser Suche.
Offen: freie Terminal-Prozesse und allgemeine UI-Aktionen. Das Terminal erhält ausführbaren Pfad,
Argumente und Arbeitsverzeichnis als getrennte Felder. MacToolExecutor führt App- und Notizaktionen aus; freie Terminalbefehle lehnt V1 ab.

## Sprachausgabe

`LocalPiperSpeechOutput` ist die lokale Ausgabe für Ollama und der Ersatz für Gemini.
Der lokale `tts`-Worker verwendet `piper_de_DE-thorsten-high`; `prepare-tts` lädt
die Stimme ausdrücklich beim Setup. Der laufende Worker lädt nur vorhandene
Dateien. Texte werden in höchstens 300 Zeichen lange Abschnitte aufgeteilt;
JSON-Zeilen liefern begrenzte PCM16-WAV-Daten im Arbeitsspeicher an AVAudioPlayer.
Es werden keine Audiodateien angelegt. `AdaptiveSpeechOutput` kann optional die
Cloud-Stimme bevorzugen. Nach einem Cloud-Fehler übernimmt Piper, weitere
Cloud-TTS-Anfragen pausieren für zwei Minuten. Der Grund bleibt in der Anzeige erhalten.
Eine eigene Anzeige hält Sprachfehler auch beim Übergang zurück zur Wake-Bereitschaft sichtbar.

`GeminiSpeechOutput` verwendet ausschließlich 3.8 Flash-Lite TTS und 3.8 Flash TTS
über die Interactions-API. Beide liefern WAV. `LocalGeminiTTSKeyStore` hält bis vier
separate Sprachschlüssel außerhalb des Repos. `GeminiSpeechCredentials` lädt sie
einmal pro Sitzung abseits des MainActor und verwirft alte Leseergebnisse nach
Änderungen. Ohne separate Schlüssel bleibt der bisherige Hauptschlüssel die Stimme-
Konfiguration; mit mindestens einem Sprachschlüssel wird der Hauptschlüssel nicht
für TTS geladen. Die Reasoning-Engine und ihr Store bleiben unabhängig.

Die Auswahl rotiert über Schlüssel und beide Modelle. Ein `GeminiTTSModelPool` pro
Credential-Fingerprint pausiert nur betroffene Kombinationen nach 429/404/5xx.
Ungültige Schlüssel (401) werden vollständig pausiert; der nächste darf übernehmen.
Fingerprints und Schlüssel werden nicht ausgegeben. Retry-After bzw.
RetryInfo haben Vorrang, ein erkanntes Tageskontingent pausiert bis Mitternacht Pacific.
Alle Modellversuche teilen eine Deadline von 20 Sekunden. Abbruch rotiert nicht weiter.
Die gewählte Stimme bleibt gleich, und der Modellname wird nach erfolgreichem Vorlesen angezeigt.
Quelle: [TTS-Modelle](https://ai.google.dev/gemini-api/docs/speech-generation),
[Limits pro Projekt und Modell](https://ai.google.dev/gemini-api/docs/rate-limits).

Die GA-Anfragen verwenden strukturierte Style-Metadaten
für deutsche Sprechweise; der Antworttext bleibt ein wörtliches Transkript.
Kore, Aoede und Charon sind auswählbar. WAV-Audio spielt AVAudioPlayer ab; Abbruch
stoppt Download und Wiedergabe. Generation- und Player-IDs verhindern verspäteten
Start bzw. Abschluss. Bei TTS-Fehlern bleibt die erhaltene Textantwort verfügbar.
`SystemSpeechOutput` bleibt als Adapter verfügbar. Die Live-Ausgabe ist
standardmäßig aktiv und abschaltbar, für finale LLM-Antworten und LLM-Fehler; Computeraktionen und
Diktat bleiben stumm. `speak` wartet auf Wiedergabeende; Stop/Abbruch beendet
die wartende Anfrage mit `CancellationError`.
„Noch einmal vorlesen“ verwendet den gespeicherten Antworttext ohne erneuten
Modellaufruf. Replay bleibt während anderer Arbeit gesperrt; ein Generation-Token
verhindert, dass alte Wiedergabe-Abschlüsse neue Befehle oder Wake beeinflussen.
ElevenLabs ist weiterhin eine mögliche Alternative, aktuell nicht aktiviert.
Andere TTS-Engines können denselben Vertrag implementieren.
Schlüssel anderer optionaler Anbieter werden ebenfalls außerhalb des Repositories gespeichert.

## Thinking Orbs

[Libraries.dev](https://libraries.dev/orbs) bietet einen nativen SwiftUI-Port
mit neun Animationen. Die MIT-Quellen sind unter `Vendor/ThinkingOrbsKit`
auf Revision `d06640864eb4adc2fe240f899a44ee6210779782` gepinnt.
`AssistantOrb` ist der app-eigene Wrapper; die Oberfläche benötigt kein npm,
React oder WebView. Der Upstream-Copyright-Hinweis liegt auch in den App-Ressourcen.
Idle und Wake-Bereitschaft sind statische 2D-Ringe; Aufnahme animiert denselben Ring.
Ausführung nutzt working, Gemini die verschachtelnde solving-Animation.
Das transparente Panel vergrößert sich nur für Aufnahme-Stop oder
das kurze Hex-Transkript und schrumpft danach zurück. Der erkannte Text bleibt bis
eine Sekunde nach erfolgreicher Computeraktion sichtbar, bei Fragen acht Sekunden;
Hex liefert derzeit keine Live-Teilsätze. Die Menüleisten-Kugel ist ein statisches
Template-Bild desselben nativen Orbs. LSUIElement entfernt das Dock-Icon; das
Einstellungsfenster wird erst auf Wunsch erzeugt.

## Gemini Flash-Lite

Optionaler Antwort-Provider über Googles GenerateContent-API. Der persönliche
API-Schlüssel wird im lokalen `Credentials/gemini-api-key.txt`-Store im Friday-
Application-Support-Ordner gespeichert (Datei 0600, Ordner 0700). Das Eingabefeld
unten im Fenster und das CLI nutzen dasselbe Format. Die App liest nicht mehr aus
dem Schlüsselbund. Schlüssel sind nicht im App-Bundle oder in Git enthalten.
`python3 scripts/configure-gemini.py` wählt das Cloud-Fallback; das normale lokale
Setup behält die gewählte Fallback-Konfiguration bei. Googles
[Thinking-Dokumentation](https://ai.google.dev/gemini-api/docs/thinking)
beschreibt die verfügbaren Stufen. Standard ist Gemini 3.5 Flash-Lite mit MINIMAL;
das ist die kleinste Thinking-Stufe, kein garantiert vollständig abgeschaltetes
Reasoning. Bei 503 und anderen vorübergehenden Fehlern übernimmt Gemini 3.8 Flash
mit LOW. Ein erfolgreicher Modelltest bestätigt Antworten
und Function Calling. App-Starts, Safari-Suche, Notizen und Schreibtischwechsel
bleiben lokale Toolaktionen. Gemini kann diese als typisierte Aufträge an Friday
zurückgeben; unbekannte Funktionen oder nicht installierte App-Namen werden
abgelehnt. Finale Antworten werden standardmäßig lokal vorgelesen. Der Schlüssel
wird pro Engine-Sitzung einmal außerhalb des UI-Threads aus der lokalen Datei
gelesen und gecacht. Nach einer Änderung im Eingabefeld wird der Sitzungscache
mit einem Generation-Token verworfen; alte ausstehende Ladevorgänge dürfen den
vorherigen Wert nicht wiederherstellen. Speichern prüft das Format, keine API-
Autorisierung. Fehlende oder von Google abgelehnte Schlüssel erzeugen klare Fehler.

## Home Assistant v8

Erweiterung Build 12: Raumzuordnungen werden über `config/area_registry/list`,
`config/device_registry/list` und `config/entity_registry/list` gelesen. Der
normale Friday-Benutzer der realen Instanz hat Zugriff; `api/template` wäre dort
nicht erlaubt und wird deshalb nicht verwendet. Geräte vererben ihren Bereich an
Entities, explizite Entity-Zuordnungen haben Vorrang. „Wohnzimmer aus“ adressiert
alle individuellen Lampen des Bereichs in einer Service-Anfrage und prüft jede
einzeln. Die Hue-Gruppe „Wohnzimmer“ enthält lediglich zwei der 13 tatsächlichen
Lampen; Kaskade und Albedo werden nun zusätzlich einbezogen. Eine konkrete
Lampe bzw. Entity-ID wird weiterhin gezielt gesteuert. Der native Live-Test meldete
13/13 Lampen aus; der Nutzer bestätigte anschließend, dass Kaskade und Albedo tatsächlich aus sind.

`HomeAssistantConfigurationStore` speichert origin-gebundene private URL/Token-Daten.
`HomeAssistantClient` entdeckt light/switch/scene/climate über `/api/states`, prüft
Einheit und Gerätefähigkeiten und ruft nur fest definierte `/api/services` auf.
Kein Retry nach POST; keine Credential-Weiterleitung. Ein zusätzlicher Laya-Intent
wählt lokale Smart-Home-Steuerung. Finder-Ordner, HTTP(S)-Links und Safari-Tab-Suche
erweitern MacToolExecutor. Gesprächsverlauf und achtsekündige Rückfrage-Aufnahme
liegen im bestehenden Gemini/VoiceController, ohne zusätzlichen Hintergrundagenten.
Dokumentation: [HA REST](https://developers.home-assistant.io/docs/api/rest/).
