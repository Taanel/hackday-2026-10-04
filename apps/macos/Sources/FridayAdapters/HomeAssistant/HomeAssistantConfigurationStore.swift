import Foundation

public struct HomeAssistantConfiguration: Codable, Sendable {
    public let baseURL: URL
    public let token: String
}

public struct HomeAssistantConfigurationStore: Sendable {
    public let fileURL: URL
    public init(directory: URL = RuntimeConfiguration.supportDirectory.appendingPathComponent("Credentials")) {
        fileURL = directory.appendingPathComponent("home-assistant.json")
    }
    public func load() throws -> HomeAssistantConfiguration {
        guard let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode(HomeAssistantConfiguration.self, from: data) else {
            throw AdapterError.unavailable("Home Assistant fehlt. Bitte Serveradresse und Token unten eintragen.")
        }
        return try Self.validated(url: saved.baseURL.absoluteString, token: saved.token)
    }
    public func save(url: String, token: String) throws -> HomeAssistantConfiguration {
        let origin = try Self.normalizedURL(url)
        var key = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty, let previous = try? load(), previous.baseURL == origin { key = previous.token }
        let value = try Self.validated(url: origin.absoluteString, token: key)
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try JSONEncoder().encode(value).write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch { throw AdapterError.unavailable("Home-Assistant-Zugang konnte lokal nicht gespeichert werden.") }
        return value
    }
    static func normalizedURL(_ raw: String) throws -> URL {
        guard var parts = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""), parts.host?.isEmpty == false,
              parts.user == nil, parts.password == nil else { throw AdapterError.unavailable("Bitte eine HTTP(S)-Serveradresse ohne eingebettete Zugangsdaten eintragen.") }
        parts.path = ""; parts.query = nil; parts.fragment = nil
        guard let url = parts.url else { throw AdapterError.unavailable("Ungültige Home-Assistant-Adresse.") }
        return url
    }
    private static func validated(url: String, token: String) throws -> HomeAssistantConfiguration {
        let baseURL = try normalizedURL(url)
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (16...4096).contains(token.count), token.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }) else {
            throw AdapterError.unavailable("Bitte den vollständigen langlebigen Home-Assistant-Token eintragen.")
        }
        return HomeAssistantConfiguration(baseURL: baseURL, token: token)
    }
}
