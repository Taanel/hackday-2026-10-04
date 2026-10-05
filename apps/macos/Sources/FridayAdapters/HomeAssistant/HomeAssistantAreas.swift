import Foundation

public struct HomeAssistantArea: Sendable {
    public let name: String
    public let entityIDs: Set<String>
    public init(name: String, entityIDs: Set<String>) {
        self.name = name; self.entityIDs = entityIDs
    }
}

/// Read-only registries are available to ordinary HA users; template rendering
/// requires elevated access on some servers. No room names are hardcoded.
enum HomeAssistantAreas {
    struct Area: Decodable { let area_id: String; let name: String }
    struct Device: Decodable { let id: String; let area_id: String? }
    struct Entity: Decodable {
        let entity_id: String; let device_id: String?; let area_id: String?
        let disabled_by: String?
    }
    struct Reply<T: Decodable>: Decodable { let id: Int; let success: Bool; let result: T? }
    struct Authentication: Decodable { let type: String }

    static func combine(areas: [Area], devices: [Device], entities: [Entity]) -> [HomeAssistantArea] {
        let deviceAreas = Dictionary(devices.compactMap { device in device.area_id.map { (device.id, $0) } }, uniquingKeysWith: { first, _ in first })
        return areas.map { area in
            HomeAssistantArea(name: area.name, entityIDs: Set(entities.filter { entity in
                entity.disabled_by == nil && (entity.area_id ?? entity.device_id.flatMap { deviceAreas[$0] }) == area.area_id
            }.map(\.entity_id)))
        }
    }

    static func load(_ configuration: HomeAssistantConfiguration, session: URLSession) async throws -> [HomeAssistantArea] {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/api/websocket"
        let socket = session.webSocketTask(with: components.url!)
        socket.maximumMessageSize = 4_000_000
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }
        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: [HomeAssistantArea].self) { group in
                group.addTask {
                    guard try JSONDecoder().decode(Authentication.self, from: await read(socket)).type == "auth_required" else { throw AdapterError.invalidResponse("Ungültige Home-Assistant-Anmeldung.") }
                    let auth = try JSONSerialization.data(withJSONObject: ["type": "auth", "access_token": configuration.token])
                    try await socket.send(.string(String(decoding: auth, as: UTF8.self)))
                    guard try JSONDecoder().decode(Authentication.self, from: await read(socket)).type == "auth_ok" else { throw AdapterError.unavailable("Home Assistant hat den Token abgelehnt.") }
                    let areas: [Area] = try await registry("config/area_registry/list", id: 1, socket: socket)
                    let devices: [Device] = try await registry("config/device_registry/list", id: 2, socket: socket)
                    let entities: [Entity] = try await registry("config/entity_registry/list", id: 3, socket: socket)
                    guard areas.count <= 2000, devices.count <= 20000, entities.count <= 40000 else { throw AdapterError.invalidResponse("Home-Assistant-Raumkatalog ist zu groß.") }
                    return combine(areas: areas, devices: devices, entities: entities)
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(3))
                    socket.cancel(with: .goingAway, reason: nil)
                    throw AdapterError.unavailable("Home-Assistant-Raumkatalog nicht erreichbar.")
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
        } onCancel: { socket.cancel(with: .goingAway, reason: nil) }
    }

    private static func read(_ socket: URLSessionWebSocketTask) async throws -> Data {
        try Task.checkCancellation()
        let message = try await socket.receive()
        let data: Data
        switch message {
        case .string(let string): data = Data(string.utf8)
        case .data(let bytes): data = bytes
        @unknown default: throw AdapterError.invalidResponse("Unbekannte Home-Assistant-Nachricht.")
        }
        guard data.count <= 4_000_000 else { throw AdapterError.invalidResponse("Home-Assistant-Nachricht ist zu groß.") }
        try Task.checkCancellation()
        return data
    }

    private static func registry<T: Decodable>(_ type: String, id: Int, socket: URLSessionWebSocketTask) async throws -> T {
        let request = try JSONSerialization.data(withJSONObject: ["id": id, "type": type])
        try await socket.send(.string(String(decoding: request, as: UTF8.self)))
        let reply = try JSONDecoder().decode(Reply<T>.self, from: await read(socket))
        guard reply.id == id, reply.success, let result = reply.result else { throw AdapterError.unavailable("Home Assistant erlaubt den Raumkatalog nicht.") }
        return result
    }
}
