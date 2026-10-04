# Friday: Thinking Orbs und Antwortverhalten

## Gewünschter Ablauf

„Hey Friday“ → Aufnahme → Hex → Laya → entweder direkte Computeraktion
oder bei komplexen Fragen das LLM → bei Bedarf TTS. Direkte Aktionen und
Diktat bleiben stumm. Die Implementierungsphasen im Sprachstack-Plan sind
Abhängigkeiten für die Entwicklung; der Laufzeitablauf ist die obige Reihenfolge.

## Anzeige

Die kostenlose MIT-SwiftUI-Version von Libraries.dev wird mit fest gepinnter
Revision unter `apps/macos/Vendor/ThinkingOrbsKit` eingebunden. Kein WebView
und keine React-Runtime. Originalquellen und MIT-Notice bleiben erhalten.

Ein 64-Punkt-Orb neben dem Status zeigt Bereit, Entscheiden, Aktion, LLM und
Sprachausgabe. Im schwebenden Panel erscheint ein 20-Punkt-Orb unter dem
vorhandenen PNG-Maskottchen. Beide beobachten dasselbe ViewModel. Die neun
Originalanimationen können in einer ausdrücklich bezeichneten Orb-Vorschau
angesehen werden. Reduce Motion und automatische Hell-/Dunkel-Darstellung
kommen aus dem nativen Paket. Aufnahme und Transkription erhalten später
eigene Zustände; die Demo behauptet noch keine Mikrofonverarbeitung.

## Verhalten und Prüfung

Der Router meldet echte Verarbeitungsphasen über einen asynchronen Callback.
Die UI wartet bei TTS auf Wiedergabeende oder Abbruch. Ein Abbruch stoppt
Sprachausgabe, setzt den Orb zurück und löst keinen neuen Tool-/LLM-Aufruf aus.
Die TTS-Option gilt ausschließlich für die finale Reasoning-Antwort.

Automatisierte Prüfungen decken Routingphasen, die stille Aktionsroute,
optionale LLM-Sprachausgabe, Diktat und Abbruch ab. `swift test` und der
signierte App-Build müssen erfolgreich sein; eine gerenderte Vorschau prüft
die echten SwiftUI-Orbs. Hex, Laya und Wake-Word bleiben bis zu ihren eigenen
Implementierungsschritten Provider-Schnittstellen.
