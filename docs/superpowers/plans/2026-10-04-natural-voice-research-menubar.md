# Natural voice, research and menu bar implementation plan

> For agentic workers: execute inline using executing-plans, with meaningful verification for each change.

**Goal:** Natural German spoken answers, current research with sources, and an unobtrusive menu bar app.

**Architecture:** Keep Laya/local tools; Gemini can request bounded research from a separate HTTP adapter. Sources travel separately through Core and are never spoken. Cloud speech uses the existing private Gemini key and cancellable AVAudioPlayer playback.

**Tech Stack:** Swift 6, SwiftUI/AppKit, URLSession, AVFoundation, Gemini Interactions, DuckDuckGo Lite, Open-Meteo.

- [x] Add `AnswerSource`, `ReasoningPlan.researchedAnswer` and response sources in `FridayCore/Contracts.swift`; propagate in `AssistantRouter.swift`. Verify research never executes a computer action.
- [x] Add `FridayAdapters/Reasoning/WebResearchService.swift`: bounded HTTPS queries, DuckDuckGo result/snippet parsing, location geocoding and 16-day daily forecast. Reject empty/captcha/error results; use actual adapter source links only. Test parser fixtures, bad URLs and weather payloads in `FridayAdaptersTests/WebResearchTests.swift`.
- [x] Extend `GeminiReasoningEngine.swift` with `search_web` and `weather_forecast`. A single validated research request retrieves evidence; a second model call can only answer, with no functions. Include today's date, ask for missing weather location, treat snippets as untrusted. Test handoff, mixed actions/research rejection and final sources in `GeminiTests.swift`.
- [x] Add `GeminiSpeechOutput.swift` using Interactions model `gemini-3.8-flash-lite-tts`, German style, WAV response and AVAudioPlayer completion. Stop cancels download/playback; UUID guards prevent old playback. Test credential-free request fixtures and malformed audio responses. Verify actual generation and playback once.
- [x] Update `AssistantViewModel.swift` and `AssistantView.swift`: default cloud voice for Gemini, three voice choices, source links, preserve answer on voice failure, one-second successful-action transcript expiry. Add timer regression test in `AssistantViewModelTests.swift`.
- [x] Replace initial WindowGroup with MenuBarExtra and static spherical label in `FridayApp.swift`; lazy settings NSWindow in `MascotPanel.swift`; add LSUIElement and bundle version 7 in packaging/Info.plist. Remove old openWindow callback. Build and inspect Info.plist; preserve all overlay animations.
- [x] Update README/integrations and record live-check limits. Run `swift test --package-path apps/macos --configuration release`; expect all pass. The added Laya intent changes Python, so run the runtime suite once.
- [x] Additional user steering: add `FridayApp/OrbPreferences.swift`, state picker and clickable previews in `AssistantOrb.swift`. Persist individual mappings, observe updates in every AssistantOrb, retain static idle, provide reset. Verify isolated UserDefaults persistence/default handling in `OrbPreferencesTests.swift`; render the actual controls without operating the running app.
- [x] Additional user steering: `MacProjectLocator.swift` searches AX titles plus bounded Terminal.app visible tab text locally. Add typed `findProject` in Core/parser/executor/Gemini and seventh Laya intent. Multiple matches use local selection buttons and opaque IDs; no image upload or shell command execution. Test parsing, local scoring, fixed JXA with mock Terminal data, real seven-intent Laya classification, and updated Python suite. Actual window/tab focus requires a user test with macOS accessibility/automation grants.
- [x] Build signed staging app under ~/Applications, verify stable signature, scan staged files and bundle for local secret, atomically replace installed app with previous build retained. Commit/push. Tell user to quit/reopen; do not operate the running GUI.


Verification, 2026-10-04:
- Swift release: 77 tests passed; Python runtime: 85 passed. No repeat of unchanged suites.
- Real seven-intent Laya: Safari search, Shapr3D, desktop, note and both project-query examples route locally; warm decision time 130–140 ms. Tool execution and speech recognition add their own latency.
- Real Gemini response, Open-Meteo weather and German neural voice generation/playback succeeded with the private local credential. Search uses actual DuckDuckGo Lite snippets. API latency varies.
- Terminal JXA is exercised against literal mock objects, with no actual app operation. Tests cover stale window/TTY/query and bounded text; network spy proves no local results are sent back to Gemini. Real Accessibility/Automation focus and Space switching require the user's live test.
- Orb controls rendered offscreen; native AppKit picker is not represented by ImageRenderer. Assignment persistence/reset tests pass.
- Signed build 7 installed under ~/Applications/Friday.app; stable designated requirement verified; previous build retained. No restart or control of running GUI. Credential byte-scan cleared repository and bundle.
