# Gehäuse-Doppeltippen für Friday

## Recherche und Entscheidung

Es gibt mehrere Programme für physisches Klopfen auf MacBooks:

- [Knock](https://www.tryknock.app/) passt zur Beschreibung einer App mit Lizenz/Bezahlschranke. Dass es genau die früher verwendete App ist, ist nicht bestätigt.
- [Tunk](https://tunk.dev/) dokumentiert Sensorzugriff, Eingabesuppression, Messungen und deren Grenzen besonders ausführlich. Sein GitHub-Repository hat zum Recherchezeitpunkt keine ausgewiesene Lizenz; veröffentlichter Quelltext allein reicht nicht als Open-Source-Lizenz.
- [nocnoc](https://github.com/shaircast/nocnoc) und [MacKnock Pro](https://github.com/bezalelsamuel/MacKnock-Pro) haben ebenfalls Quelltext, aber keine ausgewiesene Repository-Lizenz.
- [apple-silicon-accelerometer](https://github.com/olvvier/apple-silicon-accelerometer) veröffentlicht die Sensor-/Report-Schnittstelle unter MIT. [spank](https://github.com/taigrr/spank) nennt ausdrücklich M1 Pro als unterstützte Ausnahme bei M1-Modellen.

Friday verwendet eine eigene kleine Sensoranbindung und eigene Impulserkennung;
es wurden keine fremden Detektorquellen oder Binaries übernommen. Apple stellt
den SPU-Sensor nicht über eine öffentliche Motion-API bereit. Die private HID-
Ereignisschnittstelle wird dynamisch geladen und bei fehlenden Symbolen sauber
abgelehnt. Diese Schnittstelle kann sich mit macOS ändern; die Funktion ist für
diese privat installierte App, nicht als App-Store-kompatible API gedacht.

Der tatsächliche Mac ist ein MacBookPro18,3 mit M1 Pro. IORegistry zeigt einen
AppleSPUHID-Beschleunigungssensor (Usage Page 0xFF00, Usage 3). Ein nativer,
unprivilegierter Probeprozess lieferte 629 Samples in drei Sekunden mit
angeforderten 200 Hz. Kein sudo, kein externer Hintergrunddienst erforderlich.
Eine Berechtigung des Probeprozesses ersetzt nicht die Berechtigung von Friday.

## Aktivierung und Schutz vor Fehlauslösungen

- Standardmäßig ausgeschaltet. Unter Sprache eine eigene Sektion mit Testmodus.
- Angeforderte Rate 200 Hz statt 800 Hz; keine Kamera, zusätzliche Mikrofonspur,
  LLM-Aufrufe oder fortlaufende Sensorlogs.
- Baseline entfernt Gravitation/langsame Änderungen; eine begrenzte adaptive
  Rauschschwelle und Hysterese erkennen kurze getrennte Impulse.
- Zwei Impulse im Abstand 120–420 ms, danach 180 ms Ruhe zur Bestätigung.
  Ein einzelner Impuls startet nie eine Aufnahme. Lange Bewegungen, sehr starke
  Schläge, zu kleine Impulse und enges Nachschwingen werden verworfen.
- 350 ms Sperre nach Tastatur-/Maus-/Scroll-Eingaben. Friday fragt nur das Alter
  dieser Eingaben ab; es liest keine Zeichen, Tastencodes oder Zwischenablage.
  Beim Auslösen wird die Eingabesituation nochmals geprüft.
- Bereits laufende Aufnahme, Befehle, TTS, Start oder Beenden verhindern eine
  Aktivierung. Der bestehende Aufnahmeweg enthält zusätzlich die Zustandsprüfung.
- Sensorlücken verwerfen angefangene Gesten. Nach einer Aktivierung gibt es
  1,2 Sekunden Sperre. Ein stiller/gesperrter Sensor endet mit einer Meldung.
- Stop stellt das vorherige ReportInterval wieder her und gibt Sensorreferenzen
  frei. Die deaktivierte Funktion hat keinen laufenden Erkennungstask.
- Beim Einschalten sind Eingabeüberwachung und ggf. ein von macOS verlangter
  Neustart erforderlich. Die bestehende Mikrofonberechtigung gilt für Aufnahme.

## Test auf dem eigenen Mac

Der 30-Sekunden-Test zählt Gesten, startet aber selbst kein Mikrofon. Zuerst
normales Tippen und Trackpad-Nutzung: Der Doppeltipp-Zähler soll bei 0 bleiben.
Danach mehrere absichtliche Doppeltipps. Bei verpassten Gesten Schwelle senken;
bei unerwarteten Gesten erhöhen oder deaktivieren. Zum Vergleichen sind getrennte
Testdurchläufe sinnvoll. Tisch, Schoß, Hülle und Anschlag verändern das Signal.

Automatische Tests verwenden synthetische Impulse und prüfen Paarzeitfenster,
Eingabesuppression einschließlich verspäteter Ereignisse, Bewegungen, Rauschen,
Mehrfachimpulse, Sperrzeit und ungültige/unterbrochene Daten. Diese Tests beweisen
keine Erkennungsrate für reale Fingerbewegungen. Eine universelle Zuverlässigkeit
oder eine gemessene Akkulaufzeit wird deshalb nicht behauptet.

## Doppelschnipsen

Apples [SoundAnalysis](https://developer.apple.com/documentation/soundanalysis)
hat einen lokalen eingebauten Klassifikator. Auf diesem Mac enthält
`SNClassifySoundRequest(classifierIdentifier: .version1).knownClassifications`
die Klassen `finger_snapping`, `typing`, `typing_computer_keyboard`, `knock` und
`tap`; das kleinste erlaubte Analysefenster ist 500 ms.

Das ist eine machbare alternative Eingabe. Sie benötigt eine Mikrofonspur sowie
lokale Modellinferenz und getrennte negative Tests mit Tastatur, Sprache und
Lautsprecherwiedergabe. Ein einfacher Lautstärke-/Doppelpeak-Trigger wäre zu
verwechslungsanfällig. Deshalb ist in dieser ersten Version Gehäuse-Doppeltippen
implementiert; Schnipsen wurde auf API-/Modellverfügbarkeit geprüft, aber noch
nicht als Aktivierung freigeschaltet.
