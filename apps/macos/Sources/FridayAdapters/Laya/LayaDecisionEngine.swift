import Foundation
import FridayCore

public struct LayaDecisionEngine: FastDecisionEngine {
    public let worker: JSONLineProcess
    private let parser: ActionArgumentParser

    public init(worker: JSONLineProcess, parser: ActionArgumentParser = ActionArgumentParser()) {
        self.worker = worker; self.parser = parser
    }

    private struct Request: Encodable { let id: String; let op = "decide"; let text: String }
    private struct Reply: Decodable { let intent: String; let confidence: Double; let truncated: Bool }

    public func decide(text: String) async throws -> FastDecision {
        let id = UUID().uuidString
        // Canonicalize only a complete, validated search command. Laya still
        // decides the intent; the parser later extracts the original query.
        let modelInput: String
        if case .searchSafari(let query) = parser.parse(intent: "search_web", text: text) {
            modelInput = "Bitte führe eine Websuche in Safari nach dem Suchbegriff \(query) aus."
        } else { modelInput = text }
        let data = try JSONEncoder().encode(Request(id: id, text: modelInput))
        let reply = try JSONDecoder().decode(Reply.self, from: await worker.request(data, id: id))
        guard !reply.truncated, reply.confidence.isFinite, (0...1).contains(reply.confidence) else {
            return FastDecision(intent: .unknown, confidence: 0)
        }
        if let action = parser.parse(intent: reply.intent, text: text) {
            return FastDecision(intent: .action(action), confidence: reply.confidence)
        }
        return FastDecision(intent: reply.intent == "reasoning" ? .reasoning : .unknown, confidence: reply.confidence)
    }
}
