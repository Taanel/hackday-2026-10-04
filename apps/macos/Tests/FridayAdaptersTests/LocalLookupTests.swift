import Foundation
import Testing
import FridayCore
@testable import FridayAdapters

@Suite struct LocalLookupTests {
    @Test func naturalCommandsFindExistingItemsInsteadOfStartingWebSearches() {
        let parser = ActionArgumentParser()
        for (text, expected): (String, ToolRequest) in [
            ("Jo, such den Tab raus, wo ich Friday offen habe", .findSafariTab(query: "Friday", searchContents: true)),
            ("Such mir mal den Safari-Tab mit Inhalt Strompreis raus", .findSafariTab(query: "Strompreis", searchContents: true)),
            ("Such den Tab mit Seite GitHub", .findSafariTab(query: "GitHub", searchContents: false)),
            ("Such den Terminal-Tab raus, wo ich Friday offen habe", .findProject(query: "Friday")),
            ("Finde Datei Rechnung.pdf und öffne sie", .findLocalItem(query: "Rechnung.pdf", kind: .file)),
            ("Such mir mal Datei Rechnung.pdf raus und öffne sie mir mal", .findLocalItem(query: "Rechnung.pdf", kind: .file)),
            ("Such den Ordner Friday im Finder", .findLocalItem(query: "Friday", kind: .folder)),
            ("Such mir mal raus, wo der Ordner Friday ist, und mache mir den im Finder auf", .findLocalItem(query: "Friday", kind: .folder)),
            ("Finde Datei „Bericht 2026.pdf“", .findLocalItem(query: "Bericht 2026.pdf", kind: .file))
        ] { #expect(parser.parse(intent: "find_project", text: text) == expected, "\(text)") }
    }

    @Test(arguments: ["Erkläre mir die Datei Rechnung.pdf", "Such Datei Bericht und lösche alle Dateien", "Such Ordner Friday und starte Terminal", "Such den Tab mit GitHub und schließe Safari", "Finde Datei x", "Suche nach Ordnern im Internet"])
    func lookupRejectsQuestionsAndExtraActions(text: String) { #expect(ActionArgumentParser().parse(intent: "find_project", text: text) == nil) }

    @Test @MainActor func spotlightPredicateTreatsSpokenQuotesAsData() {
        let text = "report' OR TRUEPREDICATE OR '"
        let predicate = LocalFileSearch.predicate(text: text)
        #expect(!predicate.evaluate(with: [NSMetadataItemFSNameKey: "anything.pdf"]))
        #expect(predicate.evaluate(with: [NSMetadataItemFSNameKey: text + ".pdf"]))
    }

    @Test func fileResultsDistinguishFoldersExcludePrivateAndStalePathsAndKeepAmbiguity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let exact = root.appendingPathComponent("Überblick.pdf")
        let other = root.appendingPathComponent("Überblick 2026.pdf")
        let folder = root.appendingPathComponent("Überblick")
        let privateFile = root.appendingPathComponent(".hidden/Überblick.pdf")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: privateFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        for url in [exact, other, privateFile] { try Data().write(to: url) }
        let all = [other, exact, folder, privateFile, exact, root.appendingPathComponent("missing Überblick.pdf"), URL(fileURLWithPath: "/etc/passwd")]
        let files = LocalFileSearch.rank(all, text: "uberblick", kind: .file, root: root)
        #expect(files.map(\.url) == [exact, other])
        #expect(LocalFileSearch.rank(all, text: "uberblick", kind: .folder, root: root).map(\.url.path) == [folder.path])
        #expect(LocalFileSearch.shouldReveal(root.appendingPathComponent("task.command")))
        #expect(!LocalFileSearch.shouldReveal(exact))
    }

    @Test func geminiCanDelegateFileLookupButCannotSupplyAPathOrShellCommand() throws {
        func plan(_ args: String) throws -> ReasoningPlan {
            let data = Data("{\"candidates\":[{\"content\":{\"parts\":[{\"functionCall\":{\"name\":\"find_file\",\"args\":\(args)}}]}}]}".utf8)
            return try GeminiReasoningEngine.decodePlan(data, status: 200, parser: ActionArgumentParser())
        }
        #expect(try plan(#"{"query":"Rechnung.pdf"}"#) == .actions([.findLocalItem(query: "Rechnung.pdf", kind: .file)]))
        #expect(throws: FridayError.self) { try plan(#"{"query":"Rechnung.pdf","path":"/etc/passwd"}"#) }
    }

    @Test @MainActor func spotlightQueryStopsOnCancellation() async throws {
        let search = LocalFileSearch()
        let task = Task { try await search.search(text: UUID().uuidString, kind: .file) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FRIDAY_SPOTLIGHT_PROBE"] == "1"), arguments: ["Friday", "Friday App"]) @MainActor
    func actualSpotlightSearchIsReadOnlyAndTerminates(text: String) async throws {
        let start = ContinuousClock.now
        let result = try await LocalFileSearch().search(text: text, kind: .folder)
        #expect(!result.hits.isEmpty)
        print("Spotlight: \(result.hits.count) Ordner gefunden in \(start.duration(to: .now)); keine Dateien geöffnet.")
    }
}
