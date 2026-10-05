# Doppeltklatschen und Doppelschnipsen

## Ziel und Umfang

Zwei getrennt aktivierbare physische Geräuschgesten starten denselben lokalen
Befehls-Aufnahmeweg wie ein Klick auf die Overlay-Kugel. Default aus. Keine
Cloud-Anfrage, neuen Dienste, zweite Mikrofoninstanz oder persistierte Tonspur.
Die bestehende Gehäuse-Aktivierung bleibt unabhängig.

## Entscheidung

Eine reine Lautstärkeschwelle verwechselt Klopfen, Tastatur und Sprache. Ständige
SoundAnalysis-Inferenz wäre unnötig teuer. Stattdessen erkennt ein günstiger
PCM-Impulsdetektor zwei getrennte kurze Impulse mit relativem Abfall bei Nachhall; nur diesen begrenzten Ausschnitt
prüft Apples integrierter SoundAnalysis-Klassifikator. Jeder Impuls wird separat
in einem 500-ms-Fenster geprüft; der andere Impuls wird durch eine nicht
überlappende Ausschnittgrenze ausgeschlossen. Beide Ergebnisse müssen zum
selben aktivierten Typ passen; zusätzlich bestätigt ein gemeinsames Paarfenster
mit höherer Konfidenz den Geräuschtyp. Einzelclips brauchen weiterhin unabhängige
positive Evidenz. Ein breites positives Modellfenster darf nicht
einen echten Klatscher plus eine Tastaturtaste als Doppeltklatschen bestätigen.
Überlappende Modellfenster erzeugen keine zusätzlichen Tipps. Konkurrierende
Sprach-/Tastaturklassen und geringe Konfidenz führen zu keiner Aktivierung.

## Datenfluss und Lebenszyklus

AudioInput bleibt alleiniger Eigentümer des AVAudioEngine-Mikrofons. VoiceController
verteilt seinen vorhandenen 16-kHz-PCM-Stream an Wake und Geräuschaktivierung.
Geräuschgesten funktionieren auch mit ausgeschaltetem Wake-Wort. Ohne Wake,
Geräuschoption oder Aufnahme wird das Mikrofon gestoppt. Suspend, Abbruch,
Vorlesen und Shutdown verwerfen ausstehende Gesten und verspätete Ergebnisse.
Der bereits vorhandene Aufnahme-Ringpuffer bewahrt Sprache nach dem zweiten
Geräusch, während die Klassifizierung läuft; kein Wake-Präfix wird entfernt.

## Oberfläche und Prüfung

Unter Sprache eine eigene Sektion mit zwei Toggles, lokalem Mikrofonhinweis,
30-Sekunden-Test, erkanntem Typ/Zähler und optionaler Empfindlichkeit/Konfidenz.
Der Test zählt bestätigte Gesten, startet aber keine Befehlsaufnahme. Optionen
bleiben lokal gespeichert. Kein automatischer Neustart der laufenden App.

Gezielte Tests für zwei Impulse, Einzelgeräusch, Dauerlärm, Echo, drei Impulse,
Mischgesten, Klassifikations-Konfidenz, doppelte Modellfenster, Datenlücken sowie
VoiceController-Integration ohne Wake und während Suspend/Shutdown. Laufzeitprobe
des echten Klassifikators; soweit verfügbar externe beschriftete Testklänge nur
temporär und nicht ausgeliefert. Physische Zuverlässigkeit erfordert den Test
mit den echten Fingern/Händen des Besitzers; keine pauschale Genauigkeitsbehauptung.
