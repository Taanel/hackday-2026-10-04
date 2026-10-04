import Foundation
import FridayCore

public struct OllamaReasoningEngine: ReasoningEngine {
    public let model: String
    public init(model: String) { self.model = model }

    private struct Message: Codable { let role: String; let content: String }
    private struct Request: Encodable { let model: String; let messages: [Message]; let stream = false; let think = false }
    private struct Reply: Decodable { let message: Message?; let error: String? }

    public func respond(to text: String) async throws -> String {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/chat")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Request(model: model, messages: [
            Message(role: "system", content: "Du bist Friday, ein lokaler Mac-Assistent. Antworte knapp auf Deutsch. Du hast hier keine Web-Suche und keine Computerwerkzeuge. Behaupte niemals Programme geöffnet, Notizen gespeichert oder aktuelle Quellen recherchiert zu haben. Wenn eine gewünschte Computeraktion nicht unterstützt wird, erkläre das und führe sie nicht aus. Gib bei Planungsfragen einen hilfreichen Plan. Keine internen Thinking-Tokens ausgeben."),
            Message(role: "user", content: text)
        ]))
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            let reply = try JSONDecoder().decode(Reply.self, from: data)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let content = reply.message?.content, !content.isEmpty else {
                throw AdapterError.unavailable(reply.error ?? "Ollama hat keine Antwort geliefert.")
            }
            return content
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch let error as AdapterError { throw error }
        catch { throw AdapterError.unavailable("Lokales LLM nicht erreichbar. Ollama starten und das konfigurierte Modell laden.") }
    }
}
