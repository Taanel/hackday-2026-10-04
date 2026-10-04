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
statischer gepunkteter Kugel-Button öffnet das Einstellungsfenster auf Wunsch.
Dieses NSWindow wird erst beim ersten Klick erzeugt und danach wiederverwendet;
es erscheint nicht beim Start. Nach erfolgreicher Computeraktion läuft ein
generation-geschützter Ein-Sekunden-Timer für das Transkript.

Prüfung: Recherche-Routing/Quellen, ungültige Pläne und XML-Antworten, echte Wetter-
und Suchabfragen, echte Gemini-TTS-Generierung/Wiedergabe, Abbruch, Timer sowie
Release-Build und stabile Signatur. Zugangsdaten bleiben außerhalb von Git und App.
