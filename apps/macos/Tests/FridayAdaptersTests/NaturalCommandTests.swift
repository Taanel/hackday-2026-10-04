import Foundation
import Testing
import FridayCore
@testable import FridayAdapters

@Test(arguments: ["Hey, kannst du mal bitte Safari öffnen?", "Öffne mal bitte Safari", "Mach bitte mal Safari auf", "Kannst du mir bitte Safari öffnen?", "Hi Friday, starte bitte mal Safari"])
func naturalAppCommandsPreserveTheActualApplication(text: String) {
    #expect(ActionArgumentParser().parse(intent: "open_app", text: text) == .openApplication(bundleIdentifier: "com.apple.Safari"))
}

@Test(arguments: ["Kannst du mir eine Notiz machen: Milch kaufen", "Mach bitte mal eine Notiz: Milch kaufen", "Notier mir bitte Milch kaufen", "Kannst du bitte notieren: Milch kaufen"])
func naturalNotesPreserveContent(text: String) {
    #expect(ActionArgumentParser().parse(intent: "create_note", text: text) == .createNote(text: "Milch kaufen"))
}

@Test func naturalCommandNormalizationDoesNotRewriteEmbeddedWords() {
    let parser = ActionArgumentParser()
    #expect(parser.parse(intent: "create_note", text: "Hey, mach bitte mal eine Notiz: Hey, kannst du mal bitte Milch kaufen?") == .createNote(text: "Hey, kannst du mal bitte Milch kaufen?"))
    #expect(parser.parse(intent: "search_web", text: "Hey, suche mal bitte nach mal bitte in Safari") == .searchSafari(query: "mal bitte"))
    #expect(parser.parse(intent: "search_web", text: "Kannst du Safari öffnen und nach Test suchen?") == .searchSafari(query: "Test"))
    for text in ["Note: Wohnzimmer aus", "Merke dir Wohnzimmer aus", "Google Wohnzimmer aus"] {
        #expect(HomeAssistantCommandParser.parse(text) == nil)
    }
}

@Test func naturalHomeCommandsPreserveRoomAndOperation() {
    #expect(HomeAssistantCommandParser.parse("Hey, mach mal das Wohnzimmerlicht aus") == .init(target: "Wohnzimmerlicht", operation: .turnOff))
    #expect(HomeAssistantCommandParser.parse("Kannst du bitte das Licht im Wohnzimmer ausmachen?") == .init(target: "das Licht im Wohnzimmer", operation: .turnOff))
    #expect(HomeAssistantCommandParser.parse("Schalte bitte mal die Kaskade an") == .init(target: "Kaskade", operation: .turnOn))
    #expect(HomeAssistantCommandParser.parse("Stell mal bitte Albedo auf 30 Prozent") == .init(target: "Albedo", operation: .brightness, value: 30))
}

@Test(arguments: ["Hey, erkläre mir bitte wie ich Safari öffne", "Kannst du mir sagen, ob das Wohnzimmer aus ist?", "Kannst du mir sagen, warum das Licht aus ist?", "Kannst du das Wohnzimmerlicht morgen ausschalten?", "Wenn ich komme, mach mal das Licht an", "Notiz: Wohnzimmer aus", "Schalte Wohnzimmer aus und Küche an"])
func naturalQuestionsAndConditionsNeverBecomeHomeActions(text: String) {
    #expect(HomeAssistantCommandParser.parse(text) == nil)
    #expect(ActionArgumentParser().parse(intent: "open_app", text: text) == nil)
}

@Test func naturalLocalCommandsStillRequireRealLayaApproval() async throws {
    let code = #"import sys,json; print(json.dumps({'type':'ready'}),flush=True); [(print(json.dumps({'id':(r:=json.loads(line))['id'],'intent':'reasoning','confidence':0.99,'truncated':False}),flush=True)) for line in sys.stdin]"#
    let worker = JSONLineProcess(executable: "/usr/bin/python3", arguments: ["-u", "-c", code])
    let decision = try await LayaDecisionEngine(worker: worker).decide(text: "Mach mal bitte Safari auf")
    if case .action = decision.intent { Issue.record("Widersprüchliche Modellentscheidung darf keine Aktion freigeben") }
    #expect(!decision.allowsReasoningFallback)
    await worker.stop()
}
