import AppKit
import ApplicationServices
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
        case .switchDesktop(let direction):
            return try await Self.switchDesktop(direction)
        case .runExecutable:
            throw AdapterError.unavailable("Freie Terminalbefehle sind in V1 noch nicht eingerichtet.")
        }
    }

    @MainActor private static func switchDesktop(_ direction: DesktopDirection) throws -> String {
        guard AXIsProcessTrusted() else {
            throw AdapterError.unavailable("Für Schreibtischwechsel bitte Friday unter Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen erlauben. Den Button „Computersteuerung erlauben“ verwenden.")
        }
        let key: CGKeyCode = direction == .left ? 123 : 124
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else {
            throw AdapterError.unavailable("Die Tastenkombination konnte nicht gesendet werden.")
        }
        down.flags = .maskControl; up.flags = .maskControl
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        return "Schreibtischwechsel nach \(direction == .left ? "links" : "rechts") angefordert."
    }

    @MainActor public static func requestComputerControl() {
        // Literal value of kAXTrustedCheckOptionPrompt; the SDK imports that
        // CFString constant as a mutable global under Swift 6.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
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
        // Switching to a running app needs no Launch Services launch request.
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first,
           running.activate(options: [.activateAllWindows]) {
            return "\(app.deletingPathExtension().lastPathComponent) geöffnet."
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: app, configuration: config)
        return "\(app.deletingPathExtension().lastPathComponent) geöffnet."
    }
}
