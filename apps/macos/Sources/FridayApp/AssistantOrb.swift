import SwiftUI
import FridayCore
import ThinkingOrbsKit

@MainActor final class OrbWindowActivity: ObservableObject {
    static let shared = OrbWindowActivity()
    @Published var active = false
}

extension AssistantPhase {
    var orbState: OrbState {
        switch self {
        case .idle, .listening: .breathing
        case .recording: .breathing
        case .transcribing: .weaving
        case .deciding: .connecting
        case .acting: .working
        case .reasoning: .solving
        case .speaking: .composing
        case .failed: .shaping
        }
    }

    var label: String {
        switch self {
        case .idle: "Bereit"
        case .listening: "Friday aktiv"
        case .recording: "Höre deinen Befehl"
        case .transcribing: "Verstehe Sprache"
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
    var windowContent = false
    @ObservedObject var preferences: OrbPreferences = .shared
    @ObservedObject private var activity = OrbWindowActivity.shared

    var body: some View {
        ThinkingOrb(state: preferences.state(for: phase), size: size, speed: phase == .recording ? 0.5 : 1,
                    paused: phase == .idle || phase == .listening || phase == .failed || (windowContent && !activity.active))
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
    @ObservedObject var preferences: OrbPreferences = .shared
    @State private var selectedPhase: AssistantPhase = .idle
    @ObservedObject private var activity = OrbWindowActivity.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Zustand", selection: $selectedPhase) {
                ForEach(AssistantPhase.allCases, id: \.self) { phase in
                    Text(phase.configurationLabel).tag(phase)
                }
            }
            Text("Zustand wählen, dann auf einen Orb klicken. Die Auswahl wird sofort übernommen und lokal gespeichert.")
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                ForEach(OrbState.allCases, id: \.rawValue) { state in
                    Button { preferences.assign(state, to: selectedPhase) } label: {
                        VStack(spacing: 6) {
                            ThinkingOrb(state: state, size: .px64, paused: !activity.active || preferences.state(for: selectedPhase) != state)
                            HStack(spacing: 4) {
                                Text(state.rawValue)
                                if preferences.state(for: selectedPhase) == state {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                                }
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(8).frame(maxWidth: .infinity)
                        .background(preferences.state(for: selectedPhase) == state ? Color.accentColor.opacity(0.12) : .clear,
                                    in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(preferences.state(for: selectedPhase) == state ? Color.accentColor : .clear, lineWidth: 1))
                    }.buttonStyle(.plain)
                        .help("\(state.rawValue) für \(selectedPhase.configurationLabel) verwenden")
                        .accessibilityLabel("\(state.rawValue) für \(selectedPhase.configurationLabel) zuordnen")
                }
            }
            HStack {
                Text("Idle und Wake-Bereitschaft bleiben statisch.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Standard wiederherstellen") { preferences.reset() }
                    .font(.caption)
            }
        }
        .padding(.vertical, 12)
    }
}
