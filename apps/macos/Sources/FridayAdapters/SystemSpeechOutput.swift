import AVFoundation
import Foundation
import FridayCore

/// Uses installed macOS voices without an external TTS account.
@MainActor public final class SystemSpeechOutput: NSObject, SpeechOutput, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var pending: (
        utterance: ObjectIdentifier, token: UUID, continuation: CheckedContinuation<Void, any Error>
    )?

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Waits for the delegate's completion, so the UI and future wake loop can resume.
    public func speak(_ text: String) async throws {
        try Task.checkCancellation()
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
        let token = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                pending = (ObjectIdentifier(utterance), token, continuation)
                synthesizer.speak(utterance)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                // A delayed cancellation must not stop a newer utterance.
                guard self?.pending?.token == token else { return }
                self?.stop()
            }
        }
    }

    public func stop() {
        let continuation = pending?.continuation
        pending = nil
        synthesizer.stopSpeaking(at: .immediate)
        // Do not rely on didCancel: AVFoundation may not emit it for queued audio.
        continuation?.resume(throwing: CancellationError())
    }

    nonisolated public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
    ) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.complete(identifier, cancelled: false) }
    }

    nonisolated public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
    ) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.complete(identifier, cancelled: true) }
    }

    private func complete(_ identifier: ObjectIdentifier, cancelled: Bool) {
        guard let pending, pending.utterance == identifier else { return }
        self.pending = nil
        if cancelled { pending.continuation.resume(throwing: CancellationError()) }
        else { pending.continuation.resume() }
    }
}
