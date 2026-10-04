import Foundation
import Testing
@testable import FridayCore

private enum StubError: Error { case unavailable }

private actor DecisionStub: FastDecisionEngine {
    enum Behavior: Sendable { case decision(FastDecision), failure, cancellation }
    let behavior: Behavior
    private(set) var calls = 0
    init(_ behavior: Behavior) { self.behavior = behavior }

    func decide(text: String) async throws -> FastDecision {
        calls += 1
        switch behavior {
        case .decision(let decision): return decision
        case .failure: throw StubError.unavailable
        case .cancellation: throw CancellationError()
        }
    }
}

private actor ReasoningSpy: ReasoningEngine {
    private(set) var calls = 0
    func respond(to text: String) async throws -> String {
        calls += 1
        return "Reasoning: \(text)"
    }
}

private actor ToolSpy: ToolExecutor {
    private(set) var requests: [ToolRequest] = []
    let fails: Bool
    init(fails: Bool = false) { self.fails = fails }
    func execute(_ request: ToolRequest) async throws -> String {
        requests.append(request)
        if fails { throw StubError.unavailable }
        return "Tool completed"
    }
}

@Test func confidentActionUsesToolWithoutReasoning() async throws {
    let request = ToolRequest.openApplication(bundleIdentifier: "com.apple.Safari")
    let decisions = DecisionStub(.decision(FastDecision(intent: .action(request), confidence: 0.95)))
    let reasoning = ReasoningSpy()
    let tools = ToolSpy()
    let router = AssistantRouter(decisions: decisions, reasoning: reasoning, tools: tools)
    let response = try await router.handle("Öffne Safari")
    #expect(response.route == .fastAction)
    #expect(await tools.requests == [request])
    #expect(await reasoning.calls == 0)
}

@Test(arguments: [0.2, Double.nan, Double.infinity, 1.1, -0.1])
func uncertainOrInvalidConfidenceFallsBack(confidence: Double) async throws {
    let decisions = DecisionStub(.decision(FastDecision(intent: .action(.createNote(text: "Milch")), confidence: confidence)))
    let reasoning = ReasoningSpy()
    let tools = ToolSpy()
    let router = AssistantRouter(decisions: decisions, reasoning: reasoning, tools: tools)
    let response = try await router.handle("Notiz: Milch")
    #expect(response.route == .reasoning)
    #expect(await reasoning.calls == 1)
    #expect(await tools.requests.isEmpty)
}

@Test func invalidArgumentsFallBackWithoutToolExecution() async throws {
    let decisions = DecisionStub(.decision(FastDecision(intent: .action(.createNote(text: "  ")), confidence: 1)))
    let tools = ToolSpy()
    let router = AssistantRouter(decisions: decisions, reasoning: ReasoningSpy(), tools: tools)
    #expect(try await router.handle("Notiz:").route == .reasoning)
    #expect(await tools.requests.isEmpty)
}

@Test func classifierFailureUsesReasoning() async throws {
    let router = AssistantRouter(decisions: DecisionStub(.failure), reasoning: ReasoningSpy(), tools: ToolSpy())
    let response = try await router.handle("Plane den Tag")
    #expect(response == AssistantResponse(text: "Reasoning: Plane den Tag", route: .reasoning))
}

@Test func reasoningAndUnknownIntentsFallBack() async throws {
    for intent in [DecisionIntent.reasoning, .unknown] {
        let tools = ToolSpy()
        let router = AssistantRouter(
            decisions: DecisionStub(.decision(FastDecision(intent: intent, confidence: 1))),
            reasoning: ReasoningSpy(), tools: tools
        )
        #expect(try await router.handle("Recherchiere zum Punkt XY").route == .reasoning)
        #expect(await tools.requests.isEmpty)
    }
}

@Test func dictationPreservesTextAndBypassesModelsAndTools() async throws {
    let decisions = DecisionStub(.failure)
    let reasoning = ReasoningSpy()
    let tools = ToolSpy()
    let router = AssistantRouter(decisions: decisions, reasoning: reasoning, tools: tools)
    let text = "  Öffne Safari und schreibe eine Notiz.\n"
    let response = try await router.handle(text, mode: .dictation)
    #expect(response == AssistantResponse(text: text, route: .dictation))
    #expect(await decisions.calls == 0)
    #expect(await reasoning.calls == 0)
    #expect(await tools.requests.isEmpty)
}

@Test func cancellationDoesNotTriggerFallback() async throws {
    let reasoning = ReasoningSpy()
    let router = AssistantRouter(decisions: DecisionStub(.cancellation), reasoning: reasoning, tools: ToolSpy())
    await #expect(throws: CancellationError.self) { try await router.handle("Öffne Safari") }
    #expect(await reasoning.calls == 0)
}

@Test func toolFailureDoesNotRetryViaReasoning() async throws {
    let reasoning = ReasoningSpy()
    let tools = ToolSpy(fails: true)
    let router = AssistantRouter(
        decisions: DecisionStub(.decision(FastDecision(intent: .action(.createNote(text: "Milch")), confidence: 1))),
        reasoning: reasoning, tools: tools
    )
    await #expect(throws: StubError.self) { try await router.handle("Notiz: Milch") }
    #expect(await tools.requests.count == 1)
    #expect(await reasoning.calls == 0)
}

@Test func emptyInputFailsBeforeAnyProviderCall() async throws {
    let decisions = DecisionStub(.failure)
    let router = AssistantRouter(decisions: decisions, reasoning: ReasoningSpy(), tools: ToolSpy())
    await #expect(throws: FridayError.self) { try await router.handle(" \n") }
    #expect(await decisions.calls == 0)
}
