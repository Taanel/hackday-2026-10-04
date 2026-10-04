import Foundation
import Testing
@testable import FridayAdapters

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
