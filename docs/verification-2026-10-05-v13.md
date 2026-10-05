# Build 13 — organized settings and local lookup

The settings window now separates Assistent, Sprache, Computer, Home Assistant and
Darstellung. Everyday input, status, answer and lookup results stay on the assistant
page; diagnostics, wake training, credentials and orb assignment have dedicated
sections. Existing voice/provider defaults and credentials are preserved.

Local lookup supports conversational Safari/Terminal-tab commands and file/folder
names. Laya still classifies the operation before typed execution. Spotlight performs
one bounded query against the home-directory index, with cancellation, a four-second
deadline and result selection for ambiguity. Only a complete, unique result opens
automatically. Stale or private paths are filtered; executable files are revealed
in Finder. No directory crawler or background indexer was added.

Weather responses carry structured Open-Meteo values through Core to a dismissible
overlay card. Next week means the next ISO Monday–Sunday; a location supplied after
clarification retains that period. Unsupported or incomplete periods stay text-only.
The card expires after 40 seconds and is cleared by a new command or cancellation;
the forecast remains available in the answer window. Native glass on macOS 26,
material on older versions, opaque surface for reduced transparency.

Validation:

- Actual local Laya/router: 25/25 evaluation cases accepted the expected route,
  including all new file/folder/tab cases. New cases also check the requested tool
  type. Warm decisions measured about 125–140 ms; this excludes speech and search.
- 14 affected adapter/app tests passed, including mocked weather HTTP calls,
  structured forecast delivery plus speech, expiry, argument validation, result
  filtering and an actual read-only Spotlight query.
- Actual Spotlight probes found 7 folders for Friday and 2 for Friday App, taking
  about one second. Neither opened files or activated another app. Both singleton
  and compound metadata predicates were checked after correcting Spotlight's
  rejection of a singleton AND wrapper.
- 27 selected Core/project/research regression tests passed. No full Swift suite or
  unrelated Python/wake/TTS suite was run; the Python classifier remains unchanged.
- All five pages were rendered offscreen in light/dark mode and inspected. Weather
  layout was reviewed using its opaque fallback: native glass depends on the window
  server and is not faithfully reproduced by offscreen bitmap rendering.
- Signed release build succeeded. Build number 13, release binary, bundled workers,
  code signature and unchanged signing requirement were verified. Actual locally
  stored credential bytes were absent from repository files and the app bundle.

Live limits: opening a document and focusing an existing tab need a user test after
reopening Friday. Existing macOS accessibility/automation grants still apply. No
GUI action was taken on the running Friday process, and no Home Assistant device was
changed during this work. Real microphone accuracy, native on-screen glass and a
real Gemini/TTS/weather round trip were not tested in this update.
