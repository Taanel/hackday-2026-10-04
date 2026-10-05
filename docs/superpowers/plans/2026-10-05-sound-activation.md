# Sound Activation Implementation Plan

> Execute inline with targeted regression tests; existing user authorization covers implementation and installation. No automatic app restart or unrelated suites.

**Goal:** Double claps and double finger snaps activate Friday locally.

**Architecture:** Cheap PCM transient-pair gate plus bounded on-demand Apple SoundAnalysis classification, using the existing microphone stream and capture ring buffer.

**Tech Stack:** Swift, AVFoundation, SoundAnalysis, SwiftUI, Swift Testing.

- [x] Add `FridayAdapters/Activation/SoundGestureDetector.swift` and `SoundGestureActivation.swift`. First add focused `SoundGestureTests.swift` proving two real PCM impulses are required; a classifier window cannot manufacture a second event. Keep idle inference off and buffers bounded.
- [x] Add injectable sound activation protocol to `FridayApp/VoiceController.swift`; share audio and maintain independent wake/sound options. Target `VoiceControllerTests.swift` for sound-only activation, exact pre-roll start, suppression, disable and shutdown.
- [x] Add persisted sound options and test lifecycle in `AssistantViewModel.swift`, concise controls in `VoiceSettingsView.swift`. Stop tests cleanly on errors and shutdown; report sound failures separately from wake failures.
- [x] Verify only affected tests and a native classifier probe. Run `swift test --package-path apps/macos --filter 'soundGesture|soundOnly|soundActivation|manualCapture'` and a release build. Review source, scan credential bytes, sign and install Build 16 in user Applications with previous build preserved; commit and push.
