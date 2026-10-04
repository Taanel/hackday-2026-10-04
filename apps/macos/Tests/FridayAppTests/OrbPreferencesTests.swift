import Foundation
import Testing
import FridayCore
@testable import FridayApp

@Test @MainActor func orbAssignmentsPersistIndependentlyAndResetToRequestedDefaults() throws {
    let name = "Friday.Tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let preferences = OrbPreferences(defaults: defaults)
    #expect(preferences.state(for: .idle).rawValue == "breathing")
    #expect(preferences.state(for: .reasoning).rawValue == "solving")
    preferences.assign(.listening, to: .recording)
    preferences.assign(.searching, to: .acting)
    let reloaded = OrbPreferences(defaults: defaults)
    #expect(reloaded.state(for: .recording).rawValue == "listening")
    #expect(reloaded.state(for: .acting).rawValue == "searching")
    #expect(reloaded.state(for: .idle).rawValue == "breathing")
    reloaded.reset()
    #expect(OrbPreferences(defaults: defaults).state(for: .recording).rawValue == "breathing")
    #expect(reloaded.state(for: .acting).rawValue == "working")
    defaults.set(["idle": "unknown", "notAState": "solving"], forKey: "Friday.orbAssignments")
    #expect(OrbPreferences(defaults: defaults).state(for: .idle).rawValue == "breathing")
}
