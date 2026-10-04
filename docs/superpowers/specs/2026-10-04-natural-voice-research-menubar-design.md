# Natürlichere Stimme, aktuelle Antworten und Menüleisten-App

Der Nutzer hat eine natürlichere deutsche Stimme, aktuelle Wetter-/Suchantworten,
eine Sekunde Restanzeige nach erfolgreichen Computeraktionen und einen Kugel-Button
in der Menüleiste ohne Dock-Icon angefordert. Die vorhandenen Orb-Zustände bleiben.

Gemini 3.8 Flash-Lite TTS ist mit dem vorhandenen lokalen Schlüssel erreichbar.
Friday verwendet diese neuronale Stimme für Gemini-Antworten. Kore, Aoede und
Charon sind auswählbar. Die Ausgabe bleibt abbrechbar, Wake pausiert bis zum echten
Wiedergabeende. Bei einem TTS-Fehler bleibt die Textantwort erhalten; keine stille
Rückkehr zur vom Nutzer abgelehnten Systemstimme. Ollama behält lokale Sprachausgabe.
Eleven v4 Turbo bleibt eine kostenpflichtige Alternative, falls diese Stimme nicht
gefällt; keine Buchung oder zusätzlichen Zugangsdaten sind erforderlich.

Googles integrierte Suche liefert mit dem vorhandenen Schlüssel HTTP 429, normale
Textantworten und TTS funktionieren. Statt einen fehlgeschlagenen Suchpfad zu
aktivieren, erhält Gemini zwei typisierte Recherchefunktionen: search_web nutzt
für diesen privaten Prototyp DuckDuckGo Lite (maximal fünf Titel, Links und Snippets),
weather_forecast verwendet die kostenlose Open-Meteo-Geokodierung und 16-Tage-Daten.
Das Modell fragt bei fehlendem Wetter-Ort nach. Ein begrenzter zweiter Textaufruf
fasst die Daten zusammen, ohne Computerfunktionen. Suchinhalte sind untrusted
Daten, keine Anweisungen. Antworten tragen getrennte, klickbare Quellen, die nicht
vorgelesen werden. Quellen stammen nur aus Adapter-Ergebnissen mit HTTP(S)-Links,
nicht aus Modelltext. Fehlende Suchdaten, Captchas, Zeitüberschreitungen und Wetter
außerhalb des verfügbaren Zeitraums werden klar gemeldet, ohne aktuelle Fakten zu
erfinden. TTS-Abbruch umfasst Anfrage und Wiedergabe; alte Generationen dürfen
weder Audio starten noch Wake reaktivieren. Fehler geben Wake wieder frei.
Recherche und Computeraktionen werden nicht im selben Plan
ausgeführt; keine freien Terminalbefehle. Suche ist kein vollständiger Seitenabruf.

Friday startet mit LSUIElement nur Menüleiste und transparentem Overlay. Ein
statischer gepunkteter Kugel-Button öffnet das Menü mit „Friday öffnen“.
Die Overlay-Kugel öffnet das Einstellungsfenster direkt.
Dieses NSWindow wird erst beim ersten Klick erzeugt und danach wiederverwendet;
es erscheint nicht beim Start. Nach erfolgreicher Computeraktion läuft ein
generation-geschützter Ein-Sekunden-Timer für das Transkript.

Zusätzliche konkret angeforderte Zuordnung: Im vorhandenen Orb-Bereich lässt sich
einer der neun Zustände wählen und per Klick eine der neun Vorschauen zuordnen.
Die Auswahl gilt sofort im Overlay und Fenster, bleibt in lokalen UserDefaults
erhalten und lässt sich auf die bisherigen Defaults zurücksetzen. Ungültige
gespeicherte Werte fallen auf den Default zurück. Idle/Wake-Bereitschaft bleiben
auch mit anderer Orb-Auswahl statisch; aktive Zustände animieren weiterhin.

Weitere Nutzeranforderung: lokale Projektsuche. Ein neuer Laya-Intent und ein
typisierter Gemini-Fallback `find_project(query)` durchsuchen Fenstertitel per AX
und höchstens 80 offene Terminal.app-Tabs (Titel und letzte 4.000 Zeichen sichtbaren
Inhalts, nicht komplette History). Kein Screenshot, keine Übertragung dieser
Inhalte an Gemini/Laya, keine Shellbefehle im Terminal. Bei einem Treffer wird das
Fenster bzw. der Tab fokussiert, bei mehreren erscheint das Friday-Fenster mit
Auswahlknöpfen. Titel und opaque IDs verlassen den lokalen Locator nicht Richtung
Cloud; ein Klick nutzt dessen gespeicherte Ziele. Terminal-Tab-Fokus prüft Fenster-ID
und TTY statt eines möglicherweise verschobenen Tab-Indexes. Bedienungshilfen und
Terminal-Automation sind erforderlich. Ein Desktop wird nicht per privater API
nummeriert; macOS entscheidet beim Fokussieren über Space-Wechsel. Kein allgemeines
Lesen von Browser-/Editor-Inhalten. Fehlende Rechte und geschlossene Ziele werden
verständlich gemeldet. Projektsuche wird nicht mit anderen Aktionen kombiniert.
Auch beim Gemini-Fallback endet die Kette nach dem lokalen Tool; Suchergebnisse,
Fenstertitel, Tab-Inhalte und Fehler werden nicht an Gemini/TTS zurückgeschickt.
Ein Netzwerk-Spy prüft genau einen Plan-Aufruf ohne private Ergebnisse. Vor dem
Fokus wird das Ziel erneut geprüft. Abbruch und Generation-Guards verhindern alte
UI-Auswahlen. Mock-Tests prüfen geschlossene Fenster, falsche TTY und geänderte
Projektinhalte; tatsächlicher Fenster-/Space-Wechsel benötigt einen Nutzertest.
Der AX-Scan hat insgesamt drei Sekunden Budget mit 120-ms-Timeout pro Zugriff;
der Terminal-Helper hat drei Sekunden Startup- und zwölf Sekunden Request-Deadline.
Abbruch wird vor dem automatischen Fokus eines einzelnen Treffers erneut geprüft,
ebenso im MainActor-Fensterfokus bzw. vor Start und Versand des Terminal-Requests.
Eine abgebrochene Suche darf keinen verspäteten automatischen Fokus auslösen.

Prüfung: Recherche-Routing/Quellen, ungültige Pläne und XML-Antworten, echte Wetter-
und Suchabfragen, echte Gemini-TTS-Generierung/Wiedergabe, Abbruch, Timer sowie
Release-Build und stabile Signatur. Zugangsdaten bleiben außerhalb von Git und App.
