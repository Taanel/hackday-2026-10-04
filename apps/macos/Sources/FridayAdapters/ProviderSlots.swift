import Foundation
import FridayCore

/// Integrate Hex's native helper via IPC here; no Swift SDK is assumed.
public struct HexSpeechToText: SpeechToText {
    public init() {}
    public func transcribe(audioFile: URL) async throws -> String {
        throw FridayError.providerNotConfigured("Hex Speech-to-Text")
    }
}

/// Map Laya choices to validated arguments from a separate parser/allowlist.
public struct LayaDecisionEngine: FastDecisionEngine {
    public init() {}
    public func decide(text: String) async throws -> FastDecision {
        throw FridayError.providerNotConfigured("Laya")
    }
}

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
