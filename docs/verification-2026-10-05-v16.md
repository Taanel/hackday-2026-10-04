# Build 16: Geräuschaktivierung und weitere Home-Assistant-Räume

## Änderungen

- Gehäuse-Doppeltippen akzeptiert standardmäßig höchstens 0,060 g pro Impuls.
  0,050/0,060-g-Paare bleiben gültig, 0,080/0,200-g-Paare werden verworfen.
  Der Einstellungsregler endet bei 0,055 g. Alte höhere Mindestwerte werden begrenzt.
- Klatschen und Schnipsen sind getrennt zuschaltbar unter Sprache. Der bestehende
  Mikrofonstream wird geteilt; ohne Wake/Geräuschoption/Aufnahme wird er gestoppt.
  Im ruhigen Idle läuft nur ein begrenzter PCM-Filter, keine SoundAnalysis-Inferenz.
  Zwei Impulse im Abstand 150–800 ms führen zu zwei unabhängigen Einzelprüfungen
  und einer gemeinsamen Paarprüfung. Nachhall wird durch relativen Pegelabfall
  berücksichtigt. Testmodus zählt, startet aber keine Befehle.
- Aufnahme beginnt am gespeicherten Sample nach dem zweiten Geräusch. Bereits
  während der Klassifizierung gesprochene Silben bleiben im bestehenden Puffer.
  Befehlssprache wird vom Modellfenster ausgeschlossen. Ein kurzer dritter
  Impuls verwirft das Paar; bereits begonnene längere Sprache erhält es auch
  dann, wenn sie vor Ablauf der Paarwartezeit endet. Abbruch, Suspend, Shutdown
  und späte Klassifikation dürfen keine neue Aufnahme
  auslösen. Ein während Befehlen ablaufender Test wird erst danach zurückgestellt.
- Home-Assistant-Raumbefehle steuern verfügbare individuelle Lampen und nennen
  übersprungene Offline-Lampen. Küche wurde vorher von drei nicht verfügbaren
  Hall-Spots blockiert. Zusammengesetzte Raumnamen und bereichsbezogene generische
  Gerätenamen werden anhand des echten Katalogs aufgelöst. Details:
  [HA-Diagnose und Regressionen](verification-2026-10-05-v16-ha.md).

## Gezielte Prüfung

```sh
swift test --package-path apps/macos --filter 'HomeAssistantTests|shortRoomCommandsAreLocalHomeActions|questionsAreNotShortHomeCommands|extendedLocalActionsDoNotInventHomeActions|chassis|soundGesture|soundOnly|soundActivation|manualCapture|wakeFailureRecovers|followUpSilence'
```

54 Tests bestanden. Der anschließende Review fand zwei zusätzliche Grenzfälle:
sofortige kurze/lange Sprache nach dem Klatschen und Mikrofonfehler beim
Einschalten. Beide wurden zuerst mit fehlgeschlagenen Regressionen reproduziert
und korrigiert. Der abschließende erneute Lauf der 19 betroffenen Sprach-/Geräuschtests
bestand, einschließlich vier Kombinationen aus Sprechbeginn und Sprechdauer.
Die Geräte-/Gehäusetests wurden nach diesen ausschließlich sprachbezogenen
Änderungen nicht erneut ausgeführt. Die Küchenformulierungen wurden in drei parametrisierten
Fällen getestet. Alle HTTP-Schreibzugriffe wurden in Tests abgefangen, keine
realen Lampen umgeschaltet. Keine unveränderten TTS-/Dateisuche-Testreihen oder
vollständige Swift-Testsuite ausgeführt. Vor den Änderungen scheiterten die neuen
Schwellen-/HA- und Integrationsregressionen mit den erwarteten Ursachen.

Der echte eingebaute Apple-Klassifikator wurde in einem separaten nativen
CLI-Prozess ohne Mikrofonaufnahme ausgeführt. Bekannte Klassen enthalten
`clapping` und `finger_snapping`. Ein erstes 500-ms-Fenster dauerte etwa 67 ms;
drei aufeinanderfolgende Fenster in späteren Proben etwa 140–150 ms. Dies sind
isolierte Modellzeiten auf diesem Mac, keine garantierte Ende-zu-Ende-Latenz.

Temporäre beschriftete [ESC-50-Aufnahmen](https://github.com/karolpiczak/ESC-50)
wurden nicht ausgeliefert oder committed. Sie zeigten geringe Werte für sehr
kurze Einzelclips gegenüber höheren Paarwerten; deshalb unterstützt ein
Paarfenster die weiterhin unabhängigen Einzelprüfungen. Tastatur- und gemischte
Kandidaten wurden abgelehnt. Mehrere Applaus-Ausschnitte wurden auch als positive
Proben nicht bestätigt: kontinuierlicher Applaus ist kein zuverlässiger Ersatz
für ein physisches Doppelklatschen. Echte persönliche Erkennungsraten für Klatschen
und Schnipsen sind noch offen und müssen mit dem eingebauten Test geprüft werden.
Die Schnittstelle ist lokal, die Apple-Modelle sind keine ausgelieferten offenen
Gewichte. [Apple-API](https://developer.apple.com/documentation/soundanalysis/snclassifysoundrequest).

## Installation

Release-Build erfolgreich (24 s), Info.plist Build 16 geprüft. Strenge Signatur-
prüfung erfolgreich, Signierungsanforderung gegenüber Build 15 unverändert.
Repository-Kandidat und App-Bundle enthalten keine lokal gespeicherten
Credential-Bytes. Build 16 liegt in `~/Applications/Friday.app`, die vorherige
Version ist außerhalb des Repositorys gesichert. Die laufende App wurde weder
beendet noch neu gestartet; der Benutzer muss Friday selbst schließen und neu
öffnen, um Build 16 zu laden.
