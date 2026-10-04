import AVFoundation
import FridayCore

/// Uses installed macOS voices without an external TTS account.
@MainActor public final class SystemSpeechOutput: SpeechOutput {
    private let synthesizer = AVSpeechSynthesizer()

    public init() {}

    /// Starts playback; returning means queued, not finished speaking.
    public func speak(_ text: String) async throws {
        try Task.checkCancellation()
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
        synthesizer.speak(utterance)
    }

    public func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
