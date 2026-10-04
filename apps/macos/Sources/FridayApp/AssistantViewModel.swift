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

    private let router = AssistantRouter(
        decisions: DemoDecisionEngine(),
        reasoning: DemoReasoningEngine(),
        tools: PreviewToolExecutor()
    )
    private let speech = SystemSpeechOutput()
    private var task: Task<Void, Never>?

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
            defer { isWorking = false }
            do {
                let result = try await router.handle(submittedInput, mode: submittedMode)
                try Task.checkCancellation()
                response = result.text
                switch result.route {
                case .fastAction: status = "Schnelle Aktion · Vorschau"
                case .reasoning: status = "LLM-Fallback · Platzhalter"
                case .dictation: status = "Diktat · Textvorschau"
                }
                if shouldSpeak && result.route != .dictation {
                    try await speech.speak(result.text)
                }
            } catch is CancellationError {
                status = "Abgebrochen"
            } catch {
                status = "Fehler"
                response = error.localizedDescription
            }
        }
    }

    func cancel() {
        task?.cancel()
        speech.stop()
    }
}
