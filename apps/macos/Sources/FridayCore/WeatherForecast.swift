import Foundation

public struct WeatherDay: Sendable, Equatable, Identifiable {
    public let date: String
    public let low: Double?
    public let high: Double?
    public let rainProbability: Double?
    public let code: Int?
    public var id: String { date }
    public init(date: String, low: Double?, high: Double?, rainProbability: Double?, code: Int?) {
        self.date = date; self.low = low; self.high = high; self.rainProbability = rainProbability; self.code = code
    }
}

public struct WeatherForecast: Sendable, Equatable {
    public let place: String
    public let days: [WeatherDay]
    public let source: URL
    public let timeZoneIdentifier: String
    public init(place: String, days: [WeatherDay], source: URL, timeZoneIdentifier: String = "Europe/Berlin") {
        self.place = place; self.days = days; self.source = source; self.timeZoneIdentifier = timeZoneIdentifier
    }

    /// Select the requested period from API dates, never from generated prose.
    /// Unsupported periods stay text-only rather than showing unrelated days.
    public func overview(for question: String, now: Date = Date()) -> WeatherForecast? {
        let text = question.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
        let today = calendar.startOfDay(for: now)
        var start = today
        var count = 7
        if text.range(of: #"(?:nachste[nr]?|kommende[nr]?)\s+woche"#, options: .regularExpression) != nil {
            guard let week = calendar.dateInterval(of: .weekOfYear, for: today) else { return nil }
            start = week.end
        } else if text.contains("ubermorgen") { start = calendar.date(byAdding: .day, value: 2, to: today)!; count = 1 }
        else if text.contains("morgen") { start = calendar.date(byAdding: .day, value: 1, to: today)!; count = 1 }
        else if text.contains("heute") || text.contains("aktuell") { count = 1 }
        else if text.contains("wochenende") {
            let weekday = calendar.component(.weekday, from: today)
            start = calendar.date(byAdding: .day, value: weekday == 1 ? 0 : (7 - weekday), to: today)!
            count = weekday == 1 ? 1 : 2
        } else if text.contains("diese woche") {
            count = calendar.dateComponents([.day], from: today, to: calendar.dateInterval(of: .weekOfYear, for: today)!.end).day ?? 7
        } else if text.range(of: #"\b(?:montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag|monat|jahr|januar|februar|marz|april|mai|juni|juli|august|september|oktober|november|dezember)\b|\d+[./]\d+|(?:in|nach)\s+\d+\s+(?:tagen|wochen)"#, options: .regularExpression) != nil {
            return nil
        }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy-MM-dd"
        let wanted = (0..<count).map { formatter.string(from: calendar.date(byAdding: .day, value: $0, to: start)!) }
        let selected = wanted.compactMap { date in days.first { $0.date == date } }
        guard selected.count == wanted.count, !selected.isEmpty else { return nil }
        return WeatherForecast(place: place, days: selected, source: source, timeZoneIdentifier: timeZoneIdentifier)
    }
}
