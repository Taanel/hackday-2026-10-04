import Foundation
import Testing
import FridayCore
@testable import FridayAdapters

private final class GeminiRetryProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var paths: [String] = []
    static func reset() { lock.lock(); defer { lock.unlock() }; paths = [] }
    static func requests() -> [String] { lock.lock(); defer { lock.unlock() }; return paths }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.paths.append(request.url!.path); Self.lock.unlock()
        let busy = request.url!.path.contains("gemini-3.8-flash:")
        let response = HTTPURLResponse(url: request.url!, statusCode: busy ? 503 : 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((busy ? #"{"error":{"message":"Busy"}}"# : #"{"candidates":[{"content":{"parts":[{"text":"Die Antwort."}]}}]}"#).utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test func overloadedGeminiUsesBackupAndAvoidsRetryingTheBusyModel() async throws {
    GeminiRetryProtocol.reset()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [GeminiRetryProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let engine = GeminiReasoningEngine(model: "gemini-3.8-flash", session: session, apiKey: { "test-key" })
    #expect(try await engine.respond(to: "Erkläre X") == "Die Antwort.")
    #expect(try await engine.respond(to: "Erkläre Y") == "Die Antwort.")
    let paths = GeminiRetryProtocol.requests()
    #expect(paths.count == 3)
    #expect(paths[0].contains("gemini-3.8-flash:"))
    #expect(paths[1].contains("gemini-3.5-flash-lite:"))
    #expect(paths[2].contains("gemini-3.5-flash-lite:"))
}

@Test func geminiComputerRequestsResolveOnlyInstalledApps() throws {
    let parser = ActionArgumentParser(applications: ["Shapr3D": "com.shapr3d.shapr"])
    let reply = Data(#"{"candidates":[{"content":{"parts":[{"functionCall":{"name":"open_application","args":{"name":"Shaper 3D"}}}]}}]}"#.utf8)
    #expect(try GeminiReasoningEngine.decodePlan(reply, status: 200, parser: parser) == .actions([.openApplication(bundleIdentifier: "com.shapr3d.shapr")]))
    let invalid = Data(#"{"candidates":[{"content":{"parts":[{"functionCall":{"name":"run_terminal","args":{"command":"rm -rf /"}}}]}}]}"#.utf8)
    #expect(throws: AdapterError.self) { try GeminiReasoningEngine.decodePlan(invalid, status: 200, parser: parser) }
    let absent = Data(#"{"candidates":[{"content":{"parts":[{"functionCall":{"name":"open_application","args":{"name":"Absent App"}}}]}}]}"#.utf8)
    #expect(throws: AdapterError.self) { try GeminiReasoningEngine.decodePlan(absent, status: 200, parser: parser) }
}

@Test func geminiUsesHeaderAuthenticationAndTheRequestedModel() throws {
    let request = try GeminiReasoningEngine.makeRequest(text: "Plane meinen Tag", apiKey: "test-key", model: "gemini-3.8-flash")
    #expect(request.url?.path == "/v1beta/models/gemini-3.8-flash:generateContent")
    #expect(request.url?.query == nil)
    #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "test-key")
    let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
    #expect(body["contents"] != nil)
    #expect(body["systemInstruction"] != nil)
    #expect(body["tools"] == nil)
    #expect(!String(data: request.httpBody!, encoding: .utf8)!.contains("test-key"))
}

@Test func flashLiteUsesTheFastestThinkingSetting() throws {
    let request = try GeminiReasoningEngine.makeRequest(text: "Was ist ein Mac?", apiKey: "test-key", model: "gemini-3.5-flash-lite")
    let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
    let generation = body["generationConfig"] as! [String: Any]
    let thinking = generation["thinkingConfig"] as! [String: Any]
    #expect(thinking["thinkingLevel"] as? String == "MINIMAL")
    let flash = try GeminiReasoningEngine.makeRequest(text: "Plane X", apiKey: "test-key", model: "gemini-3.8-flash")
    let flashBody = try JSONSerialization.jsonObject(with: flash.httpBody!) as! [String: Any]
    let flashGeneration = flashBody["generationConfig"] as! [String: Any]
    #expect((flashGeneration["thinkingConfig"] as! [String: Any])["thinkingLevel"] as? String == "LOW")
}

private final class CredentialLoads: @unchecked Sendable {
    private let lock = NSLock()
    private var loads = 0
    func load() -> String { lock.lock(); defer { lock.unlock() }; loads += 1; return "test-key" }
    var count: Int { lock.lock(); defer { lock.unlock() }; return loads }
}

private final class GeminiSuccessProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"candidates":[{"content":{"parts":[{"text":"Antwort."}]}}]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test func concurrentGeminiQuestionsReadCredentialsOnlyOncePerSession() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [GeminiSuccessProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let loads = CredentialLoads()
    let engine = GeminiReasoningEngine(session: session, apiKey: { loads.load() })
    async let first = engine.respond(to: "Frage eins")
    async let second = engine.respond(to: "Frage zwei")
    _ = try await (first, second)
    _ = try await engine.respond(to: "Frage drei")
    #expect(loads.count == 1)
    #expect(engine.model == "gemini-3.5-flash-lite")
}

@Test func updatingLocalKeyInvalidatesTheGeminiSessionCredential() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [GeminiSuccessProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let loads = CredentialLoads()
    let engine = GeminiReasoningEngine(session: session, apiKey: { loads.load() })
    _ = try await engine.respond(to: "Frage eins")
    await engine.invalidateCredentials()
    _ = try await engine.respond(to: "Frage zwei")
    #expect(loads.count == 2)
}

@Test func geminiReturnsFinalTextAndSanitizesFailures() throws {
    let json = Data(#"{"candidates":[{"content":{"parts":[{"thought":true,"text":"Internes Denken"},{"text":"Dein Plan."}]}}]}"#.utf8)
    #expect(try GeminiReasoningEngine.decodeReply(json, status: 200) == "Dein Plan.")
    #expect(throws: AdapterError.self) { try GeminiReasoningEngine.decodeReply(Data(#"{"error":{"message":"PRIVATE KEY"}}"#.utf8), status: 401) }
    do {
        _ = try GeminiReasoningEngine.decodeReply(Data(#"{"error":{"message":"PRIVATE KEY"}}"#.utf8), status: 429)
        Issue.record("Quota error was accepted")
    } catch {
        #expect(!error.localizedDescription.contains("PRIVATE KEY"))
        #expect(error.localizedDescription.contains("Kontingent"))
    }
    #expect(throws: AdapterError.self) { try GeminiReasoningEngine.decodeReply(Data(#"{"candidates":[]}"#.utf8), status: 200) }
}
