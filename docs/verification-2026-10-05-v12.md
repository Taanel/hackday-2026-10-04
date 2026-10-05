# Build 12 — Overlay-Aufnahme, Hi Friday und vollständige Raumbefehle

Gezielte Swift-Prüfungen, keine komplette Testsuite:

- Aufnahme ohne Wake; originales Kommando bleibt erhalten. Aufnahme startet vor
  einem künstlich 250 ms verzögerten Wake-Pause-Acknowledgement. Doppelte Starts
  setzen sie nicht zurück. Bestehende Wake-Recovery und Follow-up-Abbruch geprüft.
- App-Normalisierung, Safari-Suche und dynamischer Katalog inklusive `FNDR`.
  Der vollständige native Router mit echtem Laya-Modell bestand 17/17 Fälle,
  etwa 150–170 ms nach Warmup. Der reproduzierbare Evaluator bedient keine Geräte
  und ruft keine Cloud-API auf.
- Home-Assistant-Geräte- und Bereichsauflösung, geerbte/überschriebene Raumzuordnung,
  ein Service-Aufruf für alle individuellen Lampen, keine anderen Räume, gezielte
  Einzelgeräte und kein Erfolg/Retry bei einer verbliebenen eingeschalteten Lampe.
  Fehlender Raumkatalog kann nicht auf eine unvollständige Gruppe zurückfallen.

46 Python-Wake-Tests bestanden. Standard akzeptiert Hey/Hi am Satzanfang und feste
deutsche ASR-Schreibvarianten; einzelne Namen/Erwähnungen mitten im Satz bleiben
abgewiesen. Deutsches Small-Modell mit bisherigen Bias/VAD-Werten: Hey/Hi jeweils
bei synthetischen Pegeln 0,03 und 0,01 und 15 % schnellerem Tempo erkannt. Bei
0,003 wurden beide nicht zuverlässig erkannt. 20 synthetische Gegenproben hatten
keine Aktivierung. Höhere Bias-Werte verursachten Fehlaktivierungen (3: 1/20,
4: 3/20, 6: 7/20) und wurden deshalb nicht installiert. Dies ersetzt keinen Test
mit der realen Stimme und dem Mikrofon des Nutzers; keine neue permanente
Spracherkennungsinstanz, Cloud-Wake oder automatisch aktivierter DTW-Abgleich.

Auf der realen HA-Instanz wurde read-only festgestellt: Kaskade und Albedo gehören
über Gerätezuordnung zum Bereich Wohnzimmer, sind aber nicht in der gleichnamigen
Hue-Gruppe enthalten. Anschließend eine einzige reale Aktion „Wohnzimmer aus“
über den nativen korrigierten Client: alle 13 individuellen Lampen meldeten aus.
Der Nutzer bestätigte anschließend, dass Kaskade und Albedo tatsächlich aus sind.
Laya-Aufträge in der separaten Routing-Evaluation wurden nur aufgezeichnet.

Vier lokale TTS-Schlüsselplätze aus Build 11 bleiben ausschließlich Sprachausgabe;
Reasoning verwendet den bisherigen Hauptschlüssel. Keine neuen realen TTS-Keys
eingetragen oder zusätzlichen Cloud-Sprachaufrufe für diese Änderung.

Release-Build 12 erstellt, Signatur geprüft und stabile Signing-Anforderung mit
Build 11 verglichen. Binär-UUID stimmt mit dem Release-Build überein; gebündelte
Python-Worker entsprechen dem Quellstand. Private Credential-Scans über Repository
und App bestanden. Installiert unter `~/Applications/Friday.app`; Build 11 liegt
als Backup im privaten `PreviousBuild`-Verzeichnis. Die laufende App wurde nicht
automatisiert beendet oder neu gestartet.
