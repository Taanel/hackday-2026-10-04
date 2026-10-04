import Foundation
import Testing
@testable import FridayAdapters

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
