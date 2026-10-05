# Build 15: Gehäuse-Doppeltippen

## Reproduzierter Fehler

Der Benutzer berichtete nur verworfene Impulse bei einer Anzeige von 0,04 g.
Die gespeicherte Erkennungsschwelle war ebenfalls 0,04 g. Der bisherige Regler
und der Detektor konnten diesen Wert nicht unterschreiten.

Drei neue Regressionstests scheiterten mit dem vorherigen Detektor:

- 0,025-g-Tipps bei ausdrücklich eingestellten 0,015 g wurden ignoriert; auch
  0,060-g-Tipps lagen unter dem bisherigen Standardwert von 0,120 g.
- Kurze Nachschwinger eines gültigen Tipps löschten die begonnene Geste.
- Ein kurzer 30-ms-Tipp verschob die Gravitations-Baseline so stark, dass der
  künstliche Nachlauf als zu lange Bewegung verworfen wurde.

## Änderung

Standardwert 0,030 g, persönliche Einstellungen bleiben erhalten; einstellbarer
Mindestwert 0,005 g. Die wirksame Schwelle berücksichtigt weiterhin ruhiges
Sensorrauschen. Kurze Impulse verschieben die Baseline nicht; für anhaltende
Bewegung wird sie weitergeführt. Kurze Nachschwinger innerhalb 100 ms werden
separat ignoriert und löschen die Geste nicht. Ein zweiter Tipp am Ende des
Zeitfensters darf noch vollständig ausklingen.

Die Diagnose unterscheidet Einzeltipps, Doppeltipps, Nachschwingen und Gründe
für ignorierte Impulse. Der Testmodus startet weiterhin keine Aufnahme.
Eingabesuppression, späte Tastaturereignisse, Bewegungsfilter, sehr starke Stöße,
Sperrzeiten, Datenlücken und ungültige Sensordaten bleiben berücksichtigt.

## Prüfung und Grenzen

`swift test --package-path apps/macos --filter chassis`: 11 gezielte Tests
bestanden, darunter drei Schwellenwerte im zusätzlichen parametrisierten Test.
Keine unveränderten Routing-, Wake-, Home-Assistant- oder TTS-Testreihen ausgeführt.

Eine rein lokale, 20 Sekunden lange Sensorprobe lieferte 4.200 Messwerte.
Ein Replay dieser nicht nach Gesten beschrifteten Messung ergab bei 0,040 g
mit dem alten Detektor keinen Doppeltipp, mit dem neuen einen. Das ist ein
zusätzlicher Signalvergleich, kein Nachweis, dass dieser Trigger ein absichtlich
ausgeführter Doppeltipp war. Niedrigere Schwellen waren in dieser Aufnahme nicht
besser; ausschließlich die Schwelle zu senken ist keine allgemeine Lösung.

Die tatsächliche Erkennungsrate für die Fingertipps des Benutzers ist noch
nicht gemessen. Dafür dient der 30-Sekunden-Test mit getrennten Versuchen für
normales Arbeiten und absichtliche Doppeltipps. Keine universelle Zuverlässigkeit
oder Akkulaufzeit behauptet. Die laufende Friday-App wird nicht neu gestartet.

Eine neue native Testprobe startete den Sensoradapter ohne Sprachaufnahme,
lieferte drei strukturierte Diagnosemeldungen in drei Sekunden und stoppte ihn
wieder. Release-Build und strenge Signaturprüfung erfolgreich. Build 15 liegt in
`~/Applications/Friday.app`, mit unveränderter Signierungsanforderung und einer
gesicherten vorherigen Version. Der Repository-Kandidat enthält keine lokal
gespeicherten Credential-Bytes.
