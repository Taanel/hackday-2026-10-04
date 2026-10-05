import Foundation

/// Voice-only credentials. The reasoning key is never replaced by this store.
public struct LocalGeminiTTSKeyStore: Sendable {
    public let fileURL: URL
    public init(directory: URL = RuntimeConfiguration.supportDirectory.appendingPathComponent("Credentials")) {
        fileURL = directory.appendingPathComponent("gemini-tts-api-keys.json")
    }
    public var configuredSlots: Set<Int> {
        guard let slots = try? readSlots() else { return [] }
        return Set(slots.indices.filter { slots[$0] != nil })
    }
    public func loadKeys(fallback: () throws -> String = { try LocalGeminiKeyStore().load() }) throws -> [String] {
        let keys = try readSlots().compactMap { $0 }
        return keys.isEmpty ? [try fallback()] : keys
    }
    public func save(_ key: String, slot: Int) throws {
        guard (0..<4).contains(slot) else { throw invalid }
        let value = try Self.validate(key)
        var slots = try readSlots()
        guard !slots.enumerated().contains(where: { $0.offset != slot && $0.element == value }) else {
            throw AdapterError.unavailable("Dieser TTS-Schlüssel ist bereits in einem anderen Feld gespeichert.")
        }
        slots[slot] = value; try write(slots)
    }
    public func remove(slot: Int) throws {
        guard (0..<4).contains(slot) else { throw invalid }
        var slots = try readSlots(); slots[slot] = nil; try write(slots)
    }
    private func readSlots() throws -> [String?] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return Array(repeating: nil, count: 4) }
        guard let data = try? Data(contentsOf: fileURL), data.count <= 4096,
              let slots = try? JSONDecoder().decode([String?].self, from: data), slots.count == 4 else {
            throw AdapterError.unavailable("Die lokal gespeicherten TTS-Schlüssel konnten nicht gelesen werden.")
        }
        let checked = try slots.map { try $0.map(Self.validate) }
        let keys = checked.compactMap { $0 }
        guard Set(keys).count == keys.count else { throw invalid }
        return checked
    }
    private func write(_ slots: [String?]) throws {
        let manager = FileManager.default, directory = fileURL.deletingLastPathComponent()
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try JSONEncoder().encode(slots).write(to: fileURL, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch { throw AdapterError.unavailable("TTS-Schlüssel konnten lokal nicht gespeichert werden.") }
    }
    private var invalid: AdapterError { AdapterError.unavailable("Ungültige TTS-Schlüsselkonfiguration.") }
    private static func validate(_ key: String) throws -> String {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 512,
              value.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 }) else {
            throw AdapterError.unavailable("Bitte einen TTS-API-Schlüssel ohne Leerzeichen oder Zeilenumbrüche eintragen.")
        }
        return value
    }
}

actor GeminiSpeechCredentials {
    private let loader: @Sendable () throws -> [String]
    private var keys: [String]?
    private var loading: Task<[String], any Error>?
    private var generation = UUID()
    init(loader: @escaping @Sendable () throws -> [String]) { self.loader = loader }
    func load() async throws -> [String] {
        if let keys { return keys }
        let token = generation, loader = loader
        let task = loading ?? Task.detached { try loader() }; loading = task
        do {
            let value = try await task.value
            guard generation == token else { return try await load() }
            keys = value; loading = nil; return value
        } catch {
            guard generation == token else { return try await load() }
            loading = nil; throw error
        }
    }
    func invalidate() { generation = UUID(); keys = nil; loading = nil }
}
