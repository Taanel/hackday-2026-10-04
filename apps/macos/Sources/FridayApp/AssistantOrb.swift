import SwiftUI
import FridayCore
import ThinkingOrbsKit

extension AssistantPhase {
    var orbState: OrbState {
        switch self {
        case .idle: .breathing
        case .deciding: .connecting
        case .acting: .working
        case .reasoning: .solving
        case .speaking: .listening
        case .failed: .shaping
        }
    }

    var label: String {
        switch self {
        case .idle: "Bereit"
        case .deciding: "Entscheide"
        case .acting: "Führe aus"
        case .reasoning: "Denke nach"
        case .speaking: "Antworte"
        case .failed: "Fehler"
        }
    }
}

/// The original native Libraries.dev animation, bound to actual assistant activity.
struct AssistantOrb: View {
    let phase: AssistantPhase
    var size: OrbSize = .px64

    var body: some View {
        ThinkingOrb(state: phase.orbState, size: size, paused: phase == .idle || phase == .failed)
            .overlay(alignment: .bottomTrailing) {
                if phase == .failed {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Friday: \(phase.label)")
    }
}

struct OrbGallery: View {
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 18) {
            ForEach(OrbState.allCases, id: \.rawValue) { state in
                VStack(spacing: 5) {
                    ThinkingOrb(state: state, size: .px64)
                    Text(state.rawValue).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 12)
    }
}
