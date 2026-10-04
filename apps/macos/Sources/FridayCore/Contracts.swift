import Foundation

public enum InputMode: String, CaseIterable, Sendable {
    case assistant
    case dictation
}

public enum ResponseRoute: String, Sendable {
    case fastAction
    case reasoning
    case dictation
}

/// Actual provider activity; microphone phases join this when capture is connected.
public enum AssistantPhase: Sendable, Hashable, CaseIterable {
    case idle, listening, recording, transcribing, deciding, acting, reasoning, speaking, failed
}

public struct AnswerSource: Sendable, Equatable, Hashable {
    public let title: String
    public let url: URL
    public init(title: String, url: URL) { self.title = title; self.url = url }
}

public struct AssistantResponse: Sendable, Equatable {
    public let text: String
    public let route: ResponseRoute
    public let sources: [AnswerSource]

    public init(text: String, route: ResponseRoute, sources: [AnswerSource] = []) {
        self.text = text
        self.route = route
        self.sources = sources
    }
}

public struct TerminalCommand: Sendable, Equatable {
    public let executablePath: String
    public let arguments: [String]
    public let workingDirectory: URL

    public init(executablePath: String, arguments: [String], workingDirectory: URL) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.workingDirectory = workingDirectory
    }
}

public enum DesktopDirection: String, Sendable, Equatable { case left, right }

public enum ToolRequest: Sendable, Equatable {
    case openApplication(bundleIdentifier: String)
    case searchSafari(query: String)
    case createNote(text: String)
    case switchDesktop(direction: DesktopDirection)
    case findProject(query: String)
    case runExecutable(TerminalCommand)

    /// Structural validation only. A real executor must also enforce its own policy.
    public var hasValidArguments: Bool {
        switch self {
        case .openApplication(let identifier):
            return identifier.contains(".") && !identifier.contains(where: { $0.isWhitespace })
        case .createNote(let text):
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .searchSafari(let query):
            return !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && query.count <= 2_000
        case .switchDesktop: return true
        case .findProject(let query):
            return (2...200).contains(query.trimmingCharacters(in: .whitespacesAndNewlines).count)
        case .runExecutable(let command):
            return command.executablePath.hasPrefix("/") && command.workingDirectory.isFileURL
        }
    }
}

public enum DecisionIntent: Sendable {
    case action(ToolRequest)
    case reasoning
    case unknown
}

public struct FastDecision: Sendable {
    public let intent: DecisionIntent
    public let confidence: Double

    public init(intent: DecisionIntent, confidence: Double) {
        self.intent = intent
        self.confidence = confidence
    }
}

public enum FridayError: Error, LocalizedError, Sendable {
    case emptyInput
    case providerNotConfigured(String)
    case invalidActionPlan

    public var errorDescription: String? {
        switch self {
        case .emptyInput: "Bitte gib einen Text ein."
        case .providerNotConfigured(let name): "\(name) ist noch nicht angebunden."
        case .invalidActionPlan: "Das Modell hat keine gültige ausführbare Aktion geliefert."
        }
    }
}

// Capture owns the microphone; STT consumes the completed recording.
@MainActor public protocol AudioCapture {
    func start() async throws
    func stop() async throws -> URL
    func cancel()
}

public protocol SpeechToText: Sendable {
    func transcribe(audioFile: URL) async throws -> String
}

public enum ActivationEvent: Sendable {
    case wakeWord
}

// A real implementation consumes a local microphone stream, separate from dictation.
@MainActor public protocol WakeWordDetector {
    func start(phrase: String) async throws -> AsyncStream<ActivationEvent>
    func stop()
}

public protocol FastDecisionEngine: Sendable {
    func decide(text: String) async throws -> FastDecision
}

public protocol ReasoningEngine: Sendable {
    func respond(to text: String) async throws -> String
}

public enum ReasoningPlan: Sendable, Equatable {
    case answer(String)
    case researchedAnswer(text: String, sources: [AnswerSource])
    case actions([ToolRequest])
}

public protocol ActionPlanningReasoningEngine: ReasoningEngine {
    func plan(to text: String) async throws -> ReasoningPlan
}

public protocol ToolExecutor: Sendable {
    func execute(_ request: ToolRequest) async throws -> String
}

@MainActor public protocol TextOutput {
    func insertAtCursor(_ text: String) async throws
}

@MainActor public protocol SpeechOutput {
    /// Returns when playback finishes; cancellation or stop throws CancellationError.
    func speak(_ text: String) async throws
    func stop()
}
