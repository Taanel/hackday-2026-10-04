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
- Ab Build 15 beträgt die voreingestellte Schwelle 0,030 g; bestehende persönliche
  Einstellungen bleiben erhalten. Der Regler reicht bis 0,005 g statt zuvor
  mindestens 0,040 g. Die wirksame Schwelle liegt bei mindestens siebenmal dem
  gemessenen ruhigen Sensorrauschen und wird im Test angezeigt.
- Ab Build 16 werden Impulse über **0,060 g** immer verworfen. Die einstellbare
  Mindestschwelle endet deshalb bei 0,055 g; frühere größere Einstellungen werden
  darauf begrenzt. Dies verhindert starke Stöße, ist aber keine allgemeine
  Klassifizierung jeder Anhebe-Bewegung.
- Kurze Tipps verändern die Gravitations-Baseline nicht mehr; dadurch erzeugt
  die Filterung keinen künstlichen langen Nachlauf. Bei anhaltender Bewegung
  wird die Baseline wieder nachgeführt. Kurze Nachschwinger innerhalb 100 ms
  löschen einen gültigen ersten Tipp nicht mehr und zählen separat.
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
Ab Build 15 werden außerdem erkannte Einzeltipps, Nachschwinger und der letzte
Grund angezeigt: Eingabesuppression, Einmessen, Sperrzeit, lange Bewegung,
starker Stoß oder fehlender zweiter Tipp. Ein erkannter Doppeltipp startet erst
außerhalb des Testmodus eine Aufnahme, wenn „Durch Doppeltippen sprechen“ an ist.

Automatische Tests verwenden synthetische Impulse und prüfen Paarzeitfenster,
Eingabesuppression einschließlich verspäteter Ereignisse, Bewegungen, Rauschen,
Mehrfachimpulse, Sperrzeit und ungültige/unterbrochene Daten. Diese Tests beweisen
keine Erkennungsrate für reale Fingerbewegungen. Eine universelle Zuverlässigkeit
oder eine gemessene Akkulaufzeit wird deshalb nicht behauptet.

## Doppeltklatschen und Doppelschnipsen

Ab Build 16 getrennt zuschaltbar unter **Sprache → Klatschen & Schnipsen**.
Beide Optionen sind zunächst aus. Der 30-Sekunden-Test zählt bestätigte Paare,
startet aber keine Befehle. Anders als Gehäuse-Doppeltippen erfordert diese
Aktivierung ein laufendes Mikrofon; Friday verwendet dafür denselben vorhandenen
AudioInput wie Wake und Aufnahme, keine zweite Mikrofoninstanz.

Ein günstiger Impulsfilter erkennt zwei kurze Anstiege im Abstand 150–800 ms.
Relativer Abfall erlaubt Nachhall über dem normalen Rauschpegel. Anschließend
prüft Apples [SoundAnalysis-Klassifikator](https://developer.apple.com/documentation/soundanalysis/snclassifysoundrequest)
zwei getrennte 500-ms-Ausschnitte und das gemeinsame Paar. Beide Einzelgeräusche
müssen denselben Typ unterstützen, das gemeinsame Fenster muss die eingestellte
Konfidenz erreichen. Sprach-/Tastaturklassen können eine Aktivierung verhindern;
Applaus allein zählt nicht als zusätzliche Geste. Es läuft keine Modellinferenz
im ruhigen Idle. PCM und Ergebnisse bleiben im Speicher auf dem Mac.

Während Aufnahme, Befehlen und Vorlesen sind Gesten gesperrt. Verspätete
Klassifikationen werden nach Suspend/Abbruch/Neustart des Hörens verworfen.
Sprachbeginn nach dem zweiten Geräusch bleibt im vorhandenen Aufnahme-Ringpuffer
erhalten, auch während der Klassifizierung. Zwischen Geräuschpaar und Befehl
kurz pausieren. Das bekannte Modell unterstützt `clapping` und `finger_snapping`.
Physische Erkennungsraten für die eigenen Hände sind noch nicht gemessen;
Mindestpegel und Konfidenz lassen sich nach Beenden des Tests einstellen.
