# Laya für Friday: gemessene Korrekturen und Fine-Tuning

Build 12 hält App-Starts, Notizen und Raumbefehle im lokalen Pfad. Die Ziele bleiben
dynamisch: installierte App-Bundles und Home-Assistant-Geräte/Räume, keine Liste
vordefinierter Safari- oder Wohnzimmer-Aktionen. Laya entscheidet weiterhin den
Intent; der Argumentparser prüft die ausführbaren Parameter des ursprünglichen
Befehls. Ein niedriger Modellscore wird nicht künstlich zu Sicherheit erhöht.

Der ursprüngliche Modellaufruf klassifizierte „Mach Safari auf“ als `home_control`
mit nur 0,421. Eine vollständige, validierte App-Aktion bekommt jetzt eine eindeutige
Beschreibung samt echter Bundle-ID. „Öffne Finder“ scheiterte zusätzlich am Katalog:
Finder hat Apples Bundle-Typ `FNDR`, den die bisherige `APPL`-Prüfung übersprang.
Ein Safari-Start mit Suche bleibt eine einzelne `search_web`-Aktion. Ein Erklärwunsch
über Safari bleibt eine Frage. Notizinhalte bestimmen nicht den Intent.

Der vollständige native Router auf diesem M1 Pro erreichte nach Warmup 17/17 richtige
Routen mit etwa 150–170 ms pro Entscheidung. Die Ausführung wird im Evaluator durch
ein aufzeichnendes Tool ersetzt, Gemini durch einen Zähler/Platzhalter. Gemessen ist
der lokale Entscheidungspfad, nicht Mikrofon → Hex → tatsächlich geöffnetes Fenster.
Die Fälle stehen in `services/local-runtime/evals/friday-routing.jsonl`.

```sh
./scripts/evaluate-local-routing.sh
```

Die Recherche zeigt zwei konkrete Ansätze:

- [Laya/Core ML](https://github.com/mizorewww/laya-coreml) beschreibt explizite
  Kriterien, Prüfung von Truncation und Options-Kollisionen sowie Grenzen der
  Konfidenzkalibrierung. Die ANE-Variante ist auf insgesamt 96 Tokens beschränkt;
  die publizierten rund 5 ms gelten für einen M3 Max mit einer kurzen Frage.
  Unsere zehn Intents und längere Eingaben nutzen das allgemeine 1024-Token-Modell.
  Das ANE-Ergebnis ist kein gemessener Wert für diesen M1 Pro.
- [Laya-Finetune](https://github.com/zamax14/Laya-Finetune) nutzt aufgabenspezifische
  synthetische Beispiele, Prüfung durch ein zweites Modell, RLCD-Training,
  anschließende Kalibrierung und einen von Hand geschriebenen Testsatz. Der Autor
  berichtet bei Tool-Routing erhebliche Verbesserungen. Das Training setzt in
  dieser Implementierung NVIDIA/CUDA voraus; auf diesem Mac wurde kein Training
  gestartet und kein trainierter Checkpoint installiert.

Ein eigener Friday-Checkpoint sollte auf vielfältigen deutschen Befehlen lernen:
kurze Umgangssprache, Höflichkeitsformen, ASR-Schreibvarianten und unbekannte Ziele;
zusätzlich Fragen, Erwähnungen und mehrdeutige/zusammengesetzte Aufträge als
Gegenbeispiele. Geräte- und App-Namen werden zwischen Trainings- und Testdaten
getrennt, damit das Modell die Operation statt konkreter Namen lernt. Der jetzige
Regressionstest bleibt außerhalb des Trainings. Vor dem Einsatz werden pro Intent
Fehlentscheidungen, unerwünschte Aktionen, Recall, Konfidenzkalibrierung und P50/P95
mit dem bestehenden Modell verglichen. Danach sind ein Core-ML-Export und dieselben
Router-Prüfungen nötig. Erst bei belegtem Nutzen ersetzt der Checkpoint das aktuelle
Modell. Für eine kompakte ANE-Variante muss außerdem ein kurzer Entscheidungsauftrag
innerhalb der 96-Token-Grenze entworfen und auf diesem Mac gemessen werden.
