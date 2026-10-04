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

public struct AssistantResponse: Sendable, Equatable {
    public let text: String
    public let route: ResponseRoute

    public init(text: String, route: ResponseRoute) {
        self.text = text
        self.route = route
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

public enum ToolRequest: Sendable, Equatable {
    case openApplication(bundleIdentifier: String)
    case createNote(text: String)
    case runExecutable(TerminalCommand)

    /// Structural validation only. A real executor must also enforce its own policy.
    public var hasValidArguments: Bool {
        switch self {
        case .openApplication(let identifier):
            return identifier.contains(".") && !identifier.contains(where: { $0.isWhitespace })
        case .createNote(let text):
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    public var errorDescription: String? {
        switch self {
        case .emptyInput: "Bitte gib einen Text ein."
        case .providerNotConfigured(let name): "\(name) ist noch nicht angebunden."
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

public protocol ToolExecutor: Sendable {
    func execute(_ request: ToolRequest) async throws -> String
}

@MainActor public protocol TextOutput {
    func insertAtCursor(_ text: String) async throws
}

@MainActor public protocol SpeechOutput {
    func speak(_ text: String) async throws
    func stop()
}
