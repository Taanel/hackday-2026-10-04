# Friday auf iPhone und Ray-Ban Meta

Planungsstand 2026-10-05. Der Nutzer verwendet ein iPhone und interessiert sich
für Ray-Ban Meta. Die macOS-App besitzt derzeit keinen mobilen API-Endpunkt und
keine Brillenanbindung. Die folgenden Schritte sind noch nicht implementiert.

## Gemeinsamer Friday-Dienst

Zuerst einen authentifizierten Dienst auf dem Mac ergänzen, der dieselbe
Laya-Entscheidung, validierten Tools und Gemini-Konversation wie die App verwendet.
Eine Anfrage erhält eine ID; Antworttext, Status und optional Audiodaten gehen
an den ursprünglichen Client zurück. Keine zweite ungesicherte Tool-Ausführung.
Home-Assistant-Zugangsdaten bleiben beim Dienst. Computeraktionen benötigen den
laufenden Mac; für reine Haussteuerung kann später ein separater Always-on-Host
übernehmen. Der derzeitige Laya-Core-ML-Worker setzt Apple Silicon voraus.

Außerhalb des WLANs zuerst einen privaten VPN-Zugang vorsehen. Der Mac muss
erreichbar und wach sein. Ein geschlossener oder schlafender Laptop macht diesen
Aufbau noch nicht zu einem ständig verfügbaren Hausassistenten.

## iPhone zuerst

Für einen ersten Prototyp: Kurzbefehl mit Spracheingabe, authentifizierter
Anfrage an Friday und Vorlesen der Textantwort. Danach eine kleine native App
für Audio-Streaming, Abbruch und Rückfragen. Start über Aktionstaste bei
unterstütztem iPhone, Sperrbildschirm oder Kurzbefehl/Siri.

Home Assistant dokumentiert diese Startwege bereits für seine Companion-App:
[Assist auf Apple-Geräten](https://www.home-assistant.io/voice_control/apple).
Das verbindet Friday noch nicht automatisch mit einer Assist-Pipeline; dafür
ist die gemeinsame Dienst-/Conversation-Integration nötig.

Ein vollständiger Siri-Ersatz mit eigener permanenter Wake-Phrase ist hier nicht
zugesichert. Apples aktuelle Freigabe zum Ersetzen des Assistenten an der
Seitentaste ist auf Japan begrenzt:
[Side Button Access](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.side-button-access.allow).
Die Aktionstaste und Kurzbefehl-Startwege sind der passende erste iPhone-Einstieg.

## Danach Ray-Ban Meta

Das [Meta Wearables Device Access Toolkit](https://developers.meta.com/wearables/device-access-toolkit/)
verbindet eine iOS-/Android-App mit unterstützten Brillen und bietet Mikrofon,
Audio, ASR und „Hey Meta“-Aufruf. Meta nennt Ray-Ban Meta Gen 1 und Gen 2 als
unterstützt; die Funktionen hängen vom Modell und verfügbaren Firmware-/SDK-Stand ab:
[offizielle FAQ](https://developers.meta.com/wearables/faq/).

Die geplante Kette: Brillenmikrofon → iPhone-App → Friday-Dienst →
Laya/HA oder Gemini → Antwortaudio → Brille. Erst die genaue Brillengeneration
und SDK-Funktionen an einem echten Gerät testen. Ein frei ersetzbares „Hey Friday“
oder ein vollständig auf der Brille laufendes Laya sind damit nicht zugesichert.

Abnahme: derselbe Hausbefehl funktioniert vom Mac und iPhone, eine Rückfrage
behält nur den jeweiligen Gesprächskontext, Verbindungsfehler erzeugen keine
doppelten Aktionen, und Mikrofonzugriff endet bei Abbruch bzw. Sitzungsende.
