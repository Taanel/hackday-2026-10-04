import Foundation
import FridayCore

/// Caches decisions, never effects/results/answers. The executor still resolves every target.
public actor CachedDecisionEngine: FastDecisionEngine {
    private struct Entry { let decision: FastDecision; let expires: ContinuousClock.Instant }
    private let engine: any FastDecisionEngine
    private let epoch: @Sendable () async -> UUID
    private let lifetime: Duration
    private var session: UUID?
    private var entries: [String: Entry] = [:]
    public init(engine: any FastDecisionEngine, lifetime: Duration = .seconds(300), epoch: @escaping @Sendable () async -> UUID) {
        self.engine = engine; self.lifetime = lifetime; self.epoch = epoch
    }
    public func decide(text: String) async throws -> FastDecision {
        try Task.checkCancellation()
        let current = await epoch()
        if session != current { entries = [:]; session = current }
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let entry = entries[key], entry.expires > .now { return entry.decision }
        let result = try await engine.decide(text: text)
        try Task.checkCancellation()
        let after = await epoch()
        if after != current { entries = [:]; session = after; return result }
        if result.confidence.isFinite, (0.85...1).contains(result.confidence),
           case .action(let request) = result.intent, request.hasValidArguments {
            if entries.count >= 64 { entries = entries.filter { $0.value.expires > .now }; if entries.count >= 64 { entries = [:] } }
            entries[key] = Entry(decision: result, expires: .now.advanced(by: lifetime))
        }
        return result
    }
}
