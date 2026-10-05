import SwiftUI
import FridayCore

struct WeatherOverviewCard: View {
    let forecast: WeatherForecast
    var dismiss: (() -> Void)? = nil
    var usesGlass = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    private var ink: Color { colorScheme == .dark ? .white : .black }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(forecast.place).font(.headline).lineLimit(1)
                    Text(period).font(.caption).foregroundStyle(ink.opacity(0.65))
                }
                Spacer()
                if let dismiss {
                    Button(action: dismiss) { Image(systemName: "xmark").font(.caption.weight(.semibold)).padding(5) }
                        .buttonStyle(.plain).accessibilityLabel("Wetterübersicht schließen")
                }
            }
            Divider()
            ForEach(forecast.days.prefix(7)) { day in
                HStack(spacing: 8) {
                    Text(label(day.date, format: "EE")).font(.callout.weight(.medium)).frame(width: 26, alignment: .leading)
                    Text(label(day.date, format: "dd.MM.")).font(.caption).foregroundStyle(ink.opacity(0.65)).frame(width: 46, alignment: .leading)
                    Image(systemName: Self.symbol(day.code)).symbolRenderingMode(.palette)
                        .foregroundStyle(ink.opacity(0.7), day.code == 0 || day.code == 1 || day.code == 2 ? Color.orange : Color.blue).frame(width: 24)
                        .accessibilityLabel(Self.condition(day.code))
                    Spacer(minLength: 4)
                    Text("\(number(day.low))°").foregroundStyle(ink.opacity(0.65)).frame(width: 34, alignment: .trailing)
                    Text("\(number(day.high))°").fontWeight(.semibold).frame(width: 34, alignment: .trailing)
                    Label("\(number(day.rainProbability))%", systemImage: "drop.fill").font(.caption).foregroundStyle(ink.opacity(0.65)).frame(width: 56, alignment: .trailing)
                }.font(.callout).monospacedDigit().frame(height: 20)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(label(day.date, format: "EEEE, d. MMMM")): \(Self.condition(day.code)), \(day.low.map { "\(number($0)) bis" } ?? "") \(day.high.map { "\(number($0)) Grad" } ?? "Temperatur fehlt"), \(day.rainProbability.map { "\(number($0)) Prozent Regenwahrscheinlichkeit" } ?? "Regenwahrscheinlichkeit fehlt")")
            }
            Divider()
            HStack {
                Link(destination: forecast.source) { Text("Open-Meteo").foregroundStyle(Color.accentColor) }
                Spacer()
                Text("min / max · °C").foregroundStyle(ink.opacity(0.65))
            }.font(.caption2)
        }.foregroundStyle(ink).padding(16).frame(maxWidth: .infinity, alignment: .leading).modifier(WeatherGlass(reduceTransparency: reduceTransparency || !usesGlass))
    }

    private var period: String {
        guard let first = forecast.days.first, let last = forecast.days.last else { return "Vorhersage" }
        return first.date == last.date ? label(first.date, format: "EEEE, d. MMMM") : "\(label(first.date, format: "d. MMM")) – \(label(last.date, format: "d. MMM"))"
    }
    private func number(_ value: Double?) -> String { value.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "–" }
    private func label(_ date: String, format: String) -> String {
        let parser = DateFormatter(); parser.locale = Locale(identifier: "en_US_POSIX"); parser.timeZone = TimeZone(secondsFromGMT: 0); parser.dateFormat = "yyyy-MM-dd"
        guard let value = parser.date(from: date) else { return date }
        parser.locale = Locale(identifier: "de_DE"); parser.dateFormat = format
        return parser.string(from: value)
    }
    static func symbol(_ code: Int?) -> String {
        switch code ?? -1 { case 0: "sun.max.fill"; case 1, 2: "cloud.sun.fill"; case 3: "cloud.fill"; case 45, 48: "cloud.fog.fill"; case 51...67, 80...82: "cloud.rain.fill"; case 71...77, 85, 86: "cloud.snow.fill"; case 95...99: "cloud.bolt.rain.fill"; default: "questionmark.circle" }
    }
    static func condition(_ code: Int?) -> String {
        switch code ?? -1 { case 0: "Klar"; case 1, 2: "Teilweise bewölkt"; case 3: "Bewölkt"; case 45, 48: "Nebel"; case 51...67, 80...82: "Regen"; case 71...77, 85, 86: "Schnee"; case 95...99: "Gewitter"; default: "Wetterzustand fehlt" }
    }
}

private struct WeatherGlass: ViewModifier {
    let reduceTransparency: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 20))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }
}
