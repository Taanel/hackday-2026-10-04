import Foundation

/// Discovers app names from actual bundles, including the user's Applications.
/// No model-generated bundle ID or hand-maintained app allowlist is needed.
public enum MacApplicationCatalog {
    public static func aliases(in roots: [URL] = defaultRoots) -> [String: String] {
        var matches: [String: Set<String>] = [:]
        func read(_ url: URL) {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                  let type = bundle.infoDictionary?["CFBundlePackageType"] as? String,
                  ["APPL", "FNDR"].contains(type) else { return }
            let names = [url.deletingPathExtension().lastPathComponent,
                         bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
                         bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String].compactMap { $0 }
            for name in names { matches[normalize(name), default: []].insert(id) }
        }
        for root in roots {
            if root.pathExtension.lowercased() == "app" { read(root); continue }
            guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                // Safari's system-managed link is marked hidden on recent macOS.
                options: [.skipsPackageDescendants]) else { continue }
            for case let url as URL in iterator where url.pathExtension.lowercased() == "app" { read(url) }
        }
        var aliases = matches.compactMapValues { $0.count == 1 ? $0.first : nil }
        let installed = Set(aliases.values)
        // Familiar localized synonyms only point at an app actually found above.
        for (name, id) in ActionArgumentParser.applications where installed.contains(id) && aliases[name] == nil {
            aliases[name] = id
        }
        return aliases
    }

    public static var defaultRoots: [URL] {
        [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"),
         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
         URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")]
    }

    static func normalize(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de"))
            .filter { $0.isLetter || $0.isNumber }
    }
}
