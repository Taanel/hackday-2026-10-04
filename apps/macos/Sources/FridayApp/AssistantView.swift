import SwiftUI
import FridayCore

struct AssistantView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: AssistantViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Friday").font(.largeTitle.bold())
                    Text("Dein Assistent für den Mac").foregroundStyle(.secondary)
                }
                Spacer()
                MascotImage().frame(width: 48, height: 48)
            }

            Text("Grundgerüst: Texteingabe und Aktionsvorschau. Mikrofon, „Hey Friday“, Hex und Laya werden als Nächstes angebunden.")
                .font(.callout).foregroundStyle(.secondary)

            Picker("Modus", selection: $model.mode) {
                Text("Assistent").tag(InputMode.assistant)
                Text("Diktat-Vorschau").tag(InputMode.dictation)
            }
            .pickerStyle(.segmented)
            .disabled(model.isWorking)

            TextField("Zum Beispiel: Öffne Safari oder Notiz: Milch kaufen", text: $model.input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .onSubmit { model.submit() }

            HStack {
                Button("Ausprobieren") { model.submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isWorking)
                if model.isWorking {
                    Button("Abbrechen") { model.cancel() }
                }
                Spacer()
                Toggle("Antwort vorlesen", isOn: $model.speakResponses)
                    .toggleStyle(.checkbox)
            }

            Text(model.status).font(.caption).foregroundStyle(.secondary)
            ScrollView {
                Text(model.response.isEmpty ? "Hier erscheint die Antwort." : model.response)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 80)
        }
        .padding(24)
        .frame(minWidth: 460, minHeight: 400)
        .onAppear {
            FridayAppDelegate.openAssistant = {
                openWindow(id: "assistant")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
