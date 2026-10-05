import AVFoundation
import Foundation
import FridayCore

/// German speech generated offline by the prepared Piper worker.
@MainActor public final class LocalPiperSpeechOutput: NSObject, SpeechOutput, AVAudioPlayerDelegate {
    public let worker: JSONLineProcess
    private var generation = UUID()
    private var player: AVAudioPlayer?
    private var synthesis: Task<Data, any Error>?
    private var pending: (ObjectIdentifier, CheckedContinuation<Void, any Error>)?

    public init(worker: JSONLineProcess) { self.worker = worker; super.init() }

    public func speak(_ text: String) async throws {
        try Task.checkCancellation()
        stop()
        let token = UUID(); generation = token
        try await withTaskCancellationHandler {
            for chunk in try Self.chunks(text) {
                try Task.checkCancellation()
                guard generation == token else { throw CancellationError() }
                let id = UUID().uuidString
                struct Request: Encodable { let id: String; let op = "speak"; let text: String }
                struct Reply: Decodable { let wav: String }
                let worker = self.worker
                let loading = Task { try await worker.request(JSONEncoder().encode(Request(id: id, text: chunk)), id: id) }
                synthesis = loading
                let response = try await loading.value
                try Task.checkCancellation()
                guard generation == token else { throw CancellationError() }
                synthesis = nil
                let reply = try JSONDecoder().decode(Reply.self, from: response)
                guard let data = Data(base64Encoded: reply.wav), data.count > 44, data.count <= 1_400_044,
                      data.prefix(4) == Data("RIFF".utf8), data.dropFirst(8).prefix(4) == Data("WAVE".utf8) else {
                    throw AdapterError.invalidResponse("Die lokale Stimme hat keine gültige Audiodatei geliefert.")
                }
                try Task.checkCancellation()
                guard generation == token else { throw CancellationError() }
                let playback = try AVAudioPlayer(data: data)
                playback.delegate = self; player = playback
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    pending = (ObjectIdentifier(playback), continuation)
                    if !playback.play() { complete(ObjectIdentifier(playback), success: false) }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.generation == token else { return }; self?.stop()
            }
        }
    }
    static func chunks(_ text: String) throws -> [String] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 12_000 else {
            throw AdapterError.unavailable("Die Textantwort ist zu lang oder leer für die Sprachausgabe.")
        }
        var parts: [String] = [], current = ""
        for word in text.split(whereSeparator: \.isWhitespace) {
            guard word.count <= 300 else { throw AdapterError.unavailable("Ein Wort ist zu lang für die Sprachausgabe.") }
            if current.count + word.count + 1 > 300 { parts.append(current); current = "" }
            current += (current.isEmpty ? "" : " ") + word
            if word.last.map({ ".!?".contains($0) }) == true { parts.append(current); current = "" }
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }
    public func stop() {
        generation = UUID(); synthesis?.cancel(); synthesis = nil; player?.stop(); player = nil
        let continuation = pending?.1; pending = nil
        continuation?.resume(throwing: CancellationError())
    }
    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(player)
        Task { @MainActor [weak self] in self?.complete(id, success: flag) }
    }
    nonisolated public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        let id = ObjectIdentifier(player)
        Task { @MainActor [weak self] in self?.complete(id, success: false) }
    }
    private func complete(_ id: ObjectIdentifier, success: Bool) {
        guard let pending, pending.0 == id else { return }
        self.pending = nil; player = nil
        if success { pending.1.resume() }
        else { pending.1.resume(throwing: AdapterError.unavailable("Die lokale Stimme konnte nicht abgespielt werden.")) }
    }
}

@MainActor public final class AdaptiveSpeechOutput: SpeechOutput {
    public var preferLocal = true
    public var onNotice: ((String) -> Void)?
    private let local: any SpeechOutput
    private let cloud: (any SpeechOutput)?
    private var cloudUnavailable = false
    public init(local: any SpeechOutput, cloud: (any SpeechOutput)?) { self.local = local; self.cloud = cloud }
    public func speak(_ text: String) async throws {
        if !preferLocal, !cloudUnavailable, let cloud {
            do { try await cloud.speak(text); onNotice?("Gemini-Stimme"); return }
            catch is CancellationError { throw CancellationError() }
            catch { cloudUnavailable = true; onNotice?("Gemini-Stimme nicht verfügbar · verwende Piper lokal") }
        } else { onNotice?("Piper · Thorsten High · lokal und kostenlos") }
        try Task.checkCancellation()
        try await local.speak(text)
    }
    public func resetCloudAvailability() { cloudUnavailable = false }
    public func stop() { local.stop(); cloud?.stop() }
}
