# Roadmap

Die folgenden Schritte bauen auf dem Scaffold auf. Echte Provider, Wake-Word
und Computeraktionen sind noch nicht implementiert.

Die konkrete Auswahl der lokalen Modelle und Provider, Dateipfade und die
Reihenfolge stehen im [Integrationsplan](superpowers/plans/2026-10-04-local-voice-stack.md).

## 1. Oberfläche und erstes Diktat

- [x] Native App, Menüleiste, Panel oben rechts und Demo-Eingabe.
- [ ] Team-PNG unter `Sources/FridayApp/Resources/mascot.png` hinzufügen.
- [ ] Mikrofonaufnahme mit sichtbarem Aufnahmezustand und Abbruch anbinden.
- [ ] Hex-Bridge und lokales Deutsch-Modell integrieren.
- [ ] Hotkey und `TextOutput` für das aktive Textfeld ergänzen.

Abnahme: Taste drücken, sprechen, stoppen; deutscher Text erscheint am Cursor.
Abbruch hinterlässt keinen eingefügten Text und keine offene Aufnahme.

## 2. „Hey Friday“

- [ ] Lokalen Detector wählen und `WakeWordDetector` implementieren.
- [ ] Opt-in, deaktivierbare Erkennung und Ruhemodus ergänzen.
- [ ] Wake-Erkennung während Aufnahme/Sprachausgabe pausieren.

Abnahme: Wake-Phrase startet eine Anfrage; Friday aktiviert sich nicht durch die eigene Stimme.

## 3. Laya und schnelle Computeraktionen

- [x] Decision-Vertrag, Konfidenzprüfung und Tool-Vorschau.
- [ ] Echte lokale Laya-Inferenz inklusive Warm-up anbinden.
- [ ] Deutsche Beispielsätze sammeln; Intents und Konfidenz evaluieren.
- [ ] App-Namen auf erlaubte Bundle-IDs abbilden; Notizargumente extrahieren.
- [ ] App-Start und Notizspeicherung implementieren.
- [ ] Terminal-Executor mit sichtbarer Aktion, erlaubten Prozessen und Bestätigung
  für destruktive Aktionen ergänzen; UI-Automatisierung separat anbinden.

Abnahme: „Öffne Safari“ öffnet Safari; eine unklare Anfrage führt zum Fallback.
„Notiz: …“ speichert genau den gewünschten Inhalt.

## 4. LLM-Fallback und Recherche

- [x] Reasoning-Vertrag und Fallback bei unsicheren/fehlgeschlagenen Entscheidungen.
- [ ] Ollama oder anderen Provider anbinden; Deadline und Abbruch ergänzen.
- [ ] Planung mit tatsächlichem Modell prüfen.
- [ ] Such-/Browserwerkzeug für Recherche und verlinkte Quellen anbinden.

Abnahme: „Plane XY“ liefert einen Plan; „Recherchiere XY“ liefert eine Antwort mit Quellen.

## 5. Sprachschleife und Verteilung

- [x] Optionales Vorlesen mit macOS-Systemstimme.
- [ ] TTS-Abschlussereignis und Unterbrechen beim nächsten Befehl ergänzen.
- [ ] Bei Bedarf ElevenLabs oder lokale TTS-Engine anschließen.
- [ ] Aufnahme-, Inferenz-, Tool- und TTS-Latenzen messen.
- [ ] Berechtigungs-Onboarding, stabile Codesign-Identität und notarisiertes Release.

Abnahme: komplette Sprachschleife funktioniert ohne parallele Aufnahmen;
Fehler und Abbrüche stellen den Ruhezustand wieder her.
