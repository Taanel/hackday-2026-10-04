import Foundation
import Testing
@testable import FridayAdapters

@Test func speechKeysStaySeparateAndSlotsCanBeReplacedOrRemoved() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let main = LocalGeminiKeyStore(directory: directory)
    let speech = LocalGeminiTTSKeyStore(directory: directory)
    try main.save("reasoning-test-key")
    #expect(try speech.loadKeys(fallback: { try main.load() }) == ["reasoning-test-key"])
    try speech.save("speech-key-one", slot: 0)
    try speech.save("speech-key-four", slot: 3)
    #expect(try speech.loadKeys(fallback: { throw AdapterError.unavailable("Main key must not be read") }) == ["speech-key-one", "speech-key-four"])
    #expect(speech.configuredSlots == Set([0, 3]))
    #expect(try main.load() == "reasoning-test-key")
    #expect(throws: AdapterError.self) { try speech.save("speech-key-one", slot: 1) }
    #expect(throws: AdapterError.self) { try speech.save("has spaces", slot: 0) }
    #expect(throws: AdapterError.self) { try speech.save("fifth-key", slot: 4) }
    let attributes = try FileManager.default.attributesOfItem(atPath: speech.fileURL.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    try speech.remove(slot: 0)
    #expect(try speech.loadKeys(fallback: { try main.load() }) == ["speech-key-four"])
    try speech.remove(slot: 3)
    #expect(try speech.loadKeys(fallback: { try main.load() }) == ["reasoning-test-key"])
    #expect(try main.load() == "reasoning-test-key")
}
