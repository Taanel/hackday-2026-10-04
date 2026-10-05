import Foundation
import Testing
import FridayCore
import FridayAdapters
@testable import FridayApp

private struct Decision: FastDecisionEngine {
    let intent: DecisionIntent
    func decide(text: String) async throws -> FastDecision {
        FastDecision(intent: intent, confidence: 1)
    }
}

private struct Reasoning: ReasoningEngine {
    func respond(to text: String) async throws -> String { "Ein ausführlicher Plan." }
}

private actor CountedReasoning: ReasoningEngine {
    private(set) var calls = 0
    func respond(to text: String) async throws -> String { calls += 1; return "Die gespeicherte Antwort." }
}

private struct Tools: ToolExecutor {
    func execute(_ request: ToolRequest) async throws -> String { "Aktion erledigt." }
}

@MainActor private final class SpeechSpy: SpeechOutput {
    var texts: [String] = []
    var holdsPlayback = false
    private(set) var pending: CheckedContinuation<Void, any Error>?

    func speak(_ text: String) async throws {
        texts.append(text)
        if holdsPlayback {
            try await withCheckedThrowingContinuation { pending = $0 }
        }
    }

    func finish() { let continuation = pending; pending = nil; continuation?.resume() }
    func stop() {
        let continuation = pending
        pending = nil
        continuation?.resume(throwing: CancellationError())
    }
}

@MainActor private func model(intent: DecisionIntent, speech: SpeechSpy) -> AssistantViewModel {
    AssistantViewModel(
        router: AssistantRouter(decisions: Decision(intent: intent), reasoning: Reasoning(), tools: Tools()),
        speech: speech
    )
}

@Test @MainActor func reasoningAnswersSpeakByDefault() async {
    let speech = SpeechSpy()
    let model = model(intent: .reasoning, speech: speech)
    model.submit()
    await model.task?.value
    #expect(model.speakResponses)
    #expect(speech.texts == ["Ein ausführlicher Plan."])
}

@Test(arguments: [ToolRequest.openApplication(bundleIdentifier: "com.apple.Safari"), .findProject(query: "Private Project")]) @MainActor
func directComputerActionStaysSilentEvenWhenTTSIsEnabled(request: ToolRequest) async {
    let speech = SpeechSpy()
    let model = model(intent: .action(request), speech: speech)
    model.speakResponses = true
    model.submit()
    await model.task?.value
    #expect(model.response == "Aktion erledigt.")
    #expect(speech.texts.isEmpty)
    #expect(model.phase == .idle)
}

@Test @MainActor func completedAppCommandDisappearsAfterOneSecond() async throws {
    let model = model(intent: .action(.openApplication(bundleIdentifier: "com.apple.Safari")), speech: SpeechSpy())
    model.submit(); await model.task?.value
    #expect(model.overlayTranscript == "Öffne Safari")
    try await Task.sleep(for: .milliseconds(1150))
    #expect(model.overlayTranscript.isEmpty)
}

@MainActor private final class BrokenSpeech: SpeechOutput {
    func speak(_ text: String) async throws { throw AdapterError.unavailable("TTS nicht verfügbar") }
    func stop() {}
}

@Test @MainActor func voiceFailureKeepsTheAnswerAvailableForReadingAndReplay() async {
    let model = AssistantViewModel(router: AssistantRouter(decisions: Decision(intent: .reasoning), reasoning: Reasoning(), tools: Tools()), speech: BrokenSpeech())
    model.submit(); await model.task?.value
    #expect(model.response == "Ein ausführlicher Plan.")
    #expect(model.canReplayAnswer)
    #expect(model.status.contains("Sprachausgabe"))
    #expect(!model.isWorking)
}

@Test(arguments: [false, true]) @MainActor
func reasoningSpeaksOnlyWhenRequested(enabled: Bool) async {
    let speech = SpeechSpy()
    let model = model(intent: .reasoning, speech: speech)
    model.speakResponses = enabled
    model.submit()
    await model.task?.value
    #expect(speech.texts == (enabled ? ["Ein ausführlicher Plan."] : []))
    #expect(model.phase == .idle)
}

@Test @MainActor func dictationNeverSpeaksOrReinterpretsText() async {
    let speech = SpeechSpy()
    let model = model(intent: .reasoning, speech: speech)
    model.input = "Öffne Safari"
    model.mode = .dictation
    model.speakResponses = true
    model.submit()
    await model.task?.value
    #expect(model.response == "Öffne Safari")
    #expect(speech.texts.isEmpty)
}

@Test(arguments: [false, true]) @MainActor
func speechStateLastsUntilPlaybackFinishesOrIsCancelled(cancel: Bool) async throws {
    let speech = SpeechSpy()
    speech.holdsPlayback = true
    let model = model(intent: .reasoning, speech: speech)
    model.speakResponses = true
    model.submit()
    // Bound the wait: a regression must fail instead of leaving the suite hanging.
    for _ in 0..<200 where speech.pending == nil {
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(speech.pending != nil)
    #expect(model.phase == .speaking)
    #expect(model.isWorking)
    if cancel { model.cancel() } else { speech.finish() }
    await model.task?.value
    #expect(model.phase == .idle)
    #expect(!model.isWorking)
    #expect(speech.pending == nil)
    if cancel { #expect(model.status == "Abgebrochen") }
}

@Test @MainActor func confirmedWakePrefixIsRemovedOnlyAtBeginning() {
    #expect(AssistantViewModel.removeWakePrefix("Hey Friday, öffne Safari.") == "öffne Safari.")
    #expect(AssistantViewModel.removeWakePrefix("Hey Friede, öffne Safari.") == "öffne Safari.")
    #expect(AssistantViewModel.removeWakePrefix("Friday, öffne Blender.") == "öffne Blender.")
    #expect(AssistantViewModel.removeWakePrefix("Friday!") == "")
    #expect(AssistantViewModel.removeWakePrefix("Fridaynight ist ein Wort") == "Fridaynight ist ein Wort")
    #expect(AssistantViewModel.removeWakePrefix("Notiz: Hey Friday ist der Name.") == "Notiz: Hey Friday ist der Name.")
}

@Test @MainActor func replayUsesTheSavedAnswerAndCannotOverlapPlayback() async throws {
    let speech = SpeechSpy()
    let reasoning = CountedReasoning()
    let model = AssistantViewModel(router: AssistantRouter(decisions: Decision(intent: .reasoning), reasoning: reasoning, tools: Tools()), speech: speech)
    model.submit(); await model.task?.value
    #expect(model.canReplayAnswer)
    speech.holdsPlayback = true
    model.replayAnswer()
    for _ in 0..<200 where speech.pending == nil { try await Task.sleep(for: .milliseconds(5)) }
    #expect(speech.pending != nil)
    let activeTask = model.task
    model.replayAnswer() // Cannot replace the existing playback task.
    #expect(speech.texts == ["Die gespeicherte Antwort.", "Die gespeicherte Antwort."])
    #expect(model.isWorking)
    model.cancel()
    await activeTask?.value
    #expect(!model.isWorking)
    #expect(model.phase == .idle)
    #expect(await reasoning.calls == 1)
}

@Test @MainActor func appActionCannotBeReplayedAsASpokenAnswer() async {
    let speech = SpeechSpy()
    let model = model(intent: .action(.openApplication(bundleIdentifier: "com.apple.Safari")), speech: speech)
    model.submit(); await model.task?.value
    #expect(!model.canReplayAnswer)
    model.replayAnswer()
    #expect(speech.texts.isEmpty)
}

@Test @MainActor func transcriptTimersCannotClearANewerCommand() async throws {
    let model = model(intent: .reasoning, speech: SpeechSpy())
    model.showTranscript("Öffne Safari")
    #expect(model.overlayTranscript == "Öffne Safari")
    model.expireTranscript(after: .milliseconds(20))
    model.showTranscript("Öffne Blender")
    try await Task.sleep(for: .milliseconds(40))
    #expect(model.overlayTranscript == "Öffne Blender")
    model.expireTranscript(after: .milliseconds(10))
    try await Task.sleep(for: .milliseconds(30))
    #expect(model.overlayTranscript.isEmpty)
    model.showTranscript("Alte Aufnahme")
    model.clearTranscript()
    #expect(model.overlayTranscript.isEmpty)
}

@Test @MainActor func settingsStoreTheKeyLocallyAndClearTheEntryField() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LocalGeminiKeyStore(directory: directory)
    let model = AssistantViewModel(speech: SpeechSpy(), keyStore: store)
    model.geminiKeyInput = "local-test-key"
    await model.saveGeminiKey()
    #expect(try store.load() == "local-test-key")
    #expect(model.geminiKeyInput.isEmpty)
    #expect(model.geminiKeyConfigured)
    #expect(!model.geminiKeyStatus.contains("local-test-key"))
}

@Test @MainActor func conversationCancellationNeverCallsTheLLMOrVoice() async {
    let speech=SpeechSpy(), reasoning=CountedReasoning()
    let model=AssistantViewModel(router:AssistantRouter(decisions:Decision(intent:.reasoning),reasoning:reasoning,tools:Tools()),speech:speech)
    model.input="Nee, ist egal."
    model.submit(); await model.task?.value
    #expect(await reasoning.calls == 0); #expect(speech.texts.isEmpty)
    #expect(model.response == "Alles klar.")
    #expect(AssistantViewModel.isFollowUpQuestion("Welche Stadt meinst du?"))
    #expect(!AssistantViewModel.isFollowUpQuestion("Die Sonne scheint."))
}
