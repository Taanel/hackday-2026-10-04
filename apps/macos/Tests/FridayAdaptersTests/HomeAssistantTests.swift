import Foundation
import Testing
import FridayCore
@testable import FridayAdapters

private final class HomeProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var requests: [URLRequest] = []
    nonisolated(unsafe) private static var status = 200
    static func reset(status: Int = 200) { lock.lock(); defer { lock.unlock() }; requests = []; self.status = status }
    static var posts: [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests.filter { $0.httpMethod == "POST" } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var recorded = request
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(), buffer = [UInt8](repeating:0,count:4096)
            while true { let count = stream.read(&buffer,maxLength:buffer.count); if count <= 0 { break }; data.append(contentsOf:buffer.prefix(count)) }
            recorded.httpBody = data
        }
        Self.lock.lock(); Self.requests.append(recorded); let status = Self.status; Self.lock.unlock()
        let body: String
        if request.url!.path == "/api/states" {
            body = #"[{"entity_id":"light.wohnzimmer","state":"off","attributes":{"friendly_name":"Wohnzimmer Licht","supported_color_modes":["brightness"]}},{"entity_id":"switch.kaffeemaschine","state":"off","attributes":{"friendly_name":"Kaffeemaschine"}},{"entity_id":"scene.abend","state":"unknown","attributes":{"friendly_name":"Abend"}},{"entity_id":"climate.wohnzimmer","state":"heat","attributes":{"friendly_name":"Wohnzimmer Heizung","supported_features":1,"min_temp":7,"max_temp":30,"target_temp_step":0.5}}]"#
        } else if request.url!.path == "/api/config" { body = #"{"unit_system":{"temperature":"°C"}}"# }
        else { body = "[]" }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized) struct HomeAssistantTests {
    func context() throws -> (URL, HomeAssistantClient, URLSession) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = HomeAssistantConfigurationStore(directory: directory)
        _ = try store.save(url: "http://homeassistant.local/home/overview", token: "private-test-token")
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [HomeProtocol.self]
        let session = URLSession(configuration: configuration)
        return (directory, HomeAssistantClient(store: store, session: session), session)
    }
    @Test func privateStoreNormalizesFrontendAndRestrictsTokenReuseToSameServer() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HomeAssistantConfigurationStore(directory: dir)
        let saved = try store.save(url: "http://homeassistant.local/home/overview", token: "private-test-token")
        #expect(saved.baseURL.absoluteString == "http://homeassistant.local")
        #expect(try store.save(url: "http://homeassistant.local", token: "").token == "private-test-token")
        #expect(throws: AdapterError.self) { try store.save(url: "http://different.local", token: "") }
        #expect(throws: AdapterError.self) { try store.save(url: "http://user:pass@homeassistant.local", token: "private-test-token") }
        let mode = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.posixPermissions] as! Int
        #expect(mode == 0o600)
    }
    @Test func discoveredDevicesUseRealServicesAndSceneMayNeverHaveBeenActivated() async throws {
        HomeProtocol.reset()
        let (directory, client, session) = try context()
        defer { session.invalidateAndCancel(); try? FileManager.default.removeItem(at: directory) }
        for command in [HomeAssistantAction(target:"Wohnzimmer Licht", operation:.turnOn),
                        .init(target:"Wohnzimmer Licht", operation:.brightness, value:30),
                        .init(target:"Kaffeemaschine", operation:.turnOff),
                        .init(target:"Abend", operation:.activateScene),
                        .init(target:"Wohnzimmer Heizung", operation:.temperature, value:21.5)] {
            #expect(try await client.execute(command).contains("angenommen"))
        }
        #expect(HomeProtocol.posts.map { $0.url!.path } == ["/api/services/light/turn_on", "/api/services/light/turn_on", "/api/services/switch/turn_off", "/api/services/scene/turn_on", "/api/services/climate/set_temperature"])
        #expect(HomeProtocol.posts.allSatisfy { $0.value(forHTTPHeaderField:"Authorization") == "Bearer private-test-token" && $0.url!.query == nil })
        let payload = try JSONSerialization.jsonObject(with: HomeProtocol.posts[1].httpBody!) as! [String:Any]
        #expect(payload["entity_id"] as? String == "light.wohnzimmer")
        #expect(payload["brightness_pct"] as? Double == 30)
        await #expect(throws: AdapterError.self) { try await client.execute(.init(target:"Wohnzimmer Heizung", operation:.temperature, value:21.3)) }
        await #expect(throws: AdapterError.self) { try await client.execute(.init(target:"missing", operation:.turnOn)) }
        #expect(HomeProtocol.posts.count == 5)
    }
    @Test func failedDiscoveryDoesNotActAndServiceNamesCannotBeInjected() async throws {
        HomeProtocol.reset(status:401)
        let (directory, client, session) = try context()
        defer { session.invalidateAndCancel(); try? FileManager.default.removeItem(at: directory) }
        await #expect(throws: AdapterError.self) { try await client.execute(.init(target:"Wohnzimmer Licht", operation:.turnOn)) }
        #expect(HomeProtocol.posts.isEmpty)
        #expect(!HomeAssistantAction(target:"a", operation:.turnOn).isValid)
        #expect(!HomeAssistantAction(target:"Licht", operation:.brightness, value:Double.nan).isValid)
        #expect(!HomeAssistantAction(target:"Licht", operation:.turnOn, value:20).isValid)
        let entities = try JSONDecoder().decode([HomeAssistantEntity].self, from: Data(#"[{"entity_id":"light.a","state":"off","attributes":{"friendly_name":"Licht"}},{"entity_id":"light.b","state":"off","attributes":{"friendly_name":"Licht"}}]"#.utf8))
        #expect(throws: AdapterError.self) { try HomeAssistantClient.resolve(.init(target:"Licht", operation:.turnOn), in:entities) }
    }
}

@Test(arguments:["Erkläre, wie ich das Licht einschalte", "Schalte das Licht an und öffne Safari", "Schalte morgen das Licht an", "Wenn ich komme schalte Licht an", "Schalte das Licht an, falls es dunkel ist"])
func extendedLocalActionsDoNotInventHomeActions(text:String) { #expect(HomeAssistantCommandParser.parse(text) == nil) }

@Test func extendedLocalActionsParseFoldersLinksDevicesAndSafariTabs() {
    let p=ActionArgumentParser()
    #expect(p.parse(intent:"open_folder",text:"Öffne Downloads") == .openFolder(.downloads))
    #expect(p.parse(intent:"open_url",text:"Öffne https://example.com/x?q=test") == .openURL(URL(string:"https://example.com/x?q=test")!))
    #expect(p.parse(intent:"home_control",text:"Schalte Wohnzimmer Licht an") == .homeAssistant(.init(target:"Wohnzimmer Licht",operation:.turnOn)))
    #expect(p.parse(intent:"home_control",text:"Stelle Wohnzimmer Heizung auf 21,5 Grad") == .homeAssistant(.init(target:"Wohnzimmer Heizung",operation:.temperature,value:21.5)))
    #expect(p.parse(intent:"home_control",text:"Aktiviere Szene Abend") == .homeAssistant(.init(target:"Abend",operation:.activateScene)))
    #expect(p.parse(intent:"find_project",text:"Such mir den Safari-Tab raus mit Inhalt Projekt Friday") == .findSafariTab(query:"Projekt Friday",searchContents:true))
    #expect(p.parse(intent:"find_project",text:"Finde Safari Tab mit Seite GitHub offen") == .findSafariTab(query:"GitHub",searchContents:false))
    #expect(!ToolRequest.openURL(URL(string:"file:///etc/passwd")!).hasValidArguments)
    #expect(!ToolRequest.openURL(URL(string:"https://user:secret@example.com")!).hasValidArguments)
}

private actor DecisionCounter: FastDecisionEngine {
    var calls=0
    func decide(text:String) async throws -> FastDecision { calls+=1; return FastDecision(intent:.action(.createNote(text:text)),confidence:0.99) }
}
private actor CacheEpoch { var id=UUID(); func rotate(){id=UUID()} }
@Test func decisionCachePreservesArgumentsAndInvalidatesOnHelperRestart() async throws {
    let counter=DecisionCounter(), epoch=CacheEpoch()
    let engine=CachedDecisionEngine(engine:counter,epoch:{await epoch.id})
    _=try await engine.decide(text:"Notiz: One"); _=try await engine.decide(text:"Notiz: One")
    #expect(await counter.calls == 1)
    _=try await engine.decide(text:"Notiz: one"); #expect(await counter.calls == 2)
    await epoch.rotate(); _=try await engine.decide(text:"Notiz: One"); #expect(await counter.calls == 3)
}

private actor RestartingDecision: FastDecisionEngine {
    let epoch: CacheEpoch
    var calls=0
    init(epoch:CacheEpoch){self.epoch=epoch}
    func decide(text:String) async throws -> FastDecision {
        calls+=1; if calls == 1 { await epoch.rotate() }
        return FastDecision(intent:.action(.createNote(text:text)),confidence:0.99)
    }
}
@Test func decisionCacheCannotStoreAResultAcrossAnEpochChange() async throws {
    let epoch=CacheEpoch()
    let restarting=RestartingDecision(epoch:epoch)
    let engine=CachedDecisionEngine(engine:restarting,epoch:{await epoch.id})
    _=try await engine.decide(text:"Notiz: Test"); _=try await engine.decide(text:"Notiz: Test"); _=try await engine.decide(text:"Notiz: Test")
    #expect(await restarting.calls == 2)
}
