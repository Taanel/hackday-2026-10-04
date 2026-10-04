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

private actor GeminiAvailability {
    private var retryAfter = Date.distantPast
    var primaryCoolingDown: Bool { Date() < retryAfter }
    func coolDown() { retryAfter = Date().addingTimeInterval(120) }
}

/// Keep the credential only in memory. Concurrent questions share one Keychain
/// read, and Security's authorization dialog cannot block the main UI thread.
private actor GeminiCredentials {
    private let loader: @Sendable () throws -> String
    private var key: String?
    private var loading: Task<String, any Error>?

    init(loader: @escaping @Sendable () throws -> String) { self.loader = loader }

    func load() async throws -> String {
        if let key { return key }
        if let loading { return try await loading.value }
        let loader = loader
        let task = Task.detached { try loader() }
        loading = task
        do {
            let value = try await task.value
            key = value; loading = nil
            return value
        } catch {
            loading = nil
            throw error
        }
    }
}

/// Cloud fallback can answer or return bounded, typed actions to the local router.
public struct GeminiReasoningEngine: ActionPlanningReasoningEngine {
    public let model: String
    private let credentials: GeminiCredentials
    private let session: URLSession
    private let applications: [String: String]?
    private let availability = GeminiAvailability()
    private var backupModel: String { model == "gemini-3.5-flash-lite" ? "gemini-3.8-flash" : "gemini-3.5-flash-lite" }

    public init(model: String = "gemini-3.5-flash-lite", session: URLSession = .shared, applications: [String: String]? = nil,
                apiKey: @escaping @Sendable () throws -> String = { try GeminiKeychain.load() }) {
        self.model = model; self.session = session; self.credentials = GeminiCredentials(loader: apiKey); self.applications = applications
    }

    public func respond(to text: String) async throws -> String {
        guard case .answer(let answer) = try await plan(to: text) else { throw FridayError.invalidActionPlan }
        return answer
    }

    public func plan(to text: String) async throws -> ReasoningPlan {
        try Task.checkCancellation()
        let key = try await credentials.load()
        try Task.checkCancellation()
        let models = await availability.primaryCoolingDown ? [backupModel] : [model, backupModel]
        for (index, candidate) in models.enumerated() {
            let request = try Self.makeRequest(text: text, apiKey: key, model: candidate, applications: applications)
            do {
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if [404, 429, 500, 502, 503, 504].contains(status), index + 1 < models.count {
                    await availability.coolDown(); continue
                }
                return try Self.decodePlan(data, status: status, parser: ActionArgumentParser(applications: applications ?? [:]))
            } catch is CancellationError { throw CancellationError() }
            catch let error as URLError where error.code == .cancelled { throw CancellationError() }
            catch let error as URLError where error.code == .timedOut && index + 1 < models.count {
                await availability.coolDown(); continue
            }
            catch let error as AdapterError { throw error }
            catch { throw AdapterError.unavailable("Gemini nicht erreichbar. Bitte Internetverbindung prüfen und erneut versuchen.") }
        }
        throw AdapterError.unavailable("Gemini ist gerade nicht verfügbar. Bitte erneut versuchen.")
    }

    static func makeRequest(text: String, apiKey: String, model: String, applications: [String: String]? = nil) throws -> URLRequest {
        guard model.range(of: #"^gemini-[a-zA-Z0-9.-]+$"#, options: .regularExpression) != nil,
              !apiKey.isEmpty, !apiKey.contains(where: { $0.isNewline }) else {
            throw AdapterError.unavailable("Ungültige Gemini-Konfiguration.")
        }
        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!)
        request.httpMethod = "POST"; request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        var body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": text]]]],
            "systemInstruction": ["parts": [["text": "Du bist Friday, ein Mac-Assistent. Antworte direkt und knapp auf Deutsch, normalerweise in ein bis drei kurzen Sätzen, außer der Nutzer verlangt mehr Details. Dein Text wird vorgelesen: keine Markdown-Formatierung, keine Einleitung. Für Fragen, Erklärungen und Pläne gib Text zurück, keine Notiz anlegen, außer ausdrücklich verlangt. Für ausdrücklich angeforderte Computeraktionen nutze ausschließlich die angebotenen Funktionen (maximal drei). Ein App-Start darf nur eine installierte App verwenden. Behaupte keine ausgeführten Aktionen: Funktionen werden anschließend von Friday ausgeführt. Du hast keinen allgemeinen Terminal- oder Klick-Zugriff und keine Web-Recherche. Safari-Suche öffnet nur die Suchseite. Sage bei nicht unterstützten Aktionen klar, was fehlt."]]],
            "generationConfig": ["maxOutputTokens": 1024, "thinkingConfig": ["thinkingLevel": model.contains("flash-lite") ? "MINIMAL" : "LOW", "includeThoughts": false]]
        ]
        if let applications, !applications.isEmpty {
            func function(_ name: String, _ description: String, _ key: String, _ choices: [String]? = nil) -> [String: Any] {
                var property: [String: Any] = ["type": "STRING"]
                if let choices { property["enum"] = choices }
                return ["name": name, "description": description, "parameters": ["type": "OBJECT", "properties": [key: property], "required": [key]]]
            }
            body["tools"] = [["functionDeclarations": [
                function("open_application", "Installierte Mac-App öffnen oder aktivieren", "name", applications.keys.sorted()),
                function("search_safari", "Suchbegriff auf Google in Safari öffnen", "query"),
                function("create_note", "Ausdrücklich angeforderte Notiz lokal speichern", "text"),
                function("switch_desktop", "Zum benachbarten Mac-Schreibtisch wechseln", "direction", ["left", "right"])
            ]]]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private struct Reply: Decodable {
        struct Call: Decodable { let name: String; let args: [String: String] }
        struct Part: Decodable { let text: String?; let thought: Bool?; let functionCall: Call? }
        struct Content: Decodable { let parts: [Part]? }
        struct Candidate: Decodable { let content: Content? }
        let candidates: [Candidate]?
    }

    static func decodePlan(_ data: Data, status: Int, parser: ActionArgumentParser) throws -> ReasoningPlan {
        guard status == 200 else { _ = try decodeReply(data, status: status); throw AdapterError.invalidResponse("Ungültige Gemini-Antwort.") }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw AdapterError.invalidResponse("Ungültige Gemini-Antwort.") }
        let calls = (reply.candidates?.first?.content?.parts ?? []).filter { $0.thought != true }.compactMap(\.functionCall)
        guard !calls.isEmpty else { return .answer(try decodeReply(data, status: status)) }
        guard calls.count <= 3 else { throw AdapterError.unavailable("Gemini hat zu viele Computeraktionen angefordert.") }
        let actions = try calls.map { call -> ToolRequest in
            let action: ToolRequest
            switch call.name {
            case "open_application":
                guard Set(call.args.keys) == ["name"], let name = call.args["name"], let id = parser.applicationIdentifier(named: name) else { throw AdapterError.unavailable("Die von Gemini genannte App ist nicht eindeutig installiert.") }
                action = .openApplication(bundleIdentifier: id)
            case "search_safari":
                guard Set(call.args.keys) == ["query"], let query = call.args["query"] else { throw AdapterError.invalidResponse("Ungültige Safari-Aktion.") }
                action = .searchSafari(query: query)
            case "create_note":
                guard Set(call.args.keys) == ["text"], let text = call.args["text"], text.count <= 10_000 else { throw AdapterError.invalidResponse("Ungültige Notiz-Aktion.") }
                action = .createNote(text: text)
            case "switch_desktop":
                guard Set(call.args.keys) == ["direction"], let raw = call.args["direction"], let direction = DesktopDirection(rawValue: raw) else { throw AdapterError.invalidResponse("Ungültiger Schreibtischwechsel.") }
                action = .switchDesktop(direction: direction)
            default: throw AdapterError.unavailable("Diese Computeraktion ist noch nicht unterstützt.")
            }
            guard action.hasValidArguments else { throw AdapterError.invalidResponse("Ungültige Argumente für die Computeraktion.") }
            return action
        }
        return .actions(actions)
    }

    static func decodeReply(_ data: Data, status: Int) throws -> String {
        guard status == 200 else {
            // Never copy service error bodies, credentials or submitted text into errors.
            switch status {
            case 400, 401, 403: throw AdapterError.unavailable("Gemini hat den Schlüssel oder die Modell-Konfiguration abgelehnt.")
            case 429: throw AdapterError.unavailable("Gemini-Kontingent erreicht. Bitte später erneut versuchen.")
            case 500, 502, 503, 504: throw AdapterError.unavailable("Gemini ist gerade überlastet. Auch das Ersatzmodell konnte nicht antworten. Bitte erneut versuchen.")
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
