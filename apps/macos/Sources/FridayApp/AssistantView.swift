import SwiftUI
import FridayCore
import FridayAdapters

enum AssistantPage: String, CaseIterable, Identifiable {
    case assistant = "Assistent", voice = "Sprache", computer = "Computer", home = "Home Assistant", appearance = "Darstellung"
    var id: Self { self }
    var icon: String {
        switch self { case .assistant: "sparkle"; case .voice: "waveform"; case .computer: "desktopcomputer"; case .home: "house"; case .appearance: "circle.dotted" }
    }
    var subtitle: String {
        switch self {
        case .assistant: "Sprechen, fragen und direkt ausführen."
        case .voice: "Aktivierung, Aufnahme und Vorlesen."
        case .computer: "Offene Inhalte finden und auf dem Mac arbeiten."
        case .home: "Dein Zuhause verbinden und Geräte steuern."
        case .appearance: "Die Kugel an deinen Geschmack anpassen."
        }
    }
}

struct AssistantView: View {
    @ObservedObject var model: AssistantViewModel
    @State var page: AssistantPage = .assistant

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Label("Friday", systemImage: "circle.dotted").font(.title2.weight(.semibold)).padding(.horizontal, 12)
                VStack(spacing: 4) {
                    ForEach(AssistantPage.allCases) { item in
                        Button { page = item } label: {
                            Label(item.rawValue, systemImage: item.icon)
                                .font(.system(size: 13, weight: page == item ? .semibold : .regular))
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 10)
                                .foregroundStyle(page == item ? Color.accentColor : Color.primary)
                                .background(page == item ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain).accessibilityAddTraits(page == item ? .isSelected : [])
                    }
                }
                Spacer()
                Label(model.isReady ? "Modelle bereit" : "Modelle laden", systemImage: model.isReady ? "checkmark.circle" : "clock")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12)
            }.padding(12).padding(.vertical, 10).frame(width: 190)
                .background(Color(nsColor: .controlBackgroundColor))
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(page.rawValue).font(.title2.weight(.semibold))
                    Text(page.subtitle).font(.callout).foregroundStyle(.secondary)
                }.padding(24)
                Divider()
                Group {
                    switch page {
                    case .assistant: assistant
                    case .voice: VoiceSettingsView(model: model)
                    case .computer: computer
                    case .home: HomeAssistantSettingsView(settings: model.homeSettings, disabled: model.isWorking)
                    case .appearance: ScrollView { OrbGallery().padding(24) }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }.background(Color(nsColor: .windowBackgroundColor))
        }.frame(minWidth: 760, minHeight: 560)
            .onChange(of: model.projectMatches.count) { _, count in if count > 0 { page = .assistant } }
    }

    private var assistant: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    AssistantOrb(phase: model.phase, windowContent: true).scaleEffect(0.625).frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.phase.label).font(.headline)
                        Text(model.status).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !model.isReady { Button("Erneut laden") { model.prepare() } }
                }
                HStack {
                    Toggle("Hey Friday", isOn: Binding(get: { model.wakeEnabled }, set: { model.setWakeEnabled($0) }))
                        .toggleStyle(.switch).disabled(!model.isReady || model.isWorking)
                    Spacer()
                    if model.isRecording { Button("Aufnahme beenden", systemImage: "stop.fill") { model.stopRecording() } }
                    else { Button("Sprechen", systemImage: "mic.fill") { model.startRecording() }.disabled(!model.isReady || model.isWorking) }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Modus", selection: $model.mode) {
                        Text("Assistent").tag(InputMode.assistant)
                        Text("Diktat").tag(InputMode.dictation)
                    }.pickerStyle(.segmented).disabled(model.isWorking)
                    TextField("Frag etwas oder gib einen Auftrag …", text: $model.input, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(2...5).onSubmit { model.submit() }
                        .disabled(model.isWorking)
                    HStack {
                        Button("Ausführen", systemImage: "arrow.up") { model.submit() }
                            .buttonStyle(.borderedProminent).disabled(model.isWorking || !model.isReady || model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if model.isWorking { Button("Abbrechen") { model.cancel() } }
                    }
                }
                if !model.response.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Text(model.projectMatches.isEmpty ? "Antwort" : "Treffer auswählen").font(.headline)
                        Text(model.response).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(model.projectMatches) { match in
                            Button { model.focusProjectMatch(match.id) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: match.icon).font(.title3).foregroundStyle(.secondary).frame(width: 24)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(match.title).font(.body.weight(.medium)).lineLimit(2)
                                        Text(match.detail ?? match.application).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.forward").foregroundStyle(.secondary)
                                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain).disabled(model.isWorking).help("Treffer öffnen")
                        }
                        if let weather = model.weatherOverview { WeatherOverviewCard(forecast: weather, usesGlass: false) }
                        ForEach(model.answerSources, id: \.url) { Link($0.title, destination: $0.url).font(.caption) }
                        if model.canReplayAnswer { Button("Noch einmal vorlesen", systemImage: "speaker.wave.2") { model.replayAnswer() }.disabled(model.isWorking) }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ein Klick auf die Overlay-Kugel startet die Aufnahme.").font(.callout)
                        Text("„Such den Tab raus, wo ich Friday offen habe“\n„Such Datei Rechnung.pdf und öffne sie“\n„Wie wird das Wetter nächste Woche in Berlin?“")
                            .font(.callout).foregroundStyle(.secondary).lineSpacing(5)
                    }
                }
                Divider()
                DisclosureGroup("Gemini-Verbindung & Gespräch") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("API-Schlüssel für Antworten").font(.subheadline.weight(.medium))
                        HStack {
                            SecureField(model.geminiKeyConfigured ? "Gespeicherten Schlüssel ersetzen" : "API-Schlüssel", text: $model.geminiKeyInput).textFieldStyle(.roundedBorder)
                            Button("Speichern") { Task { await model.saveGeminiKey() } }.disabled(model.geminiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        Text(model.geminiKeyStatus.isEmpty ? "Nur lokal gespeichert · kein Schlüsselbundzugriff." : model.geminiKeyStatus).font(.caption).foregroundStyle(.secondary)
                        Button("Gesprächskontext löschen") { Task { await model.clearConversation() } }
                    }.padding(.top, 12).disabled(model.isWorking)
                }.font(.callout)
            }.padding(24)
        }
    }

    private var computer: some View {
        Form {
            Section("Zugriff") {
                Text("Fenster und Terminal-Tabs brauchen Bedienungshilfen. Safari und Terminal fragen zusätzlich nach Automation, wenn du sie erstmals durchsuchen lässt.").font(.callout).foregroundStyle(.secondary)
                Button("Computersteuerung erlauben", systemImage: "keyboard") { MacToolExecutor.requestComputerControl() }
            }
            Section("Bereits offene Inhalte") {
                Label("„Such den Safari-Tab mit Seite XY“", systemImage: "safari")
                Label("„Such den Tab raus, wo ich XY offen habe“", systemImage: "rectangle.on.rectangle")
                Label("„Wo habe ich Projekt XY offen?“", systemImage: "macwindow")
                Text("Titel und Adressen zuerst. Bei einer Inhaltssuche liest Friday begrenzt Seitentext bzw. sichtbaren Terminaltext lokal. Mehrere Treffer kannst du auswählen.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Dateien & Ordner") {
                Label("„Such Datei Rechnung.pdf und öffne sie“", systemImage: "doc")
                Label("„Such Ordner Friday im Finder“", systemImage: "folder")
                Text("Suche nach Namen im Spotlight-Index deines Benutzerordners. Pfade bleiben lokal. Skripte und Installationsdateien werden im Finder gezeigt.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Notizen") {
                Button("Gespeicherte Notizen öffnen", systemImage: "folder") {
                    let directory = RuntimeConfiguration.supportDirectory.appendingPathComponent("Notes")
                    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(directory)
                }
            }
        }.formStyle(.grouped)
    }
}
