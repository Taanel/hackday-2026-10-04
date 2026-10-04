import Foundation
import Testing
import FridayCore
@testable import FridayAdapters

@Test(arguments: ["Kannst du Shaper 3D öffnen?", "Öffne Shapr 3D", "Bitte öffne Shapr3D", "Mach Shapr3D auf", "Kannst du bitte Shapr3D für mich öffnen?"])
func spokenInstalledAppNamesResolveDespiteSpacingAndOneTypo(text: String) {
    let parser = ActionArgumentParser(applications: ["Shapr3D": "com.shapr3d.shapr", "Blender": "org.blenderfoundation.blender"])
    #expect(parser.parse(intent: "open_app", text: text) == .openApplication(bundleIdentifier: "com.shapr3d.shapr"))
}

@Test func ambiguousAndShortFuzzyAppNamesNeverPickAnArbitraryApp() {
    let parser = ActionArgumentParser(applications: ["FooEditor": "example.one", "FooEdator": "example.two", "Mail": "com.apple.mail"])
    #expect(parser.parse(intent: "open_app", text: "Öffne FooEddtor") == nil)
    #expect(parser.parse(intent: "open_app", text: "Öffne Mal") == nil)
}

@Test(arguments: ["Wechsel Schreibtisch", "Wechsle zum nächsten Schreibtisch", "Geh zum nächsten Desktop", "Wechsel Schreibtisch nach links"])
func desktopChangesAreComputerActions(text: String) {
    #expect(ActionArgumentParser().parse(intent: "switch_desktop", text: text) != nil)
}

@Test func hexPreparesOnceAndReusesTheWarmService() async throws {
    let code = #"""
import sys,json,threading,http.server
counts={'models':0,'prepare':0,'transcriptions':0}
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*args): pass
 def do_GET(self):
  counts['models']+=1; self.send_response(200); self.end_headers(); self.wfile.write(b'[{"id":"whisper_large_v3_turbo","installed":true,"verified":true}]')
 def do_POST(self):
  self.rfile.read(int(self.headers.get('Content-Length','0'))); self.send_response(200); self.end_headers()
  if '/prepare' in self.path: counts['prepare']+=1; self.wfile.write(b'data: {"type":"loading"}\n\ndata: {"type":"ok"}\n\n')
  else: counts['transcriptions']+=1; self.wfile.write(b'{"transcript":"test"}')
server=http.server.HTTPServer(('127.0.0.1',0),Handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
print(json.dumps({'type':'ready','url':f'http://127.0.0.1:{server.server_port}','token':'test-token','apiVersion':'2'}),flush=True)
for line in sys.stdin:
 r=json.loads(line); print(json.dumps({'id':r['id'],**counts}),flush=True)
"""#
    let worker = JSONLineProcess(executable: "/usr/bin/python3", arguments: ["-u", "-c", code])
    let hex = HexService(worker: worker)
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
    defer { try? FileManager.default.removeItem(at: file) }
    try WAVEncoder.encode(Array(repeating: 0, count: 1600)).write(to: file)
    try await hex.start()
    try await hex.start()
    #expect(try await hex.transcribe(audioFile: file) == "test")
    let result = try await worker.request(Data(#"{"id":"counts"}"#.utf8), id: "counts")
    await hex.stop()
    struct Counts: Decodable { let models: Int; let prepare: Int; let transcriptions: Int }
    let counts = try JSONDecoder().decode(Counts.self, from: result)
    #expect(counts.models == 1)
    #expect(counts.prepare == 1)
    #expect(counts.transcriptions == 1)
}

@Test(arguments: ["Öffne Safari und suche nach test", "Öffne Safari und suche nach Test.", "Bitte öffne Safari und suche nach roten Schuhen", "Starte Safari und google Test & Beispiel", "Suche nach test", "Suche bitte in Safari nach test"])
func naturalSafariSearchAlsoOpensTheBrowser(text: String) {
    #expect(ActionArgumentParser().parse(intent: "search_web", text: text) != nil)
}

@Test func openingAndSearchingKeepsOnlyTheSearchTerms() {
    #expect(ActionArgumentParser().parse(intent: "search_web", text: "Öffne Safari und suche nach test") == .searchSafari(query: "test"))
    #expect(ActionArgumentParser().parse(intent: "search_web", text: "Öffne Safari und suche nach test und öffne Terminal") == nil)
}

@Test func microphonePCMIsBoundedBeforeSendingToWake() async throws {
    let code = #"""
import sys,json,base64,struct,math; print(json.dumps({'type':'ready'}),flush=True); valid=True; count=0
for line in sys.stdin:
 r=json.loads(line)
 if r.get('op')=='audio':
  raw=base64.b64decode(r['pcm']); v=struct.unpack('<'+'f'*(len(raw)//4),raw); count+=len(v); valid=valid and len(v)<=16000 and all(math.isfinite(s) and abs(s)<=1 for s in v)
 elif 'id' in r: print(json.dumps({'id':r['id'],'valid':valid,'count':count}),flush=True)
"""#
    let worker = JSONLineProcess(executable: "/usr/bin/python3", arguments: ["-u", "-c", code])
    let wake = MoonshineWakeWordDetector(worker: worker)
    try await wake.start()
    try await wake.feed([.nan, .infinity, -1.1, 1.1] + Array(repeating: 0.0, count: 20_000))
    let data = try await worker.request(Data(#"{"id":"check"}"#.utf8), id: "check")
    await worker.stop()
    struct Reply: Decodable { let valid: Bool; let count: Int }
    let reply = try JSONDecoder().decode(Reply.self, from: data)
    #expect(reply.valid)
    #expect(reply.count == 20_004)
}

@Test(arguments: ["Suche nach test auf Safari", "Suche in Safari nach roten Schuhen", "Suche auf Safari nach Test & Beispiel"])
func safariSearchCommandsUseADirectAction(text: String) {
    #expect(ActionArgumentParser().parse(intent: "search_web", text: text) != nil)
}

@Test func layaReceivesCanonicalSafariSearchAndKeepsTheOriginalQuery() async throws {
    let code = #"import sys,json; print(json.dumps({'type':'ready'}),flush=True); [(print(json.dumps({'id':(r:=json.loads(line))['id'],'intent':'search_web' if r['text']=='Bitte f\u00fchre eine Websuche in Safari nach dem Suchbegriff test aus.' else 'unknown','confidence':0.99,'truncated':False,'error':None if r['text']=='Bitte f\u00fchre eine Websuche in Safari nach dem Suchbegriff test aus.' else ascii(r['text'])}),flush=True)) for line in sys.stdin]"#
    let worker = JSONLineProcess(executable: "/usr/bin/python3", arguments: ["-u", "-c", code])
    let decision = try await LayaDecisionEngine(worker: worker).decide(text: "Suche nach test auf Safari")
    await worker.stop()
    guard case .action(let request) = decision.intent else {
        Issue.record("Safari-Suche wurde nicht an Laya normalisiert")
        return
    }
    #expect(request == .searchSafari(query: "test"))
}

@Test func installedAppNamesNeedNoManualConfiguration() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let contents = root.appendingPathComponent(".Beliebige Neue App.app/Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "example.new.application", "CFBundleName": "Beliebige Neue App", "CFBundlePackageType": "APPL"], format: .xml, options: 0)
    try plist.write(to: contents.appendingPathComponent("Info.plist"))
    let parser = ActionArgumentParser(applications: MacApplicationCatalog.aliases(in: [root]))
    #expect(parser.parse(intent: "open_app", text: "Öffne Beliebige Neue App") == .openApplication(bundleIdentifier: "example.new.application"))
    #expect(parser.parse(intent: "open_app", text: "Öffne Beliebige Neue App und Safari") == nil)
}

@Test func safariSearchPreservesQueryAndRejectsCompoundActions() throws {
    #expect(ActionArgumentParser().parse(intent: "search_web", text: "Suche nach test auf Safari") == .searchSafari(query: "test"))
    #expect(ActionArgumentParser().parse(intent: "search_web", text: "Suche nach test auf Safari und öffne Terminal") == nil)
    let query = "Test & Beispiel + Grüße #1"
    let url = try MacToolExecutor.safariSearchURL(query: query)
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
    #expect(components.host == "www.google.com")
    #expect(components.queryItems == [URLQueryItem(name: "q", value: query)])
    #expect(throws: AdapterError.self) { try MacToolExecutor.safariSearchURL(query: "  ") }
}

@Test(arguments: ["Öffne Safari", "öffne Safari.", "Kannst du Safari öffnen?", "Bitte starte Safari"])
func explicitApplicationCommandsResolve(text: String) {
    #expect(ActionArgumentParser().parse(intent: "open_app", text: text) == .openApplication(bundleIdentifier: "com.apple.Safari"))
}

@Test(arguments: ["Öffne Safari und Terminal", "Öffne irgendein Programm", "Schließe Safari", "Safari", "Öffne Safari; rm -rf /", "Erkläre mir wie ich Safari öffne"])
func ambiguousOrMultipleActionsAreRejected(text: String) {
    #expect(ActionArgumentParser().parse(intent: "open_app", text: text) == nil)
}

@Test(arguments: ["Mach eine Notiz: Milch kaufen", "Schreibe eine Notiz Milch kaufen", "Notiz: Milch kaufen", "Notiere Milch kaufen"])
func spokenNotesAcceptMissingPunctuation(text: String) {
    #expect(ActionArgumentParser().parse(intent: "create_note", text: text) == .createNote(text: "Milch kaufen"))
}

@Test func germanArticleAndCompoundNoteCommands() {
    #expect(ActionArgumentParser().parse(intent: "open_app", text: "Bitte starte den Taschenrechner") == .openApplication(bundleIdentifier: "com.apple.calculator"))
    #expect(ActionArgumentParser().parse(intent: "create_note", text: "Mach eine Notiz: Milch kaufen und öffne Safari") == nil)
}

@Test func cancelledStartupDoesNotLaunchWorker() async throws {
    let marker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: marker) }
    let worker = JSONLineProcess(executable: "/usr/bin/touch", arguments: [marker.path])
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await worker.start()
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(!FileManager.default.fileExists(atPath: marker.path))
    await worker.stop()
}

@Test func noteStorePreservesContentsExactlyOnce() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executor = MacToolExecutor(notesDirectory: directory)
    let text = "Milch kaufen\nNächsten Freitag: 10 Uhr."
    _ = try await executor.execute(.createNote(text: text))
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    #expect(files.count == 1)
    #expect(try String(contentsOf: files[0], encoding: .utf8) == text)
}

@Test func terminalAndUnknownAppsFailWithoutExecution() async {
    let executor = MacToolExecutor()
    await #expect(throws: AdapterError.self) { try await executor.execute(.openApplication(bundleIdentifier: "com.example.unknown")) }
    await #expect(throws: AdapterError.self) {
        try await executor.execute(.runExecutable(TerminalCommand(executablePath: "/bin/echo", arguments: ["test"], workingDirectory: URL(fileURLWithPath: "/tmp"))))
    }
}

@Test func wavContainsRealPCM16HeaderAndClampedSamples() {
    let wav = WAVEncoder.encode([0, 1, -1, .nan])
    #expect(String(data: wav.prefix(4), encoding: .ascii) == "RIFF")
    #expect(String(data: wav[8..<12], encoding: .ascii) == "WAVE")
    #expect(wav.count == 52)
    #expect(Array(wav[44...]) == [0,0,255,127,1,128,0,0])
}

@Test func processUsesIDsAndCanRestartAfterStop() async throws {
    let program = #"import sys,json; print(json.dumps({'type':'ready'}),flush=True); [(print(json.dumps({'id':json.loads(line)['id'],'value':42}),flush=True)) for line in sys.stdin]"#
    let worker = JSONLineProcess(executable: "/usr/bin/python3", arguments: ["-u", "-c", program])
    for _ in 0..<2 {
        let id = UUID().uuidString
        let data = try await worker.request(Data("{\"id\":\"\(id)\"}".utf8), id: id)
        #expect(String(data: data, encoding: .utf8)?.contains("42") == true)
        await worker.stop()
    }
}

@Test func processDeadlineStopsAnUnresponsiveWorker() async throws {
    let worker = JSONLineProcess(executable: "/usr/bin/python3", arguments: ["-u","-c", "import time; print('{\"type\":\"ready\"}',flush=True); time.sleep(20)"])
    await #expect(throws: AdapterError.self) {
        try await worker.request(Data("{\"id\":\"test\"}".utf8), id: "test", timeout: 0.05)
    }
    await worker.stop()
}
