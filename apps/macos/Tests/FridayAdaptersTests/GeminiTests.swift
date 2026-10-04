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
    let engine = GeminiReasoningEngine(session: session, apiKey: { "test-key" })
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
