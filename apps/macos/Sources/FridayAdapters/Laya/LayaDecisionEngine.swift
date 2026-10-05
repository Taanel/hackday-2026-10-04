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
        let localIntents = ["home_control", "open_folder", "open_url", "find_project", "search_web", "switch_desktop", "open_app", "create_note"]
        let candidate = localIntents.first { parser.parse(intent: $0, text: text) != nil }
        let names = ["home_control": "Home Assistant", "open_folder": "Ordner öffnen", "open_url": "Webseite öffnen", "find_project": "Lokale Suche", "search_web": "Safari-Suche", "switch_desktop": "Schreibtisch wechseln", "open_app": "App öffnen", "create_note": "Notiz speichern"]
        let localSummary = candidate.flatMap { names[$0] }
        // Canonicalize only a complete, validated search command. Laya still
        // decides the intent; the parser later extracts the original query.
        let modelInput: String
        if case .homeAssistant = parser.parse(intent: "home_control", text: text) {
            modelInput = "Steuere ein Smart-Home-Gerät mit Home Assistant: " + text
        } else if case .openFolder = parser.parse(intent: "open_folder", text: text) {
            modelInput = "Öffne einen lokalen Finder-Ordner auf diesem Mac: " + text
        } else if case .openURL = parser.parse(intent: "open_url", text: text) {
            modelInput = "Öffne eine konkrete Webseiten-Adresse im Browser: " + text
        } else if case .findSafariTab(let query, _) = parser.parse(intent: "find_project", text: text) {
            modelInput = "Finde das bereits geöffnete Projekt \(query) in einem lokalen Safari-Tab."
        } else if case .findProject(let query) = parser.parse(intent: "find_project", text: text) {
            modelInput = "Finde das bereits geöffnete Projekt \(query) in einem lokalen Fenster oder Terminal-Tab auf diesem Mac."
        } else if case .findLocalItem(let query, let kind) = parser.parse(intent: "find_project", text: text) {
            modelInput = "Suche eine vorhandene \(kind == .folder ? "Projektmappe" : "Projektdatei") mit dem Namen \(query) auf diesem Mac."
        } else if case .searchSafari(let query) = parser.parse(intent: "search_web", text: text) {
            modelInput = "Bitte führe eine Websuche in Safari nach dem Suchbegriff \(query) aus."
        } else if case .switchDesktop(let direction) = parser.parse(intent: "switch_desktop", text: text) {
            modelInput = "Wechsle den macOS-Schreibtisch nach \(direction == .left ? "links" : "rechts")."
        } else if case .openApplication(let identifier) = parser.parse(intent: "open_app", text: text) {
            modelInput = "Öffne die installierte App \(identifier) auf diesem Mac."
        } else if case .createNote = parser.parse(intent: "create_note", text: text) {
            // Classify the requested operation, not the contents of the note.
            modelInput = "Schreibe eine Notiz mit dem diktierten Text."
        } else { modelInput = text }
        let data = try JSONEncoder().encode(Request(id: id, text: modelInput))
        let reply: Reply
        do { reply = try JSONDecoder().decode(Reply.self, from: await worker.request(data, id: id)) }
        catch is CancellationError { throw CancellationError() }
        catch {
            if candidate != nil { throw LocalDecisionFailure("Laya ist für diesen lokalen Auftrag gerade nicht verfügbar. Gemini wurde dafür nicht aufgerufen. Bitte erneut versuchen.") }
            throw error
        }
        guard !reply.truncated, reply.confidence.isFinite, (0...1).contains(reply.confidence) else {
            return FastDecision(intent: .unknown, confidence: 0, allowsReasoningFallback: candidate == nil, summary: localSummary)
        }
        if let candidate, candidate != reply.intent {
            return FastDecision(intent: .unknown, confidence: reply.confidence, allowsReasoningFallback: false, summary: "\(localSummary ?? "Lokaler Auftrag") · Modellzuordnung widersprüchlich")
        }
        if let action = parser.parse(intent: reply.intent, text: text) {
            return FastDecision(intent: .action(action), confidence: reply.confidence, allowsReasoningFallback: candidate == nil, summary: names[reply.intent])
        }
        return FastDecision(intent: reply.intent == "reasoning" ? .reasoning : .unknown, confidence: reply.confidence,
                            summary: reply.intent == "reasoning" ? "Frage / Erklärung" : "Keine vollständige lokale Aktion erkannt")
    }
}
