# Friday V1: testbare lokale Overlay-App

Die bereits vereinbarte Kette wird jetzt umgesetzt: Hey Friday → Aufnahme → Hex
→ Laya → echte Computeraktion oder lokales LLM → optionale TTS nur für LLM-Antworten.
Die native App bleibt auf macOS 15+/Apple Silicon und zeigt ein Maskottchen mit
Status-Orb oben rechts. Fenster, Panel und Menüleiste teilen einen Coordinator.

## Lokale Provider

Laya läuft als persistenter Python-3.12/Core-ML-Prozess mit dem gepinnten
Multilingual-Snapshot. JSON-Zeilen auf stdin/stdout liefern IDs, Entscheidung,
Konfidenz und Trunkierungsangaben. Kein Regelmodell als stiller Ersatz für Laya.
Ein separater Moonshine-Tiny-Streaming-Prozess bekommt extern aufgenommene
16-kHz-PCM-Blöcke und meldet „Hey Friday“. Beide laufen nach Setup offline.

Hex wird aus dem offiziellen ARM64-App-Release bereitgestellt und direkt als
app-eigener `service --embedded`-Prozess gestartet. Friday hält dessen stdin-Lease,
prüft API 2 und verwendet die authentifizierte Loopback-API mit deutscher Whisper-
Transkription. Das Modell wird beim expliziten Setup vorbereitet. App-Logs dürfen
das Bearer-Token nicht ausgeben. Die App lädt während normaler Nutzung keine Modelle.

Fridays zentrale AVAudioEngine liefert Mono-PCM an Wake-Erkennung und Aufnahme.
Nach Aktivierung bleibt ein kurzer Audio-Vorlauf erhalten; die Wake-Phrase wird
nur am Transkriptanfang entfernt. Silenz beendet den Befehl, alternativ Stop-Taste.
Während Transkription, Entscheidung, Aktion, LLM und TTS pausiert Wake-Erkennung.
Nach Abschluss oder Fehler beginnt wieder der sichtbare Hörzustand.

## Testbare Aktionen und Antwort

V1 öffnet installierte Programme über NSWorkspace mit bekannten Bundle-IDs und
speichert Notizen als Markdown in Fridays Application Support. Ein eigener
Argumentparser validiert vollständige deutsche Befehle; mehrteilige Anweisungen
oder fehlende Argumente werden nicht teilweise ausgeführt. Frei generierte Shell-
Befehle werden nicht angeboten. Der Terminalvertrag bleibt für die nächste Version.
Komplexe Fragen gehen an Ollama (einstellbares lokales Modell, vorhandenes Modell
als erste Testoption). Web-Recherche meldet ihre fehlenden Suchwerkzeuge sichtbar.
System-TTS ist die sofort verfügbare lokale Stimme; offene TTS bleibt eigener Schritt.

## Bedienung, Setup und Abbruch

Das Overlay öffnet per Klick das kompakte Fenster. Dort: lokale Providerbereitschaft,
„Hey Friday aktivieren“, Aufnahme/Stop, manuelle Texteingabe, TTS und Abbrechen.
Mikrofonzugriff wird erst beim Aktivieren angefordert. Eine dauerhafte Aufnahme
wird klar angezeigt und kann ausgeschaltet werden. Fehler sind sichtbar und die
App bleibt bedienbar. Beenden schließt alle eigenen Helper und die Mikrofonquelle.

Ein reproduzierbares Setup-Skript installiert die isolierte Runtime und Modelle
unter `~/Library/Application Support/Friday`, außerhalb Git. Der lokale App-Build
bündelt Helper-Quellen und Runtime-Konfiguration. Andere Teammitglieder können
denselben Setup-/Build-Weg benutzen; die erste Version ist eine Entwicklungs-App.

## Abnahme

Echte Laya-Inferenz an deutschen Befehlen, echte Hex-Transkription an WAV-Dateien,
Wake-Phrase an Audiodateien, Parser/Router/Abbruchtests und macOS-App-Build prüfen.
„Öffne Safari“ öffnet Safari; „Mach eine Notiz: Milch kaufen“ speichert den Text.
Direkte Aktionen bleiben stumm. Physische Mikrofonberechtigung und Akustik werden
auf dem Ziel-Mac durch den Nutzer getestet; synthetische Audiofixtures prüfen
zuvor denselben Wake-/STT-Pfad ohne Zugriff auf das Mikrofon.
