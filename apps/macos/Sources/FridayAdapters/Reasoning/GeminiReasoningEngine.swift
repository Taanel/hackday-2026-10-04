import Foundation
import Security
import FridayCore

public enum GeminiKeychain {
    public static func load() throws -> String {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "dev.hackday.friday.gemini",
            kSecAttrAccount: "Friday",
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else {
            throw AdapterError.unavailable("Gemini-Schlüssel nicht verfügbar. Bitte den Friday-Schlüsselbundzugriff erlauben oder scripts/configure-gemini.py ausführen.")
        }
        return key
    }
}

/// Only the reasoning branch sends text to Google. Hex and Laya remain local.
public struct GeminiReasoningEngine: ReasoningEngine {
    public let model: String
    private let apiKey: @Sendable () throws -> String
    private let session: URLSession

    public init(model: String = "gemini-3.8-flash", session: URLSession = .shared,
                apiKey: @escaping @Sendable () throws -> String = { try GeminiKeychain.load() }) {
        self.model = model; self.session = session; self.apiKey = apiKey
    }

    public func respond(to text: String) async throws -> String {
        try Task.checkCancellation()
        let request = try Self.makeRequest(text: text, apiKey: apiKey(), model: model)
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            return try Self.decodeReply(data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch let error as AdapterError { throw error }
        catch { throw AdapterError.unavailable("Gemini nicht erreichbar. Bitte Internetverbindung prüfen und erneut versuchen.") }
    }

    static func makeRequest(text: String, apiKey: String, model: String) throws -> URLRequest {
        guard model.range(of: #"^gemini-[a-zA-Z0-9.-]+$"#, options: .regularExpression) != nil,
              !apiKey.isEmpty, !apiKey.contains(where: { $0.isNewline }) else {
            throw AdapterError.unavailable("Ungültige Gemini-Konfiguration.")
        }
        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!)
        request.httpMethod = "POST"; request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "contents": [["role": "user", "parts": [["text": text]]]],
            "systemInstruction": ["parts": [["text": "Du bist Friday, ein Mac-Assistent. Antworte knapp auf Deutsch. Du beantwortest Fragen und erstellst Pläne. Du hast in diesem Antwortpfad keine Computerwerkzeuge oder Websuche. Behaupte keine ausgeführten Aktionen oder recherchierten aktuellen Quellen. Unterstützte direkte Aktionen sind App öffnen, Safari-Suche und Notiz speichern; andere Aktionen sind noch nicht implementiert."]]],
            "generationConfig": ["maxOutputTokens": 2048, "thinkingConfig": ["thinkingLevel": "LOW", "includeThoughts": false]]
        ])
        return request
    }

    private struct Reply: Decodable {
        struct Part: Decodable { let text: String?; let thought: Bool? }
        struct Content: Decodable { let parts: [Part]? }
        struct Candidate: Decodable { let content: Content? }
        let candidates: [Candidate]?
    }

    static func decodeReply(_ data: Data, status: Int) throws -> String {
        guard status == 200 else {
            // Never copy service error bodies, credentials or submitted text into errors.
            switch status {
            case 400, 401, 403: throw AdapterError.unavailable("Gemini hat den Schlüssel oder die Modell-Konfiguration abgelehnt.")
            case 429: throw AdapterError.unavailable("Gemini-Kontingent erreicht. Bitte später erneut versuchen.")
            default: throw AdapterError.unavailable("Gemini-Anfrage fehlgeschlagen (HTTP \(status)).")
            }
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            throw AdapterError.invalidResponse("Ungültige Gemini-Antwort.")
        }
        let text = (reply.candidates?.first?.content?.parts ?? [])
            .filter { $0.thought != true }.compactMap(\.text).joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AdapterError.unavailable("Gemini hat keine Antwort geliefert.") }
        return text
    }
}
