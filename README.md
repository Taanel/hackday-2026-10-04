# Friday — lokaler Assistent für macOS

Erste testbare Version: Thinking-Orb-Overlay oben rechts, native Thinking Orbs,
„Hey Friday“ (weitere Wake-Varianten optional), deutsche Spracheingabe mit Hex, lokale Laya-Entscheidungen und
Computeraktionen. Komplexe Fragen gehen je nach Konfiguration an Gemini Flash oder Ollama; nur LLM-Antworten können
optional mit der lokalen deutschen Piper-Stimme vorgelesen werden. Gemini-TTS ist zusätzlich auswählbar. Friday startet als Menüleisten-App
mit transparentem Overlay, ohne Dock-Icon oder automatisch geöffnetes Fenster.

## Starten

Apple Silicon, macOS 15+, Swift 6, Python 3.12 über [uv](https://docs.astral.sh/uv/).
Das einmalige Setup lädt die offenen Modellgewichte und das offizielle Hex-Binary.
Danach arbeiten Wake, Hex, Laya und Piper lokal ohne API-Key.

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

Unten im Friday-Fenster den Schlüssel im Feld „Gemini API-Schlüssel“ eintragen und
„Lokal speichern“ wählen. Alternativ verwendet das CLI oben denselben lokalen Store.
Die Datei liegt außerhalb von Repo und App-Bundle unter
`~/Library/Application Support/Friday/Credentials/gemini-api-key.txt` (0600,
Ordner 0700). Die App fragt für Gemini nicht mehr nach dem Schlüsselbund. Das Feld
bleibt nach dem Speichern leer; ein neuer Wert ersetzt den bisherigen und gilt bei
der nächsten Anfrage. Leere oder formal fehlerhafte Werte werden abgelehnt; die
Autorisierung des Schlüssels bei Google wird erst beim API-Aufruf geprüft.
`runtime.json` enthält nur Provider/Modell. API-Keys werden nicht in Git gespeichert.
Für eine stabile App-Identität kann `FRIDAY_SIGNING_IDENTITY` beim Bauen gesetzt oder
deren Name/Hash in `~/Library/Application Support/Friday/signing-identity` gespeichert
werden. Gemini-Reasoning und die optional ausgewählte Gemini-Stimme senden Anfrage- bzw. Antworttext an
Google; Hex, Wake, Laya und die Standardstimme Piper bleiben lokal. Recherche sendet Suchbegriffe an DuckDuckGo
oder den ausdrücklich genannten Wetter-Ort an Open-Meteo.
Mit `reasoningProvider: "ollama"` in runtime.json lässt sich wieder lokal antworten.

## Direkt testen

1. Auf den Orb klicken und auf „Bereit · Laya und Hex lokal“ warten.
2. „Hey Friday aktivieren“ und macOS-Mikrofonzugriff erlauben.
   Das Setup verwendet jetzt Moonshine Small Streaming Deutsch mit „Hey Friday“ als Schlüsselphrase.
   Unter „Mikrofon und Wake-Erkennung prüfen“ sind Pegel und der zuletzt erkannte
   Text sichtbar, solange das Einstellungsfenster aktiv ist; diese Diagnose wird nicht gespeichert.
   Wenn die Standard-Erkennung die Aussprache nicht versteht: „Hey Friday anlernen“
   anklicken und dreimal nur die Phrase einsprechen, jeweils kurz still sein.
   Nach jeder Probe den Button für die nächste Aufnahme verwenden. Das persönliche
   Klangmuster wird lokal gespeichert. Seine Aktivierung bleibt eine ausdrückliche Option.
   „Zurücksetzen“ entfernt das Profil. Die Anlernfunktion ist ein Prototyp;
   ihre Zuverlässigkeit mit der eigenen Stimme muss live geprüft werden.
3. „Hey Friday, öffne Safari“ sagen; etwa 0,75 Sekunden
   Stille beenden die Aufnahme. Das persönliche Klangmuster und „Friday“ allein sind unter „Wake-Erkennung erweitern“ ausdrücklich zuschaltbar; standardmäßig können sie nicht aktivieren.
4. „Hey Friday, suche nach test auf Safari“ öffnet eine Google-Suche in Safari.
   Auch „Öffne Safari und suche nach Test“ und „Suche nach Test“ funktionieren als direkte Safari-Aktion.
   „Kannst du Shaper 3D öffnen?“ erkennt die installierte App Shapr3D auch mit dieser
   Schreibweise. Leerzeichen und eindeutige kleine Schreibfehler in App-Namen sind erlaubt.
5. „Hey Friday, mach eine Notiz: Milch kaufen“ probieren. „Notizen zeigen“ öffnet den Ordner.

Alternativ „Sprechen“ drücken oder einen Befehl als Text eingeben. „Abbrechen“
stoppt die laufende Verarbeitung; das Overlay hat während der Aufnahme eine Stop-Taste.
Wake ist standardmäßig aus und pausiert während Aufnahme, Verarbeitung und TTS.
Im Idle und bei Wake-Bereitschaft bleibt der Orb als Ring stehen, ohne Beschriftung.
Während der Aufnahme wobbelt derselbe 2D-Ring. Ausführung zeigt kreisende Punkte;
Gemini zeigt die verschachtelnde solving-Animation. Nach Hex erscheint der erkannte Befehl
am Overlay; nach erfolgreicher Computeraktion verschwindet er nach einer Sekunde,
bei Fragen nach acht Sekunden. Beim nächsten Befehl wird
er entfernt. Das ist kein Wort-für-Wort-Live-Transkript.
LLM-Antworten werden standardmäßig mit Piper „Thorsten High“ auf Deutsch vorgelesen,
vollständig lokal und ohne API-Kosten. Die Stimme wird beim Setup vorbereitet,
beim ersten Vorlesen geladen und verwendet anschließend keine Netzwerkverbindung.
Alternativ sind Gemini 3.8 Flash-Lite TTS mit Kore, Aoede und Charon auswählbar.
Bei einem Cloud-Sprachfehler übernimmt Piper; bis zur erneuten Auswahl bzw. zum
Speichern eines Schlüssels wird die Cloud-Stimme in dieser Sitzung nicht erneut angefragt.
Die Anzeige unter dem Sprachschalter nennt die verwendete Stimme oder einen Fehler;
die Textantwort bleibt erhalten. Der Schalter kann die Sprachausgabe ausschalten.
Gemini 3.5 Flash-Lite mit minimalem Thinking ist der Standard für Textantworten.
Bei Überlastung übernimmt Gemini 3.8 Flash mit niedrigem Thinking. Das
überlastete Modell wird danach zwei Minuten lang nicht erneut angefragt.
„Noch einmal vorlesen“ wiederholt die letzte LLM-Antwort, ohne eine neue Gemini-
Text-Anfrage. TTS erzeugt beim Replay neue Audiodaten. Während Aufnahme, Verarbeitung oder Wiedergabe ist Replay gesperrt.

Aktuelle Fragen können über DuckDuckGo Lite recherchiert werden. Gemini erhält bis
zu fünf Suchergebnisse mit Snippets und formuliert daraus eine Antwort mit getrennten,
klickbaren Quellen. Das ist kein vollständiger Abruf der Quellseiten; bei Captchas
oder fehlenden Daten erscheint eine klare Meldung. Wetterfragen verwenden echte
Open-Meteo-Daten bis 16 Tage. Ohne Ort fragt Friday nach der Stadt; ein kurzer
Gesprächskontext bleibt im Arbeitsspeicher für Antworten wie „Berlin“ erhalten.
Suchdaten können keine zusätzlichen Computeraktionen auslösen. Googles integrierte
Suche ist bei diesem kostenlosen Schlüssel nicht verfügbar und wird nicht verwendet.

Die Kugel in der Menüleiste öffnet das Friday-Menü; „Friday öffnen“ oder ein Klick
auf die Overlay-Kugel öffnet Einstellungen und Antworten. Schließen dieses Fensters
beendet Friday nicht. „Beenden“ im Menü beendet auch die Mikrofon-Helper.

Unter „Orbs zuordnen · 9 Animationen“ einen Zustand wählen und auf die gewünschte
Animation klicken. Die Zuordnung gilt sofort für Overlay und Fenster und bleibt
lokal gespeichert. Alle neun Zustände sind einzeln einstellbar; „Standard
wiederherstellen“ setzt alle Zuordnungen zurück. Idle/Wake-Bereitschaft bleiben
auch mit anderer Auswahl statisch.

„Friday, finde Projekt hackday“ oder „Such mir den Terminal-Tab raus, wo ich
Projekt Friday offen habe“ sucht lokal in Fenstertiteln und im sichtbaren Text von
Terminal.app-Tabs. Ein Treffer wird fokussiert; bei mehreren öffnet sich eine
Auswahl im Friday-Fenster. Dafür sind Bedienungshilfen und beim ersten Terminal-
Zugriff die macOS-Automationsfreigabe erforderlich. Gelesene Titel und Inhalte
gehen weder an Gemini noch an TTS. Die Suche liest keine Screenshots, komplette
Terminal-History oder Browser-/Editor-Inhalte. macOS übernimmt beim Fokussieren
den Wechsel zum zugehörigen Schreibtisch; Friday ermittelt keine Space-Nummern.

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
Klicken in fremden Apps und Einfügen am Cursor folgen später.
„Diktat-Vorschau“ zeigt den erkannten Text. „LLM-Antwort vorlesen“ ist optional;
App-Starts und Notizen bleiben stumm.

## Bausteine

| Funktion | Erste Version |
| --- | --- |
| Wake | Moonshine Small Streaming Deutsch (123M) für Hey Friday; optional Friday allein / persönliche lokale Klangmuster (3 Sprachproben, DTW) |
| Deutsch → Text | Hex 2.1.24, Whisper large-v3-turbo über lokalen API-2-Helper |
| Schnelle Entscheidung | Laya multilingual Core ML, Auswahl aus zehn Intents |
| Computer Use | Installierte Apps starten, Safari-Suche, lokale Notizen, Schreibtischwechsel, offene Projekte finden |
| Komplexe Antwort | Gemini 3.5 Flash-Lite (minimal), Ersatz 3.8 Flash (low); alternativ Ollama lokal |
| Text → Sprache | Piper Thorsten High lokal; Gemini 3.8 Flash-Lite TTS optional mit lokalem Fallback |
| Recherche | DuckDuckGo-Snippets, Open-Meteo-Prognose, Quellen separat zur Antwort |
| Oberfläche | Menüleisten-Kugel und transparentes Thinking-Orb-Overlay; native MIT-Animationen |

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
Die lokalen Python-Worker für Laya, Wake und Piper liegen unter `services/local-runtime` und werden
mit der `.app` gebündelt. Modelle und Python-Umgebung bleiben außerhalb des Repos.

Geprüft: Swift-/Python-Tests, echte lokale Laya-Inferenz, synthetische Wake-Aufnahme, Audio-Callback auf Hintergrundthread,
deutsches WAV → Hex → Laya und tatsächliches Speichern einer Notiz sowie App-Build/Signatur.
Mikrofon, individuelle Aussprache und sichtbarer App-Start benötigen einen Live-Test auf dem Mac.
Das deutsche Small-Modell erkannte synthetisches „Hey Friday“ auch bei stark
reduzierter Lautstärke; das ist keine Abnahme der individuellen Mikrofonerkennung.
Die Sprachabschluss-Erkennung berücksichtigt jetzt den lokalen Ruhepegel, damit
leise Befehle nicht vorzeitig enden. „Hey Friday“ ohne Auftrag öffnet eine kurze
weitere Aufnahme. Bei fehlender Aktivierung die Mikrofon-Diagnose oder „Sprechen“ verwenden.
Ohne konfigurierte Apple-Signatur wird ad-hoc signiert. Die Entwicklungs-App ist
kein notarisiertes Release. Bereits laufende Apps werden direkt aktiviert; der
Kaltstart einer App hängt von deren eigener Startzeit ab.

[Architektur](docs/architecture.md) · [Integrationen](docs/integrations.md) ·
[Roadmap](docs/roadmap.md) · [Build-9-Prüfung](docs/verification-2026-10-05-v9.md) ·
[Handy und Brille: nächster Schritt](docs/mobile-access.md) · [CONTRIBUTING.md](CONTRIBUTING.md)

## Lizenz

Friday-Code, Maskottchen und lokale Worker stehen unter MIT; Laya-Code und die
verwendeten Laya-Gewichte unter Apache-2.0, Moonshine Small Deutsch und Hex/Whisper unter MIT.
Die [Thinking Orbs](https://github.com/Jakubantalik/Libraries.dev) sind mit MIT-Hinweis gebündelt.
Piper verwendet die offene [Thorsten-High-Stimme](https://huggingface.co/rhasspy/piper-voices/blob/main/de/de_DE/thorsten/high/MODEL_CARD)
mit CC0-Sprachdaten; die Engine wird über Moonshine Voice bereitgestellt.
Jedes gewählte Ollama-Modell hat seine eigene Lizenz. `main.py` und `ai.py` bleiben
als ursprünglicher D&D-Starter erhalten; dafür enthielt das Ausgangsrepo keine Lizenz.

Gemini ist ein optionaler Cloud-Dienst mit eigenem Modell und Kontingent, kein
Open-Weight-Modell. Die lokale Ollama-Alternative bleibt verfügbar.

## Home Assistant und neue lokale Aktionen

Im Friday-Fenster „Home Assistant“ aufklappen, Serveradresse (z.B.
`http://homeassistant.local`) und einen langlebigen Token aus dem Home-Assistant-
Profil eintragen, dann „Speichern & verbinden“. Frontend-Pfade wie `/home/overview`
werden zur Serveradresse normalisiert. Konfiguration und Token liegen nur unter
`~/Library/Application Support/Friday/Credentials/home-assistant.json` (0600),
außerhalb von Git/App-Bundle. HTTP-Weiterleitungen erhalten keinen Token.

Friday erkennt Namen und IDs vorhandener Lichter, Steckdosen, Szenen und Heizungen.
Beispiele: „Wohnzimmer an“, „Licht im Wohnzimmer aus“, „Schalte Wohnzimmer Licht an“, „Dimme Wohnzimmer Licht auf 30 Prozent“,
„Aktiviere Szene Abend“, „Stelle Wohnzimmer Heizung auf 21 Grad“. Mehrdeutige Namen
führen zu einem Hinweis; die eindeutigen IDs stehen im Einstellungsbereich. Helligkeit
und Temperatur werden gegen Gerätefähigkeiten geprüft (Temperatur in Celsius,
vorhandene Zieltemperatur-Funktion und passende Bereich/Schrittweite). Zeitpläne,
Bedingungen und freie HA-Dienste sind nicht implementiert. Nach HTTP-Timeout wird
kein Steuerungsauftrag automatisch wiederholt. Eindeutig benannte Lichtgruppen
haben bei Raumbefehlen Vorrang vor einzelnen Lampen; Räume und IDs werden aus dem
Gerätekatalog ermittelt. Laya klassifiziert auch die kurzen Befehle lokal.
Nach genau einem Steuerungsauftrag liest Friday den Zustand erneut aus Home Assistant.
Bei Lichtgruppen müssen auch die gelisteten Mitglieder den Zielzustand melden.
Die Erfolgsanzeige bestätigt diesen gemeldeten Zustand. Bleibt die Bestätigung
aus, erscheint ein Fehler ohne erneuten Steuerungsauftrag. Der reale Wohnzimmer-
Test schaltete Gruppe und beide Lampen ein; der Nutzer bestätigte das Licht.

Zusätzliche Mac-Befehle: „Öffne Downloads“, „Öffne Dokumente“, „Öffne Schreibtisch“,
„Öffne https://example.com“. Webseiten müssen ausdrücklich als HTTP(S)-Adresse
angegeben werden. „Finde Safari Tab mit Seite GitHub offen“ sucht lokal in Titel
und Adresse. „Such mir den Safari-Tab raus mit Inhalt Projekt XY“ liest zusätzlich
nativen Safari-Seitentext, ohne Screenshot, Webseiten-JavaScript oder Cloud-Upload.
Bis 80 Tabs werden anhand von Titel/Adresse geprüft, Seitentext nur für die ersten
20 und höchstens 12.000 Zeichen je Tab. Safari-Automation muss freigegeben sein;
mehrere Treffer erscheinen zur Auswahl. Doppelte URLs in demselben Fenster können
nicht eindeutig fokussiert werden und führen zu einem Hinweis.

## Geschwindigkeit, Energie und Gespräch

„Schneller Sprechabschluss“ verkürzt die erforderliche Pause von 750 auf 500 ms.
Bei längeren Denkpausen deaktivieren. Validierte sichere Entscheidungen werden
für identische Befehle fünf Minuten im Arbeitsspeicher gecacht (maximal 64);
Werkzeugausführung, Geräteauflösung und Argumentprüfung bleiben bei jedem Aufruf.
Keine Antwort-/Ergebnis-Caches und keine Speicherung dieser Befehle auf Disk.

Aktive Orb-Animationen laufen höchstens mit 24 fps. In der Galerie animiert nur
die gewählte Vorschau; bei inaktivem Einstellungsfenster pausieren alle Fenster-
Animationen. Idle/Listening bleiben statisch. Der persönliche DTW-Abgleich wurde
bei gleichen Scores/Schwellen beschleunigt; ohne die opt-in Klangmuster-Aktivierung
läuft er nicht mit. Moonshine erhält weiterhin alle Audiosamples und dieselbe
250-ms-Erkennungstaktung. Der tatsächliche Verbrauch und die Erkennung müssen
nach Neustart mit der eigenen Stimme überprüft werden.

Gemini behält bis acht Frage-/Antwortpaare (maximal 16.000 Zeichen) im Arbeitsspeicher.
Computeraktionen/Ergebnisse gehören nicht in diesen Kontext. „Gesprächskontext
löschen“ entfernt ihn. Nach erfolgreichem Vorlesen einer Rückfrage kann Friday
bei aktiviertem Wake direkt aufnehmen; die Overlay-Anzeige markiert dies deutlich.
Ohne Sprachbeginn nach acht Sekunden endet die Aufnahme ohne neue Modellanfrage.
„Nee, ist egal“ beendet das Gespräch. „Nach Rückfragen direkt antworten“ ist
abschaltbar. Normale Antworten starten keine Aufnahme.
