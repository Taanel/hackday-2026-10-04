import Foundation
import Testing
@testable import FridayAdapters

@Test func localGeminiKeyCanBeUpdatedWithoutAKeychain() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LocalGeminiKeyStore(directory: directory)
    #expect(!store.isConfigured)
    #expect(throws: AdapterError.self) { try store.load() }
    try store.save("  test-key-first  ")
    #expect(try store.load() == "test-key-first")
    #expect(store.isConfigured)
    let folderAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
    let fileAttributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
    #expect((folderAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    #expect((fileAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    try store.save("test-key-second")
    #expect(try LocalGeminiKeyStore(directory: directory).load() == "test-key-second")
}

@Test(arguments: ["", "  ", "key with whitespace", "key\nsecondline", "🔑", String(repeating: "x", count: 513)])
func malformedKeyCannotReplaceTheSavedKey(candidate: String) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = LocalGeminiKeyStore(directory: directory)
    try store.save("working-test-key")
    #expect(throws: AdapterError.self) { try store.save(candidate) }
    #expect(try store.load() == "working-test-key")
}
