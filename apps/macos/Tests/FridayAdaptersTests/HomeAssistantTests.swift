import Foundation
import Testing
import FridayCore
@testable import FridayAdapters

private final class HomeProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var requests: [URLRequest] = []
    nonisolated(unsafe) private static var status = 200
    nonisolated(unsafe) private static var changed: [String: [String: Any]] = [:]
    nonisolated(unsafe) private static var applyChanges = true
    nonisolated(unsafe) private static var fixtures: String?
    nonisolated(unsafe) private static var unchanged: Set<String> = []
    static func reset(status: Int = 200, applyChanges: Bool = true, fixtures: String? = nil, unchanged: Set<String> = []) { lock.lock(); defer { lock.unlock() }; requests = []; changed = [:]; self.status = status; self.applyChanges = applyChanges; self.fixtures = fixtures; self.unchanged = unchanged }
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
        Self.lock.lock()
        Self.requests.append(recorded); let status = Self.status
        if recorded.httpMethod == "POST", Self.applyChanges,
           let data = recorded.httpBody, let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let identifiers = (payload["entity_id"] as? [String]) ?? (payload["entity_id"] as? String).map { [$0] } ?? []
            for id in identifiers where !Self.unchanged.contains(id) {
            Self.changed[id] = ["state": request.url!.path.hasSuffix("turn_off") ? "off" : id.hasPrefix("scene.") ? "2026-10-05T12:00:00Z" : "on",
                                "brightness": (payload["brightness_pct"] as? Double).map { ($0 * 255 / 100).rounded() } ?? 255,
                                "temperature": payload["temperature"] ?? 21.5]
            }
        }
        let changed = Self.changed
        let fixtures = Self.fixtures
        Self.lock.unlock()
        let body: String
        if request.url!.path == "/api/states" {
            body = fixtures ?? #"[{"entity_id":"light.wohnzimmer","state":"off","attributes":{"friendly_name":"Wohnzimmer Licht","supported_color_modes":["brightness"]}},{"entity_id":"switch.kaffeemaschine","state":"off","attributes":{"friendly_name":"Kaffeemaschine"}},{"entity_id":"scene.abend","state":"unknown","attributes":{"friendly_name":"Abend"}},{"entity_id":"climate.wohnzimmer","state":"heat","attributes":{"friendly_name":"Wohnzimmer Heizung","supported_features":1,"min_temp":7,"max_temp":30,"target_temp_step":0.5}}]"#
        } else if request.url!.path == "/api/config" { body = #"{"unit_system":{"temperature":"°C"}}"# }
        else { body = "[]" }
        var responseData = Data(body.utf8)
        if request.url!.path == "/api/states", var states = try? JSONSerialization.jsonObject(with: responseData) as? [[String: Any]] {
            for index in states.indices {
                if let id = states[index]["entity_id"] as? String, let observed = changed[id] {
                    states[index]["state"] = observed["state"]
                    var attributes = states[index]["attributes"] as! [String: Any]
                    attributes["brightness"] = observed["brightness"]; attributes["temperature"] = observed["temperature"]
                    states[index]["attributes"] = attributes
                }
            }
            responseData = try! JSONSerialization.data(withJSONObject: states)
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseData); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized) struct HomeAssistantTests {
    private let roomFixture = #"[{"entity_id":"light.black_hole","state":"on","attributes":{"friendly_name":"Black Hole"}},{"entity_id":"light.stripes","state":"on","attributes":{"friendly_name":"Stripes"}},{"entity_id":"light.wohnzimmer","state":"on","attributes":{"friendly_name":"Wohnzimmer","entity_id":["light.black_hole","light.stripes"]}},{"entity_id":"light.kaskade_01","state":"on","attributes":{"friendly_name":"01"}},{"entity_id":"light.kaskade","state":"on","attributes":{"friendly_name":"Kaskade","entity_id":["light.kaskade_01"]}},{"entity_id":"light.albedo","state":"on","attributes":{"friendly_name":"Albedo"}},{"entity_id":"light.kueche","state":"on","attributes":{"friendly_name":"Küche"}}]"#
    private var room: HomeAssistantArea { .init(name: "Wohnzimmer", entityIDs: ["light.black_hole", "light.stripes", "light.wohnzimmer", "light.kaskade_01", "light.kaskade", "light.albedo"]) }

    @Test func roomCommandIncludesOtherGroupsAndPlugsWithoutTouchingAnotherRoom() async throws {
        HomeProtocol.reset(fixtures: roomFixture)
        let (directory, client, session) = try context(areas: [room])
        defer { session.invalidateAndCancel(); try? FileManager.default.removeItem(at: directory) }
        let result = try await client.execute(.init(target: "Alle Lampen im Wohnzimmer", operation: .turnOff))
        #expect(result.contains("4 Lampen geprüft"))
        #expect(HomeProtocol.posts.count == 1)
        #expect(HomeProtocol.posts[0].url!.path == "/api/services/light/turn_off")
        let body = try JSONSerialization.jsonObject(with: HomeProtocol.posts[0].httpBody!) as! [String: Any]
        #expect(Set(body["entity_id"] as! [String]) == ["light.black_hole", "light.stripes", "light.kaskade_01", "light.albedo"])
    }

    @Test func oneLampStillOnPreventsRoomSuccessAndNeverRetriesTheCommand() async throws {
        HomeProtocol.reset(fixtures: roomFixture, unchanged: ["light.albedo"])
        let (directory, client, session) = try context(areas: [room])
        defer { session.invalidateAndCancel(); try? FileManager.default.removeItem(at: directory) }
        await #expect(throws: AdapterError.self) { try await client.execute(.init(target: "Wohnzimmer", operation: .turnOff)) }
        #expect(HomeProtocol.posts.count == 1)
    }

    @Test func compoundRoomLightNameControlsTheSameCompleteRoom() async throws {
        HomeProtocol.reset(fixtures: roomFixture)
        let (directory, client, session) = try context(areas: [room])
        defer { session.invalidateAndCancel(); try? FileManager.default.removeItem(at: directory) }
        let action = try #require(HomeAssistantCommandParser.parse("Hey, mach mal das Wohnzimmerlicht aus"))
        _ = try await client.execute(action)
        let body = try JSONSerialization.jsonObject(with: HomeProtocol.posts[0].httpBody!) as! [String: Any]
        #expect(Set(body["entity_id"] as! [String]) == ["light.black_hole", "light.stripes", "light.kaskade_01", "light.albedo"])
        #expect(HomeProtocol.posts.count == 1)
    }

    @Test(arguments: ["Küche Licht aus", "Küche-Licht aus", "Küchenlicht aus"])
    func kitchenRoomCommandsSkipUnavailableLightsAndReportPartialState(text: String) async throws {
        let fixtures = #"[{"entity_id":"light.island_01","state":"on","attributes":{"friendly_name":"Kücheninsel 01"}},{"entity_id":"light.island_02","state":"on","attributes":{"friendly_name":"Kücheninsel 02"}},{"entity_id":"light.hall_01","state":"unavailable","attributes":{"friendly_name":"Hall Spot 01"}},{"entity_id":"light.office","state":"on","attributes":{"friendly_name":"Büro"}}]"#
        HomeProtocol.reset(fixtures: fixtures)
        let kitchen = HomeAssistantArea(name: "Küche", entityIDs: ["light.island_01", "light.island_02", "light.hall_01"])
        let (directory, client, session) = try context(areas: [kitchen])
        defer { session.invalidateAndCancel(); try? FileManager.default.removeItem(at: directory) }
        let action = try #require(HomeAssistantCommandParser.parse(text))
        let result = try await client.execute(action)
        #expect(HomeProtocol.posts.count == 1)
        let body = try JSONSerialization.jsonObject(with: HomeProtocol.posts[0].httpBody!) as! [String: Any]
        #expect(Set(body["entity_id"] as! [String]) == ["light.island_01", "light.island_02"])
        #expect(result.contains("2 von 3 Lampen"))
        #expect(result.contains("übersprungen"))
        #expect(result.contains("Hall Spot 01"))
        #expect(result.contains("light.hall_01"))
        #expect(!result.hasPrefix("Home Assistant meldet: „Küche“ aus"))
    }

    @Test func allUnavailableRoomLightsDoNotSendAServiceRequest() async throws {
        let fixtures = #"[{"entity_id":"light.hall_01","state":"unavailable","attributes":{"friendly_name":"Hall Spot 01"}},{"entity_id":"light.hall_02","state":"unknown","attributes":{"friendly_name":"Hall Spot 02"}}]"#
        HomeProtocol.reset(fixtures: fixtures)
        let (directory, client, session) = try context(areas: [.init(name: "Küche", entityIDs: ["light.hall_01", "light.hall_02"])])
        defer { session.invalidateAndCancel(); try? FileManager.default.removeItem(at: directory) }
        do {
            _ = try await client.execute(.init(target: "Küche Licht", operation: .turnOff))
            Issue.record("Ein vollständig nicht verfügbarer Raum darf keine Erfolgsmeldung liefern.")
        } catch {
            #expect(error.localizedDescription.contains("Keine erreichbaren Lampen"))
            #expect(error.localizedDescription.contains("Hall Spot 01"))
        }
        #expect(HomeProtocol.posts.isEmpty)
    }

    @Test func explicitUnavailableLampIsNotSilentlySkipped() async throws {
        HomeProtocol.reset(fixtures: #"[{"entity_id":"light.hall_01","state":"unavailable","attributes":{"friendly_name":"Hall Spot 01"}}]"#)
        let (directory, client, session) = try context(areas: [.init(name: "Küche", entityIDs: ["light.hall_01"])])
        defer { session.invalidateAndCancel(); try? FileManager.default.removeItem(at: directory) }
        await #expect(throws: AdapterError.self) { try await client.execute(.init(target: "light.hall_01", operation: .turnOff)) }
        #expect(HomeProtocol.posts.isEmpty)
    }

    @Test func linkingCompoundPrefersAnExactCatalogRoomBeforeRemovingASuffix() throws {
        let entities = try JSONDecoder().decode([HomeAssistantEntity].self, from: Data(#"[{"entity_id":"light.a","state":"on","attributes":{"friendly_name":"A"}},{"entity_id":"light.b","state":"on","attributes":{"friendly_name":"B"}}]"#.utf8))
        let areas: [HomeAssistantArea] = [.init(name: "Küche", entityIDs: ["light.a"]), .init(name: "Küchen", entityIDs: ["light.b"])]
        let result = try #require(try HomeAssistantClient.roomLights(.init(target: "Küchenlicht", operation: .turnOff), areas: areas, entities: entities))
        #expect(result.entities.map(\.id) == ["light.b"])
    }

    @Test func domainQualifiedDeviceNamesSelectOnlyTheRequestedDomain() throws {
        let entities = try JSONDecoder().decode([HomeAssistantEntity].self, from: Data(#"[{"entity_id":"light.a","state":"on","attributes":{"friendly_name":"Steckdose"}},{"entity_id":"switch.a","state":"on","attributes":{"friendly_name":"Steckdose"}},{"entity_id":"light.b","state":"on","attributes":{"friendly_name":"Lampe"}},{"entity_id":"switch.b","state":"on","attributes":{"friendly_name":"Lampe"}}]"#.utf8))
        #expect(try HomeAssistantClient.resolve(.init(target: "Steckdose", operation: .turnOff), in: entities).id == "switch.a")
        #expect(try HomeAssistantClient.resolve(.init(target: "Lampe", operation: .turnOff), in: entities).id == "light.b")
    }

    @Test func areaQualifiedGenericDevicesUseRegistryMembership() async throws {
        let fixtures = #"[{"entity_id":"switch.plug_a","state":"on","attributes":{"friendly_name":"Steckdose"}},{"entity_id":"switch.plug_b","state":"on","attributes":{"friendly_name":"Steckdose"}},{"entity_id":"climate.thermostat_a","state":"heat","attributes":{"friendly_name":"Thermostat","supported_features":1,"min_temp":7,"max_temp":30,"target_temp_step":0.5}},{"entity_id":"climate.thermostat_b","state":"heat","attributes":{"friendly_name":"Thermostat","supported_features":1,"min_temp":7,"max_temp":30,"target_temp_step":0.5}}]"#
        HomeProtocol.reset(fixtures: fixtures)
        let areas: [HomeAssistantArea] = [.init(name: "Küche", entityIDs: ["switch.plug_a", "climate.thermostat_a"]), .init(name: "Büro", entityIDs: ["switch.plug_b", "climate.thermostat_b"])]
        let (directory, client, session) = try context(areas: areas)
        defer { session.invalidateAndCancel(); try? FileManager.default.removeItem(at: directory) }
        for text in ["Schalte die Steckdose in der Küche aus", "Stelle die Heizung im Büro auf 21,5 Grad"] {
            _ = try await client.execute(try #require(HomeAssistantCommandParser.parse(text)))
        }
        #expect(HomeProtocol.posts.map { $0.url!.path } == ["/api/services/switch/turn_off", "/api/services/climate/set_temperature"])
        let bodies = try HomeProtocol.posts.map { try JSONSerialization.jsonObject(with: $0.httpBody!) as! [String: Any] }
        #expect(bodies[0]["entity_id"] as? String == "switch.plug_a")
        #expect(bodies[1]["entity_id"] as? String == "climate.thermostat_b")
    }

    @Test func duplicateSceneNamesRemainAmbiguousAndDoNotAct() async throws {
        HomeProtocol.reset(fixtures: #"[{"entity_id":"scene.old","state":"unknown","attributes":{"friendly_name":"Büro Nachtlicht"}},{"entity_id":"scene.new","state":"unknown","attributes":{"friendly_name":"Büro Nachtlicht"}}]"#)
        let (directory, client, session) = try context()
        defer { session.invalidateAndCancel(); try? FileManager.default.removeItem(at: directory) }
        await #expect(throws: AdapterError.self) { try await client.execute(.init(target: "Büro Nachtlicht", operation: .activateScene)) }
        #expect(HomeProtocol.posts.isEmpty)
    }

    @Test func explicitDeviceCommandDoesNotExpandToTheEntireRoom() async throws {
        HomeProtocol.reset(fixtures: roomFixture)
        let (directory, client, session) = try context(areas: [room])
        defer { session.invalidateAndCancel(); try? FileManager.default.removeItem(at: directory) }
        _ = try await client.execute(.init(target: "Albedo", operation: .turnOff))
        let body = try JSONSerialization.jsonObject(with: HomeProtocol.posts[0].httpBody!) as! [String: Any]
        #expect(body["entity_id"] as? String == "light.albedo")
    }

    @Test func unusedAreaWithSameNameDoesNotBlockAnExistingLampGroup() async throws {
        HomeProtocol.reset(fixtures: roomFixture)
        let (directory, client, session) = try context(areas: [room, .init(name: "Kaskade", entityIDs: [])])
        defer { session.invalidateAndCancel(); try? FileManager.default.removeItem(at: directory) }
        _ = try await client.execute(.init(target: "Kaskade", operation: .turnOn))
        let body = try JSONSerialization.jsonObject(with: HomeProtocol.posts[0].httpBody!) as! [String: Any]
        #expect(body["entity_id"] as? String == "light.kaskade")
    }

    @Test func areaDiscoveryUsesDeviceInheritanceAndHonorsEntityOverrides() throws {
        let decoder = JSONDecoder()
        let areas = try decoder.decode([HomeAssistantAreas.Area].self, from: Data(#"[{"area_id":"room_a","name":"Wohnzimmer"},{"area_id":"room_b","name":"Büro"}]"#.utf8))
        let devices = try decoder.decode([HomeAssistantAreas.Device].self, from: Data(#"[{"id":"bridge_lamp","area_id":"room_a"}]"#.utf8))
        let entities = try decoder.decode([HomeAssistantAreas.Entity].self, from: Data(#"[{"entity_id":"light.a","device_id":"bridge_lamp"},{"entity_id":"light.b","device_id":"bridge_lamp","area_id":"room_b"},{"entity_id":"light.disabled","device_id":"bridge_lamp","disabled_by":"user"}]"#.utf8))
        let result = HomeAssistantAreas.combine(areas: areas, devices: devices, entities: entities)
        #expect(result[0].entityIDs == ["light.a"])
        #expect(result[1].entityIDs == ["light.b"])
    }

    func context(areas: [HomeAssistantArea] = [], discoveryFails: Bool = false) throws -> (URL, HomeAssistantClient, URLSession) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = HomeAssistantConfigurationStore(directory: directory)
        _ = try store.save(url: "http://homeassistant.local/home/overview", token: "private-test-token")
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [HomeProtocol.self]
        let session = URLSession(configuration: configuration)
        return (directory, HomeAssistantClient(store: store, session: session, areaDiscovery: { _ in
            if discoveryFails { throw AdapterError.unavailable("Raumkatalog nicht verfügbar") }
            return areas
        }), session)
    }
    @Test func missingRoomCatalogCannotSilentlyFallBackToAnIncompleteGroup() async throws {
        HomeProtocol.reset(fixtures: roomFixture)
        let (directory, client, session) = try context(discoveryFails: true)
        defer { session.invalidateAndCancel(); try? FileManager.default.removeItem(at: directory) }
        await #expect(throws: AdapterError.self) { try await client.execute(.init(target: "Wohnzimmer", operation: .turnOff)) }
        #expect(HomeProtocol.posts.isEmpty)
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
            #expect(try await client.execute(command).contains("meldet"))
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
    @Test func acceptedServiceWithoutStateChangeIsNotReportedAsSuccessOrRetried() async throws {
        HomeProtocol.reset(applyChanges: false)
        let (directory, client, session) = try context()
        defer { session.invalidateAndCancel(); try? FileManager.default.removeItem(at: directory) }
        await #expect(throws: AdapterError.self) { try await client.execute(.init(target: "Wohnzimmer Licht", operation: .turnOn)) }
        #expect(HomeProtocol.posts.count == 1)
    }
    @Test func roomLightNamesSelectTheNamedGroupInsteadOfItsIndividualBulbs() throws {
        let entities = try JSONDecoder().decode([HomeAssistantEntity].self, from: Data(#"[{"entity_id":"light.wohnzimmer_black_hole","state":"off","attributes":{"friendly_name":"Black Hole"}},{"entity_id":"light.wohnzimmer_stripes","state":"off","attributes":{"friendly_name":"Stripes"}},{"entity_id":"light.wohnzimmer_wohnzimmer","state":"off","attributes":{"friendly_name":"Wohnzimmer","entity_id":["light.wohnzimmer_black_hole","light.wohnzimmer_stripes"]}}]"#.utf8))
        for name in ["Wohnzimmer", "Licht im Wohnzimmer", "Wohnzimmer Licht", "im Wohnzimmer das Licht", "alle Lampen im Wohnzimmer"] {
            #expect(try HomeAssistantClient.resolve(.init(target: name, operation: .turnOn), in: entities).id == "light.wohnzimmer_wohnzimmer")
        }
        #expect(try HomeAssistantClient.resolve(.init(target: "Black Hole", operation: .turnOn), in: entities).id == "light.wohnzimmer_black_hole")
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

@Test(arguments: ["Wohnzimmer an", "Wohnzimmer aus", "Licht im Wohnzimmer an", "Mach das Licht im Wohnzimmer an", "Schalte alle Lampen im Wohnzimmer aus", "Wohnzimmer Licht einschalten", "Bitte Wohnzimmer einschalten", "Schalte das Licht im Wohnzimmer ein"])
func shortRoomCommandsAreLocalHomeActions(text: String) {
    let action = HomeAssistantCommandParser.parse(text)
    #expect(action != nil)
    #expect(action?.operation == (text.contains("aus") ? .turnOff : .turnOn))
}

@Test(arguments: ["Warum ist das Licht an?", "Ist das Wohnzimmer an?", "Erkläre Licht an", "Ich mache morgen Wohnzimmer an", "Wohnzimmer an und Küche aus"])
func questionsAreNotShortHomeCommands(text: String) { #expect(HomeAssistantCommandParser.parse(text) == nil) }

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
