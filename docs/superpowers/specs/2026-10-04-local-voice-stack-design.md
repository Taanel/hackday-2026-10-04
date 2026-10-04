# Friday: lokaler Sprachstack und offene Modellgewichte

Stand: 04.10.2026. Dieser Entwurf konkretisiert den vorhandenen Scaffold.
Laya und Hex müssen lokal laufen. Der Nutzer erlaubt eine optionale Cloud-Stimme,
priorisiert aber offenen Code und offene Modellgewichte. Diese Änderung plant
die Integration; sie implementiert und installiert noch keine neuen Provider.

## Auswahl

| Funktion | Auswahl | Betrieb / Offenheit |
| --- | --- | --- |
| macOS-App | vorhandene SwiftUI/AppKit-App | eigener App-Code MIT; macOS-APIs proprietär |
| Fast Response | Laya Multilingual + `laya-coreml` 0.2.0 | lokal; Code und Gewichte Apache-2.0 |
| Speech-to-Text | Hex-Helper + Whisper Large v3 Turbo | lokal; Hex und Whisper MIT |
| Aktivierung | Moonshine Tiny Streaming, Englisch | lokal; MIT-Code und MIT-Streaminggewichte |
| LLM-Fallback | Ollama + Qwen3 8B | lokal; Ollama MIT, Qwen-Gewichte Apache-2.0 |
| Offene TTS | Qwen3-TTS 0.6B CustomVoice, MLX 4-bit | lokal; Swift-Runtime MIT, Modell Apache-2.0 |
| Sofortige TTS / Rückfall | vorhandene macOS-Systemstimme | lokal, ohne TTS-Servicekosten; kein offenes Modell |
| Optionale Cloud-TTS | ElevenLabs Flash v2.5 | proprietärer Cloud-Dienst; explizite Einstellung |

Offene Gewichte bedeuten hier: herunterladbare und lokal verwendbare Parameter
mit der jeweiligen Lizenz. Damit behaupten wir nicht, dass alle Trainingsdaten
und Trainingsprozesse vollständig veröffentlicht sind. Core ML und Metal bleiben
Apple-Systemkomponenten. Eine offene Stimme ist die geplante lokale Standardwahl,
sobald Deutschqualität und Reaktionszeit auf dem Ziel-Mac geprüft sind.

## Integrationsform

Die App besitzt Audioaufnahme, UI, Texteingabe und Toolausführung. Laya läuft
zunächst in einem persistenten Python-3.12-Helfer mit Core ML; die App kommuniziert
über JSON-Zeilen auf stdin/stdout. Modelle einmal herunterladen, danach ausschließlich
aus dem lokalen Verzeichnis laden. Keine Laya-Cloud und kein Prozessstart pro Befehl.

Für Laya nehmen wir `aac6fef/laya-multilingual-coreml`, den 1024-Token-Export für
CPU/GPU. Der schnelle ANE-Export hat nur 96 Token einschließlich Aufgabenbeschreibung
und Optionen und ist deshalb zunächst eine spätere Optimierung. Beide Ports sind
Community-Konvertierungen. Mac-Kompatibilität, deutsche Genauigkeit und warme
Latenz werden lokal geprüft; veröffentlichte M3-Max-Zahlen sind keine Zusage für uns.

Hex startet als app-eigener nativer Helper mit authentifizierter Loopback-API.
Friday liefert WAV-Aufnahmen und bekommt rohe Transkripte. Die Swift-Bridge
bauen wir in Friday; das vorhandene Hex-SDK ist TypeScript. Ein passender nativer
Helper muss derzeit separat bereitgestellt werden. Die Distribution eines gebündelten
Helpers wird vor einem Release gesondert geprüft.

Moonshine verarbeitet fortlaufende lokale Audioblöcke und löst nur bei der
stabil erkannten Phrase „Hey Friday“ aus. Das ist Streaming-ASR mit Phrasenerkennung,
kein eigens trainiertes neuronales Wake-Word-Modell. Für die englische Aktivierungsphrase
wird das englische Streaming-Modell verwendet; das folgende deutsche Diktat übernimmt
Hex. Eine zentrale Audioquelle verhindert konkurrierende Mikrofonaufnahmen.

Qwen3-TTS läuft möglichst direkt in Swift über `mlx-audio-swift`, mit dem Modell
`mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-4bit`, Sprache `German` und einer
im Hörtest gewählten Preset-Stimme. Der aktuelle Paketstand verlangt Swift 6.2;
Toolchain und Metal-Ressourcen müssen im App-Build und CI dazu passen. Die deutsche
Ausgabe und Quantisierungsqualität werden geprüft, bevor sie Standard wird.

## Datenfluss und Verhalten

Laufzeit: „Hey Friday“ → zentrale Audioaufnahme → Hex → Laya → Verzweigung.
Eine sichere Computeraktion wird direkt ausgeführt und visuell bestätigt,
ohne TTS. Eine komplexe Anfrage geht an das LLM; dessen finale Antwort kann
bei Bedarf vorgelesen werden. Eine Taste kann die Aktivierung ebenfalls starten.

Der explizite Diktiermodus zweigt nach Hex vor Laya ab.
Diktat wird am Cursor eingefügt. Assistententext geht an Laya. Laya wählt aus
Programm öffnen, Notiz erstellen, Reasoning und unbekannt. Argumente extrahiert
ein separater Parser; App-Namen werden auf bekannte Bundle-IDs abgebildet.
Terminalaktionen werden nicht aus frei erzeugtem Text ausgeführt.

Unsichere, unvollständige oder abgeschnittene Entscheidungen gehen an das lokale
Reasoning-Modell. Dessen Antwort wird in der UI gezeigt; optionale TTS spricht nur den finalen
Antworttext, keine internen Thinking-Tokens. Toolfehler erzeugen keinen automatischen
zweiten Ausführungsversuch. Recherche braucht zusätzlich ein Such-/Browserwerkzeug
und Quellen; Offline-Inferenz ermöglicht keine Live-Websuche ohne Netzwerk.

Die Sprachschleife hat einen zentralen Coordinator mit Aufnahme-, Transkriptions-,
Entscheidungs-, Ausführungs- und Wiedergabezustand. Wake-Erkennung pausiert während
Aufnahme und eigener Sprachausgabe. Abbruch stoppt Audiowiedergabe und laufende
Anfragen und stellt den Ruhezustand wieder her. TTS benötigt ein Abschlussereignis.

## Alternativen und Abnahme

Der offizielle Python-Laya-Server bleibt der Rückfall, falls der Core-ML-Port auf
unserem Mac scheitert; er bringt mehr Runtime-Abhängigkeiten mit. Eine vollständig
native Swift-Laya-Inferenz ist ein späterer Schritt. Ein Hex-TypeScript-Sidecar
würde dessen SDK wiederverwenden, fügt aber eine zweite Runtime hinzu.

Die folgenden Schritte beschreiben Entwicklungsabhängigkeiten; der Laufzeitablauf
beginnt immer mit Aktivierung und Hex vor Laya. Zuerst Laya mit Texteingabe,
dann Hex-Diktat und echte App-/Notizaktionen. TTS kann
nach Klärung ihres Abschlussvertrags unabhängig bearbeitet werden. Wake-Word folgt
auf die zentrale Audioquelle. Abnahme: deutsche Befehle mit geprüften Argumenten,
keine Aktionen bei unsicherer/abgeschnittener Entscheidung, Sprachloop ohne Selbstauslösung,
und Inferenz mit abgeschaltetem Netzwerk nach vorbereitetem Modelldownload.
