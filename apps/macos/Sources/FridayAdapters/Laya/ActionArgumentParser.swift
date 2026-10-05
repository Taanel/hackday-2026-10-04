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
        applicationAliases = Dictionary(grouping: applications, by: { MacApplicationCatalog.normalize($0.key) })
            .compactMapValues { entries in
                let ids = Set(entries.map(\.value))
                return ids.count == 1 ? ids.first : nil
            }
    }

    public func applicationIdentifier(named name: String) -> String? {
        let key = MacApplicationCatalog.normalize(name)
        if let exact = applicationAliases[key] { return exact }
        guard key.count >= 5 else { return nil }
        let limit = key.count >= 10 ? 2 : 1
        let candidates = applicationAliases.compactMap { alias, identifier -> (Int, String)? in
            guard abs(alias.count - key.count) <= limit else { return nil }
            let distance = Self.editDistance(key, alias)
            return distance <= limit ? (distance, identifier) : nil
        }
        guard let best = candidates.map(\.0).min() else { return nil }
        let identifiers = Set(candidates.filter { $0.0 == best }.map(\.1))
        return identifiers.count == 1 ? identifiers.first : nil
    }

    private static func editDistance(_ left: String, _ right: String) -> Int {
        let a = Array(left), b = Array(right)
        var row = Array(0...b.count)
        for (i, letter) in a.enumerated() {
            var next = [i + 1] + Array(repeating: 0, count: b.count)
            for (j, other) in b.enumerated() {
                next[j + 1] = min(row[j + 1] + 1, next[j] + 1, row[j] + (letter == other ? 0 : 1))
            }
            row = next
        }
        return row[b.count]
    }

    public func parse(intent: String, text: String) -> ToolRequest? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch intent {
        case "home_control":
            return HomeAssistantCommandParser.parse(text).map(ToolRequest.homeAssistant)
        case "open_folder":
            guard let name = capture(#"^(?:bitte\s+)?(?:öffne|oeffne|zeige|zeig)\s+(?:bitte\s+)?(?:(?:den|die|das|meinen|meine)\s+)?(?:ordner\s+)?(downloads|dokumente|documents|schreibtisch|desktop|home|benutzerordner)(?:\s+ordner)?(?:\s+im\s+finder)?[.!?]*$"#, text) else { return nil }
            let names: [String: MacFolder] = ["downloads": .downloads, "dokumente": .documents, "documents": .documents, "schreibtisch": .desktop, "desktop": .desktop, "home": .home, "benutzerordner": .home]
            return names[name.lowercased()].map(ToolRequest.openFolder)
        case "open_url":
            guard let address = capture(#"^(?:bitte\s+)?(?:öffne|oeffne|besuche|geh\s+auf|gehe\s+auf)\s+(?:bitte\s+)?((?:https?://|www\.)[^\s]+?)(?:\s+im\s+browser)?[!?]*$"#, text),
                  let url = URL(string: address.hasPrefix("www.") ? "https://" + address : address), ToolRequest.openURL(url).hasValidArguments else { return nil }
            return .openURL(url)
        case "find_project":
            if let expression = try? NSRegularExpression(pattern: #"^(?:bitte\s+)?(?:finde|such|suche|zeige|zeig)\b.*?\bsafari[\s-]*tab\b.*?\b(?:mit|zu|nach)\s+(?:(?:dem\s+|der\s+)?(inhalt|seite)\s+)?(.+?)(?:\s+(?:offen|raus))?[.!?]*$"#, options: .caseInsensitive),
               let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 2), in: text) {
                let query = String(text[range])
                let contents = Range(match.range(at: 1), in: text).map { String(text[$0]).lowercased() == "inhalt" } ?? false
                let request = ToolRequest.findSafariTab(query: query, searchContents: contents)
                if request.hasValidArguments { return request }
            }
            guard let query = capture(#"^(?:bitte\s+)?(?:(?:kannst|könntest)\s+du\s+(?:bitte\s+)?)?(?:finde|such|suche|zeige|zeig|wo)\b.*?\b(?:projekt|project)\s+[„\"']?(.+?)[”\"']?(?:\s+(?:offen|geöffnet|raus)(?:\s+.*)?)?[.!?]*$"#, text),
                  text.range(of: #"\b(?:safari|google|web|internet)\b"#, options: [.regularExpression, .caseInsensitive]) == nil,
                  query.range(of: #"\b(?:und|dann|danach)\s+(?:öffne|lösche|starte|mach|schließe)\b"#, options: [.regularExpression, .caseInsensitive]) == nil,
                  ToolRequest.findProject(query: query).hasValidArguments else { return nil }
            return .findProject(query: query)
        case "search_web":
            // Opening Safari is already part of searchSafari. Treat this
            // common spoken combination as one action, keeping only the query.
            guard let query = capture(#"^(?:bitte\s+)?(?:öffne|oeffne|starte|open)\s+(?:bitte\s+)?(?:den\s+)?(?:safari|browser)\s*[,;]?\s+(?:und\s+(?:dann\s+)?|dann\s+)(?:bitte\s+)?(?:suche|such|google)\s+(?:bitte\s+)?(?:nach\s+)?(.+?)[.!?]*$"#, text)
                ?? capture(#"^(?:bitte\s+)?(?:suche|such|google)\s+(?:bitte\s+)?(?:nach\s+)?(.+?)\s+(?:auf|in|mit)\s+(?:dem\s+)?(?:safari|browser)[.!?]*$"#, text)
                ?? capture(#"^(?:bitte\s+)?(?:suche|such)\s+(?:bitte\s+)?(?:auf|in|mit)\s+(?:dem\s+)?(?:safari|browser)\s+nach\s+(.+?)[.!?]*$"#, text)
                ?? capture(#"^(?:bitte\s+)?(?:suche|such|google)\s+(?:bitte\s+)?(?:nach\s+)?(.+?)[.!?]*$"#, text),
                  !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  query.count <= 2_000,
                  query.range(of: #"\b(?:und|dann|danach)\s+(?:bitte\s+)?(?:öffne|starte|lösche|schließe|mach|erstelle|schreibe|führe|suche|google)\b"#, options: [.regularExpression, .caseInsensitive]) == nil else { return nil }
            return .searchSafari(query: query)
        case "open_app":
            guard let name = capture(
                #"^(?:bitte\s+)?(?:(?:kannst|könntest)\s+du\s+(?:bitte\s+)?)?(?:öffne|oeffne|starte|open|launch)\s+(?:bitte\s+)?(?:(?:das\s+programm|die\s+app|den|die|das)\s+)?(.+?)(?:\s+(?:bitte|für\s+mich))?[.!?]*$"#, text
            ) ?? capture(#"^(?:kannst|könntest)\s+du\s+(?:bitte\s+)?(.+?)(?:\s+für\s+mich)?\s+(?:öffnen|starten)[.!?]*$"#, text)
              ?? capture(#"^(?:bitte\s+)?(?:mach|mache)\s+(?:bitte\s+)?(.+?)\s+auf[.!?]*$"#, text)
              ?? capture(#"^(?:bitte\s+)?(.+?)\s+(?:öffnen|starten)(?:\s*,?\s+bitte)?[.!?]*$"#, text),
                  let identifier = applicationIdentifier(named: name) else { return nil }
            return .openApplication(bundleIdentifier: identifier)
        case "switch_desktop":
            let pattern = #"^(?:bitte\s+)?(?:wechsel|wechsle|wechsele|geh|gehe)\s+(?:bitte\s+)?(?:(?:zum|auf\s+den|zu\s+dem|den)\s+)?(?:(nächsten|vorherigen|linken|rechten)\s+)?(?:schreibtisch|desktop)(?:\s+nach\s+(links|rechts))?[.!?]*$"#
            guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
            let words = (1...2).compactMap { index in Range(match.range(at: index), in: text).map { String(text[$0]).lowercased() } }
            return .switchDesktop(direction: words.contains(where: { ["links", "linken", "vorherigen"].contains($0) }) ? .left : .right)
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
