# Friday Build 14 — lokale Entscheidungen und Doppeltippen

## Laya / Routing

- Fehler mit natürlicher Sprache reproduziert: 13/27 richtige Routen vor der
  Präfix-/Argumentkorrektur, 27/27 danach. Drei weitere Fälle trennen Notiz und
  Websuche ausdrücklich von Home-Assistant-Aktionen.
- Abschließender realer Core-ML-Lauf: **55/55** korrekte Routen und Tool-Intents
  (25 bisherige + 30 neue Fälle), ohne echte Aktionen / Cloud-Aufrufe.
- Die warmen Entscheidungen lagen im letzten getrennten 27er-Lauf bei
  151,0–163,5 ms, Median 153,1 ms. Gemessen wurde der lokale Router, ohne
  Aufnahme, ASR, Netzwerk oder reale Ausführung.
- 27 gezielt ausgewählte Swift-Tests bestanden, darunter natürliche Befehle,
  vollständige Raumauflösung bei „Wohnzimmerlicht“, unveränderte Notiz-/Suchtexte,
  Ablehnung von Fragen/Bedingungen, Modellfreigabe und lokaler Fehler ohne Cloud.
- Die geänderten Schutzprüfungen für Notiz-/Suchpräfixe und Raumauflösung wurden
  anschließend nochmals gezielt geprüft.
- Keine neue Kalibrierung und kein Gewichtstraining. Testformulierungen dienen
  Regressionen und sind kein unabhängiger Holdout.

## Gehäuseaktivierung

- Tatsächlicher M1-Pro-SPU-Sensor über private IOKit-Ereignisschnittstelle gelesen:
  629 Samples in drei Sekunden bei angeforderten 200 Hz, ohne sudo oder Dienst.
- Native Swift-Adapterprobe lief acht Sekunden im Testmodus, lieferte acht
  Diagnoseberichte und stoppte sauber. Benutzer-/System-CPU zusammen ca. 0,08 s
  in 8,32 s Wall Time; das ist eine kurze Prozessprobe, keine Akkumessung.
- 100 Start-/Stop-Zyklen: nach dem Abbau der asynchronen HID-Registrierungen im
  Runloop keine wachsende Mach-Port-Zahl (52 davor, 49 nach Beruhigung). Während
  einer synchronen Schleife liegen die Freigaben zunächst noch in der Queue.
- Fünf DSP-Tests für Doppelimpulse, Tastatur-/verspätete Eingabesuppression,
  Bewegung/Rauschen/Nachschwingen, Sperrzeit und Sensorlücken bestanden.
- Zwei bestehende Aufnahme-Tests bestanden: Aufnahme ohne Wake und Aufnahme
  vor verzögerter Pause-Bestätigung. Keine unbeteiligten Wake-/TTS-Tests ausgeführt.
- Sprache- und Computer-Einstellungen in Hell/Dunkel offscreen gerendert und
  visuell geprüft. Die laufende App wurde dabei nicht bedient.
- Echte Fingerimpulse, Tisch/Schoß und falsche Aktivierungen bei normalem Arbeiten
  müssen mit dem 30-Sekunden-Test von der Person am Mac geprüft werden. Es wird
  keine universelle Erkennungsrate behauptet.
- SoundAnalysis-Klassifikator auf dem Mac enthält `finger_snapping`; Minimum
  Analysefenster 500 ms. Schnipsen ist noch keine aktivierte Eingabe.

## Paket

Release-Build und Codesign werden vor Installation geprüft; Source- und
Bundle-Dateien werden gegen tatsächlich lokal gespeicherte Geheimnisse geprüft.
Build 13 bleibt als lokale Rückfallkopie erhalten. Die neue App ersetzt die
Installationsdateien, ohne die laufende App zu schließen oder zu starten.
Ein manueller Neustart lädt Build 14. Gemini-Kontingent, Live-Spracherkennung,
Gemini-TTS und reale Lampenschaltungen wurden in dieser Prüfung nicht aufgerufen.
