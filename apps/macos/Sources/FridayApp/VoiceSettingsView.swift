import SwiftUI
import FridayAdapters

struct VoiceSettingsView: View {
    @ObservedObject var model: AssistantViewModel
    var body: some View {
        Form {
            Section("Aktivierung") {
                Toggle("Auf „Hey Friday“ und „Hi Friday“ hören", isOn: Binding(get: { model.wakeEnabled }, set: { model.setWakeEnabled($0) }))
                    .disabled(!model.isReady || model.isWorking)
                Text("Erkennung läuft lokal. Du kannst jederzeit auf die Overlay-Kugel klicken und sprechen.").font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Zusätzliche Wake-Optionen") {
                    Toggle("Auch auf „Friday“ allein reagieren", isOn: $model.allowBareWake)
                    Toggle("Persönliches Klangmuster darf aktivieren", isOn: $model.allowPersonalWake)
                    Text("Experimentell: Kann normale Gespräche als Aktivierung verstehen. Wake-Erkennung ausschalten, um diese Optionen zu ändern.").font(.caption).foregroundStyle(.secondary)
                }.disabled(model.wakeEnabled || model.isWorking)
                DisclosureGroup("Klangmuster anlernen") {
                    HStack {
                        Button(model.wakeTrainingCount > 0 ? "Probe \(model.wakeTrainingCount + 1)/3 aufnehmen" : "Hey Friday anlernen", systemImage: "waveform") { model.startWakeTraining() }.disabled(!model.isReady || model.isWorking)
                        if model.personalWakeReady || model.wakeTrainingCount > 0 { Button("Zurücksetzen") { model.resetPersonalWake() }.disabled(model.isWorking) }
                    }
                    Text(model.personalWakeReady ? "Klangmuster gespeichert. Aktivierung unter „Zusätzliche Wake-Optionen“ einschalten." : "Dreimal nur „Hey Friday“ einsprechen. Optionale Testfunktion.").font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup("Mikrofon-Diagnose") {
                    ProgressView(value: min(1, model.microphoneLevel * 8))
                    Text(model.wakeEnabled ? "Sprich normal laut. Der Balken zeigt den Mikrofonpegel." : "Aktiviere Hey Friday, um Pegel und Erkennung zu prüfen.").font(.caption).foregroundStyle(.secondary)
                    Text(model.lastWakeTranscript.isEmpty ? "Noch keine Sprache erkannt." : "Zuletzt gehört: \(model.lastWakeTranscript)").font(.caption).textSelection(.enabled)
                    Text("Bleibt lokal und wird nicht gespeichert.").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Section("Gehäuse-Doppeltippen") {
                Toggle("Durch Doppeltippen sprechen", isOn: Binding(get: { model.chassisEnabled }, set: { model.setChassisEnabled($0) }))
                    .disabled(!model.isReady || model.isWorking || model.chassisTesting)
                Text("Zweimal auf das Aluminium neben dem Trackpad tippen, dann sprechen. Funktioniert auch ohne Hey Friday. Nach Tastatur- und Trackpad-Eingaben kurz warten.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(model.chassisStatus).font(.caption).textSelection(.enabled)
                DisclosureGroup("Einrichten & testen") {
                    Button("Eingabeüberwachung erlauben", systemImage: "hand.raised") {
                        ChassisActivation.requestInputPermission()
                        if !ChassisActivation.hasInputPermission { ChassisActivation.openInputSettings() }
                    }
                    Text("In Datenschutz → Eingabeüberwachung Friday erlauben. Falls macOS es verlangt, Friday schließen und erneut öffnen. Die Erkennung liest keine getippten Texte.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button(model.chassisTesting ? "Test beenden" : "30 Sekunden testen", systemImage: "hand.tap") {
                            if model.chassisTesting { model.finishChassisTest() } else { model.testChassis() }
                        }.disabled(!model.isReady || model.isWorking)
                        Text("\(model.chassisPairs) Doppeltipps · \(model.chassisRejected) verworfen")
                            .font(.caption).monospacedDigit()
                    }
                    Text("Erst normal tippen und das Trackpad benutzen: Der Doppeltipp-Zähler soll bei 0 bleiben. Dann einige Doppeltipps probieren. Im Testmodus wird dadurch keine Aufnahme gestartet.")
                        .font(.caption).foregroundStyle(.secondary)
                    LabeledContent("Erkennungsschwelle") {
                        Slider(value: $model.chassisThreshold, in: 0.04...0.35, step: 0.01).frame(maxWidth: 200)
                        Text(String(format: "%.2f g", model.chassisThreshold)).monospacedDigit()
                    }
                    Text("Kleiner = empfindlicher. Letzter Impuls: \(String(format: "%.3f g", model.chassisStrength)). Auf weichen Unterlagen kann die Erkennung schwächer sein.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Aufnahme & Gespräch") {
                Toggle("Kurze Befehle schneller abschließen", isOn: $model.fastEndpoint).disabled(model.isWorking)
                Text("500 ms Sprechpause. Für längere Denkpausen ausschalten.").font(.caption).foregroundStyle(.secondary)
                Toggle("Nach Rückfragen direkt antworten", isOn: $model.conversationMode).disabled(model.isWorking)
                Text("Nach einer vorgelesenen Rückfrage hört Friday bis zu 8 Sekunden weiter zu.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Vorlesen") {
                Toggle("Antworten vorlesen", isOn: $model.speakResponses)
                Text("Computeraktionen und Diktat bleiben stumm.").font(.caption).foregroundStyle(.secondary)
                if model.usesCloudSpeech {
                    Picker("Sprachausgabe", selection: $model.ttsProvider) {
                        Text("Gemini 3.8 · Cloud").tag("gemini"); Text("Piper · Deutsch · lokal").tag("local")
                    }.disabled(model.isWorking)
                    if model.ttsProvider == "gemini" {
                        Picker("Stimme", selection: $model.ttsVoice) {
                            Text("Kore · klar").tag("Kore"); Text("Aoede · entspannt").tag("Aoede"); Text("Charon · ruhig").tag("Charon")
                        }.disabled(model.isWorking)
                    }
                    Text(model.speechNotice).font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("Separate TTS-Schlüssel") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(0..<4, id: \.self) { slot in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Schlüssel \(slot + 1)\(model.configuredTTSKeySlots.contains(slot) ? " · gespeichert" : "")").font(.subheadline.weight(.medium))
                                    SecureField("API-Schlüssel", text: $model.ttsKeyInputs[slot]).textFieldStyle(.roundedBorder)
                                    HStack {
                                        Button("Speichern") { Task { await model.updateTTSKey(slot: slot) } }.disabled(model.ttsKeyInputs[slot].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                        Button("Entfernen") { Task { await model.updateTTSKey(slot: slot, remove: true) } }.disabled(!model.configuredTTSKeySlots.contains(slot))
                                    }
                                }
                            }
                            Text("Nur für Stimme. Antworten verwenden weiter den Gemini-Schlüssel unter Assistent. Ohne separate Schlüssel wird dieser auch für TTS genutzt. Schlüssel desselben Google-Projekts teilen das Kontingent.").font(.caption).foregroundStyle(.secondary)
                            if !model.ttsKeyStatus.isEmpty { Text(model.ttsKeyStatus).font(.caption) }
                        }.padding(.vertical, 8).disabled(model.isWorking)
                    }
                }
            }
        }.formStyle(.grouped)
    }
}
