import Foundation
import FridayCore

/// Parses a single explicit device command, not explanations or future conditions.
public enum HomeAssistantCommandParser {
    public static func parse(_ text: String) -> HomeAssistantAction? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard HomeAssistantAction.isImmediateRequest(clean) else { return nil }
        func captures(_ pattern: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let m = regex.firstMatch(in: clean, range: NSRange(clean.startIndex..., in: clean)),
                  m.range == NSRange(clean.startIndex..., in: clean) else { return nil }
            return (1..<m.numberOfRanges).compactMap { Range(m.range(at: $0), in: clean).map { String(clean[$0]) } }
        }
        let prefix = #"^(?:bitte\s+)?(?:(?:kannst|könntest)\s+du\s+(?:bitte\s+)?)?"#
        let action: HomeAssistantAction?
        if let c = captures(prefix + #"(?:schalte|schalt|mach|mache)\s+(?:bitte\s+)?(?:das\s+|die\s+|den\s+)?(.+?)\s+(an|ein|aus|einschalten|ausschalten)(?:\s+bitte)?[.!?]*$"#), c.count == 2 {
            action = HomeAssistantAction(target: c[0], operation: c[1].lowercased().hasPrefix("aus") ? .turnOff : .turnOn)
        } else if let c = captures(prefix + #"(?:aktiviere|aktivier|starte)\s+(?:bitte\s+)?(?:die\s+)?szene\s+(.+?)[.!?]*$"#), c.count == 1 {
            action = HomeAssistantAction(target: c[0], operation: .activateScene)
        } else if let c = captures(prefix + #"(?:dimme|dimm|stelle|stell|setze|setz)\s+(?:bitte\s+)?(?:das\s+|die\s+|den\s+)?(.+?)\s+auf\s+(\d{1,3}(?:[.,]\d)?)\s*(prozent|%|grad(?:\s+celsius)?|°c)[.!?]*$"#), c.count == 3,
                  let value = Double(c[1].replacingOccurrences(of: ",", with: ".")) {
            action = HomeAssistantAction(target: c[0], operation: ["prozent", "%"].contains(c[2].lowercased()) ? .brightness : .temperature, value: value)
        } else if let c = captures(#"^(?:bitte\s+)?(.+?)\s+(an|ein|aus|einschalten|ausschalten)(?:\s+bitte)?[.!?]*$"#), c.count == 2,
                  c[0].range(of: #"^(?:warum|wieso|weshalb|wie|was|wer|wo|wann|welche\w*|ist|sind|ob|ich|erklär\w*|erzähl\w*|kann\w*|könnt\w*|suche?|öffne|starte|notiz|notiere|schreibe|sage?)\b"#, options: [.regularExpression, .caseInsensitive]) == nil {
            action = HomeAssistantAction(target: c[0], operation: c[1].lowercased().hasPrefix("aus") ? .turnOff : .turnOn)
        } else { action = nil }
        return action.flatMap { $0.isValid ? $0 : nil }
    }
}
