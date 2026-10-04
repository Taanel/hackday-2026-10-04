# Lokaler Gemini-Schlüssel und ruhiges Friday-Overlay

Der Nutzer hat lokale Schlüssel-Eingabe außerhalb von Git, einen ruhigen Idle-Orb,
eine andere Aufnahme-Animation, ein überprüfbares Transkript und funktionierende
Sprachausgabe angefordert. Diese konkret vorgegebenen Änderungen sind der Umfang.

## Entscheidungen

Ein SecureField unten im Friday-Fenster speichert den Schlüssel unter
`~/Library/Application Support/Friday/Credentials/gemini-api-key.txt`. Dieser
Ordner erhält Modus 0700, die Datei 0600. Ein leerer oder formal fehlerhafter Wert
(Whitespaces, nicht-ASCII, über 512 Zeichen) ersetzt keinen vorhandenen Schlüssel.
Das Speichern prüft nicht die Gültigkeit bei Google; abgelaufene oder nicht
autorisierte Schlüssel werden erst beim API-Aufruf abgelehnt.
Der Inhalt erscheint weder im Fenster noch in
Fehlern, Logs, Commits oder dem App-Bundle. Der Schlüsselbund wird im App-Code nicht
mehr verwendet. Der vorhandene Schlüssel wird einmal lokal migriert, ohne ihn
auszugeben. Hartcodieren würde bei Updates erneutes Bauen verlangen; die lokale
Eingabe lässt sich sofort ändern und entspricht der ausdrücklich erlaubten Variante.

Gemini behält seinen Sitzungscache. Nach dem Speichern verwirft Friday diesen Cache,
damit die nächste Anfrage den neuen Wert verwendet. Speichern ist während laufender
Anfragen deaktiviert. Ein fehlender Schlüssel verweist auf das Eingabefeld.

Idle und Wake-Bereitschaft zeigen einen statischen gepunkteten Ring. Erst die
Aufnahme nach Wake oder manuellem Start animiert denselben 2D-Ring (breathing).
Ausführung zeigt working, Gemini die verschachtelnde solving-Animation. Aktive Verarbeitung
behält ihre bisherigen unterscheidbaren Animationen. Keine Idle-Beschriftung.

Ein kleines, maximal drei Zeilen langes Transkript erscheint am transparenten
Overlay nach erfolgreicher Hex-Transkription. Es ist ausdrücklich keine Live-ASR:
Hex liefert derzeit erst nach Ende der Aufnahme den vollständigen Text. Beim
nächsten Aufnahmestart verschwindet der alte Text; nach Verarbeitung bleibt er
acht Sekunden sichtbar und blendet dann aus. Lange Befehle werden am Overlay
abgekürzt, im Hauptfenster bleiben sie vollständig. Der Orb selbst behält rechts
oben seine Position; das Panel wird nur nach links/unten für Text erweitert.

## Sprachausgabe

Gemini-Antworten werden mit AVSpeechSynthesizer auf Deutsch vorgelesen, sofern der
standardmäßig aktive Schalter gesetzt ist. Ein „Noch einmal vorlesen“-Button an
der Antwort wiederholt ausschließlich die zuletzt erhaltene LLM-Antwort, ohne
Gemini erneut anzufragen. Währenddessen bleibt Wake pausiert; Abbrechen beendet
die Stimme und rearmt Wake. Computeraktionen und Diktat bleiben stumm.
Replay ist während Aufnahme, Verarbeitung und Wiedergabe deaktiviert und im
Handler zusätzlich gesperrt. Jede Wiedergabe besitzt einen Generation-Token;
alte Abschlüsse dürfen weder einen neuen Auftrag überschreiben noch Wake rearmen.

## Prüfung

Tests prüfen Schlüsseldatei, Zugriffsrechte, Updates und Ablehnung ungültiger Werte;
Cache-Invalidierung; Wiederholung ohne erneutes Reasoning und Abbruch der Stimme;
vorübergehende Transkript-Anzeige und Entfernung beim nächsten Befehl. Bestehende
Routing- und Wake-Tests bleiben erhalten. Ein echter Gemini-Aufruf verwendet den
lokalen Store ohne Keychain; ein hörbarer Sprachtest bestätigt das Ende der
Wiedergabe. Ein Renderbild prüft statischen Ring, Aufnahme-Ring und Textposition
ohne Bedienung der laufenden App. Release-Build, Signatur und Git-Diff werden geprüft.
