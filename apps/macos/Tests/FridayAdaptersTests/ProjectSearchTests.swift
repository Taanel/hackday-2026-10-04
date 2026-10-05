import Foundation
import Testing
import FridayCore
@testable import FridayAdapters

@Test(arguments: ["Finde Projekt Friday", "Wo habe ich Projekt Friday offen?", "Such mir den Terminal-Tab raus, wo ich Projekt Friday offen habe", "Kannst du mir Projekt Friday zeigen?"])
func spokenProjectQueriesAreBoundedLocalActions(text: String) {
    let action = ActionArgumentParser().parse(intent: "find_project", text: text)
    if text.contains("zeigen") {
        #expect(action == nil) // Unsupported phrasing goes to the bounded Gemini function.
    } else { #expect(action == .findProject(query: "Friday")) }
}

@Test func projectSearchDoesNotConfuseWebResearchOrExplanationsWithLocalLookup() {
    let parser = ActionArgumentParser()
    #expect(parser.parse(intent: "find_project", text: "Erkläre mir Projekt Friday") == nil)
    #expect(parser.parse(intent: "find_project", text: "Suche nach Projekt Friday in Safari") == nil)
    #expect(parser.parse(intent: "find_project", text: "Finde Projekt Friday und lösche alle Dateien") == nil)
    #expect(MacProjectLocator.score(query: "hackday 2026", title: "hackday-2026 — Terminal") == 2)
    #expect(MacProjectLocator.score(query: "friday", title: "Terminal", contents: "~/Projects/Friday > swift build") == 1)
    #expect(MacProjectLocator.score(query: "other", title: "Terminal", contents: "~/Projects/Friday") == 0)
    #expect(!ToolRequest.findProject(query: "").hasValidArguments)
}

@Test func geminiProjectLookupIsTypedAndRejectsUnboundedQueries() throws {
    let valid = Data(#"{"candidates":[{"content":{"parts":[{"functionCall":{"name":"find_project","args":{"query":"hackday"}}}]}}]}"#.utf8)
    #expect(try GeminiReasoningEngine.decodePlan(valid, status: 200, parser: ActionArgumentParser()) == .actions([.findProject(query: "hackday")]))
    #expect(!MacProjectLocator.terminalScript.contains("doScript"))
    #expect(!MacProjectLocator.terminalScript.contains(".history()"))
}

@Test func terminalLookupUsesStableIDsAndRejectsStaleMatchesWithoutOpeningAnApp() async throws {
    let mock = #"""
    var terminal = {activate:function(){},running:function(){return true;},windows:function(){return [{
        id:function(){return 1234;},name:function(){return 'Friday';},tabs:function(){return [{
            tty:function(){return '/dev/ttys999';},customTitle:function(){return '';},selected:function(){return true;},
            contents:function(){return 'x'.repeat(5000)+'Friday';}
        }];}
    }];}};
    """#
    let source = MacProjectLocator.terminalScript.replacingOccurrences(of: "var terminal = Application('com.apple.Terminal');", with: mock)
    #expect(!source.contains("Application("))
    let worker = JSONLineProcess(executable: "/usr/bin/osascript", arguments: ["-l", "JavaScript", "-e", source], startupTimeout: 3)
    func request(_ fields: [String: Any]) async throws -> Data {
        let id = UUID().uuidString
        var fields = fields; fields["id"] = id
        return try await worker.request(JSONSerialization.data(withJSONObject: fields), id: id, timeout: 3)
    }
    do {
        let data = try await request(["op": "snapshot"])
        let reply = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let tabs = reply["tabs"] as! [[String: Any]]
        #expect(tabs.count == 1)
        #expect((tabs[0]["contents"] as! String).count == 4000)
        #expect(tabs[0]["title"] as? String == "Friday")
        let focused = try await request(["op": "focus", "windowID": 1234, "tty": "/dev/ttys999", "query": "friday"])
        #expect((try JSONSerialization.jsonObject(with: focused) as! [String: Any])["ok"] as? Bool == true)
        for invalid: [String: Any] in [
            ["op": "focus", "windowID": 1234, "tty": "/dev/closed", "query": "friday"],
            ["op": "focus", "windowID": 9999, "tty": "/dev/ttys999", "query": "friday"],
            ["op": "focus", "windowID": 1234, "tty": "/dev/ttys999", "query": "differentproject"]
        ] {
            await #expect(throws: AdapterError.self) { try await request(invalid) }
        }
        await worker.stop()
    } catch { await worker.stop(); throw error }
}

private final class ProjectPlanProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var bodies: [String] = []
    static func reset() { lock.lock(); defer { lock.unlock() }; bodies = [] }
    static func requests() -> [String] { lock.lock(); defer { lock.unlock() }; return bodies }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        Self.lock.lock(); Self.bodies.append(String(decoding: body, as: UTF8.self)); Self.lock.unlock()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"candidates":[{"content":{"parts":[{"functionCall":{"name":"find_project","args":{"query":"Friday"}}}]}}]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private struct UnknownProjectDecision: FastDecisionEngine {
    func decide(text: String) async throws -> FastDecision { FastDecision(intent: .unknown, confidence: 0) }
}
private struct PrivateProjectTool: ToolExecutor {
    func execute(_ request: ToolRequest) async throws -> String {
        #expect(request == .findProject(query: "Friday"))
        return "PRIVATE_WINDOW_TITLE_AND_LOCAL_CONTENT"
    }
}

@Test func geminiDelegatesLookupOnceWithoutReceivingLocalWindowContents() async throws {
    ProjectPlanProtocol.reset()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ProjectPlanProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let engine = GeminiReasoningEngine(session: session, applications: ["Safari": "com.apple.Safari"], apiKey: { "test-key" })
    let router = AssistantRouter(decisions: UnknownProjectDecision(), reasoning: engine, tools: PrivateProjectTool())
    let response = try await router.handle("Kannst du mir Projekt Friday zeigen?")
    #expect(response.route == .fastAction)
    #expect(response.text == "PRIVATE_WINDOW_TITLE_AND_LOCAL_CONTENT")
    let requests = ProjectPlanProtocol.requests()
    #expect(requests.count == 1)
    #expect(requests[0].contains("find_project"))
    #expect(!requests[0].contains("PRIVATE_WINDOW_TITLE_AND_LOCAL_CONTENT"))
}

@Test func safariTabSearchReadsLocallyAndDoesNotUseTabIndexFallback() async throws {
    let mock = #"""
    var safari={running:function(){return true;},activate:function(){},windows:function(){return [{
        id:function(){return 42;},tabs:function(){return [{name:function(){return 'Demo';},url:function(){return 'https://example.org';},text:function(){return 'Secret content about Friday';}}];}
    }];}};
    """#
    let script = SafariTabScript.source.replacingOccurrences(of:"var safari = Application('com.apple.Safari');", with:mock)
    #expect(!script.contains("Application(")); #expect(!script.contains("doJavaScript"))
    let worker=JSONLineProcess(executable:"/usr/bin/osascript",arguments:["-l","JavaScript","-e",script],startupTimeout:3)
    func request(_ fields:[String:Any]) async throws -> Data {
        let id=UUID().uuidString; var fields=fields; fields["id"]=id
        return try await worker.request(JSONSerialization.data(withJSONObject:fields),id:id,timeout:3)
    }
    do {
        let body=try await request(["op":"snapshot","query":"secret","contents":true])
        let tabs=(try JSONSerialization.jsonObject(with:body) as! [String:Any])["tabs"] as! [[String:Any]]
        #expect(tabs.count == 1)
        #expect(!String(decoding:body,as:UTF8.self).contains("Secret content"))
        let reply=try await request(["op":"focus","query":"secret","contents":true,"windowID":42,"url":"https://example.org"])
        #expect((try JSONSerialization.jsonObject(with:reply) as! [String:Any])["ok"] as? Bool == true)
        await #expect(throws:AdapterError.self) { try await request(["op":"focus","query":"secret","contents":true,"windowID":42,"url":"https://closed.example.org"]) }
        await worker.stop()
    } catch { await worker.stop(); throw error }
}
