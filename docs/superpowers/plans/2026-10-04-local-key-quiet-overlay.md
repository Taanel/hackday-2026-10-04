# Local key and quiet overlay implementation plan

> **For agentic workers:** Use executing-plans to implement the approved user scope inline, task by task. Reviewers inspect documents only; no parallel code changes.

**Goal:** Remove Gemini Keychain prompts and make Friday's overlay and spoken answers easier to understand.

**Architecture:** A local credential store replaces the Security read; the existing Gemini cache is invalidated on edits. The shared ViewModel owns transient transcript and replay state, while the existing AppKit panel and SwiftUI orb render these states.

**Tech Stack:** Swift 6, SwiftUI/AppKit, Foundation file APIs, AVSpeechSynthesizer, ThinkingOrbsKit.

## Task 1: Local credentials

Files: create `apps/macos/Sources/FridayAdapters/Reasoning/LocalGeminiKeyStore.swift`;
modify `Reasoning/GeminiReasoningEngine.swift`, `FridayApp/AssistantViewModel.swift`,
`FridayApp/AssistantView.swift`, `scripts/configure-gemini.py`, `.gitignore`;
tests in `apps/macos/Tests/FridayAdaptersTests/LocalGeminiKeyStoreTests.swift`.

- [ ] Add tests: temporary-directory store; missing-key error; 0700 directory and
  0600 file; overwriting key; invalid/empty input preserves previous key.
- [ ] Run `swift test --package-path apps/macos --configuration release --filter LocalGemini`;
  expect failure before store exists.
- [ ] Implement a Sendable store with injectable directory, `load`, `save`,
  `isConfigured`. Trim input, reject whitespace inside the key and excessive length.
  Save atomically inside the private directory, never include key content in errors.
- [ ] Replace the default Gemini loader with this store. Add async cache invalidation
  with a generation token so an old in-flight load cannot restore an invalidated key.
- [ ] Add a blank SecureField and explicit save button, clear the field after success,
  disable edits while busy, invalidate the live engine cache after saving.
- [ ] Change the CLI configurator to the same local format. Migrate existing local
  Keychain entry once with captured output, then verify the app source contains no
  `SecItemCopyMatching` call and the real key is absent from staged files.

## Task 2: Transcript and calm animation

Files: `FridayApp/AssistantOrb.swift`, `FridayApp/AssistantViewModel.swift`,
`FridayApp/MascotPanel.swift`, `FridayApp/AssistantView.swift`;
tests in `FridayAppTests/AssistantViewModelTests.swift`.

- [ ] Add transcript state and tests for setting recognized text, clearing on next
  recording, and timed clearing after completion.
- [ ] Pause the orb in idle/listening; map recording to the slow searching sphere.
  Remove animateIdle overrides and Idle label text in the floating view.
- [ ] Expand panel to 280×164 while retaining the orb's right edge. Add an upper-right
  aligned text bubble below the orb with max three lines and tail truncation.
- [ ] On recognized audio update the transient transcript before routing. Use a
  cancellable eight-second task with generation guard to prevent stale clearing.
- [ ] Render state variants to PNG with ImageRenderer for visual inspection. Do not
  automate the existing Friday GUI.

## Task 3: Audible answers and replay

Files: `FridayApp/AssistantViewModel.swift`, `FridayApp/AssistantView.swift`,
`FridayAppTests/AssistantViewModelTests.swift`.

- [ ] Add meaningful tests: replay reads the saved reasoning answer without calling
  reasoning a second time; computer results have no replay; cancellation finishes playback.
- [ ] Preserve default speakResponses=true. Store replay text only for reasoning
  answers. Add replay action using the existing voice suspend/rearm and speech.stop flow.
- [ ] Add „Noch einmal vorlesen“ only when a reasoning answer is available.
- [ ] Run full Swift/Python suites; real Gemini request from LocalGeminiKeyStore;
  actual SystemSpeechOutput playback completion with bounded timeout.

## Task 4: Build and publish

- [ ] Update README/integrations to local key entry, transcript timing, static Idle,
  and voice replay. Bump CFBundleVersion.
- [ ] Run `git diff --check`; build with `FRIDAY_APP_PATH` in ~/Applications staging;
  verify stable Apple signature, install atomically while keeping previous build.
- [ ] Inspect staged paths and scan in memory for the actual local key without
  printing it. Commit and push main, then report app path, validation and live-ASR limit.
