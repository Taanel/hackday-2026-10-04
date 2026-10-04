import Foundation
import Testing
import FridayCore
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

@Test @MainActor func directComputerActionStaysSilentEvenWhenTTSIsEnabled() async {
    let speech = SpeechSpy()
    let model = model(intent: .action(.openApplication(bundleIdentifier: "com.apple.Safari")), speech: speech)
    model.speakResponses = true
    model.submit()
    await model.task?.value
    #expect(model.response == "Aktion erledigt.")
    #expect(speech.texts.isEmpty)
    #expect(model.phase == .idle)
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
    #expect(AssistantViewModel.removeWakePrefix("Notiz: Hey Friday ist der Name.") == "Notiz: Hey Friday ist der Name.")
}
