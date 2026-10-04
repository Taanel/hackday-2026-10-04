import Foundation
import Combine
import FridayCore
import ThinkingOrbsKit

extension AssistantPhase {
    var preferenceKey: String {
        switch self {
        case .idle: "idle"
        case .listening: "listening"
        case .recording: "recording"
        case .transcribing: "transcribing"
        case .deciding: "deciding"
        case .acting: "acting"
        case .reasoning: "reasoning"
        case .speaking: "speaking"
        case .failed: "failed"
        }
    }

    var configurationLabel: String {
        switch self {
        case .idle: "Idle"
        case .listening: "Wake-Bereitschaft"
        case .recording: "Zuhören / Aufnahme"
        case .transcribing: "Sprache verstehen · Hex"
        case .deciding: "Entscheiden · Laya"
        case .acting: "Ausführen"
        case .reasoning: "Gemini / LLM"
        case .speaking: "Antwort vorlesen"
        case .failed: "Fehler"
        }
    }
}

@MainActor final class OrbPreferences: ObservableObject {
    static let shared = OrbPreferences()
    private static let storageKey = "Friday.orbAssignments"
    private let defaults: UserDefaults
    @Published private(set) var assignments: [String: String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let validKeys = Set(AssistantPhase.allCases.map(\.preferenceKey))
        assignments = (defaults.dictionary(forKey: Self.storageKey) ?? [:]).reduce(into: [:]) { result, pair in
            if validKeys.contains(pair.key), let raw = pair.value as? String, OrbState(rawValue: raw) != nil {
                result[pair.key] = raw
            }
        }
    }

    func state(for phase: AssistantPhase) -> OrbState {
        assignments[phase.preferenceKey].flatMap(OrbState.init(rawValue:)) ?? phase.orbState
    }

    func assign(_ state: OrbState, to phase: AssistantPhase) {
        assignments[phase.preferenceKey] = state.rawValue
        defaults.set(assignments, forKey: Self.storageKey)
    }

    func reset() {
        assignments = [:]
        defaults.removeObject(forKey: Self.storageKey)
    }
}
