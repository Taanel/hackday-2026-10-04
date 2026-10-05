import Foundation

/// Normalize only the command prefix. Note contents / search terms are preserved.
/// This does not turn explanations, conditions or future requests into actions.
enum SpokenCommandText {
    static func normalize(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        value = replacing(#"^(?:(?:hey|hi|hei|jo|ey|okay|ok)\s*[,!]\s*|(?:hey|hi|hei)\s+(?:friday|frida|freda|freitag)\s*[,!:]?\s*|(?:hey|hi|jo|ey)\s+)"#, in: value, with: "")
        value = replacing(#"^(?:bitte\s+)?(?:(?:kannst|könntest|würdest)\s+du\s+)(?:(?:mir|bitte|mal|eben|kurz|doch)\s+)*"#, in: value, with: "")
        value = replacing(#"^(?:(?:bitte|mal|eben|kurz)\s+)+(?=(?:öffne|oeffne|starte|mach|mache|schalt|schalte|stell|stelle|setz|setze|dimm|dimme|suche?|google|wechsel\w*|notier\w*|schreib\w*|erstell\w*|finde|zeige|zeig)\b)"#, in: value, with: "")
        value = replacing(#"^(öffne|oeffne|starte|mach|mache|schalt|schalte|stell|stelle|setz|setze|dimm|dimme|suche?|google|wechsel\w*|notier\w*|schreib\w*|erstell\w*|finde|zeige|zeig)\s+(?:(?:mir|bitte|mal|eben|kurz|doch)\s+)+"#, in: value, with: "$1 ")
        return value
    }

    private static func replacing(_ pattern: String, in text: String, with replacement: String) -> String {
        text.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
    }
}
