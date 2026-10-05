import Foundation
import Testing
import FridayCore
import FridayAdapters
@testable import FridayApp

@Suite @MainActor struct WeatherOverviewTests {
    private var forecast: WeatherForecast {
        WeatherForecast(place: "Berlin", days: [WeatherDay(date: "2026-10-05", low: 8, high: 18, rainProbability: nil, code: 3)], source: URL(string: "https://open-meteo.com")!)
    }

    @Test func dismissKeepsWeatherInAnswerButRemovesItFromOverlay() {
        let model = AssistantViewModel()
        model.showWeather(forecast)
        model.dismissWeatherOverlay()
        #expect(model.weatherOverlay == nil)
        #expect(model.weatherOverview == forecast)
    }

    @Test func expiryFromOldAnswerCannotHideNewWeather() async throws {
        let model = AssistantViewModel()
        model.showWeather(forecast); model.expireWeather(after: .milliseconds(30))
        let next = WeatherForecast(place: "Hamburg", days: forecast.days, source: forecast.source)
        model.showWeather(next)
        try await Task.sleep(for: .milliseconds(70))
        #expect(model.weatherOverlay == next)
        model.expireWeather(after: .milliseconds(20))
        try await Task.sleep(for: .milliseconds(60))
        #expect(model.weatherOverlay == nil)
        #expect(model.weatherOverview == next)
    }

    @Test func typedWeatherTravelsThroughRouterAndIsSpokenAsOneAnswer() async {
        let voice = WeatherSpeech()
        let model = AssistantViewModel(router: AssistantRouter(decisions: WeatherDecision(), reasoning: WeatherPlan(forecast: forecast), tools: PreviewToolExecutor()), speech: voice)
        model.input = "Wetter heute in Berlin"; model.submit(); await model.task?.value
        #expect(model.weatherOverview == forecast)
        #expect(model.weatherOverlay == forecast)
        #expect(voice.answers == ["Heute wird es bewölkt."])
        #expect(model.canReplayAnswer)
        model.cancel()
        #expect(model.weatherOverlay == nil)
    }
}
private struct WeatherDecision: FastDecisionEngine {
    func decide(text: String) async throws -> FastDecision { FastDecision(intent: .reasoning, confidence: 1) }
}
private struct WeatherPlan: ActionPlanningReasoningEngine {
    let forecast: WeatherForecast
    func plan(to text: String) async throws -> ReasoningPlan { .weatherAnswer(text: "Heute wird es bewölkt.", sources: [], forecast: forecast) }
    func respond(to text: String) async throws -> String { "Heute wird es bewölkt." }
}
@MainActor private final class WeatherSpeech: SpeechOutput {
    var answers: [String] = []
    func speak(_ text: String) async throws { answers.append(text) }
    func stop() {}
}
