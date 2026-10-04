import AppKit
import FridayCore

public struct MacToolExecutor: ToolExecutor {
    public let notesDirectory: URL
    public init(notesDirectory: URL = RuntimeConfiguration.supportDirectory.appendingPathComponent("Notes")) {
        self.notesDirectory = notesDirectory
    }

    public func execute(_ request: ToolRequest) async throws -> String {
        try Task.checkCancellation()
        switch request {
        case .openApplication(let identifier):
            guard request.hasValidArguments else { throw AdapterError.unavailable("Ungültiger Programmname.") }
            return try await Self.open(identifier)
        case .searchSafari(let query):
            let url = try Self.safariSearchURL(query: query)
            return try await Self.searchSafari(url: url, query: query)
        case .createNote(let text):
            guard request.hasValidArguments else { throw AdapterError.unavailable("Die Notiz ist leer.") }
            try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
            let filename = "Notiz-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).md"
            try text.write(to: notesDirectory.appendingPathComponent(filename), atomically: true, encoding: .utf8)
            return "Notiz gespeichert: \(filename)"
        case .runExecutable:
            throw AdapterError.unavailable("Freie Terminalbefehle sind in V1 noch nicht eingerichtet.")
        }
    }

    static func safariSearchURL(query: String) throws -> URL {
        guard ToolRequest.searchSafari(query: query).hasValidArguments else {
            throw AdapterError.unavailable("Bitte einen Suchbegriff für Safari angeben.")
        }
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else { throw AdapterError.invalidResponse("Ungültige Safari-Suche.") }
        return url
    }

    @MainActor private static func searchSafari(url: URL, query: String) async throws -> String {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") else {
            throw AdapterError.unavailable("Safari ist nicht installiert.")
        }
        try Task.checkCancellation()
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        _ = try await NSWorkspace.shared.open([url], withApplicationAt: app, configuration: config)
        return "Safari-Suche geöffnet: \(query)"
    }

    @MainActor private static func open(_ identifier: String) async throws -> String {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else {
            throw AdapterError.unavailable("Das gewünschte Programm ist nicht installiert.")
        }
        try Task.checkCancellation()
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: app, configuration: config)
        return "\(app.deletingPathExtension().lastPathComponent) geöffnet."
    }
}
