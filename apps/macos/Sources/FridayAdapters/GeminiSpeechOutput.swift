import AVFoundation
import CryptoKit
import Foundation
import FridayCore

/// Gemini 3.8 speech using dedicated voice keys, or the original key when unset.
@MainActor public final class GeminiSpeechOutput: NSObject, SpeechOutput, AVAudioPlayerDelegate {
    public var voiceName = "Kore"
    public private(set) var lastModel: String?
    private var models: [Data: GeminiTTSModelPool] = [:]
    private var keyCursor = 0
    private let credentials: GeminiSpeechCredentials
    private let session: URLSession
    private var download: Task<Data, any Error>?
    private var player: AVAudioPlayer?
    private var generation = UUID()
    private var pending: (player: ObjectIdentifier, continuation: CheckedContinuation<Void, any Error>)?

    public init(session: URLSession = .shared,
                apiKey: (@Sendable () throws -> String)? = nil,
                apiKeys: (@Sendable () throws -> [String])? = nil) {
        self.session = session
        if let apiKeys { credentials = GeminiSpeechCredentials(loader: apiKeys) }
        else if let apiKey { credentials = GeminiSpeechCredentials(loader: { [try apiKey()] }) }
        else { credentials = GeminiSpeechCredentials(loader: { try LocalGeminiTTSKeyStore().loadKeys() }) }
        super.init()
    }

    public func invalidateCredentials() async { await credentials.invalidate(); resetModelAvailability() }
    public func resetModelAvailability() { models = [:]; keyCursor = 0 }

    public func speak(_ text: String) async throws {
        try Task.checkCancellation()
        stop()
        let token = UUID(); generation = token
        let voice = voiceName
        let loading = Task {
            let keys = try await credentials.load()
            try Task.checkCancellation()
            return try await generateAudio(text: text, apiKeys: keys, voice: voice)
        }
        download = loading
        try await withTaskCancellationHandler {
            do {
                let audio = try await loading.value
                try Task.checkCancellation()
                guard generation == token else { throw CancellationError() }
                download = nil
                let playback = try AVAudioPlayer(data: audio)
                playback.delegate = self
                player = playback
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    pending = (ObjectIdentifier(playback), continuation)
                    guard playback.play() else {
                        pending = nil; player = nil
                        continuation.resume(throwing: AdapterError.unavailable("Die Stimme konnte nicht abgespielt werden."))
                        return
                    }
                }
            } catch {
                if generation == token { stop() }
                throw error
            }
        } onCancel: {
            loading.cancel()
            Task { @MainActor [weak self] in
                guard self?.generation == token else { return }
                self?.stop()
            }
        }
    }

    // The shared deadline bounds all model attempts, not each individual retry.
    func generateAudio(text: String, apiKey: String, voice: String) async throws -> Data {
        try await generateAudio(text: text, apiKeys: [apiKey], voice: voice)
    }

    func generateAudio(text: String, apiKeys: [String], voice: String) async throws -> Data {
        guard (1...4).contains(apiKeys.count), Set(apiKeys).count == apiKeys.count else {
            throw AdapterError.unavailable("Ein bis vier unterschiedliche TTS-Schlüssel sind erforderlich.")
        }
        let ids = apiKeys.map { Data(SHA256.hash(data: Data($0.utf8))) }
        models = models.filter { ids.contains($0.key) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        for _ in 0..<(apiKeys.count * GeminiTTSModelPool.models.count) {
            try Task.checkCancellation()
            let index = keyCursor % apiKeys.count; keyCursor = (index + 1) % apiKeys.count
            let id = ids[index], apiKey = apiKeys[index]
            var pool = models[id] ?? GeminiTTSModelPool()
            guard let model = pool.next() else { continue }
            models[id] = pool
            let remaining = ContinuousClock.now.duration(to: deadline)
            guard remaining > .zero else { break }
            var request = try Self.makeRequest(text: text, apiKey: apiKey, voice: voice, model: model)
            request.timeoutInterval = Double(remaining.components.seconds) + Double(remaining.components.attoseconds) / 1e18
            do {
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                let http = response as? HTTPURLResponse
                let status = http?.statusCode ?? 0
                if status == 401 || status == 403 || status == 429 || status == 404 || (500...599).contains(status) {
                    let until = status == 401 || status == 403 ? Date().addingTimeInterval(86_400) : GeminiTTSModelPool.cooldown(status: status, data: data, response: http)
                    if status == 401 { for name in GeminiTTSModelPool.models { pool.pause(name, until: until) } }
                    else { pool.pause(model, until: until) }
                    models[id] = pool
                    continue
                }
                let audio = try Self.decodeAudio(data, status: status)
                lastModel = model
                return audio
            } catch let error as URLError where error.code == .cancelled { throw CancellationError() }
            catch let error as URLError where error.code == .timedOut {
                throw AdapterError.unavailable("Die Sprachgenerierung dauert zu lange. Die Textantwort bleibt verfügbar.")
            }
            catch is URLError { throw AdapterError.unavailable("Der Sprachdienst ist gerade nicht erreichbar. Die Textantwort bleibt verfügbar.") }
        }
        throw AdapterError.unavailable("Gemini 3.8 TTS ist mit den gespeicherten Sprachschlüsseln derzeit nicht verfügbar oder das Kontingent ist erreicht.")
    }

    public func stop() {
        generation = UUID()
        download?.cancel(); download = nil
        player?.stop(); player = nil
        let continuation = pending?.continuation; pending = nil
        continuation?.resume(throwing: CancellationError())
    }

    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identifier = ObjectIdentifier(player)
        Task { @MainActor [weak self] in self?.complete(identifier, success: flag) }
    }

    nonisolated public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        let identifier = ObjectIdentifier(player)
        Task { @MainActor [weak self] in self?.complete(identifier, success: false) }
    }

    private func complete(_ identifier: ObjectIdentifier, success: Bool) {
        guard let pending, pending.player == identifier else { return }
        self.pending = nil; player = nil
        if success { pending.continuation.resume() }
        else { pending.continuation.resume(throwing: AdapterError.unavailable("Fehler bei der Sprachwiedergabe.")) }
    }

    static func makeRequest(text: String, apiKey: String, voice: String = "Kore", model: String = "gemini-3.8-flash-lite-tts") throws -> URLRequest {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 12_000,
              ["Kore", "Aoede", "Charon"].contains(voice), GeminiTTSModelPool.models.contains(model), !apiKey.isEmpty,
              !apiKey.contains(where: { $0.isNewline }) else { throw AdapterError.unavailable("Ungültige Sprachkonfiguration.") }
        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions")!)
        request.httpMethod = "POST"; request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "store": false,
            "input": [["type": "user_input", "content": [[
                "type": "text", "text": text,
                "annotations": [["type": "speech_metadata", "style": "Sprich natürliches, warmes Hochdeutsch. Freundlich, entspannt und direkt, wie im persönlichen Gespräch. Flüssig und ohne übertriebene Pausen."]]
            ]]]],
            "response_format": ["type": "audio", "mime_type": "audio/wav"],
            "generation_config": ["speech_config": [["voice": voice]]]
        ])
        return request
    }

    static func decodeAudio(_ data: Data, status: Int) throws -> Data {
        guard status == 200 else {
            switch status {
            case 429: throw AdapterError.unavailable("Das Gemini-Sprachkontingent ist erreicht. Die Textantwort bleibt verfügbar.")
            case 400, 401, 403: throw AdapterError.unavailable("Gemini-TTS hat den Schlüssel oder die Sprachkonfiguration abgelehnt.")
            default: throw AdapterError.unavailable("Gemini-TTS ist gerade nicht verfügbar (HTTP \(status)).")
            }
        }
        guard data.count <= 30_000_000,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw invalidAudio }
        guard let steps = obj["steps"] as? [[String: Any]] else { throw invalidAudio }
        let parts = steps.filter { $0["type"] as? String == "model_output" }.flatMap { $0["content"] as? [[String: Any]] ?? [] }
        guard let part = parts.last(where: { $0["type"] as? String == "audio" }),
              part["mime_type"] as? String == "audio/wav", let encoded = part["data"] as? String,
              let audio = Data(base64Encoded: encoded), audio.count > 44,
              audio.prefix(4) == Data("RIFF".utf8), audio.dropFirst(8).prefix(4) == Data("WAVE".utf8) else { throw invalidAudio }
        return audio
    }

    private static var invalidAudio: AdapterError { .invalidResponse("Gemini-TTS hat keine gültige Audiodatei geliefert.") }
}
