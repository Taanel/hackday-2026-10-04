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
    var body: some View {
        DisclosureGroup("Home Assistant") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Serveradresse", text: $settings.address).textFieldStyle(.roundedBorder)
                SecureField("Langlebiger Token · leer lassen zum Beibehalten", text: $settings.token).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Speichern & verbinden") { Task { await settings.connect(save: true) } }
                    Button("Geräte neu laden") { Task { await settings.connect(save: false) } }
                }
                Text(settings.status.isEmpty ? "Token im Home-Assistant-Profil erstellen. Zugangsdaten bleiben lokal auf diesem Mac." : settings.status)
                    .font(.caption).foregroundStyle(.secondary)
                Text("Zum Beispiel: Wohnzimmer an · Licht im Wohnzimmer aus · Dimme Wohnzimmer Licht auf 30 Prozent · Aktiviere Szene Abend.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(settings.entities.prefix(40)) { entity in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entity.name).font(.caption)
                        Text(entity.entity_id).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                if settings.entities.count > 40 { Text("\(settings.entities.count - 40) weitere Geräte sind ebenfalls steuerbar.").font(.caption) }
            }.padding(.vertical, 8).disabled(disabled || settings.working)
        }
    }
}
