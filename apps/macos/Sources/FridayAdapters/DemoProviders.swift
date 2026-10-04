import Foundation
import FridayCore

/// Deterministic examples to exercise the scaffold. This is not Laya inference.
public struct DemoDecisionEngine: FastDecisionEngine {
    public init() {}

    public func decide(text: String) async throws -> FastDecision {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()
        if normalized == "öffne safari" || normalized == "open safari" {
            return FastDecision(intent: .action(.openApplication(bundleIdentifier: "com.apple.Safari")), confidence: 1)
        }
        if normalized.hasPrefix("notiz:") {
            let body = String(trimmed.dropFirst("notiz:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return FastDecision(intent: .action(.createNote(text: body)), confidence: 1)
        }
        return FastDecision(intent: .reasoning, confidence: 1)
    }
}

public struct DemoReasoningEngine: ReasoningEngine {
    public init() {}

    public func respond(to text: String) async throws -> String {
        "LLM-Platzhalter: Diese Anfrage würde an das Reasoning-Modell gehen: \(text)"
    }
}

/// Shows an action's intended effect. No apps, notes or terminal commands are executed.
public struct PreviewToolExecutor: ToolExecutor {
    public init() {}

    public func execute(_ request: ToolRequest) async throws -> String {
        switch request {
        case .switchDesktop(let direction): "Vorschau: Schreibtischwechsel nach \(direction.rawValue)."
        case .findProject(let query): "Vorschau: Lokale Projektsuche nach \(query)."
        case .openApplication(let identifier):
            "Aktionsvorschau: Programm \(identifier) öffnen."
        case .createNote(let text):
            "Aktionsvorschau: Notiz anlegen: \(text)"
        case .searchSafari(let query):
            "Aktionsvorschau: Safari-Suche nach \(query)"
        case .runExecutable(let command):
            "Aktionsvorschau: \(command.executablePath) mit \(command.arguments.count) Argumenten ausführen."
        }
    }
}
