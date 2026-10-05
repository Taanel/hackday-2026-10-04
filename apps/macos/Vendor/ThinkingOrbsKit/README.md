# ThinkingOrbsKit — vendored SwiftUI source

Upstream: [Jakubantalik/Libraries.dev](https://github.com/Jakubantalik/Libraries.dev/tree/d06640864eb4adc2fe240f899a44ee6210779782/packages/thinking-orbs/ports/ios/ThinkingOrbsKit).
Revision: `d06640864eb4adc2fe240f899a44ee6210779782`.
MIT, copyright 2026 Jakub Antalik; see [LICENSE](LICENSE).

The source retains the pinned upstream geometry. Local change: ThinkingOrb uses a minimum animation interval of 1/24 s to reduce Friday CPU/GPU work.
The local manifest includes only the library. Upstream golden/performance tests
and their web-engine fixtures are available in the linked repository.
No Pro presets, Studio exports or paid content are included.

Native SwiftUI `TimelineView` + `Canvas`, nine states, 64/20-point presets,
automatic light/dark and Reduce Motion support. Friday wraps it in
`AssistantOrb.swift`; the MIT notice is also bundled in the app resources.

To update, choose and record a revision, replace all ten source files and license,
then verify `swift test --package-path apps/macos` and the packaged app build.
