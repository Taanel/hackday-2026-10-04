import Foundation
import FridayCore

private final class NoCredentialRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

public struct HomeAssistantEntity: Decodable, Sendable, Identifiable {
    public let entity_id: String
    public let state: String
    public struct Attributes: Decodable, Sendable {
        public let friendly_name: String?
        let min_temp: Double?; let max_temp: Double?; let target_temp_step: Double?
        let supported_features: Int?; let supported_color_modes: [String]?
    }
    public let attributes: Attributes
    public var id: String { entity_id }
    public var name: String { attributes.friendly_name ?? entity_id }
    var domain: String { String(entity_id.split(separator: ".").first ?? "") }
}

public actor HomeAssistantClient {
    private let store: HomeAssistantConfigurationStore
    private let session: URLSession
    private var configuration: HomeAssistantConfiguration?
    private var revision = UUID()
    private var entities: [HomeAssistantEntity] = []
    private var expires = ContinuousClock.Instant.now
    private var temperatureUnit: String?

    public init(store: HomeAssistantConfigurationStore = .init(), session: URLSession? = nil) {
        self.store = store
        self.session = session ?? URLSession(configuration: .ephemeral, delegate: NoCredentialRedirects(), delegateQueue: nil)
    }
    public func invalidate() {
        revision = UUID(); configuration = nil; entities = []; temperatureUnit = nil; expires = .now
    }
    public func refresh() async throws -> [HomeAssistantEntity] {
        try Task.checkCancellation()
        let current = try config()
        let generation = revision
        let data = try await fetch(path: "api/states", configuration: current)
        guard let decoded = try? JSONDecoder().decode([HomeAssistantEntity].self, from: data) else {
            throw AdapterError.invalidResponse("Home Assistant hat eine ungültige Geräteliste geliefert.")
        }
        try Task.checkCancellation()
        guard generation == revision else { throw CancellationError() }
        let configData = try await fetch(path: "api/config", configuration: current)
        struct ServerInfo: Decodable { struct Units: Decodable { let temperature: String }; let unit_system: Units }
        let unit = try? JSONDecoder().decode(ServerInfo.self, from: configData).unit_system.temperature
        try Task.checkCancellation()
        guard generation == revision else { throw CancellationError() }
        let supported = decoded.filter { ["light", "switch", "scene", "climate"].contains($0.domain) && $0.entity_id.range(of: #"^[a-z_]+\.[a-z0-9_]+$"#, options: .regularExpression) != nil }
        entities = Array(supported.prefix(2000)); temperatureUnit = unit; expires = .now.advanced(by: .seconds(60))
        return entities
    }
    public func execute(_ action: HomeAssistantAction) async throws -> String {
        guard action.isValid else { throw AdapterError.unavailable("Ungültiger Home-Assistant-Befehl.") }
        if entities.isEmpty || expires <= .now { _ = try await refresh() }
        try Task.checkCancellation()
        let current = try config(), generation = revision
        let entity = try Self.resolve(action, in: entities)
        guard entity.state != "unavailable", entity.state != "unknown" || entity.domain == "scene" else { throw AdapterError.unavailable("Das gewählte Home-Assistant-Gerät ist nicht verfügbar.") }
        var body: [String: Any] = ["entity_id": entity.entity_id]
        let service: String
        switch action.operation {
        case .turnOn: service = "turn_on"
        case .turnOff: service = "turn_off"
        case .activateScene: service = "turn_on"
        case .brightness:
            guard let modes = entity.attributes.supported_color_modes, modes.contains(where: { ["brightness", "color_temp", "hs", "xy", "rgb", "rgbw", "rgbww", "white"].contains($0) }) else {
                throw AdapterError.unavailable("Dieses Licht unterstützt keine erkannte Helligkeitsregelung.")
            }
            service = "turn_on"; body["brightness_pct"] = action.value!
        case .temperature:
            let attributes = entity.attributes
            guard temperatureUnit == "°C", (attributes.supported_features ?? 0) & 1 != 0,
                  let minimum = attributes.min_temp, let maximum = attributes.max_temp,
                  let step = attributes.target_temp_step, minimum.isFinite, maximum.isFinite, minimum <= maximum, step.isFinite, step > 0,
                  let value = action.value, (minimum...maximum).contains(value), abs((value - minimum) / step - ((value - minimum) / step).rounded()) < 0.001 else {
                throw AdapterError.unavailable("Temperatur passt nicht zu Einheit, Zieltemperatur-Funktion oder Bereich/Schrittweite dieser Heizung.")
            }
            service = "set_temperature"; body["temperature"] = value
        }
        try Task.checkCancellation()
        guard generation == revision else { throw CancellationError() }
        // No retry: after POST starts, a timeout/cancellation may mean an unknown outcome.
        _ = try await fetch(path: "api/services/\(entity.domain)/\(service)", configuration: current, body: body)
        try Task.checkCancellation()
        guard generation == revision else { throw AdapterError.unavailable("Auftrag an die vorherige Serverkonfiguration gesendet. Keine automatische Wiederholung.") }
        return "Home Assistant hat den Auftrag für „\(entity.name)“ angenommen."
    }
    private func config() throws -> HomeAssistantConfiguration {
        if let configuration { return configuration }
        let value = try store.load(); configuration = value; return value
    }
    static func resolve(_ action: HomeAssistantAction, in entities: [HomeAssistantEntity]) throws -> HomeAssistantEntity {
        let domains: [String]
        switch action.operation {
        case .turnOn, .turnOff: domains = ["light", "switch"]
        case .activateScene: domains = ["scene"]
        case .brightness: domains = ["light"]
        case .temperature: domains = ["climate"]
        }
        let pool = entities.filter { domains.contains($0.domain) }
        let exact = pool.filter { MacApplicationCatalog.normalize($0.name) == MacApplicationCatalog.normalize(action.target) || $0.entity_id == action.target }
        if exact.count == 1 { return exact[0] }
        if exact.count > 1 { throw AdapterError.unavailable("Mehrere Geräte heißen so. Bitte die eindeutige Entity-ID nennen.") }
        func words(_ value: String) -> Set<String> {
            let filtered = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
                .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
            let ignored = Set(["das", "die", "der", "den", "im", "in", "am", "raum", "zimmer", "bitte"])
            let replacements = ["lampe":"licht", "lampen":"licht", "light":"licht", "steckdose":"switch", "heizung":"climate", "thermostat":"climate"]
            return Set(filtered.filter { !ignored.contains($0) }.map { replacements[$0] ?? $0 })
        }
        let needle = words(action.target)
        guard !needle.isEmpty else { throw AdapterError.unavailable("Bitte einen konkreten Gerätenamen nennen.") }
        let matches = pool.filter { needle.isSubset(of: words($0.name + " " + $0.entity_id)) }
        guard matches.count == 1 else {
            throw AdapterError.unavailable(matches.isEmpty ? "Kein passendes Gerät gefunden. Gerätenamen im Home-Assistant-Bereich prüfen." : "Mehrere Geräte passen. Bitte einen genaueren Namen oder die Entity-ID nennen.")
        }
        return matches[0]
    }
    private func fetch(path: String, configuration: HomeAssistantConfiguration, body: [String: Any]? = nil) async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(path))
        request.timeoutInterval = 10
        request.httpMethod = body == nil ? "GET" : "POST"
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse else { throw AdapterError.invalidResponse("Ungültige Home-Assistant-Antwort.") }
            guard (200...299).contains(response.statusCode) else {
                switch response.statusCode {
                case 401, 403: throw AdapterError.unavailable("Home Assistant hat den Token abgelehnt. Bitte einen gültigen langlebigen Token eintragen.")
                case 300...399: throw AdapterError.unavailable("Home Assistant leitet weiter. Bitte die direkte Serveradresse eintragen; der Token wird nicht weitergeleitet.")
                default: throw AdapterError.unavailable("Home Assistant hat die Anfrage abgelehnt (HTTP \(response.statusCode)).")
                }
            }
            guard data.count <= 4_000_000 else { throw AdapterError.invalidResponse("Home-Assistant-Antwort ist zu groß.") }
            return data
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch let error as AdapterError { throw error }
        catch { throw AdapterError.unavailable(body == nil ? "Home Assistant nicht erreichbar. Serveradresse und WLAN prüfen." : "Keine Bestätigung von Home Assistant. Der Auftrag könnte bereits ausgeführt sein; er wird nicht automatisch wiederholt.") }
    }
}
