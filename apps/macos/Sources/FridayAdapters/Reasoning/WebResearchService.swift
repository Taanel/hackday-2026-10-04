import Foundation
import FridayCore

struct ResearchEvidence: Sendable {
    let text: String
    let sources: [AnswerSource]
    var weather: WeatherForecast? = nil
}

/// Public endpoints only: search snippets and weather data, never arbitrary URLs.
struct WebResearchService: Sendable {
    let session: URLSession

    func search(query: String) async throws -> ResearchEvidence {
        let url = try Self.url("https://lite.duckduckgo.com/lite/", parameters: ["q": query, "kl": "de-de"])
        let data = try await fetch(url)
        guard let html = String(data: data, encoding: .utf8) else { throw Self.searchError }
        return try Self.decodeSearch(html)
    }

    func weather(location: String) async throws -> ResearchEvidence {
        let geoURL = try Self.url("https://geocoding-api.open-meteo.com/v1/search", parameters: [
            "name": location, "count": "5", "language": "de", "format": "json"
        ])
        let geo = try JSONDecoder().decode(Geocoding.self, from: await fetch(geoURL))
        guard let place = geo.results?.first else {
            return ResearchEvidence(text: "Der Ort wurde nicht gefunden. Frage nach Stadt und Land; erfinde keine Vorhersage.", sources: [])
        }
        // Small towns with several equally plausible matches need clarification.
        if let other = geo.results?.dropFirst().first,
           (place.population ?? 0) < 100_000,
           (other.population ?? 0) > (place.population ?? 0) / 2 {
            let choices = (geo.results ?? []).prefix(3).map { "\($0.name), \($0.admin1 ?? ""), \($0.country ?? "")" }
            return ResearchEvidence(text: "Mehrere Orte gefunden: \(choices.joined(separator: "; ")). Frage nach dem gewünschten Ort.", sources: [])
        }
        let url = try Self.url("https://api.open-meteo.com/v1/forecast", parameters: [
            "latitude": String(place.latitude), "longitude": String(place.longitude),
            "timezone": "auto", "forecast_days": "16",
            "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"
        ])
        let data = try await fetch(url)
        let context = try Self.decodeWeather(data)
        return ResearchEvidence(text: "Ort: \(place.name), \(place.admin1 ?? ""), \(place.country ?? "").\n\(context)", sources: [
            AnswerSource(title: "Open-Meteo · \(place.name)", url: url)
        ], weather: try Self.decodeForecast(data, place: place.name, source: url))
    }

    private struct Geocoding: Decodable {
        struct Place: Decodable {
            let name: String; let latitude: Double; let longitude: Double
            let country: String?; let admin1: String?; let population: Int?
        }
        let results: [Place]?
    }

    private func fetch(_ url: URL) async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/131.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 1_000_000 else { throw Self.searchError }
            return data
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw Self.searchError }
    }

    static func url(_ base: String, parameters: [String: String]) throws -> URL {
        guard parameters.values.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 1_000 }) else {
            throw AdapterError.invalidResponse("Ungültige Recherche-Anfrage.")
        }
        var components = URLComponents(string: base)!
        components.queryItems = parameters.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }

    static var searchError: AdapterError {
        .unavailable("Recherche liefert gerade keine verwertbaren Daten. Bitte später erneut versuchen; ich erfinde keine aktuellen Angaben.")
    }

    static func decodeSearch(_ html: String) throws -> ResearchEvidence {
        let regex = try NSRegularExpression(pattern: #"(?s)<a\b[^>]*class=['\"]result-link['\"][^>]*>.*?</a>|<a\b[^>]*href=['\"][^'\"]+['\"][^>]*class=['\"]result-link['\"][^>]*>.*?</a>"#)
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        var sources: [AnswerSource] = []
        var excerpts: [String] = []
        for (index, match) in matches.enumerated() {
            guard sources.count < 5, let range = Range(match.range, in: html) else { continue }
            let anchor = String(html[range])
            let hrefPattern = #"href=['\"]([^'\"]+)['\"]"#
            guard let href = capture(hrefPattern, in: anchor),
                  let sourceURL = searchResultURL(href) else { continue }
            let title = plainText(anchor)
            guard !title.isEmpty, !sources.contains(where: { $0.url == sourceURL }) else { continue }
            let end = index + 1 < matches.count ? matches[index + 1].range.location : (html as NSString).length
            let tail = (html as NSString).substring(with: NSRange(location: NSMaxRange(match.range), length: end - NSMaxRange(match.range)))
            let snippet = plainText(capture(#"(?s)<td\b[^>]*class=['\"]result-snippet['\"][^>]*>(.*?)</td>"#, in: tail) ?? "")
            sources.append(AnswerSource(title: String(title.prefix(180)), url: sourceURL))
            excerpts.append("[\(sources.count)] \(title)\n\(sourceURL.absoluteString)\n\(snippet.prefix(700))")
        }
        guard !sources.isEmpty else { throw searchError }
        return ResearchEvidence(text: "Suchmaschinen-Snippets (keine vollständig gelesenen Seiten):\n" + excerpts.joined(separator: "\n\n"), sources: sources)
    }

    static func searchResultURL(_ href: String) -> URL? {
        let raw = href.replacingOccurrences(of: "&amp;", with: "&")
        let normalized = raw.hasPrefix("//") ? "https:" + raw : raw
        guard let components = URLComponents(string: normalized) else { return nil }
        let destination: String
        if components.host == "duckduckgo.com", components.path == "/l/" {
            guard let target = components.queryItems?.first(where: { $0.name == "uddg" })?.value else { return nil }
            destination = target
        } else { destination = normalized }
        guard let url = URL(string: destination), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    static func plainText(_ html: String) -> String {
        var text = html.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        let entities = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " "]
        for (entity, value) in entities { text = text.replacingOccurrences(of: entity, with: value) }
        return text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct Forecast: Decodable {
            struct Daily: Decodable {
                let time: [String]
                let temperature_2m_max: [Double?]; let temperature_2m_min: [Double?]
                let precipitation_probability_max: [Double?]; let weather_code: [Int?]
            }
            let daily: Daily
            let timezone: String?
    }

    static func decodeForecast(_ data: Data, place: String, source: URL) throws -> WeatherForecast {
        let forecast = try? JSONDecoder().decode(Forecast.self, from: data)
        guard let daily = forecast?.daily,
              !daily.time.isEmpty, daily.time.count <= 16,
              [daily.temperature_2m_max.count, daily.temperature_2m_min.count,
               daily.precipitation_probability_max.count, daily.weather_code.count].allSatisfy({ $0 == daily.time.count }),
              daily.temperature_2m_max.contains(where: { $0 != nil }),
              Set(daily.time).count == daily.time.count,
              daily.time == daily.time.sorted(),
              daily.time.allSatisfy({ $0.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil }),
              (daily.temperature_2m_max + daily.temperature_2m_min).allSatisfy({ $0 == nil || (-100...70).contains($0!) }),
              daily.precipitation_probability_max.allSatisfy({ $0 == nil || (0...100).contains($0!) }) else { throw searchError }
        let days = daily.time.indices.map { WeatherDay(date: daily.time[$0], low: daily.temperature_2m_min[$0], high: daily.temperature_2m_max[$0], rainProbability: daily.precipitation_probability_max[$0], code: daily.weather_code[$0]) }
        return WeatherForecast(place: place, days: days, source: source, timeZoneIdentifier: forecast?.timezone ?? "UTC")
    }

    static func decodeWeather(_ data: Data) throws -> String {
        let forecast = try decodeForecast(data, place: "", source: URL(string: "https://open-meteo.com/")!)
        let dateParser = DateFormatter(); dateParser.locale = Locale(identifier: "en_US_POSIX")
        dateParser.timeZone = TimeZone(secondsFromGMT: 0); dateParser.dateFormat = "yyyy-MM-dd"
        let weekday = DateFormatter(); weekday.locale = Locale(identifier: "de_DE")
        weekday.timeZone = TimeZone(secondsFromGMT: 0); weekday.dateFormat = "EEEE"
        let lines = forecast.days.map { day -> String in
            let temperatures: String
            if let low = day.low, let high = day.high {
                temperatures = "\(low) bis \(high) °C"
            } else { temperatures = "keine Temperaturdaten verfügbar" }
            let rain = day.rainProbability.map { "Regenwahrscheinlichkeit \($0) %" } ?? "keine Regenwahrscheinlichkeit verfügbar"
            let code = day.code.map { "WMO-Wettercode \($0)" } ?? "kein Wettercode verfügbar"
            let label = dateParser.date(from: day.date).map { weekday.string(from: $0) + ", " } ?? ""
            return "\(label)\(day.date): \(temperatures), \(rain), \(code)"
        }
        return "Aktuelle Vorhersage, täglich. WMO-Codes: 0 klar, 1–3 bewölkt, 45/48 Nebel, 51–67 Regen, 71–77 Schnee, 80–86 Schauer, 95–99 Gewitter. Verwende nur die angefragten Tage. Außerhalb dieses Zeitraums keine Prognose erfinden.\n" + lines.joined(separator: "\n")
    }
}
