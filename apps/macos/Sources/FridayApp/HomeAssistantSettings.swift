import SwiftUI
import FridayAdapters

@MainActor final class HomeAssistantSettings: ObservableObject {
    @Published var address = "http://homeassistant.local"
    @Published var token = ""
    @Published private(set) var status = ""
    @Published private(set) var entities: [HomeAssistantEntity] = []
    @Published private(set) var working = false
    private let client: HomeAssistantClient
    private let store: HomeAssistantConfigurationStore
    init(client: HomeAssistantClient, store: HomeAssistantConfigurationStore = .init()) {
        self.client = client; self.store = store
        if let stored = try? store.load() { address = stored.baseURL.absoluteString }
    }
    func connect(save: Bool) async {
        guard !working else { return }
        working = true; status = "Verbinde …"
        defer { working = false }
        do {
            if save {
                let config = try store.save(url: address, token: token)
                token = ""; address = config.baseURL.absoluteString
                await client.invalidate()
            }
            entities = try await client.refresh()
            status = "Verbunden · \(entities.count) steuerbare Geräte/Szenen erkannt."
        } catch { entities = []; status = error.localizedDescription }
    }
}

struct HomeAssistantSettingsView: View {
    @ObservedObject var settings: HomeAssistantSettings
    let disabled: Bool
    @State private var filter = ""
    private var visibleEntities: [HomeAssistantEntity] {
        settings.entities.filter { filter.isEmpty || $0.name.localizedStandardContains(filter) || $0.entity_id.localizedStandardContains(filter) }
    }
    var body: some View {
        Form {
            Section("Verbindung") {
                TextField("Serveradresse", text: $settings.address).textFieldStyle(.roundedBorder)
                SecureField("Zugriffstoken", text: $settings.token, prompt: Text("Neuen Token eintragen")).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Speichern & verbinden") { Task { await settings.connect(save: true) } }
                    Button("Geräte neu laden") { Task { await settings.connect(save: false) } }
                }
                Text(settings.status.isEmpty ? "Token im Home-Assistant-Profil erstellen. Zugangsdaten bleiben lokal auf diesem Mac." : settings.status)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Befehle") {
                Text("„Wohnzimmer an“\n„Licht im Wohnzimmer aus“\n„Dimme Wohnzimmer Licht auf 30 Prozent“\n„Aktiviere Szene Abend“")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Raumbefehle steuern die zugeordneten Lampen. Friday prüft anschließend die gemeldeten Zustände.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Geräte & Szenen · \(settings.entities.count)") {
                TextField("Nach Name oder ID filtern", text: $filter)
                ForEach(visibleEntities.prefix(40)) { entity in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entity.name).font(.caption)
                        Text(entity.entity_id).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                if visibleEntities.count > 40 { Text("\(visibleEntities.count - 40) weitere Treffer. Suche eingrenzen, um sie zu sehen.").font(.caption).foregroundStyle(.secondary) }
                if settings.entities.isEmpty { Text("Lade die Geräte über „Geräte neu laden“.").font(.caption).foregroundStyle(.secondary) }
            }
        }.formStyle(.grouped).disabled(disabled || settings.working)
    }
}
