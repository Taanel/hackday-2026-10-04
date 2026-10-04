# Natural voice, research and menu bar implementation plan

> For agentic workers: execute inline using executing-plans, with meaningful verification for each change.

**Goal:** Natural German spoken answers, current research with sources, and an unobtrusive menu bar app.

**Architecture:** Keep Laya/local tools; Gemini can request bounded research from a separate HTTP adapter. Sources travel separately through Core and are never spoken. Cloud speech uses the existing private Gemini key and cancellable AVAudioPlayer playback.

**Tech Stack:** Swift 6, SwiftUI/AppKit, URLSession, AVFoundation, Gemini Interactions, DuckDuckGo Lite, Open-Meteo.

- [ ] Add `AnswerSource`, `ReasoningPlan.researchedAnswer` and response sources in `FridayCore/Contracts.swift`; propagate in `AssistantRouter.swift`. Verify research never executes a computer action.
- [ ] Add `FridayAdapters/Reasoning/WebResearchService.swift`: bounded HTTPS queries, DuckDuckGo result/snippet parsing, location geocoding and 16-day daily forecast. Reject empty/captcha/error results; use actual adapter source links only. Test parser fixtures, bad URLs and weather payloads in `FridayAdaptersTests/WebResearchTests.swift`.
- [ ] Extend `GeminiReasoningEngine.swift` with `search_web` and `weather_forecast`. A single validated research request retrieves evidence; a second model call can only answer, with no functions. Include today's date, ask for missing weather location, treat snippets as untrusted. Test handoff, mixed actions/research rejection and final sources in `GeminiTests.swift`.
- [ ] Add `GeminiSpeechOutput.swift` using Interactions model `gemini-3.8-flash-lite-tts`, German style, WAV response and AVAudioPlayer completion. Stop cancels download/playback; UUID guards prevent old playback. Test credential-free request fixtures and malformed audio responses. Verify actual generation and playback once.
- [ ] Update `AssistantViewModel.swift` and `AssistantView.swift`: default cloud voice for Gemini, three voice choices, source links, preserve answer on voice failure, one-second successful-action transcript expiry. Add timer regression test in `AssistantViewModelTests.swift`.
- [ ] Replace initial WindowGroup with MenuBarExtra and static spherical label in `FridayApp.swift`; lazy settings NSWindow in `MascotPanel.swift`; add LSUIElement and bundle version 7 in packaging/Info.plist. Remove old openWindow callback. Build and inspect Info.plist; preserve all overlay animations.
- [ ] Update README/integrations and record live-check limits. Run `swift test --package-path apps/macos --configuration release`; expect all pass. Python is unchanged, so no redundant runtime suite.
- [ ] Build signed staging app under ~/Applications, verify stable signature, scan staged files and bundle for local secret, atomically replace installed app with previous build retained. Commit/push. Tell user to quit/reopen; do not operate the running GUI.
