# Friday: macOS assistant scaffold

## Scope

Create a small, buildable repository structure for the assistant described by the team.
This milestone is the foundation, not the completed voice assistant. Keep the existing
Python/Ollama hack-day demo available. No model downloads or API keys are needed to build.

## Approach

A native SwiftUI shell is the default because the target is macOS, with an AppKit
panel for the mascot in the upper-right corner. Electron with Hex's TypeScript SDK
would reduce the speech integration work but add another app runtime. Forking Hex
would inherit its dictation UI and maintenance; an adapter keeps Friday independent.

Use a Swift package with three targets: FridayCore (contracts and routing),
FridayAdapters (provider placeholders, demo implementations and system TTS), and
FridayApp (menu bar, floating mascot, manual demo input). Bundle it as Friday.app
with a local build script. Minimum OS: macOS 15; Swift 6 toolchain.

## Data flow

Activation (button / future shortcut / future "Hey Friday") → audio capture → STT
→ explicit input mode. Dictation goes directly to text insertion. Assistant mode
goes to the fast decision provider; a sufficiently confident typed action goes to
the tool executor, while reasoning, unknown decisions and classifier failures go
to the reasoning provider. Optional TTS speaks only the final reasoning response;
direct computer actions and dictated text stay silent (updated user requirement).

Laya selects among predefined actions; it does not generate arbitrary app names,
note content or shell commands. Argument extraction/validation is separate and
must complete before an action may execute. A confidence threshold is configurable
and provisional until calibrated on real German commands. Cancellation propagates.

## Modules and boundaries

- Audio capture: supplies an audio file, owns microphone lifecycle.
- Speech-to-text: Hex adapter slot; audio in, transcript out.
- Wake word: separate streaming detector contract, disabled until integrated.
- Fast decisions: Laya adapter slot; transcript in, typed decision out.
- Reasoning: replaceable LLM provider; Ollama starter is a reference for later integration.
- Computer use: typed application/note/terminal requests, initially preview-only.
  Terminal requests use executable + argument array + working directory, never interpolated shell text.
- Text output: separate foreground-app insertion contract for dictation.
- Speech output: system macOS voice as the initial optional TTS; ElevenLabs adapter slot.
- Mascot: resource slot for mascot.png, SF Symbol until the team supplies artwork.

## Demo behavior and errors

Manual text entry exercises routing without microphone access. An explicitly labelled
demo classifier recognizes only "Öffne Safari" and "Notiz: …"; tools return a preview.
Other text produces a clearly labelled placeholder response. Real provider adapters
throw provider-not-configured rather than pretending to infer or transcribe.
Wake-word and dictation insertion remain documented integration tasks.

## Verification and delivery

Build all Swift targets, test the routing boundaries (fast action, low confidence,
invalid confidence, missing arguments, classifier failure, cancellation, dictation),
validate the .app bundle, and add macOS CI. Publish on a branch; if upstream access
is read-only, use a fork and pull request. Real audio, wake-word, provider quality and
actual computer use are outside this scaffold's verification claims.
