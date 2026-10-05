import Foundation
import Darwin
import FridayCore
import FridayAdapters

private struct Case: Decodable { let text: String; let expectedRoute: String; let expectedTool: String?; let intent: String? }
private struct Result: Encodable {
    let text: String; let route: String; let correct: Bool; let milliseconds: Double; let localIntent: String; let confidence: Double
}
private actor ObservedDecisions: FastDecisionEngine {
    let engine: LayaDecisionEngine
    var last: FastDecision?
    init(engine: LayaDecisionEngine) { self.engine = engine }
    func decide(text: String) async throws -> FastDecision { let decision = try await engine.decide(text: text); last = decision; return decision }
    func snapshot() -> (String, Double) {
        guard let last else { return ("error", 0) }
        let name: String
        switch last.intent {
        case .unknown: name = "unknown"
        case .reasoning: name = "reasoning"
        case .action(let request):
            switch request {
            case .homeAssistant: name = "home_control"
            case .openApplication: name = "open_app"
            case .createNote: name = "create_note"
            case .searchSafari: name = "search_web"
            case .switchDesktop: name = "switch_desktop"
            case .findProject, .findSafariTab, .findLocalItem: name = "find_project"
            case .openFolder: name = "open_folder"
            case .openURL: name = "open_url"
            case .runExecutable: name = "unknown"
            }
        }
        return (name, last.confidence)
    }
}
private struct CaptureTools: ToolExecutor {
    func execute(_ request: ToolRequest) async throws -> String {
        switch request {
        case .findLocalItem: "findLocalItem"
        case .findSafariTab: "findSafariTab"
        case .findProject: "findProject"
        default: "other"
        }
    }
}
private struct OfflineReasoning: ReasoningEngine {
    func respond(to text: String) async throws -> String { "Fallback aufgezeichnet; keine API-Anfrage." }
}

@main struct EvaluateLocalRouting {
    static func main() async throws {
        guard CommandLine.arguments.count == 3 else { throw NSError(domain: "Usage: evaluate-local-routing <repo> <jsonl>", code: 1) }
        let repo = CommandLine.arguments[1]
        let cases = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8).split(separator: "\n")
            .map { try JSONDecoder().decode(Case.self, from: Data($0.utf8)) }
        var configuration = try RuntimeConfiguration.load()
        configuration.workerDirectory = repo + "/services/local-runtime/src"
        let worker = configuration.worker("laya")
        let decisions = ObservedDecisions(engine: LayaDecisionEngine(worker: worker, parser: ActionArgumentParser(applications: MacApplicationCatalog.aliases())))
        let router = AssistantRouter(
            decisions: decisions,
            reasoning: OfflineReasoning(), tools: CaptureTools(), minimumConfidence: 0.75)
        do {
            _ = try await worker.start() // Warmup is excluded from per-command measurements.
            var failures = 0
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            for item in cases {
                let start = ContinuousClock.now
                let response = try await router.handle(item.text)
                let elapsed = start.duration(to: .now).components
                let (intent, confidence) = await decisions.snapshot()
                let correct = response.route.rawValue == item.expectedRoute && (item.expectedTool == nil || item.expectedTool == response.text)
                    && (item.expectedRoute != "fastAction" || item.intent == nil || item.intent == intent)
                if !correct { failures += 1 }
                let result = Result(text: item.text, route: response.route.rawValue, correct: correct,
                                    milliseconds: Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15, localIntent: intent, confidence: confidence)
                print(String(decoding: try encoder.encode(result), as: UTF8.self))
            }
            await worker.stop()
            print("\(cases.count - failures)/\(cases.count) korrekte Routen; keine Computer-/HA-Aktionen und keine Cloud-Aufrufe.")
            if failures > 0 { exit(1) }
        } catch { await worker.stop(); throw error }
    }
}
