# Friday — lokaler Assistent für macOS

Erste testbare Version: Thinking-Orb-Overlay oben rechts, native Thinking Orbs,
„Hey Friday“ oder „Hi Friday“ (weitere Wake-Varianten optional), deutsche Spracheingabe mit Hex, lokale Laya-Entscheidungen und
Computeraktionen. Komplexe Fragen gehen je nach Konfiguration an Gemini Flash oder Ollama; nur LLM-Antworten können
optional mit Gemini-TTS auf Deutsch vorgelesen werden; Piper ist der lokale Ersatz. Friday startet als Menüleisten-App
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

Unter „Assistent → Gemini-Verbindung & Gespräch“ den API-Schlüssel eintragen und
„Speichern“ wählen. Alternativ verwendet das CLI oben denselben lokalen Store.
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
Google; Hex, Wake, Laya und die auswählbare Piper-Stimme bleiben lokal. Recherche sendet Suchbegriffe an DuckDuckGo
oder den ausdrücklich genannten Wetter-Ort an Open-Meteo.
Mit `reasoningProvider: "ollama"` in runtime.json lässt sich wieder lokal antworten.

Unter „Sprache → Vorlesen → Separate TTS-Schlüssel“ lassen sich vier Google-Schlüssel
einzeln speichern, ersetzen und entfernen. Gespeicherte Schlüssel werden nicht
wieder angezeigt. Sobald mindestens einer eingerichtet ist, verwendet die
Sprachausgabe nur diese Schlüssel im Wechsel; Textantworten und Recherche bleiben
beim ursprünglichen Gemini-Schlüssel. Ohne separate TTS-Schlüssel wird dieser auch
für die Stimme verwendet. Die vier Plätze liegen ausschließlich lokal in
`~/Library/Application Support/Friday/Credentials/gemini-tts-api-keys.json`
(0600, Ordner 0700). Gleiche Schlüssel werden abgelehnt.
Google zählt Limits pro Projekt, nicht pro Schlüssel: vier Schlüssel desselben
Projekts erhöhen das Kontingent nicht. Verschiedene Projekte besitzen ihre eigenen
Limits, deren tatsächliche Höhe in AI Studio geprüft werden muss.

## Direkt testen

App-Starts, Notizen und Lichtbefehle unterstützen auch „mal bitte“, „kannst du mir“
und ähnliche Befehlspräfixe. Laya liefert Intent und Konfidenz; Parameter werden
lokal gegen Apps bzw. Home Assistant geprüft. Ein vollständig erkannter lokaler
Auftrag geht bei Laya-Fehlern oder Unsicherheit nicht automatisch an Gemini.
Unter **Computer → Lokale Entscheidungen → Letzte Entscheidung prüfen** steht,
ob lokal ausgeführt oder an das LLM weitergegeben wurde. [Messungen und
Fine-Tuning-Grenzen](docs/laya-optimization.md).

Optional: **Sprache → Gehäuse-Doppeltippen → Einrichten & testen**.
Friday in macOS unter Datenschutz → Eingabeüberwachung erlauben, anschließend
den 30-Sekunden-Test starten. Erst normal schreiben / Trackpad benutzen (0
Doppeltipps erwartet), dann zweimal auf das Aluminium neben dem Trackpad tippen.
Die Empfindlichkeit lässt sich dort einstellen. Im Testmodus startet Tippen keine
Aufnahme. Danach „Durch Doppeltippen sprechen“ einschalten: Ein Doppeltipp startet
dieselbe Aufnahme wie ein Klick aufs Overlay, auch ohne eingeschaltetes Wake-Wort.
Einzelanschläge, kürzliches Tippen / Klicken und aktive Befehle / Sprachausgabe
sperren diese Aktivierung. Ohne eingeschaltete Option läuft der Sensor nicht.
Die erste Version ist experimentell; echte Erkennungsraten müssen auf der eigenen
Unterlage geprüft werden. [Technik, Grenzen und Recherche](docs/chassis-activation.md).

1. „Friday öffnen“ im Menüleisten-Menü wählen und auf „Bereit · Laya und Hex lokal“ warten.
2. „Hey Friday“ einschalten und macOS-Mikrofonzugriff erlauben.
   Das Setup verwendet Moonshine Small Streaming Deutsch mit „Hey Friday“ und „Hi Friday“ als Schlüsselphrasen.
   Unter „Sprache → Aktivierung → Mikrofon-Diagnose“ sind Pegel und der zuletzt erkannte
   Text sichtbar, solange das Einstellungsfenster aktiv ist; diese Diagnose wird nicht gespeichert.
   Wenn die Standard-Erkennung die Aussprache nicht versteht: „Hey Friday anlernen“
   anklicken und dreimal nur die Phrase einsprechen, jeweils kurz still sein.
   Nach jeder Probe den Button für die nächste Aufnahme verwenden. Das persönliche
   Klangmuster wird lokal gespeichert. Seine Aktivierung bleibt eine ausdrückliche Option.
   „Zurücksetzen“ entfernt das Profil. Die Anlernfunktion ist ein Prototyp;
   ihre Zuverlässigkeit mit der eigenen Stimme muss live geprüft werden.
3. „Hey Friday, öffne Safari“ sagen; etwa 0,75 Sekunden
   Stille beenden die Aufnahme. Das persönliche Klangmuster und „Friday“ allein sind unter „Sprache → Aktivierung → Zusätzliche Wake-Optionen“ ausdrücklich zuschaltbar; standardmäßig können sie nicht aktivieren.
4. „Hey Friday, suche nach test auf Safari“ öffnet eine Google-Suche in Safari.
   Auch „Öffne Safari und suche nach Test“ und „Suche nach Test“ funktionieren als direkte Safari-Aktion.
   „Kannst du Shaper 3D öffnen?“ erkennt die installierte App Shapr3D auch mit dieser
   Schreibweise. Leerzeichen und eindeutige kleine Schreibfehler in App-Namen sind erlaubt.
5. „Hey Friday, mach eine Notiz: Milch kaufen“ probieren. „Notizen zeigen“ öffnet den Ordner.

Alternativ die Overlay-Kugel anklicken und sofort sprechen — auch bei ausgeschaltetem Wake.
Während der Aufnahme bleibt die Stop-Taste darunter erreichbar; erneute Klicks setzen die Aufnahme nicht zurück.
Oder „Sprechen“ drücken bzw. einen Befehl als Text eingeben. „Abbrechen“
stoppt die laufende Verarbeitung; das Overlay hat während der Aufnahme eine Stop-Taste.
Wake ist standardmäßig aus und pausiert während Aufnahme, Verarbeitung und TTS.
Im Idle und bei Wake-Bereitschaft bleibt der Orb als Ring stehen, ohne Beschriftung.
Während der Aufnahme wobbelt derselbe 2D-Ring. Ausführung zeigt kreisende Punkte;
Gemini zeigt die verschachtelnde solving-Animation. Nach Hex erscheint der erkannte Befehl
am Overlay; nach erfolgreicher Computeraktion verschwindet er nach einer Sekunde,
bei Fragen nach acht Sekunden. Beim nächsten Befehl wird
er entfernt. Das ist kein Wort-für-Wort-Live-Transkript.
Gemini-Antworten werden standardmäßig mit Gemini-TTS vorgelesen. Nur zwei 3.8-Modelle
wechseln sich ab: 3.8 Flash-Lite TTS und 3.8 Flash TTS. 3.1 wird nicht mehr verwendet.
Die gewählte Stimme (Kore, Aoede oder Charon) bleibt gleich. Bei Rate-Limits werden
betroffene Schlüssel-/Modellkombinationen bis zum Retry-Zeitpunkt bzw. Tagesreset übersprungen. Alle
Versuche einer Antwort teilen ein 20-Sekunden-Zeitbudget. Die Anzeige nennt das
tatsächlich verwendete Modell. Drei Stimmen oder Schlüssel im selben Google-
Projekt erhöhen dessen Kontingent nicht; Modellkontingente hängen vom Projekt ab.
Wenn die Cloud-Ausgabe scheitert, übernimmt Piper „Thorsten High“, vollständig
lokal und ohne API-Kosten. Die Cloud-Ausgabe pausiert dann zwei Minuten;
Modell-Sperren bleiben erhalten. Piper lässt sich auch dauerhaft auswählen und
ist bei Ollama die lokale Ausgabe. Die Stimme wird beim Setup vorbereitet,
beim ersten Vorlesen geladen und verwendet anschließend keine Netzwerkverbindung.
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

Die Kugel in der Menüleiste öffnet das Friday-Menü. „Friday öffnen“ oder Rechtsklick
auf die Overlay-Kugel → „Einstellungen und Antworten öffnen“ öffnet das Fenster. Ein normaler Overlay-Klick startet die Aufnahme. Schließen dieses Fensters
beendet Friday nicht. „Beenden“ im Menü beendet auch die Mikrofon-Helper.

Unter „Darstellung“ einen Zustand wählen und auf die gewünschte
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
Terminal-History oder Editor-Inhalte. Eine ausdrücklich angeforderte Safari-Inhaltssuche liest begrenzt Seitentext lokal. macOS übernimmt beim Fokussieren
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
„Diktat“ zeigt den erkannten Text. „Sprache → Vorlesen → Antworten vorlesen“ ist optional;
App-Starts und Notizen bleiben stumm.

## Oberfläche und lokale Suche

Das Fenster trennt **Assistent**, **Sprache**, **Computer**, **Home Assistant** und
**Darstellung**. Diagnose, Anlernen und Schlüssel sind in ihrem Bereich einklappbar.
Die Alltagsansicht enthält Aufnahme, Texteingabe, Antwort und auswählbare Treffer.

„Jo, such den Tab raus, wo ich XY offen habe“ findet bestehende Safari-Tabs anhand
von Titel, Adresse und bei Bedarf lokal lesbarem Seitentext. Titel/Links werden
zuerst geprüft; die Inhaltssuche ist auf 20 Tabs begrenzt. „Such den Terminal-Tab
raus, wo ich XY offen habe“ findet Fenster/Terminal-Tabs. Ein eindeutiger Treffer
wird nach vorn gebracht; mehrere Treffer erscheinen zur Auswahl.

„Such mir Datei Rechnung.pdf raus und öffne sie“ und „Such den Ordner Friday im
Finder“ verwenden eine einmalige, auf vier Sekunden begrenzte
[Spotlight-Abfrage](https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/SpotlightQuery/Concepts/QueryingMetadata.html).
Gesucht wird nach Namen im indexierten Benutzerordner, ohne dauernden Dateiscan.
Versteckte Verzeichnisse, lokale Zugangsdaten und Library-Inhalte außer iCloud Drive
werden ausgelassen. Pfade erscheinen bei mehreren Treffern; höchstens acht werden
angezeigt. Nicht indexierte Orte bleiben unsichtbar. Ein einzelnes Dokument wird
mit seiner Standard-App geöffnet, ein Ordner im Finder; ausführbare Dateien und
Installationsdateien werden nur im Finder gezeigt. Lokale Suchinhalte werden nicht
an Gemini übertragen, auch wenn Gemini den typisierten Suchauftrag liefert.

Bei Wetterfragen zeigt Friday Ort, Datumsbereich, Tages-Minimum/Maximum,
Regenwahrscheinlichkeit und Quelle unter der Overlay-Kugel. Die Werte stammen
direkt aus Open-Meteo. „Nächste Woche“ meint Montag bis Sonntag der nächsten
Kalenderwoche; eine nachgereichte Stadt behält diesen Zeitraum. Unterstützt sind
außerdem heute, morgen, übermorgen, diese Woche und Wochenende. Andere Zeiträume
bleiben vorerst Textantworten. Ohne Ort fragt Friday nach. Die Karte lässt sich
schließen, verschwindet beim nächsten Auftrag oder 40 Sekunden nach der Antwort;
im Antwortfenster bleibt die Vorhersage erhalten. Auf macOS 26 nutzt das Overlay
[natives Liquid Glass](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:));
ältere Systeme verwenden Material, reduzierte Transparenz eine deckende Fläche.

## Bausteine

| Funktion | Erste Version |
| --- | --- |
| Wake | Moonshine Small Streaming Deutsch (123M) für Hey/Hi Friday; optional Friday allein / persönliche lokale Klangmuster (3 Sprachproben, DTW) |
| Deutsch → Text | Hex 2.1.24, Whisper large-v3-turbo über lokalen API-2-Helper |
| Schnelle Entscheidung | Laya multilingual Core ML, Auswahl aus zehn Intents |
| Computer Use | Apps, Safari-Suche, Notizen, Schreibtischwechsel, offene Fenster/Tabs und Spotlight-Dateisuche |
| Komplexe Antwort | Gemini 3.5 Flash-Lite (minimal), Ersatz 3.8 Flash (low); alternativ Ollama lokal |
| Text → Sprache | Gemini 3.8 Flash-/Flash-Lite-TTS, bis vier separate Sprachschlüssel; Piper Thorsten High als Ersatz oder eigene Auswahl |
| Recherche | DuckDuckGo-Snippets, Open-Meteo-Prognose, Quellen separat zur Antwort |
| Oberfläche | Fünf Einstellungsbereiche, Menüleisten-Kugel, transparentes Orb-Overlay und Wetterkarte |

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
Raumbefehle verwenden seit Build 12 die echten Home-Assistant-Bereiche, einschließlich
der vom Gerät geerbten Raumzuordnung. „Wohnzimmer aus“ steuert alle individuellen
Lampen dieses Raums; eine gleichnamige Hue-Gruppe kann nur einen Teil enthalten.
Kaskade und Albedo gehören daher ebenfalls dazu. Einzelne Gerätenamen bleiben
gezielte Aktionen. Der Raumkatalog wird lokal über drei lesende WebSocket-Abfragen
geladen und zusammen mit der Geräteliste 60 Sekunden gecacht. Kein Admin-Token nötig.
Die Prüfung umfasst jede ausgewählte Lampe; eine verbliebene eingeschaltete Lampe
verhindert die Erfolgsmeldung. Kein erneuter Steuerungsauftrag bei fehlender Bestätigung.
Der native Test für „Wohnzimmer aus“ meldete alle 13 individuellen Lampen als aus.
Der Nutzer bestätigte anschließend auch Kaskade und Albedo als tatsächlich aus.
Die Anzeige beschreibt den von Home Assistant gemeldeten Zustand.

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
Build 12 normalisiert auch validierte App-Starts und Notizen vor der Laya-Entscheidung.
„Mach Safari auf“ und „Safari öffnen, bitte“ bleiben dadurch lokal; Finder wird mit
Apples Bundle-Typ `FNDR` ebenfalls entdeckt. Argumente stammen weiterhin aus dem
ursprünglichen Befehl und dem installierten App-Katalog. Der lokale Router wurde auf
diesem M1 Pro mit 17 Befehlen geprüft: 17 richtige Routen, etwa 150–170 ms je Entscheidung.
`./scripts/evaluate-local-routing.sh` wiederholt diese Prüfung mit vorhandenen Modellen,
ohne Computer-/HA-Aktionen oder Cloud-Aufrufe. [Laya-Optimierung und Fine-Tuning](docs/laya-optimization.md).

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
