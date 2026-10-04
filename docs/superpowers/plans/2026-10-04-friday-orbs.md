# Friday Orbs Implementation Plan

> Umsetzung inline mit den bereits autorisierten UI- und Routingänderungen.

**Ziel:** Native Thinking Orbs anzeigen und direkte Computeraktionen stumm halten.

**Architektur:** Gepinntes lokales Swift-Paket, Router-Phasen, ein gemeinsam
beobachtetes App-ViewModel und System-TTS mit Wiedergabeabschluss.

**Stack:** SwiftUI, AppKit, AVFoundation, ThinkingOrbsKit (MIT).

Entwurf: [Friday Orbs](../specs/2026-10-04-friday-orbs-design.md).

- [x] `apps/macos/Vendor/ThinkingOrbsKit`: zehn unveränderte Swift-Quelldateien,
  minimales Paketmanifest, MIT-Lizenz und README mit Upstream-Revision vendoren.
  `Package.swift` und mitgelieferte `Resources/ThirdPartyNotices.txt` ergänzen.
- [x] `FridayCore/Contracts.swift`, `AssistantRouter.swift`: Entscheiden, Aktion
  und Reasoning vor dem jeweiligen Provider über `onPhase` melden. Abbruch nach
  dem Callback prüfen. Routingtests um Reihenfolge und Abbruch ergänzen.
- [x] `FridayAdapters/SystemSpeechOutput.swift`: auf AVSpeechSynthesizer-Ende
  warten; Stop/Task-Abbruch beendet die ausstehende Fortsetzung genau einmal.
- [x] `FridayApp/AssistantViewModel.swift`: Router und Sprache injizierbar machen;
  Phasen/Fehler/Bereit veröffentlichen; nur `.reasoning` mit aktiver TTS-Option
  sprechen. Tests in `Tests/FridayAppTests/AssistantViewModelTests.swift`.
- [x] `FridayApp/AssistantOrb.swift`, `AssistantView.swift`, `MascotPanel.swift`,
  `FridayApp.swift`: echte Orbs in Fenster und Panel, gemeinsames Modell,
  ausdrücklich getrennte Vorschau aller neun Animationen.
- [x] README, Architektur, Sprachstack-Entwurf/-Plan, Roadmap und Integrationen
  auf den gewünschten Ablauf und den TTS-Abschlussvertrag aktualisieren.
- [x] `swift test --package-path apps/macos`, `./scripts/build-macos.sh`,
  gerenderte SwiftUI-Vorschau, `git diff --check`; dann committen und pushen.

Verifiziert: 17 Swift-Tests erfolgreich; der neue Test für stille Computeraktionen
schlug vor der TTS-Korrektur fehl. Release-App gebaut und signiert, alle neun
Original-Orbs sowie die App-Status-Orbs in Hell/Dunkel mit ImageRenderer geprüft.
Die interaktive UI-Prüfung war wegen fehlender Computer-Use-Freigabe nicht verfügbar.
