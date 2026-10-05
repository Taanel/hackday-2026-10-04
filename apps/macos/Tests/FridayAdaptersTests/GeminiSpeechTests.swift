import Foundation
import Testing
@testable import FridayAdapters

@Test func speechModelsRotateAndRecoverAfterTheirOwnCooldown() {
    var models = GeminiTTSModelPool()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let first = models.next(at: now)!
    let second = models.next(at: now)!
    #expect(Set([first, second]).count == 2)
    #expect(GeminiTTSModelPool.models.allSatisfy { $0.hasPrefix("gemini-3.8-") })
    models.pause(first, until: now.addingTimeInterval(120))
    #expect(models.next(at: now) == second)
    models.pause(second, until: now.addingTimeInterval(120))
    #expect(models.next(at: now) == nil)
    #expect(models.next(at: now.addingTimeInterval(121)) != nil)
}

@Test @MainActor func speechGenerationStaysOnGemini38() throws {
    for model in GeminiTTSModelPool.models {
        let request = try GeminiSpeechOutput.makeRequest(text: "Hallo", apiKey: "test-key", model: model)
        #expect(request.url?.path == "/v1beta/interactions")
    }
    #expect(throws: AdapterError.self) { try GeminiSpeechOutput.makeRequest(text: "Hallo", apiKey: "test-key", model: "gemini-3.1-flash-tts-preview") }
    #expect(throws: AdapterError.self) { try GeminiSpeechOutput.makeRequest(text: "Hallo", apiKey: "test-key", model: "unapproved-model") }
}

@Test @MainActor func neuralSpeechUsesVerbatimGermanTextAndPrivateHeader() throws {
    let request = try GeminiSpeechOutput.makeRequest(text: "Hallo, das ist deine Antwort.", apiKey: "test-key", voice: "Aoede")
    #expect(request.url?.path == "/v1beta/interactions")
    #expect(request.url?.query == nil)
    #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "test-key")
    let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
    #expect(body["model"] as? String == "gemini-3.8-flash-lite-tts")
    #expect(body["store"] as? Bool == false)
    #expect(!String(data: request.httpBody!, encoding: .utf8)!.contains("test-key"))
    #expect(throws: AdapterError.self) { try GeminiSpeechOutput.makeRequest(text: "Hallo", apiKey: "test-key", voice: "Unknown") }
}

@Test @MainActor func neuralSpeechValidatesAudioAndSanitizesServerErrors() throws {
    var wav = Data("RIFF".utf8); wav.append(Data(repeating: 0, count: 4)); wav.append(Data("WAVE".utf8)); wav.append(Data(repeating: 0, count: 40))
    let response = try JSONSerialization.data(withJSONObject: ["steps": [["type": "model_output", "content": [["type": "audio", "mime_type": "audio/wav", "data": wav.base64EncodedString()]]]]])
    #expect(try GeminiSpeechOutput.decodeAudio(response, status: 200) == wav)
    #expect(throws: AdapterError.self) { try GeminiSpeechOutput.decodeAudio(Data(#"{"steps":[]}"#.utf8), status: 200) }
    do { _ = try GeminiSpeechOutput.decodeAudio(Data("PRIVATE KEY".utf8), status: 429); Issue.record("Quota was ignored") }
    catch { #expect(!error.localizedDescription.contains("PRIVATE KEY")); #expect(error.localizedDescription.contains("Kontingent") || error.localizedDescription.contains("kontingent")) }
}

private final class RotatingSpeechProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var names: [String] = []
    nonisolated(unsafe) private static var allLimited = false
    nonisolated(unsafe) private static var keyHeaders: [String] = []
    nonisolated(unsafe) private static var limitLite = true
    nonisolated(unsafe) private static var limitedKeys: Set<String> = []
    static func reset(allLimited: Bool, limitLite: Bool = true, limitedKeys: Set<String> = []) {
        lock.lock(); defer { lock.unlock() }
        names = []; keyHeaders = []; self.allLimited = allLimited; self.limitLite = limitLite; self.limitedKeys = limitedKeys
    }
    static var requested: [String] { lock.lock(); defer { lock.unlock() }; return names }
    static var requestedKeys: [String] { lock.lock(); defer { lock.unlock() }; return keyHeaders }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let model: String
        if request.url!.path.contains("generateContent") { model = "gemini-3.1-flash-tts-preview" }
        else {
            var body = request.httpBody
            if body == nil, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var bytes = [UInt8](repeating: 0, count: 4096); var result = Data()
                while stream.hasBytesAvailable { let count = stream.read(&bytes, maxLength: bytes.count); if count <= 0 { break }; result.append(contentsOf: bytes.prefix(count)) }
                body = result
            }
            model = ((try? JSONSerialization.jsonObject(with: body ?? Data())) as? [String: Any])?["model"] as? String ?? "unknown"
        }
        let key = request.value(forHTTPHeaderField: "x-goog-api-key") ?? ""
        Self.lock.lock(); Self.names.append(model); Self.keyHeaders.append(key)
        let limited = Self.allLimited || Self.limitedKeys.contains(key) || (Self.limitLite && model == "gemini-3.8-flash-lite-tts")
        Self.lock.unlock()
        let status = limited ? 429 : 200
        let data: Data
        if status == 429 { data = Data(#"{"error":{"message":"10 requests per day"}}"#.utf8) }
        else if model == "gemini-3.1-flash-tts-preview" {
            data = try! JSONSerialization.data(withJSONObject: ["candidates": [["content": ["parts": [["inlineData": ["mimeType": "audio/l16; rate=24000; channels=1", "data": Data([0,0,1,0]).base64EncodedString()]]]]]]])
        } else {
            let wav = WAVEncoder.encode([0,0,0], sampleRate: 24_000)
            data = try! JSONSerialization.data(withJSONObject: ["steps": [["type": "model_output", "content": [["type": "audio", "mime_type": "audio/wav", "data": wav.base64EncodedString()]]]]])
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test @MainActor func cloudSpeechSkipsLimitedModelsAndDoesNotRequestThemAgain() async throws {
    RotatingSpeechProtocol.reset(allLimited: false)
    let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [RotatingSpeechProtocol.self]
    let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
    let speech = GeminiSpeechOutput(session: session, apiKey: { "test-key" })
    let first = try await speech.generateAudio(text: "Hallo", apiKey: "test-key", voice: "Kore")
    let second = try await speech.generateAudio(text: "Wieder hallo", apiKey: "test-key", voice: "Kore")
    #expect(first.prefix(4) == Data("RIFF".utf8)); #expect(second.prefix(4) == Data("RIFF".utf8))
    #expect(RotatingSpeechProtocol.requested == ["gemini-3.8-flash-lite-tts", "gemini-3.8-flash-tts", "gemini-3.8-flash-tts"])
    #expect(speech.lastModel == "gemini-3.8-flash-tts")
    RotatingSpeechProtocol.reset(allLimited: true); speech.resetModelAvailability()
    await #expect(throws: AdapterError.self) { try await speech.generateAudio(text: "Hallo", apiKey: "test-key", voice: "Kore") }
    await #expect(throws: AdapterError.self) { try await speech.generateAudio(text: "Hallo", apiKey: "test-key", voice: "Kore") }
    #expect(RotatingSpeechProtocol.requested == GeminiTTSModelPool.models)
    let voiceKeys = ["voice-key-1", "voice-key-2", "voice-key-3", "voice-key-4"]
    RotatingSpeechProtocol.reset(allLimited: false, limitLite: false); speech.resetModelAvailability()
    for _ in 0..<4 { _ = try await speech.generateAudio(text: "Hallo", apiKeys: voiceKeys, voice: "Kore") }
    #expect(RotatingSpeechProtocol.requestedKeys == voiceKeys)
    #expect(RotatingSpeechProtocol.requested.allSatisfy { $0.hasPrefix("gemini-3.8-") })
    RotatingSpeechProtocol.reset(allLimited: false, limitLite: false, limitedKeys: ["voice-key-1"]); speech.resetModelAvailability()
    for _ in 0..<4 { _ = try await speech.generateAudio(text: "Hallo", apiKeys: voiceKeys, voice: "Kore") }
    #expect(RotatingSpeechProtocol.requestedKeys == ["voice-key-1", "voice-key-2", "voice-key-3", "voice-key-4", "voice-key-1", "voice-key-2"])
}

private final class PendingSpeechProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var started = false
    static func reset() { lock.lock(); defer { lock.unlock() }; started = false }
    static var hasStarted: Bool { lock.lock(); defer { lock.unlock() }; return started }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.lock.lock(); Self.started = true; Self.lock.unlock() }
    override func stopLoading() {}
}

@Test @MainActor func stoppingNeuralSpeechCancelsItsPendingDownloadBeforePlayback() async throws {
    PendingSpeechProtocol.reset()
    let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [PendingSpeechProtocol.self]
    let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
    let speech = GeminiSpeechOutput(session: session, apiKey: { "test-key" })
    let speaking = Task { try await speech.speak("Hallo") }
    for _ in 0..<200 where !PendingSpeechProtocol.hasStarted { try await Task.sleep(for: .milliseconds(5)) }
    #expect(PendingSpeechProtocol.hasStarted)
    speech.stop()
    do { try await speaking.value; Issue.record("Stopped speech succeeded") }
    catch { #expect(error is CancellationError) }
}
