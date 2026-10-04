import Foundation

public struct AssistantRouter: Sendable {
    private let decisions: any FastDecisionEngine
    private let reasoning: any ReasoningEngine
    private let tools: any ToolExecutor
    private let minimumConfidence: Double

    public init(
        decisions: any FastDecisionEngine,
        reasoning: any ReasoningEngine,
        tools: any ToolExecutor,
        minimumConfidence: Double = 0.85
    ) {
        precondition(minimumConfidence.isFinite && (0...1).contains(minimumConfidence))
        self.decisions = decisions
        self.reasoning = reasoning
        self.tools = tools
        self.minimumConfidence = minimumConfidence
    }

    public func handle(
        _ text: String,
        mode: InputMode = .assistant,
        onPhase: @Sendable (AssistantPhase) async -> Void = { _ in }
    ) async throws -> AssistantResponse {
        try Task.checkCancellation()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FridayError.emptyInput
        }
        // Dictation must not reinterpret a spoken sentence as a computer command.
        if mode == .dictation {
            return AssistantResponse(text: text, route: .dictation)
        }

        let decision: FastDecision
        await onPhase(.deciding)
        try Task.checkCancellation()
        do {
            decision = try await decisions.decide(text: text)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await fallback(text, onPhase: onPhase)
        }

        try Task.checkCancellation()
        if decision.confidence.isFinite,
           (0...1).contains(decision.confidence),
           decision.confidence >= minimumConfidence,
           case .action(let request) = decision.intent,
           request.hasValidArguments {
            // Tool failures propagate: do not repeat a potentially completed action via an LLM.
            await onPhase(.acting)
            try Task.checkCancellation()
            let result = try await tools.execute(request)
            try Task.checkCancellation()
            return AssistantResponse(text: result, route: .fastAction)
        }
        return try await fallback(text, onPhase: onPhase)
    }

    private func fallback(
        _ text: String, onPhase: @Sendable (AssistantPhase) async -> Void
    ) async throws -> AssistantResponse {
        try Task.checkCancellation()
        await onPhase(.reasoning)
        try Task.checkCancellation()
        if let planner = reasoning as? any ActionPlanningReasoningEngine {
            let plan = try await planner.plan(to: text)
            try Task.checkCancellation()
            switch plan {
            case .answer(let answer):
                return AssistantResponse(text: answer, route: .reasoning)
            case .actions(let actions):
                guard (1...3).contains(actions.count), actions.allSatisfy({ request in
                    if case .runExecutable = request { return false }
                    return request.hasValidArguments
                }), actions.enumerated().allSatisfy({ index, action in !actions.prefix(index).contains(action) }) else {
                    throw FridayError.invalidActionPlan
                }
                var results: [String] = []
                await onPhase(.acting)
                for action in actions {
                    try Task.checkCancellation()
                    results.append(try await tools.execute(action))
                }
                try Task.checkCancellation()
                return AssistantResponse(text: results.joined(separator: "\n"), route: .fastAction)
            }
        }
        let result = try await reasoning.respond(to: text)
        try Task.checkCancellation()
        return AssistantResponse(text: result, route: .reasoning)
    }
}
