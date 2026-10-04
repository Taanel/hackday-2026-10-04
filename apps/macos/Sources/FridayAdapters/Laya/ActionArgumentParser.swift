import Foundation
import FridayCore

/// Laya selects the route. This parser accepts only a complete supported action.
public struct ActionArgumentParser: Sendable {
    public static let applications: [String: String] = [
        "safari": "com.apple.Safari", "chrome": "com.google.Chrome", "google chrome": "com.google.Chrome",
        "firefox": "org.mozilla.firefox", "finder": "com.apple.finder", "terminal": "com.apple.Terminal",
        "notizen": "com.apple.Notes", "notes": "com.apple.Notes", "kalender": "com.apple.iCal",
        "calendar": "com.apple.iCal", "rechner": "com.apple.calculator", "taschenrechner": "com.apple.calculator",
        "calculator": "com.apple.calculator", "musik": "com.apple.Music", "music": "com.apple.Music",
        "mail": "com.apple.mail", "vscode": "com.microsoft.VSCode", "visual studio code": "com.microsoft.VSCode",
        "slack": "com.tinyspeck.slackmacgap", "discord": "com.hnc.Discord", "claude": "com.anthropic.claudefordesktop"
    ]

    private let applicationAliases: [String: String]
    public init(applications: [String: String] = Self.applications) {
        applicationAliases = applications
    }

    public func parse(intent: String, text: String) -> ToolRequest? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch intent {
        case "search_web":
            guard let query = capture(#"^(?:bitte\s+)?(?:suche|such|google)\s+(?:nach\s+)?(.+?)\s+(?:auf|in|mit)\s+(?:dem\s+)?(?:safari|browser)[.!?]*$"#, text)
                ?? capture(#"^(?:bitte\s+)?(?:suche|such)\s+(?:auf|in|mit)\s+(?:dem\s+)?(?:safari|browser)\s+nach\s+(.+?)[.!?]*$"#, text),
                  !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  query.count <= 2_000,
                  query.range(of: #"\b(?:und|dann|danach)\s+(?:bitte\s+)?(?:öffne|starte|lösche|schließe|mach|erstelle|schreibe|führe)\b"#, options: [.regularExpression, .caseInsensitive]) == nil else { return nil }
            return .searchSafari(query: query)
        case "open_app":
            guard let name = capture(
                #"^(?:bitte\s+)?(?:(?:kannst|könntest)\s+du\s+(?:bitte\s+)?)?(?:öffne|oeffne|starte|open|launch)\s+(?:(?:das\s+programm|die\s+app|den|die|das)\s+)?(.+?)(?:\s+bitte)?[.!?]*$"#, text
            ) ?? capture(#"^(?:kannst|könntest)\s+du\s+(?:bitte\s+)?(.+?)\s+(?:öffnen|starten)[.!?]*$"#, text),
                  let identifier = applicationAliases[MacApplicationCatalog.normalize(name)] else { return nil }
            return .openApplication(bundleIdentifier: identifier)
        case "create_note":
            guard let content = capture(
                #"^(?:(?:bitte\s+)?(?:mach|mache|erstell|erstelle|schreib|schreibe)\s+(?:mir\s+)?(?:eine\s+)?(?:notiz|note)(?:\s+mit\s+(?:dem\s+)?(?:inhalt|text))?|notiz|note)(?:\s*[:,-]\s*|\s+)(.+)$"#, text
            ) ?? capture(#"^(?:notiere|merke)\s+(?:dir\s+)?(.+)$"#, text),
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  content.range(of: #"\b(?:und|dann|danach|außerdem)\s+(?:bitte\s+)?(?:öffne|starte|lösche|schließe|mach|erstelle|schreibe|führe)\b"#, options: [.regularExpression, .caseInsensitive]) == nil,
                  content.count <= 10_000 else { return nil }
            return .createNote(text: content)
        default: return nil
        }
    }

    private func capture(_ pattern: String, _ text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.range == NSRange(text.startIndex..., in: text),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
