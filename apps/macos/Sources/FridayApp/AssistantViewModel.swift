import Foundation
import FridayCore
import FridayAdapters

@MainActor final class AssistantViewModel: ObservableObject {
    @Published var input = "Öffne Safari"
    @Published var mode: InputMode = .assistant
    @Published var speakResponses = false
    @Published private(set) var response = ""
    @Published private(set) var status = "Bereit · Demo"
    @Published private(set) var isWorking = false
    @Published private(set) var phase: AssistantPhase = .idle

    private let router: AssistantRouter
    private let speech: any SpeechOutput
    private(set) var task: Task<Void, Never>?

    init(
        router: AssistantRouter = AssistantRouter(
            decisions: DemoDecisionEngine(),
            reasoning: DemoReasoningEngine(),
            tools: PreviewToolExecutor()
        ),
        speech: any SpeechOutput = SystemSpeechOutput()
    ) {
        self.router = router
        self.speech = speech
    }

    func submit() {
        guard !isWorking else { return }
        let submittedInput = input
        let submittedMode = mode
        let shouldSpeak = speakResponses
        speech.stop()
        isWorking = true
        response = ""
        status = "Verarbeite …"
        task = Task {
            defer { isWorking = false; task = nil }
            do {
                let result = try await router.handle(submittedInput, mode: submittedMode) { [weak self] phase in
                    await self?.showPhase(phase)
                }
                try Task.checkCancellation()
                response = result.text
                switch result.route {
                case .fastAction: status = "Schnelle Aktion · Vorschau"
                case .reasoning: status = "LLM-Fallback · Platzhalter"
                case .dictation: status = "Diktat · Textvorschau"
                }
                // Computer actions finish visually; only requested LLM answers are spoken.
                if shouldSpeak && result.route == .reasoning {
                    phase = .speaking
                    try await speech.speak(result.text)
                }
                try Task.checkCancellation()
                phase = .idle
            } catch is CancellationError {
                status = "Abgebrochen"
                phase = .idle
            } catch {
                status = "Fehler"
                response = error.localizedDescription
                phase = .failed
            }
        }
    }

    private func showPhase(_ phase: AssistantPhase) {
        self.phase = phase
        switch phase {
        case .deciding: status = "Entscheidung · Demo"
        case .acting: status = "Computeraktion · Vorschau"
        case .reasoning: status = "LLM · Demo"
        default: break
        }
    }

    func cancel() {
        task?.cancel()
        speech.stop()
    }
}
