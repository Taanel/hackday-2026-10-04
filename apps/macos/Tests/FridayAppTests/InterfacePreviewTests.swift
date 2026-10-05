import AppKit
import SwiftUI
import Testing
import FridayCore
@testable import FridayApp

/// Opt-in offscreen visual review. Never activates or touches the running app.
@Suite @MainActor struct InterfacePreviewTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FRIDAY_RENDER_PREVIEWS"] == "1"))
    func renderChassisVoiceSettingsOffscreen() async throws {
        _ = NSApplication.shared
        let model = AssistantViewModel.live()
        for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
            for page in [AssistantPage.voice, .computer] {
                try await capture(AssistantView(model: model, page: page).environment(\.colorScheme, scheme), size: NSSize(width: 800, height: 700), file: "/tmp/friday-v14-\(page.id)-\(name).png", dark: name == "dark")
            }
        }
        await model.shutdown()
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FRIDAY_RENDER_PREVIEWS"] == "1"))
    func renderSettingsAndWeatherOffscreen() async throws {
        _ = NSApplication.shared
        let model = AssistantViewModel.live() // Providers are not started.
        for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
            for page in AssistantPage.allCases {
                try await capture(AssistantView(model: model, page: page).environment(\.colorScheme, scheme), size: NSSize(width: 800, height: 700), file: "/tmp/friday-v13-\(page.id)-\(name).png", dark: name == "dark")
            }
            let codes = [0, 2, 3, 61, 80, 95, 0]
            let days: [WeatherDay] = (12...18).map { day in
                let rain = Double((day - 12) * 15)
                return WeatherDay(date: "2026-10-\(day)", low: Double(day - 5), high: Double(day + 5), rainProbability: rain, code: codes[day - 12])
            }
            let forecast = WeatherForecast(place: "Berlin", days: days, source: URL(string: "https://open-meteo.com")!)
            // Window-server glass is unavailable to an offscreen bitmap. Review
            // the same layout with its accessible opaque material fallback.
            try await capture(WeatherOverviewCard(forecast: forecast, dismiss: {}, usesGlass: false).environment(\.colorScheme, scheme).padding(10), size: NSSize(width: 376, height: 356), file: "/tmp/friday-v13-weather-\(name).png", dark: name == "dark")
        }
        await model.shutdown()
    }

    private func capture<V: View>(_ view: V, size: NSSize, file: String, dark: Bool) async throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: file))
        window.contentView = nil
    }
}
