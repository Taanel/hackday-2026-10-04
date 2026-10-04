import Foundation
import FridayCore

public struct LayaDecisionEngine: FastDecisionEngine {
    public let worker: JSONLineProcess
    private let parser = ActionArgumentParser()

    public init(worker: JSONLineProcess) { self.worker = worker }

    private struct Request: Encodable { let id: String; let op = "decide"; let text: String }
    private struct Reply: Decodable { let intent: String; let confidence: Double; let truncated: Bool }

    public func decide(text: String) async throws -> FastDecision {
        let id = UUID().uuidString
        let data = try JSONEncoder().encode(Request(id: id, text: text))
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
