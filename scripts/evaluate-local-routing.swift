import Foundation
import Darwin
import FridayCore
import FridayAdapters

private struct Case: Decodable { let text: String; let expectedRoute: String }
private struct Result: Encodable {
    let text: String; let route: String; let correct: Bool; let milliseconds: Double
}
private struct CaptureTools: ToolExecutor {
    func execute(_ request: ToolRequest) async throws -> String { "Validiertes Tool aufgezeichnet; kein Gerät/Programm wird bedient." }
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
        let router = AssistantRouter(
            decisions: LayaDecisionEngine(worker: worker, parser: ActionArgumentParser(applications: MacApplicationCatalog.aliases())),
            reasoning: OfflineReasoning(), tools: CaptureTools(), minimumConfidence: 0.75)
        do {
            _ = try await worker.start() // Warmup is excluded from per-command measurements.
            var failures = 0
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            for item in cases {
                let start = ContinuousClock.now
                let response = try await router.handle(item.text)
                let elapsed = start.duration(to: .now).components
                let correct = response.route.rawValue == item.expectedRoute
                if !correct { failures += 1 }
                let result = Result(text: item.text, route: response.route.rawValue, correct: correct,
                                    milliseconds: Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
                print(String(decoding: try encoder.encode(result), as: UTF8.self))
            }
            await worker.stop()
            print("\(cases.count - failures)/\(cases.count) korrekte Routen; keine Computer-/HA-Aktionen und keine Cloud-Aufrufe.")
            if failures > 0 { exit(1) }
        } catch { await worker.stop(); throw error }
    }
}
