import Foundation

public struct LocalGeminiKeyStore: Sendable {
    public let fileURL: URL
    public init(directory: URL = RuntimeConfiguration.supportDirectory.appendingPathComponent("Credentials")) {
        fileURL = directory.appendingPathComponent("gemini-api-key.txt")
    }
    public var isConfigured: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    public func load() throws -> String {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            throw AdapterError.unavailable("Gemini-Schlüssel fehlt. Bitte unten im Friday-Fenster eintragen und speichern.")
        }
        return try Self.validate(contents)
    }

    public func save(_ key: String) throws {
        let value = try Self.validate(key)
        let manager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            // Atomic-write temporary files stay inside the private directory.
            try Data(value.utf8).write(to: fileURL, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            throw AdapterError.unavailable("Gemini-Schlüssel konnte lokal nicht gespeichert werden.")
        }
    }

    private static func validate(_ key: String) throws -> String {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 512,
              value.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }) else {
            throw AdapterError.unavailable("Bitte einen API-Schlüssel ohne Leerzeichen oder Zeilenumbrüche eintragen.")
        }
        return value
    }
}
