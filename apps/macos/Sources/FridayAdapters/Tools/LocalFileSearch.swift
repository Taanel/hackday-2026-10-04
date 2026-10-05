import Foundation
import FridayCore

struct LocalFileHit: Sendable { let url: URL; let score: Int }
struct LocalFileResults: Sendable { let hits: [LocalFileHit]; let complete: Bool }

/// One bounded Spotlight query per command. No directory crawl or file-content read.
@MainActor final class LocalFileSearch {
    private let query = NSMetadataQuery()
    private var observers: [NSObjectProtocol] = []
    private var timeout: Task<Void, Never>?
    private var continuation: CheckedContinuation<LocalFileResults, any Error>?
    private var text = ""
    private var kind: LocalItemKind = .file

    static func predicate(text: String) -> NSPredicate {
        let words = text.split(whereSeparator: { $0.isWhitespace }).prefix(12)
        let predicates = words.map {
            NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, String($0))
        }
        // Spotlight rejects an AND wrapper containing only one predicate.
        if predicates.count == 1 { return predicates[0] }
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    func search(text: String, kind: LocalItemKind) async throws -> LocalFileResults {
        try Task.checkCancellation()
        guard ToolRequest.findLocalItem(query: text, kind: kind).hasValidArguments else { throw AdapterError.unavailable("Bitte einen konkreten Namen nennen.") }
        self.text = text; self.kind = kind
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                query.predicate = Self.predicate(text: text)
                query.searchScopes = [NSMetadataQueryUserHomeScope]
                observers.append(NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.finish() }
                })
                guard query.start() else { finish(error: AdapterError.unavailable("Spotlight konnte die Suche nicht starten.")); return }
                timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(4)) } catch { return }
                    self?.finish(error: AdapterError.unavailable("Spotlight antwortet gerade nicht. Bitte den Dateinamen genauer nennen und erneut suchen."))
                }
            }
        } onCancel: { Task { @MainActor in self.finish(error: CancellationError()) } }
    }

    private func finish(error: (any Error)? = nil) {
        guard let continuation else { return }
        self.continuation = nil
        query.disableUpdates()
        let result: LocalFileResults
        if error == nil {
            let count = query.resultCount
            let urls = (0..<min(count, 1_000)).compactMap { index -> URL? in
                guard let item = query.result(at: index) as? NSMetadataItem,
                      let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { return nil }
                return URL(fileURLWithPath: path)
            }
            result = LocalFileResults(hits: Self.rank(urls, text: text, kind: kind), complete: count <= 1_000)
        } else { result = LocalFileResults(hits: [], complete: false) }
        query.stop()
        observers.forEach(NotificationCenter.default.removeObserver); observers = []
        timeout?.cancel(); timeout = nil
        if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: result) }
    }

    nonisolated static func rank(_ urls: [URL], text: String, kind: LocalItemKind, root: URL = FileManager.default.homeDirectoryForCurrentUser) -> [LocalFileHit] {
        var seen: Set<String> = []
        return urls.compactMap { url -> LocalFileHit? in
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            guard allowed(resolved, root: root), seen.insert(resolved.path).inserted,
                  let values = try? resolved.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isPackageKey]),
                  values.isPackage != true,
                  (kind == .folder ? values.isDirectory == true : values.isRegularFile == true) else { return nil }
            let score = score(text: text, filename: resolved.lastPathComponent)
            return score > 0 ? LocalFileHit(url: resolved, score: score) : nil
        }.sorted { a, b in a.score == b.score ? a.url.path.localizedStandardCompare(b.url.path) == .orderedAscending : a.score > b.score }
    }

    nonisolated static func allowed(_ url: URL, root: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let base = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard url.isFileURL, url.path.hasPrefix(base) else { return false }
        let relative = String(url.path.dropFirst(base.count))
        let parts = relative.split(separator: "/")
        guard !parts.contains(where: { $0.hasPrefix(".") || ["node_modules", "Credentials", "VoiceProfile"].contains(String($0)) }) else { return false }
        if parts.first == "Library", !relative.hasPrefix("Library/Mobile Documents/") { return false }
        return true
    }

    nonisolated static func score(text: String, filename: String) -> Int {
        let needle = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
        let name = filename.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
        guard !needle.isEmpty else { return 0 }
        if name == needle || (name as NSString).deletingPathExtension == needle { return 4 }
        if name.hasPrefix(needle) { return 3 }
        if name.contains(needle) { return 2 }
        return needle.split(whereSeparator: { $0.isWhitespace }).allSatisfy { name.contains($0) } ? 1 : 0
    }

    nonisolated static func shouldReveal(_ url: URL) -> Bool {
        if let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isExecutableKey]), values.isRegularFile == true, values.isExecutable == true { return true }
        return ["command", "sh", "bash", "zsh", "py", "js", "scpt", "applescript", "workflow", "automator", "pkg", "dmg"].contains(url.pathExtension.lowercased())
    }
}
