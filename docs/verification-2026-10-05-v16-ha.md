# Build 16: Home Assistant über mehrere Räume

## Reproduzierter Fehler

Die Nutzerformulierung „Küche Licht aus“ beziehungsweise „Küche-Licht aus“
wird vom lokalen Parser bereits als unmittelbarer Home-Assistant-Befehl erkannt.
Ein nur lesender Abruf der echten Zustände und Bereichs-/Geräte-/Entity-Register
zeigte sechs individuelle Lampen im Bereich Küche. Drei Hall-Spots waren
`unavailable`. Die bisherige Verfügbarkeitsprüfung blockierte deshalb den gesamten
Raum, einschließlich der erreichbaren Kücheninsel-Lampen.

Die genaue aktuelle Swift-Parser-/Resolver-Implementierung wurde zusätzlich mit
diesem Inventar ausgeführt, ohne einen Service aufzurufen. „Büro an“ löste fünf
erreichbare Lampen auf, „Schlafzimmer an“ eine. „Küchenlicht aus“ scheiterte am
Wortabgleich: Der zusammengesetzte Name ergab `kuchen`, der HA-Bereich `kuche`.
„Albedo“ war wegen gleichnamiger `light`-/`switch`-Entities mehrdeutig;
„Büro Nachtlicht“ wegen doppelter Szenennamen.

Eine echte lokale Laya/Core-ML-Probe für Wohnzimmer, Küche, Büro, Schlafzimmer,
Küchenlicht und Büro Nachtlicht wählte jeweils `home_control`, ohne Truncation,
mit Modellscore 0,9991–0,9995. Diese Fehler lagen nach der Modellentscheidung;
die Probe belegt keine allgemeine Sprachgenauigkeit.

Die exakten Nutzertexte „Küche Licht aus“ und „Küche-Licht aus“ wurden separat
geprüft: jeweils `home_control`, Score 0,9995, ohne Truncation. Die neuen
bereichsbezogenen Steckdosen-/Heizungsformulierungen wählten ebenfalls
`home_control` (0,9993 beziehungsweise 0,9999). Diese Modellproben führen keine
Geräteaktion aus.

## Änderung und Prüfung

Raumbefehle sprechen erreichbare individuelle Lampen einmal an und bestätigen deren
HA-Zustände. Nicht verfügbare Lampen werden namentlich als übersprungen
gemeldet; eine Teilbestätigung nennt die Anzahl gegenüber dem gesamten Raum.
Ein vollständig nicht verfügbarer Raum und ein ausdrücklich genanntes nicht
verfügbares Gerät senden keinen Service-Aufruf. Zusammengesetzte Lichtnamen
werden nur auf vorhandene HA-Bereiche abgebildet; ein exakter Bereichsname hat
Vorrang. Bereichszuordnungen disambiguieren auch generische Steckdosen-/Thermostatnamen,
ohne andere Bereiche zu steuern. Doppelte Szenennamen bleiben
mehrdeutig.

Die Regressionen liegen in `HomeAssistantTests.swift`. Alle schreibenden
HTTP-Anfragen dieser Tests werden von `URLProtocol` abgefangen; sie erreichen
keine echten Geräte. Gezielter Prüflauf nach der Implementierung:

```sh
swift test --package-path apps/macos --filter 'HomeAssistantTests|shortRoomCommandsAreLocalHomeActions|questionsAreNotShortHomeCommands|extendedLocalActionsDoNotInventHomeActions'
```

Die vier zunächst ausgeführten Regressionen schlugen vor der Produktionsänderung
mit den erwarteten Ursachen fehl: blockierter Küchenraum, fehlender
Zusammensetzungsabgleich, doppelte Namen über Gerätetypen und fehlende
Bereichszuordnung bei generischen Geräten. RED-Protokoll:
`/tmp/friday-v16-policy-red.log`. Der abschließende gezielte Lauf `/tmp/friday-v16-final-tests.log` bestand
mit 54 Tests einschließlich der 19 serialisierten Home-Assistant-Tests und der
drei Küchenformulierungen. Die erste GREEN-Ausführung fand eine zu breite
Textassertion: Teilbestätigungen enthalten ebenfalls den Raumnamen mit „aus“.
Die Assertion prüft nun konkret, dass keine vollständige Raumbestätigung
ausgegeben wird, und prüft weiterhin Anzahl, übersprungene Namen und POST-Ziele. Die Diagnose hat ausschließlich GET- und
Register-Lesezugriffe verwendet. Zugangsdaten wurden weder ausgegeben noch in
Testdateien übernommen; die laufende App und reale Geräte wurden nicht verändert.
