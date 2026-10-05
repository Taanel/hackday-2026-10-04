import Foundation
import Testing
import FridayCore
@testable import FridayAdapters

@Suite struct WeatherAdapterTests {
    @Test func locationAfterClarificationRetainsRequestedWeekButNewPeriodOverridesIt() {
        let history = [GeminiTurn(role: "user", text: "Wie wird das Wetter nächste Woche?"), GeminiTurn(role: "model", text: "Für welche Stadt?")]
        #expect(GeminiReasoningEngine.weatherQuestion("Berlin", history: history).contains("nächste Woche"))
        #expect(GeminiReasoningEngine.weatherQuestion("Berlin, morgen", history: history) == "Berlin, morgen")
        #expect(GeminiReasoningEngine.weatherQuestion("Wie wird das Wetter heute in Berlin?", history: history).contains("heute"))
    }
    @Test func chartValuesComeFromForecastNotFromGeneratedAnswer() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WeatherFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let engine = GeminiReasoningEngine(session: session, apiKey: { "fixture-key" })
        let plan = try await engine.plan(to: "Wie wird das Wetter nächste Woche in Berlin?")
        guard case .weatherAnswer(let text, let sources, let forecast) = plan else { Issue.record("Wetterkarte fehlt"); return }
        #expect(text == "Es wird mild.")
        #expect(forecast.place == "Berlin")
        #expect(forecast.days.count == 7)
        #expect(forecast.days.allSatisfy { $0.high == 18 && $0.low == 8 && $0.rainProbability == 40 })
        #expect(sources.first?.url.host == "api.open-meteo.com")
        #expect(forecast.source == sources.first?.url)
    }

    @Test func malformedDataCannotBecomeAPlausibleChart() {
        let invalid = Data(#"{"daily":{"time":["2026-10-05"],"temperature_2m_max":[180],"temperature_2m_min":[8],"precipitation_probability_max":[140],"weather_code":[3]}}"#.utf8)
        #expect(throws: AdapterError.self) { try WebResearchService.decodeForecast(invalid, place: "Berlin", source: URL(string: "https://open-meteo.com")!) }
    }
}

private final class WeatherFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var bytes = request.httpBody ?? Data()
        if bytes.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; bytes.append(contentsOf: buffer.prefix(count)) }
        }
        let input = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
        let data: Data
        if request.url?.host == "geocoding-api.open-meteo.com" {
            data = Data(#"{"results":[{"name":"Berlin","latitude":52.52,"longitude":13.41,"country":"Deutschland","population":3600000}]}"#.utf8)
        } else if request.url?.host == "api.open-meteo.com" {
            var calendar = Calendar(identifier: .iso8601); calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
            let parser = DateFormatter(); parser.calendar = calendar; parser.timeZone = calendar.timeZone; parser.dateFormat = "yyyy-MM-dd"
            let days = (0..<16).map { parser.string(from: calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: Date()))!) }
            data = try! JSONSerialization.data(withJSONObject: ["timezone": "Europe/Berlin", "daily": ["time": days, "temperature_2m_max": Array(repeating: 18, count: 16), "temperature_2m_min": Array(repeating: 8, count: 16), "precipitation_probability_max": Array(repeating: 40, count: 16), "weather_code": Array(repeating: 3, count: 16)]])
        } else if input?["tools"] == nil {
            data = Data(#"{"candidates":[{"content":{"parts":[{"text":"Es wird mild."}]}}]}"#.utf8)
        } else {
            data = Data(#"{"candidates":[{"content":{"parts":[{"functionCall":{"name":"weather_forecast","args":{"location":"Berlin"}}}]}}]}"#.utf8)
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
