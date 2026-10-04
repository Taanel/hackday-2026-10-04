import Foundation
import FridayCore

/// Replace with Ollama or a configured hosted reasoning model.
public struct UnconfiguredReasoningEngine: ReasoningEngine {
    public init() {}
    public func respond(to text: String) async throws -> String {
        throw FridayError.providerNotConfigured("Reasoning-LLM")
    }
}

@MainActor public final class UnconfiguredWakeWordDetector: WakeWordDetector {
    public init() {}
    public func start(phrase: String) async throws -> AsyncStream<ActivationEvent> {
        throw FridayError.providerNotConfigured("Wake-Word \(phrase)")
    }
    public func stop() {}
}

@MainActor public final class ElevenLabsSpeechOutput: SpeechOutput {
    public init() {}
    public func speak(_ text: String) async throws {
        throw FridayError.providerNotConfigured("ElevenLabs Text-to-Speech")
    }
    public func stop() {}
}
