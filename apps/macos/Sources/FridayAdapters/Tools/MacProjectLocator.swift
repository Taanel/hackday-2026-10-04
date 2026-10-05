import AppKit
import ApplicationServices
import FridayCore

public struct ProjectMatch: Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let application: String
}

/// Searches locally. No screen image or terminal contents are sent to an LLM.
public actor MacProjectLocator {
    private final class WindowReference: @unchecked Sendable {
        let element: AXUIElement
        let pid: pid_t
        let query: String
        init(_ element: AXUIElement, pid: pid_t, query: String) { self.element = element; self.pid = pid; self.query = query }
    }
    private struct AppInfo: Sendable { let pid: pid_t; let name: String; let identifier: String }
    private enum Target: Sendable { case window(WindowReference), terminal(windowID: Int, tty: String, query: String), safari(windowID: Int, url: String, query: String, contents: Bool) }
    private struct Candidate: Sendable { let match: ProjectMatch; let target: Target; let score: Int }
    private var candidates: [Candidate] = []
    public var matches: [ProjectMatch] { candidates.map(\.match) }
    public init() {}
    public func clearMatches() { candidates = [] }

    public func find(query: String) async throws -> String {
        guard ToolRequest.findProject(query: query).hasValidArguments else { throw AdapterError.unavailable("Bitte einen konkreten Projektnamen nennen.") }
        guard AXIsProcessTrusted() else {
            throw AdapterError.unavailable("Für die lokale Projektsuche bitte „Computersteuerung erlauben“ wählen und Friday in den Bedienungshilfen freigeben.")
        }
        let apps = await MainActor.run {
            NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != "dev.hackday.friday" }
                .prefix(50).map { AppInfo(pid: $0.processIdentifier, name: $0.localizedName ?? "App", identifier: $0.bundleIdentifier ?? "") }
        }
        var found: [Candidate] = []
        let scanDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        scan: for app in apps {
            try Task.checkCancellation()
            if ContinuousClock.now >= scanDeadline { break }
            let application = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(application, 0.12)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(application, "AXWindows" as CFString, &value) == .success,
                  let windows = value as? [AXUIElement] else { continue }
            for window in windows.prefix(20) {
                try Task.checkCancellation()
                if ContinuousClock.now >= scanDeadline { break scan }
                AXUIElementSetMessagingTimeout(window, 0.12)
                var title: CFTypeRef?
                guard AXUIElementCopyAttributeValue(window, "AXTitle" as CFString, &title) == .success,
                      let text = title as? String else { continue }
                let score = Self.score(query: query, title: text)
                if score > 0 {
                    found.append(Candidate(match: ProjectMatch(id: UUID(), title: String(text.prefix(180)), application: app.name),
                                           target: .window(WindowReference(window, pid: app.pid, query: query)), score: score))
                }
            }
        }
        var terminalUnavailable = false
        if apps.contains(where: { $0.identifier == "com.apple.Terminal" }) {
            do {
                let data = try await terminalRequest(op: "snapshot")
                let tabs = try JSONDecoder().decode(TerminalReply.self, from: data).tabs ?? []
                // Tab matches replace duplicate Terminal window matches.
                found.removeAll { candidate in
                    if case .window(let window) = candidate.target {
                        return apps.contains { $0.pid == window.pid && $0.identifier == "com.apple.Terminal" }
                    }
                    return false
                }
                for tab in tabs {
                    let score = Self.score(query: query, title: tab.title, contents: tab.contents)
                    if score > 0 {
                        found.append(Candidate(match: ProjectMatch(id: UUID(), title: "Tab \(tab.index): \(tab.title)", application: "Terminal"),
                                               target: .terminal(windowID: tab.windowID, tty: tab.tty, query: query), score: score))
                    }
                }
            } catch is CancellationError { throw CancellationError() }
            catch { terminalUnavailable = true }
        }
        try Task.checkCancellation()
        candidates = Array(found.sorted { $0.score > $1.score }.prefix(8))
        guard !candidates.isEmpty else {
            return terminalUnavailable
                ? "Kein Fenstertitel mit „\(query)“ gefunden. Für Terminal-Tab-Inhalte bitte Friday den Terminal-Zugriff unter Datenschutz & Sicherheit → Automation erlauben."
                : "Kein offenes Fenster oder Terminal-Tab mit „\(query)“ im Titel oder sichtbaren Terminaltext gefunden. Ich habe lokal gesucht; keine Screenshots oder Inhalte an Gemini gesendet."
        }
        if candidates.count == 1, let only = candidates.first {
            return try await focus(only.match.id)
        }
        return "\(candidates.count) passende Fenster oder Tabs gefunden. Im Friday-Fenster einen Treffer wählen."
    }

    public func focus(_ id: UUID) async throws -> String {
        guard let candidate = candidates.first(where: { $0.match.id == id }) else {
            throw AdapterError.unavailable("Der Treffer ist nicht mehr aktuell. Bitte erneut suchen.")
        }
        try Task.checkCancellation()
        switch candidate.target {
        case .safari(let windowID, let url, let query, let contents):
            _ = try await safariRequest(op: "focus", query: query, contents: contents, windowID: windowID, url: url)
        case .terminal(let windowID, let tty, let query):
            _ = try await terminalRequest(op: "focus", windowID: windowID, tty: tty, query: query)
        case .window(let reference):
            try await MainActor.run {
                try Task.checkCancellation()
                guard let app = NSRunningApplication(processIdentifier: reference.pid), !app.isTerminated else {
                    throw AdapterError.unavailable("Das gefundene Programm wurde inzwischen geschlossen.")
                }
                var title: CFTypeRef?
                guard AXUIElementCopyAttributeValue(reference.element, "AXTitle" as CFString, &title) == .success,
                      let currentTitle = title as? String, Self.score(query: reference.query, title: currentTitle) > 0 else {
                    throw AdapterError.unavailable("Das Fenster passt nicht mehr zum Projekt. Bitte erneut suchen.")
                }
                _ = AXUIElementSetAttributeValue(reference.element, "AXMinimized" as CFString, kCFBooleanFalse)
                _ = app.activate(options: [])
                guard AXUIElementPerformAction(reference.element, "AXRaise" as CFString) == .success else {
                    throw AdapterError.unavailable("Das gefundene Fenster konnte nicht fokussiert werden.")
                }
                _ = AXUIElementSetAttributeValue(AXUIElementCreateApplication(reference.pid), "AXFocusedWindow" as CFString, reference.element)
            }
        }
        try Task.checkCancellation()
        candidates = []
        return "Gefunden und fokussiert: \(candidate.match.application) · \(candidate.match.title)."
    }

    public func findSafari(query: String, searchContents: Bool) async throws -> String {
        guard ToolRequest.findSafariTab(query: query, searchContents: searchContents).hasValidArguments else { throw AdapterError.unavailable("Bitte einen konkreten Safari-Suchbegriff nennen.") }
        let data = try await safariRequest(op: "snapshot", query: query, contents: searchContents)
        struct Reply: Decodable {
            struct Tab: Decodable { let windowID: Int; let title: String; let url: String }
            let tabs: [Tab]; let contentUnavailable: Bool?
        }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        try Task.checkCancellation()
        candidates = Array(reply.tabs.prefix(8)).map { tab in
            Candidate(match: ProjectMatch(id: UUID(), title: tab.title + " · " + tab.url, application: "Safari"),
                      target: .safari(windowID: tab.windowID, url: tab.url, query: query, contents: searchContents), score: 1)
        }
        if let only = candidates.first, candidates.count == 1 { return try await focus(only.match.id) }
        if !candidates.isEmpty { return "\(candidates.count) Safari-Tabs gefunden. Im Friday-Fenster einen Treffer wählen." }
        return reply.contentUnavailable == true ? "Kein passender Titel oder Link gefunden; der Safari-Seitentext war nicht lesbar." : "Kein offener Safari-Tab passt zu „\(query)“. Lokal in Titel, Adresse\(searchContents ? " und Seitentext" : "") gesucht."
    }

    private func safariRequest(op: String, query: String, contents: Bool, windowID: Int? = nil, url: String? = nil) async throws -> Data {
        let worker = JSONLineProcess(executable: "/usr/bin/osascript", arguments: ["-l", "JavaScript", "-e", SafariTabScript.source], startupTimeout: 3)
        let id = UUID().uuidString
        var fields: [String: Any] = ["id": id, "op": op, "query": MacApplicationCatalog.normalize(query), "contents": contents]
        if let windowID { fields["windowID"] = windowID }; if let url { fields["url"] = url }
        do {
            let reply = try await worker.request(JSONSerialization.data(withJSONObject: fields), id: id, timeout: 10)
            await worker.stop(); return reply
        } catch { await worker.stop(); throw error }
    }

    static func score(query: String, title: String, contents: String = "") -> Int {
        let needle = MacApplicationCatalog.normalize(query)
        guard needle.count >= 2 else { return 0 }
        if MacApplicationCatalog.normalize(title).contains(needle) { return 2 }
        return MacApplicationCatalog.normalize(String(contents.suffix(4_000))).contains(needle) ? 1 : 0
    }

    private struct TerminalReply: Decodable {
        struct Tab: Decodable {
            let windowID: Int; let index: Int; let tty: String; let title: String; let contents: String
        }
        let tabs: [Tab]?
    }

    private func terminalRequest(op: String, windowID: Int? = nil, tty: String? = nil, query: String? = nil) async throws -> Data {
        // Fixed script, structured arguments through stdin. Never runs a shell
        // command inside Terminal or interpolates spoken text into executable code.
        let worker = JSONLineProcess(executable: "/usr/bin/osascript", arguments: ["-l", "JavaScript", "-e", Self.terminalScript], startupTimeout: 3)
        let id = UUID().uuidString
        var request: [String: Any] = ["id": id, "op": op]
        if let windowID { request["windowID"] = windowID }
        if let tty { request["tty"] = tty }
        if let query { request["query"] = MacApplicationCatalog.normalize(query) }
        do {
            let data = try JSONSerialization.data(withJSONObject: request)
            let reply = try await worker.request(data, id: id, timeout: 12)
            await worker.stop()
            return reply
        } catch { await worker.stop(); throw error }
    }

    static let terminalScript = #"""
    ObjC.import('Foundation');
    function emit(value) {
        var line = $.NSString.alloc.initWithUTF8String(JSON.stringify(value) + '\n');
        $.NSFileHandle.fileHandleWithStandardOutput.writeData(line.dataUsingEncoding($.NSUTF8StringEncoding));
    }
    function normalize(value) {
        return String(value).normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^\p{L}\p{N}]/gu,'');
    }
    emit({type:'ready'});
    while (true) {
        var data = $.NSFileHandle.fileHandleWithStandardInput.availableData;
        if (data.length === 0) break;
        var raw = ObjC.unwrap($.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding));
        var request;
        try {
            request = JSON.parse(raw.trim());
            var terminal = Application('com.apple.Terminal');
            if (!terminal.running()) throw new Error('closed');
            var windows = terminal.windows().slice(0,20);
            if (request.op === 'snapshot') {
                var results = [];
                windows.forEach(function(window) {
                    window.tabs().slice(0,20).forEach(function(tab,index) {
                        if (results.length >= 80) return;
                        var custom = tab.customTitle();
                        var title = custom || (tab.selected() ? window.name() : 'Terminal');
                        results.push({windowID:window.id(),index:index+1,tty:tab.tty(),title:String(title).slice(0,180),contents:String(tab.contents()).slice(-4000)});
                    });
                });
                emit({id:request.id,tabs:results});
            } else if (request.op === 'focus') {
                var window = windows.filter(function(w) { return w.id() === request.windowID; })[0];
                if (!window) throw new Error('closed');
                var tab = window.tabs().filter(function(t) { return t.tty() === request.tty; })[0];
                if (!tab) throw new Error('closed');
                var title = tab.customTitle() || (tab.selected() ? window.name() : 'Terminal');
                if (!request.query || (normalize(title).indexOf(request.query) < 0 && normalize(String(tab.contents()).slice(-4000)).indexOf(request.query) < 0)) throw new Error('changed');
                tab.selected = true;
                window.miniaturized = false;
                window.index = 1;
                terminal.activate();
                emit({id:request.id,ok:true});
            } else { throw new Error('invalid operation'); }
        } catch (error) {
            emit({id:request ? request.id : null,error:'Terminal-Zugriff fehlgeschlagen. Bitte Automation für Friday erlauben; der Tab muss noch offen sein.'});
        }
    }
    """#
}
