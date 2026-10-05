import Foundation
import FridayCore

enum LocalLookupCommandParser {
    static func parse(_ original: String) -> ToolRequest? {
        let text = original.replacingOccurrences(of: #"^(?:(?:jo|ey|hey)\s*,?\s+)?(?:(?:kannst|könntest)\s+du\s+)?(?:bitte\s+)?"#, with: "", options: [.regularExpression, .caseInsensitive])
        let prefix = #"^(?:finde|such|suche|zeige|zeig)\s+(?:mir\s+)?(?:bitte\s+)?(?:mal\s+)?(?:(?:den|die|das|meinen|meine|einen|eine)\s+)?"#
        let fileTail = #"(?:\s+(?:raus|heraus))?(?:\s*,?\s+und\s+(?:öffne|oeffne|zeige|zeig)\s+(?:sie|ihn)(?:\s+mir)?(?:\s+mal)?(?:\s+im\s+finder)?)?(?:\s+im\s+finder)?[!?]*$"#
        if let parts = captures(prefix + #"(datei|ordner)\s+(?:namens\s+)?(.+?)"# + fileTail, text), parts.count == 2 {
            return item(parts[1], kind: parts[0].lowercased() == "ordner" ? .folder : .file)
        }
        if let parts = captures(#"^(?:such|suche|finde)\s+(?:mir\s+)?(?:bitte\s+)?(?:mal\s+)?(?:raus\s*,?\s*)?wo\s+(?:der|mein)\s+ordner\s+(.+?)\s+ist(?:\s*,?\s+und\s+(?:mach|mache)\s+(?:mir\s+)?(?:den|ihn)\s+(?:im\s+finder\s+)?auf)?[.!?]*$"#, text) {
            return item(parts[0], kind: .folder)
        }
        // A plain "Tab" refers to Safari; explicit Terminal tabs use project lookup.
        if let parts = captures(prefix + #"terminal[\s-]*tab\s+(?:raus\s*,?\s*)?(?:wo|in\s+dem)\s+(?:ich\s+)?(?:projekt\s+)?(.+?)\s+(?:offen|geöffnet)(?:\s+habe|\s+ist)?[.!?]*$"#, text) {
            let query = clean(parts[0])
            let request = ToolRequest.findProject(query: query)
            return safe(query) && request.hasValidArguments ? request : nil
        }
        if let parts = captures(prefix + #"(?:bereits\s+offenen\s+|offenen\s+)?(?:safari[\s-]*)?tab\s+(?:raus\s*,?\s*)?(?:wo|in\s+dem|auf\s+dem)\s+(?:ich\s+)?(.+?)\s+(?:offen|geöffnet)(?:\s+habe|\s+ist)?[.!?]*$"#, text) {
            return tab(parts[0], contents: true)
        }
        if let parts = captures(prefix + #"(?:bereits\s+offenen\s+|offenen\s+)?(?:safari[\s-]*)?tab\s+(?:raus\s+)?(?:mit|zu|nach)\s+(?:(?:dem|der)\s+)?(?:(inhalt|seite)\s+)?(.+?)(?:\s+(?:offen|raus))?[.!?]*$"#, text) {
            return tab(parts[1], contents: parts[0].lowercased() == "inhalt")
        }
        return nil
    }

    private static func clean(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasSuffix(".") { value.removeLast() }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "„“”\"'"))
    }
    private static func safe(_ query: String) -> Bool {
        query.range(of: #"\b(?:und|dann|danach)\s+(?:bitte\s+)?(?:öffne|oeffne|lösche|starte|mach|mache|schließe|suche|such|zeige|zeig)\b"#, options: [.regularExpression, .caseInsensitive]) == nil
    }
    private static func item(_ text: String, kind: LocalItemKind) -> ToolRequest? {
        let query = clean(text)
        let request = ToolRequest.findLocalItem(query: query, kind: kind)
        return safe(query) && request.hasValidArguments ? request : nil
    }
    private static func tab(_ text: String, contents: Bool) -> ToolRequest? {
        let query = clean(text)
        let request = ToolRequest.findSafariTab(query: query, searchContents: contents)
        return safe(query) && request.hasValidArguments ? request : nil
    }
    private static func captures(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }
}
