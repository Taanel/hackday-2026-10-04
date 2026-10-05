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
        let brightness: Double?; let temperature: Double?
        let entity_id: [String]?
    }
    public let attributes: Attributes
    public var id: String { entity_id }
    public var name: String { attributes.friendly_name ?? entity_id }
    var domain: String { String(entity_id.split(separator: ".").first ?? "") }
}

public actor HomeAssistantClient {
    private let store: HomeAssistantConfigurationStore
    private let session: URLSession
    private let discoverAreas: @Sendable (HomeAssistantConfiguration) async throws -> [HomeAssistantArea]
    private var configuration: HomeAssistantConfiguration?
    private var revision = UUID()
    private var entities: [HomeAssistantEntity] = []
    private var areas: [HomeAssistantArea] = []
    private var areaCatalogAvailable = false
    private var expires = ContinuousClock.Instant.now
    private var temperatureUnit: String?

    public init(store: HomeAssistantConfigurationStore = .init(), session: URLSession? = nil,
                areaDiscovery: (@Sendable (HomeAssistantConfiguration) async throws -> [HomeAssistantArea])? = nil) {
        self.store = store
        let connection = session ?? URLSession(configuration: .ephemeral, delegate: NoCredentialRedirects(), delegateQueue: nil)
        self.session = connection
        self.discoverAreas = areaDiscovery ?? { try await HomeAssistantAreas.load($0, session: connection) }
    }
    public func invalidate() {
        revision = UUID(); configuration = nil; entities = []; areas = []; areaCatalogAvailable = false; temperatureUnit = nil; expires = .now
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
        let rooms: [HomeAssistantArea]
        let roomsAvailable: Bool
        do { rooms = try await discoverAreas(current); roomsAvailable = true }
        catch is CancellationError { throw CancellationError() }
        catch { rooms = []; roomsAvailable = false }
        try Task.checkCancellation()
        guard generation == revision else { throw CancellationError() }
        let supported = decoded.filter { ["light", "switch", "scene", "climate"].contains($0.domain) && $0.entity_id.range(of: #"^[a-z_]+\.[a-z0-9_]+$"#, options: .regularExpression) != nil }
        entities = Array(supported.prefix(2000)); areas = rooms; areaCatalogAvailable = roomsAvailable; temperatureUnit = unit; expires = .now.advanced(by: .seconds(60))
        return entities
    }
    public func execute(_ action: HomeAssistantAction) async throws -> String {
        guard action.isValid else { throw AdapterError.unavailable("Ungültiger Home-Assistant-Befehl.") }
        if entities.isEmpty || expires <= .now { _ = try await refresh() }
        try Task.checkCancellation()
        let current = try config(), generation = revision
        let room = try Self.roomLights(action, areas: areas, entities: entities)
        let requestedTargets = try room?.entities ?? [Self.resolve(action, in: entities, areas: areas)]
        // An unavailable room member must not prevent the reachable lamps from
        // responding. Explicit device commands still fail rather than disappear.
        let skipped = room == nil ? [] : requestedTargets.filter(Self.isUnavailable)
        let targets = room == nil ? requestedTargets : requestedTargets.filter { !Self.isUnavailable($0) }
        guard !targets.isEmpty else {
            throw AdapterError.unavailable("Keine erreichbaren Lampen in „\(room?.name ?? action.target)“. Nicht verfügbar: \(Self.unavailableNames(skipped)).")
        }
        let entity = targets[0]
        let name = room?.name ?? entity.name
        if !areaCatalogAvailable, action.target != entity.id, !(entity.attributes.entity_id ?? []).isEmpty {
            throw AdapterError.unavailable("Raumzuordnung nicht abrufbar. Diese Lichtgruppe kann nur einen Teil des Raums enthalten. Bitte Home Assistant aktualisieren oder eine konkrete Lampe nennen.")
        }
        guard targets.allSatisfy({ !Self.isUnavailable($0) }) else { throw AdapterError.unavailable("Das gewählte Home-Assistant-Gerät ist nicht verfügbar.") }
        var body: [String: Any] = ["entity_id": room == nil ? entity.entity_id as Any : targets.map(\.entity_id) as Any]
        let service: String
        switch action.operation {
        case .turnOn: service = "turn_on"
        case .turnOff: service = "turn_off"
        case .activateScene: service = "turn_on"
        case .brightness:
            guard targets.allSatisfy({ target in
                target.attributes.supported_color_modes?.contains(where: { ["brightness", "color_temp", "hs", "xy", "rgb", "rgbw", "rgbww", "white"].contains($0) }) == true
            }) else {
                throw AdapterError.unavailable("Nicht alle gewählten Lampen unterstützen Helligkeitsregelung. Bitte eine einzelne dimmbare Lampe nennen.")
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
        return try await confirm(action, targets: targets, skipped: skipped, name: name, configuration: current, generation: generation)
    }
    private func confirm(_ action: HomeAssistantAction, targets: [HomeAssistantEntity], skipped: [HomeAssistantEntity], name: String,
                         configuration: HomeAssistantConfiguration, generation: UUID) async throws -> String {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        for attempt in 0..<7 {
            try Task.checkCancellation()
            guard generation == revision else { throw CancellationError() }
            if attempt > 0 { try await Task.sleep(for: .milliseconds(350)) }
            guard ContinuousClock.now < deadline else { break }
            let data: Data
            do { data = try await fetch(path: "api/states", configuration: configuration, timeout: 2) }
            catch is CancellationError { throw CancellationError() }
            catch { throw AdapterError.unavailable("Auftrag gesendet, aber der Gerätezustand konnte nicht geprüft werden. Keine automatische Wiederholung.") }
            guard generation == revision else { throw CancellationError() }
            guard let observed = try? JSONDecoder().decode([HomeAssistantEntity].self, from: data) else { break }
            let matches = targets.allSatisfy { entity in
                guard let target = observed.first(where: { $0.id == entity.id }) else { return false }
                switch action.operation {
            case .turnOn, .turnOff:
                let state = action.operation == .turnOn ? "on" : "off"
                let members = entity.attributes.entity_id ?? []
                return target.state == state && members.allSatisfy { id in observed.first(where: { $0.id == id })?.state == state }
            case .brightness:
                return action.value == 0 ? target.state == "off" : target.state == "on" && target.attributes.brightness.map { abs($0 * 100 / 255 - action.value!) <= 1.5 } == true
            case .temperature:
                return target.attributes.temperature.map { abs($0 - action.value!) < 0.05 } == true
            case .activateScene:
                return target.state != entity.state && target.state != "unknown" && target.state != "unavailable"
                }
            }
            if matches {
                // Refresh cached observations without claiming physical feedback beyond HA.
                entities = Array(observed.filter { ["light", "switch", "scene", "climate"].contains($0.domain) && $0.entity_id.range(of: #"^[a-z_]+\.[a-z0-9_]+$"#, options: .regularExpression) != nil }.prefix(2000))
                let result: String
                switch action.operation {
                case .turnOn: result = "an"
                case .turnOff: result = "aus"
                case .brightness: result = "auf \(action.value!.formatted()) Prozent"
                case .temperature: result = "auf \(action.value!.formatted()) Grad"
                case .activateScene: result = "aktiviert"
                }
                if !skipped.isEmpty {
                    return "Home Assistant meldet: \(targets.count) von \(targets.count + skipped.count) Lampen in „\(name)“ \(result). Nicht verfügbar und übersprungen: \(Self.unavailableNames(skipped))."
                }
                let members = targets[0].attributes.entity_id ?? []
                let count = targets.count > 1 ? " · \(targets.count) Lampen geprüft" : members.isEmpty ? "" : " · \(members.count) Gruppenmitglieder geprüft"
                return "Home Assistant meldet: „\(name)“ \(result)\(count)."
            }
        }
        let skippedNotice = skipped.isEmpty ? "" : " Nicht verfügbar und übersprungen: \(Self.unavailableNames(skipped))."
        throw AdapterError.unavailable("Auftrag für „\(name)“ gesendet, aber Home Assistant bestätigt den gewünschten Zustand noch nicht für alle gewählten Geräte. Keine automatische Wiederholung.\(skippedNotice)")
    }

    private static func isUnavailable(_ entity: HomeAssistantEntity) -> Bool {
        entity.state == "unavailable" || (entity.state == "unknown" && entity.domain != "scene")
    }

    private static func unavailableNames(_ entities: [HomeAssistantEntity]) -> String {
        let names = entities.prefix(5).map { "\($0.name) (\($0.id))" }.joined(separator: ", ")
        return entities.count > 5 ? names + " und \(entities.count - 5) weitere" : names
    }

    static func roomLights(_ action: HomeAssistantAction, areas: [HomeAssistantArea], entities: [HomeAssistantEntity]) throws -> (name: String, entities: [HomeAssistantEntity])? {
        guard [.turnOn, .turnOff, .brightness].contains(action.operation), !action.target.contains(".") else { return nil }
        let words = targetWords(action.target).subtracting(["licht"])
        let exact = areas.filter { targetWords($0.name) == words }
        // Linking sounds (Küche + n + licht) are accepted only when the resulting
        // stem identifies an actual HA area. Exact catalog names win first.
        let alternatives = compoundRoomWords(action.target)
        let matches = exact.isEmpty ? areas.filter { alternatives.contains(targetWords($0.name)) } : exact
        guard !matches.isEmpty else { return nil }
        guard matches.count == 1 else { throw AdapterError.unavailable("Mehrere Räume heißen so. Bitte den eindeutigen Raumnamen nennen.") }
        let area = matches[0]
        // A Hue group named like the room can omit other Hue groups, plugs or
        // bridges. Address the area's individual lights once, excluding groups.
        let lights = entities.filter { $0.domain == "light" && area.entityIDs.contains($0.id) && ($0.attributes.entity_id ?? []).isEmpty }
        // Empty/stale areas may share a name with a still-valid explicit group.
        guard !lights.isEmpty else { return nil }
        return (area.name, lights.sorted { $0.id < $1.id })
    }

    private static func compoundRoomWords(_ value: String) -> [Set<String>] {
        let words = targetWords(value).subtracting(["licht"])
        let tokens = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        var alternatives: [Set<String>] = []
        for token in tokens {
            for suffix in ["beleuchtung", "lampen", "licht"] where token.hasSuffix(suffix) && token.count > suffix.count + 2 {
                let stem = String(token.dropLast(suffix.count))
                for linker in ["n", "en", "s", "es"] where stem.hasSuffix(linker) && stem.count > linker.count + 2 {
                    alternatives.append(words.subtracting([stem]).union([String(stem.dropLast(linker.count))]))
                }
            }
        }
        return alternatives
    }

    private static func targetWords(_ value: String) -> Set<String> {
        let filtered = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let ignored = Set(["das", "die", "der", "den", "im", "in", "am", "raum", "zimmer", "bitte", "alle", "allen"])
        let replacements = ["lampe":"licht", "lampen":"licht", "lichter":"licht", "beleuchtung":"licht", "light":"licht", "steckdose":"switch", "heizung":"climate", "thermostat":"climate"]
        return Set(filtered.filter { !ignored.contains($0) }.flatMap { word -> [String] in
            for suffix in ["beleuchtung", "lampen", "licht"] where word.hasSuffix(suffix) && word.count > suffix.count + 2 {
                return [String(word.dropLast(suffix.count)), "licht"]
            }
            return [replacements[word] ?? word]
        })
    }
    private func config() throws -> HomeAssistantConfiguration {
        if let configuration { return configuration }
        let value = try store.load(); configuration = value; return value
    }
    static func resolve(_ action: HomeAssistantAction, in entities: [HomeAssistantEntity], areas: [HomeAssistantArea] = []) throws -> HomeAssistantEntity {
        let domains: [String]
        switch action.operation {
        case .turnOn, .turnOff:
            let qualifiers = action.target.contains(".") ? [] : targetWords(action.target).intersection(["licht", "switch"])
            if qualifiers == ["licht"] { domains = ["light"] }
            else if qualifiers == ["switch"] { domains = ["switch"] }
            else { domains = ["light", "switch"] }
        case .activateScene: domains = ["scene"]
        case .brightness: domains = ["light"]
        case .temperature: domains = ["climate"]
        }
        let pool = entities.filter { domains.contains($0.domain) }
        let exact = pool.filter { MacApplicationCatalog.normalize($0.name) == MacApplicationCatalog.normalize(action.target) || $0.entity_id == action.target }
        if exact.count == 1 { return exact[0] }
        if exact.count > 1 { throw AdapterError.unavailable("Mehrere Geräte heißen so. Bitte die eindeutige Entity-ID nennen.") }
        let words = targetWords
        let needle = words(action.target)
        guard !needle.isEmpty else { throw AdapterError.unavailable("Bitte einen konkreten Gerätenamen nennen.") }
        // A named room group takes precedence over its member bulbs. Names and
        // group membership come from HA, never a hardcoded list of rooms.
        if domains.contains("light") {
            let room = needle.subtracting(["licht"])
            if !room.isEmpty {
                let groups = pool.filter { $0.domain == "light" && !($0.attributes.entity_id ?? []).isEmpty && words($0.name).subtracting(["licht"]) == room }
                if groups.count == 1 { return groups[0] }
                if groups.count > 1 { throw AdapterError.unavailable("Mehrere Lichtgruppen passen. Bitte einen genaueren Namen nennen.") }
            }
        }
        let matches = pool.filter { entity in
            let entityWords = words(entity.name + " " + entity.entity_id)
            if needle.isSubset(of: entityWords) { return true }
            return areas.contains { area in
                area.entityIDs.contains(entity.id) && needle.isSubset(of: entityWords.union(words(area.name)))
            }
        }
        guard matches.count == 1 else {
            throw AdapterError.unavailable(matches.isEmpty ? "Kein passendes Gerät gefunden. Gerätenamen im Home-Assistant-Bereich prüfen." : "Mehrere Geräte passen. Bitte einen genaueren Namen oder die Entity-ID nennen.")
        }
        return matches[0]
    }
    private func fetch(path: String, configuration: HomeAssistantConfiguration, body: [String: Any]? = nil, timeout: TimeInterval = 10) async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(path))
        request.timeoutInterval = timeout
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
