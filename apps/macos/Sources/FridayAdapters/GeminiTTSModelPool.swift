import Foundation

/// One project, separate supported models. Voices and API keys do not change quotas.
struct GeminiTTSModelPool {
    static let models = ["gemini-3.8-flash-lite-tts", "gemini-3.8-flash-tts", "gemini-3.1-flash-tts-preview"]
    private var cursor = 0
    private var pausedUntil: [String: Date] = [:]

    mutating func next(at now: Date = Date()) -> String? {
        for _ in Self.models {
            let model = Self.models[cursor]
            cursor = (cursor + 1) % Self.models.count
            if let until = pausedUntil[model], until > now { continue }
            pausedUntil[model] = nil
            return model
        }
        return nil
    }

    mutating func pause(_ model: String, until: Date) { pausedUntil[model] = until }

    static func cooldown(status: Int, data: Data, response: HTTPURLResponse?, now: Date = Date()) -> Date {
        if status == 429 {
            if let raw = response?.value(forHTTPHeaderField: "Retry-After"), let seconds = Double(raw), seconds.isFinite {
                return now.addingTimeInterval(min(86_400, max(30, seconds)))
            }
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = object["error"] as? [String: Any] {
                for detail in error["details"] as? [[String: Any]] ?? [] {
                    if let delay = detail["retryDelay"] as? String, delay.hasSuffix("s"),
                       let seconds = Double(delay.dropLast()), seconds.isFinite {
                        return now.addingTimeInterval(min(86_400, max(30, seconds)))
                    }
                }
                if (error["message"] as? String)?.lowercased().contains("per day") == true {
                    var calendar = Calendar(identifier: .gregorian)
                    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
                    return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
                }
            }
        }
        return now.addingTimeInterval(status == 404 ? 86_400 : 120)
    }
}
