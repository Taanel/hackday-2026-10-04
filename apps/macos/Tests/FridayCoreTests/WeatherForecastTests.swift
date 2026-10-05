import Foundation
import Testing
@testable import FridayCore

@Suite struct WeatherForecastTests {
    private func forecast() -> WeatherForecast {
        let days = (5...20).map { WeatherDay(date: "2026-10-\(String(format: "%02d", $0))", low: 8, high: 18, rainProbability: 40, code: 3) }
        return WeatherForecast(place: "Berlin", days: days, source: URL(string: "https://open-meteo.com")!)
    }
    private var monday: Date { ISO8601DateFormatter().date(from: "2026-10-05T12:00:00Z")! }

    @Test func nextWeekUsesMondayThroughSundayAndTomorrowUsesOneDay() throws {
        let next = try #require(forecast().overview(for: "Wie wird das Wetter nächste Woche?", now: monday))
        #expect(next.days.map(\.date) == (12...18).map { "2026-10-\($0)" })
        #expect(forecast().overview(for: "Wetter morgen", now: monday)?.days.map(\.date) == ["2026-10-06"])
        #expect(forecast().overview(for: "Wetter übermorgen", now: monday)?.days.map(\.date) == ["2026-10-07"])
        #expect(forecast().overview(for: "Wetter am Wochenende", now: monday)?.days.map(\.date) == ["2026-10-10", "2026-10-11"])
    }

    @Test func incompleteAndUnsupportedPeriodsDoNotShowUnrelatedDays() {
        #expect(forecast().overview(for: "Wetter nächsten Monat", now: monday) == nil)
        #expect(forecast().overview(for: "Wetter am Freitag", now: monday) == nil)
        let short = WeatherForecast(place: "Berlin", days: Array(forecast().days.prefix(7)), source: forecast().source)
        #expect(short.overview(for: "Wetter nächste Woche", now: monday) == nil)
    }
}
