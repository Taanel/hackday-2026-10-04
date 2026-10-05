# Faster commands and Home Assistant implementation plan

> Execute inline, with targeted tests and checkpoints. User authorized implementation; no additional design-approval stop.

**Goal:** Faster voice endpoint and repeated local commands, additional Mac actions, local HA device control.
**Architecture:** Typed Core tools, local parser / cached Laya classifier, private HA configuration + REST adapter, separate SwiftUI settings model.
**Tech stack:** Swift 6, URLSession, NSWorkspace, Laya Core ML, Home Assistant REST.

- [x] Add Core HomeAssistantAction and folder enum/URL tools; extend parser using a separate HomeAssistantCommandParser.swift.
- [x] Add HomeAssistantConfigurationStore.swift, HomeAssistantClient.swift with validated discovery, name resolution, no redirect/retry and bounded services; test HTTP/store cases.
- [x] Add bounded CachedDecisionEngine.swift; wire live Laya, ten intent choices and canonical input; update affected Python fixtures, measure actual classification/cache.
- [x] Add HomeAssistantSettings.swift and view; wire shared adapter into MacToolExecutor, validate Gemini typed fallback, route stays silent.
- [x] Add opt-in 500-ms speech endpoint, targeted endpoint tests. Tighten default answer length while respecting detailed requests.

- [x] Additional user steering: Safari title/URL/native text tab search in existing locator, local multi-choice UI and stable targets; mock JXA fixture without actual Safari control.
- [x] Energy: 24-fps animations, selected gallery preview only, inactive settings pause; exact DTW scalar optimization and reference equivalence. Keep audio and Moonshine cadence.
- [x] Dialogue: eight memory-only pairs, optional eight-second clarification capture, silence timeout, cancellation phrases and clear-history button. Default strict Hey Friday; bare/acoustic wake opt-in. Verify affected wake and voice lifecycle tests only.
- [x] Run affected tests only, real classification/cache probe and signed build 8. Update docs, scan secrets, preserve old app, install and deliver through Git.

## Verification and handoff

- Targeted Swift runs: 39 affected tests, then 11 tests covering final parser/cache/lifecycle changes; both passed. The full suite was not rerun.
- Targeted Python run: 62 Laya/CLI/wake/personal-wake tests passed; after adding the DTW reference check, the nine personal-wake tests passed.
- Actual local Laya probe correctly routed all sampled commands, including Safari tabs, folders, links and HA. Warm classification was 151–159 ms; an identical cached HA command was 0.056 ms. These measure classification, not the complete speech/action pipeline.
- DTW reference benchmark: 26.59 ms to 8.47 ms, with the same score and span. Actual post-update app energy use remains a live-user check.
- HA HTTP mocks verified discovery, typed service requests, capability/range checks, ambiguous names, credential handling and failures. The actual server responded 401 without a token; no live device action was attempted.
- Safari search/focus was verified using a mocked JXA environment. Live Safari permissions/focus and microphone recognition remain user checks after restart.
- Signed build 8 installed at `~/Applications/Friday.app`; build 7 preserved under the private `PreviousBuild` directory. Signing requirement stayed stable and bundled workers matched source. Private credential scans passed. The running app was not restarted.
