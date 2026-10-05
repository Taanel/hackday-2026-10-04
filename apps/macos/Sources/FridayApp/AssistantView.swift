import SwiftUI
import FridayCore
import FridayAdapters

struct AssistantView: View {
    @ObservedObject var model: AssistantViewModel
    @State private var showsOrbGallery = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Friday").font(.largeTitle.bold())
                        Text("Dein Assistent für den Mac").foregroundStyle(.secondary)
                    }
                    Spacer()
                    AssistantOrb(phase: model.phase, windowContent: true)
                        .scaleEffect(0.625).frame(width: 40, height: 40)
                }

                Text("Sag „Hey Friday, öffne Safari“ oder „Hey Friday, erklär mir einen Quantencomputer“.")
                    .font(.callout).foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    AssistantOrb(phase: model.phase, windowContent: true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.phase.label).font(.title3.weight(.semibold))
                        Text(model.status).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))

                if !model.response.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Antwort").font(.headline)
                        Text(model.response).textSelection(.enabled)
                        ForEach(model.answerSources, id: \.url) { source in
                            Link(source.title, destination: source.url).font(.caption)
                        }
                        ForEach(model.projectMatches) { match in
                            Button { model.focusProjectMatch(match.id) } label: {
                                HStack {
                                    Image(systemName: "macwindow")
                                    VStack(alignment: .leading) {
                                        Text(match.application).font(.caption).foregroundStyle(.secondary)
                                        Text(match.title).lineLimit(2)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.forward")
                                }.frame(maxWidth: .infinity)
                            }.disabled(model.isWorking)
                        }
                        if model.canReplayAnswer {
                            Button("Noch einmal vorlesen", systemImage: "speaker.wave.2.fill") { model.replayAnswer() }
                                .disabled(model.isWorking)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                }

                HStack {
                    Toggle("Hey Friday aktivieren", isOn: Binding(
                        get: { model.wakeEnabled }, set: { model.setWakeEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    .disabled(!model.isReady || model.isWorking)
                    Spacer()
                    if model.isRecording {
                        Button("Aufnahme beenden") { model.stopRecording() }
                    } else {
                        Button("Sprechen", systemImage: "mic.fill") { model.startRecording() }
                            .disabled(!model.isReady || model.isWorking)
                    }
                }
                Text(model.wakeEnabled ? "Mikrofon aktiv · Erkennung läuft lokal." : "Mikrofon startet beim Aktivieren oder über „Sprechen“.")
                    .font(.caption).foregroundStyle(.secondary)
                if model.wakeEnabled {
                    DisclosureGroup("Mikrofon und Wake-Erkennung prüfen") {
                        ProgressView(value: min(1, model.microphoneLevel * 8))
                        Text("Sprich normal laut. Der Balken zeigt, ob das Mikrofon dich hört.").font(.caption).foregroundStyle(.secondary)
                        Text(model.lastWakeTranscript.isEmpty ? "Noch keine Sprache erkannt." : "Zuletzt gehört: \(model.lastWakeTranscript)").font(.caption).textSelection(.enabled)
                        Text("Diese Anzeige bleibt lokal und wird nicht gespeichert.").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Toggle("Schneller Sprechabschluss · 500 ms Pause", isOn: $model.fastEndpoint)
                    .toggleStyle(.checkbox).disabled(model.isWorking)
                Text("Für kurze Befehle. Ausschalten, wenn du längere Denkpausen beim Sprechen brauchst.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Nach Rückfragen direkt antworten · höchstens 8 Sekunden warten", isOn: $model.conversationMode)
                    .toggleStyle(.checkbox).disabled(model.isWorking)
                DisclosureGroup("Wake-Erkennung erweitern") {
                    Toggle("Auch auf „Friday“ allein reagieren", isOn: $model.allowBareWake).toggleStyle(.checkbox)
                    Toggle("Klangmuster darf allein aktivieren · experimentell", isOn: $model.allowPersonalWake).toggleStyle(.checkbox)
                    Text("Beides kann normale Gespräche als Aktivierung verstehen. Änderungen gelten beim nächsten Aktivieren.")
                        .font(.caption).foregroundStyle(.secondary)
                }.disabled(model.wakeEnabled || model.isWorking)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Button(model.wakeTrainingCount > 0 ? "Sprachprobe \(model.wakeTrainingCount + 1)/3 aufnehmen" : "Hey Friday anlernen", systemImage: "waveform") {
                            model.startWakeTraining()
                        }
                        .disabled(!model.isReady || model.isWorking)
                        if model.personalWakeReady || model.wakeTrainingCount > 0 {
                            Button("Zurücksetzen") { model.resetPersonalWake() }
                                .disabled(model.isWorking)
                        }
                    }
                    Text(model.personalWakeReady ? "Klangmuster gespeichert · Aktivierung unter Wake-Erkennung erweitern ist optional." : "Dreimal nur „Hey Friday“ einsprechen. Klangmuster-Erkennung ist eine Testfunktion.")
                        .font(.caption).foregroundStyle(.secondary)
                }

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
                    Button("Ausführen") { model.submit() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isWorking || !model.isReady)
                    if model.isWorking {
                        Button("Abbrechen") { model.cancel() }
                    }
                    Spacer()
                    Toggle("LLM-Antwort vorlesen", isOn: $model.speakResponses)
                        .toggleStyle(.checkbox)
                }
                Text("Computeraktionen und Diktat bleiben stumm.")
                    .font(.caption).foregroundStyle(.secondary)
                if model.usesCloudSpeech {
                    Picker("Sprachausgabe", selection: $model.ttsProvider) {
                        Text("Piper · Deutsch · lokal und kostenlos").tag("local")
                        Text("Gemini · 3 TTS-Modelle").tag("gemini")
                    }.disabled(model.isWorking)
                    if model.ttsProvider == "gemini" {
                    Picker("Stimme", selection: $model.ttsVoice) {
                        Text("Kore · klar").tag("Kore")
                        Text("Aoede · entspannt").tag("Aoede")
                        Text("Charon · ruhig").tag("Charon")
                    }.disabled(model.isWorking)
                    }
                    Text(model.speechNotice)
                        .font(.caption).foregroundStyle(.secondary)
                }

                HStack {
                    Button("Computersteuerung erlauben", systemImage: "keyboard") {
                        MacToolExecutor.requestComputerControl()
                    }
                    Button("Notizen zeigen", systemImage: "folder") {
                        let directory = RuntimeConfiguration.supportDirectory.appendingPathComponent("Notes")
                        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(directory)
                    }
                    if !model.isReady { Button("Erneut laden") { model.prepare() } }
                }

                DisclosureGroup("Orbs zuordnen · 9 Animationen", isExpanded: $showsOrbGallery) {
                    OrbGallery()
                }
                HomeAssistantSettingsView(settings: model.homeSettings, disabled: model.isWorking)
                Button("Gesprächskontext löschen") { Task { await model.clearConversation() } }.disabled(model.isWorking)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Gemini API-Schlüssel").font(.headline)
                    HStack {
                        SecureField(model.geminiKeyConfigured ? "Neuen Schlüssel eintragen" : "API-Schlüssel eintragen", text: $model.geminiKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .disabled(model.isWorking)
                        Button("Lokal speichern") { Task { await model.saveGeminiKey() } }
                            .disabled(model.isWorking || model.geminiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Text(model.geminiKeyStatus.isEmpty
                         ? (model.geminiKeyConfigured ? "Schlüssel lokal gespeichert · kein Schlüsselbundzugriff." : "Nur auf diesem Mac gespeichert, außerhalb des Projekts.")
                         : model.geminiKeyStatus)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 500, minHeight: 520)
    }
}
