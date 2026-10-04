# Friday Scaffold Implementation Plan

> For agentic workers: execute the scaffold inline; review the written design and plan before implementation.

**Goal:** Publish a buildable macOS assistant foundation for the team's later voice/model integrations.

**Architecture:** SwiftUI/AppKit shell, pure Swift contracts/router, replaceable adapters. Demo input and preview tools let the team inspect the pipeline without provider setup.

**Tech Stack:** Swift 6, Swift Package Manager, macOS 15+, AVFoundation, GitHub Actions.

## 1. Contracts and routing

- [ ] Create `apps/macos/Package.swift` with core, adapters, app and test targets.
- [ ] Create `Sources/FridayCore/Contracts.swift` for audio, transcription, wake-word,
  decisions, reasoning, text insertion, tool execution and speech output.
- [ ] Create `Sources/FridayCore/AssistantRouter.swift`: explicit dictation bypass,
  validated confidence/arguments, classifier-error fallback, cancellation propagation.
- [ ] Create `Tests/FridayCoreTests/AssistantRouterTests.swift` for routing boundaries.

## 2. Provider slots and native shell

- [ ] Create `Sources/FridayAdapters/DemoProviders.swift`, `ProviderSlots.swift`,
  and `SystemSpeechOutput.swift`. Use descriptive errors for unconfigured providers.
- [ ] Create `Sources/FridayApp/FridayApp.swift`, `AssistantViewModel.swift`,
  `AssistantView.swift`, and `MascotPanel.swift` with demo labels and resource fallback.
- [ ] Add `Sources/FridayApp/Resources/README.md` for the future PNG.
- [ ] Add `packaging/Info.plist` and `scripts/build-macos.sh` to produce `dist/Friday.app`.

## 3. Documentation, verification and GitHub

- [ ] Update `README.md`, `.gitignore`; add `docs/architecture.md`,
  `docs/integrations.md`, `docs/roadmap.md` and `CONTRIBUTING.md`.
- [ ] Add `.github/workflows/macos.yml` to run build and tests on macOS.
- [ ] Run `swift test --package-path apps/macos` (all boundary tests pass).
- [ ] Run `scripts/build-macos.sh` (build and bundle validation pass).
- [ ] Review the diff for accidental secrets and generated files; run `git diff --check`.
- [ ] Commit, push to the writable fork and open a pull request against upstream main.

Future work is deliberately tracked in the roadmap rather than implemented in this milestone.
