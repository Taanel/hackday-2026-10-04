import Foundation
import FridayCore
import FridayAdapters

@MainActor final class AssistantViewModel: ObservableObject {
    @Published var input = "Öffne Safari"
    @Published var mode: InputMode = .assistant
    @Published var speakResponses = true
    @Published var geminiKeyInput = ""
    @Published private(set) var geminiKeyConfigured = false
    @Published private(set) var geminiKeyStatus = ""
    @Published private(set) var overlayTranscript = ""
    @Published private(set) var canReplayAnswer = false
    @Published private(set) var response = ""
    @Published private(set) var status = "Bereit · Demo"
    @Published private(set) var isWorking = false
    @Published private(set) var phase: AssistantPhase = .idle
    @Published private(set) var isReady = true
    @Published private(set) var wakeEnabled = false
    @Published private(set) var isRecording = false
    @Published private(set) var wakeTrainingCount = 0
    @Published private(set) var isTrainingWake = false
    @Published private(set) var personalWakeReady = FileManager.default.fileExists(atPath:
        RuntimeConfiguration.supportDirectory.appendingPathComponent("VoiceProfile/profile.json").path)

    private let router: AssistantRouter
    private let speech: any SpeechOutput
    private let keyStore: LocalGeminiKeyStore
    private var gemini: GeminiReasoningEngine?
    private var replayText: String?
    private var transcriptExpiry: Task<Void, Never>?
    private var transcriptGeneration = UUID()
    private var voice: VoiceController?
    private var hex: HexService?
    private var layaWorker: JSONLineProcess?
    private var startupTask: Task<Void, Never>?
    private var microphoneTask: Task<Void, Never>?
    private var generation = UUID()
    private var isLive = false
    private var reasoningLabel = "LLM"
    private var shuttingDown = false
    private var wakeTrainingFiles: [URL] = []
    private(set) var task: Task<Void, Never>?

    init(
        router: AssistantRouter = AssistantRouter(
            decisions: DemoDecisionEngine(),
            reasoning: DemoReasoningEngine(),
            tools: PreviewToolExecutor()
        ),
        speech: any SpeechOutput = SystemSpeechOutput(),
        keyStore: LocalGeminiKeyStore = LocalGeminiKeyStore()
    ) {
        self.router = router
        self.speech = speech
        self.keyStore = keyStore
        geminiKeyConfigured = keyStore.isConfigured
    }

    func saveGeminiKey() async {
        guard !shuttingDown, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try keyStore.save(geminiKeyInput)
            await gemini?.invalidateCredentials()
            geminiKeyInput = ""
            geminiKeyConfigured = true
            geminiKeyStatus = "Lokal gespeichert · kein Schlüsselbundzugriff."
        } catch { geminiKeyStatus = error.localizedDescription }
    }

    func replayAnswer() {
        guard !shuttingDown, !isWorking, !isRecording, let text = replayText else { return }
        let token = UUID(); generation = token
        speech.stop()
        isWorking = true; phase = .speaking; status = "Lese die Antwort noch einmal vor …"
        task = Task {
            defer { if generation == token { isWorking = false; task = nil } }
            do {
                await voice?.suspend()
                try Task.checkCancellation()
                guard generation == token else { throw CancellationError() }
                try await speech.speak(text)
                try Task.checkCancellation()
                guard generation == token else { return }
                phase = .idle; status = "Antwort vorgelesen"
            } catch is CancellationError {
                guard generation == token else { return }
                phase = .idle; status = "Abgebrochen"
            } catch {
                guard generation == token else { return }
                phase = .failed; status = "Sprachausgabe: \(error.localizedDescription)"
            }
            await rearmVoice(token: token)
        }
    }

    func showTranscript(_ text: String) {
        clearTranscript()
        overlayTranscript = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func clearTranscript() {
        transcriptGeneration = UUID()
        transcriptExpiry?.cancel(); transcriptExpiry = nil
        overlayTranscript = ""
    }

    func expireTranscript(after duration: Duration = .seconds(8)) {
        guard !overlayTranscript.isEmpty else { return }
        transcriptExpiry?.cancel()
        let token = transcriptGeneration
        transcriptExpiry = Task { [weak self] in
            do { try await Task.sleep(for: duration) } catch { return }
            guard let self, self.transcriptGeneration == token else { return }
            self.clearTranscript()
        }
    }

    static func live() -> AssistantViewModel {
        do {
            let configuration = try RuntimeConfiguration.load()
            let applications = MacApplicationCatalog.aliases()
            let parser = ActionArgumentParser(applications: applications)
            let laya = configuration.worker("laya")
            let wake = MoonshineWakeWordDetector(worker: configuration.worker("wake"))
            let hex = HexService(configuration: configuration)
            let reasoning: any ReasoningEngine
            let reasoningLabel: String
            var gemini: GeminiReasoningEngine?
            if configuration.reasoningProvider == "gemini" {
                let name = configuration.geminiModel ?? "gemini-3.5-flash-lite"
                let engine = GeminiReasoningEngine(model: name, applications: applications)
                gemini = engine; reasoning = engine
                reasoningLabel = name.contains("flash-lite") ? "Gemini Flash-Lite" : "Gemini Flash"
            } else {
                reasoning = OllamaReasoningEngine(model: configuration.ollamaModel)
                reasoningLabel = "Ollama · lokal"
            }
            let model = AssistantViewModel(router: AssistantRouter(
                decisions: LayaDecisionEngine(worker: laya, parser: parser),
                reasoning: reasoning,
                tools: MacToolExecutor(), minimumConfidence: 0.75
            ))
            model.isLive = true; model.isReady = false
            model.gemini = gemini
            model.reasoningLabel = reasoningLabel
            model.hex = hex; model.layaWorker = laya
            let voice = VoiceController(wake: wake)
            model.voice = voice
            voice.onPhase = { [weak model] phase in
                guard let model else { return }
                model.phase = phase
                model.isRecording = phase == .recording
                model.isWorking = phase == .recording
                if phase == .listening { model.status = "Höre auf „Friday“ oder „Hey Friday“ · lokal" }
                else if phase == .recording {
                    model.clearTranscript()
                    model.status = "Sprich deinen Befehl. Eine Pause beendet die Aufnahme."
                }
            }
            voice.onCommand = { [weak model] file, stripWake in model?.processRecording(file, stripWake: stripWake) }
            voice.onWakeRecovery = { [weak model] in model?.status = "Wake-Erkennung startet neu …" }
            voice.onError = { [weak model] error in
                guard let model else { return }
                model.wakeEnabled = false
                model.cancel()
                model.status = "Audiofehler"; model.response = error.localizedDescription
            }
            model.status = "Lokale Modelle werden geladen …"
            return model
        } catch {
            let model = AssistantViewModel(router: AssistantRouter(
                decisions: LayaDecisionEngine(worker: JSONLineProcess(executable: "/nonexistent", arguments: [])),
                reasoning: UnconfiguredReasoningEngine(), tools: MacToolExecutor()
            ))
            model.isLive = true; model.isReady = false
            model.phase = .failed; model.status = "Lokales Setup fehlt"
            model.response = error.localizedDescription
            return model
        }
    }

    func prepare() {
        guard !shuttingDown, let layaWorker, let hex, startupTask == nil, !isReady else { return }
        startupTask = Task {
            do {
                async let model = layaWorker.start()
                async let service: Void = hex.start()
                _ = try await (model, service)
                try Task.checkCancellation()
                isReady = true; phase = .idle
                status = "Bereit · Laya und Hex lokal"
            } catch is CancellationError {}
            catch { phase = .failed; status = "Modellstart fehlgeschlagen"; response = error.localizedDescription }
            startupTask = nil
        }
    }

    func submit() {
        guard !isWorking, isReady else { return }
        run(text: input, mode: mode)
    }

    private func processRecording(_ file: URL, stripWake: Bool) {
        if isTrainingWake { processWakeTraining(file); return }
        guard task == nil, isReady else { try? FileManager.default.removeItem(at: file); return }
        isRecording = false
        run(text: nil, mode: mode, audioFile: file, stripWake: stripWake)
    }

    func startWakeTraining() {
        guard !shuttingDown, isReady, !isWorking, voice != nil else { return }
        isTrainingWake = true; isWorking = true; response = ""
        microphoneTask = Task {
            do {
                try await voice?.manualRecording()
                status = "Probe \(wakeTrainingCount + 1)/3: Sag nur „Hey Friday“, dann kurz warten."
            } catch {
                isTrainingWake = false; isWorking = false; phase = .failed
                response = error.localizedDescription
            }
        }
    }

    private func processWakeTraining(_ file: URL) {
        let token = UUID(); generation = token
        isRecording = false; isTrainingWake = false
        wakeTrainingFiles.append(file); wakeTrainingCount = wakeTrainingFiles.count
        isWorking = true
        task = Task {
            defer { if generation == token { isWorking = false; task = nil } }
            do {
                if wakeTrainingFiles.count == 3 {
                    status = "Persönliches Klangmuster wird gespeichert …"
                    try await voice?.enrollWake(files: wakeTrainingFiles)
                    try Task.checkCancellation()
                    guard generation == token, !shuttingDown else { throw CancellationError() }
                    clearTrainingFiles()
                    personalWakeReady = true
                    wakeEnabled = true
                    try await voice?.setEnabled(true)
                    response = "Persönliches Hey Friday ist aktiv. Sag jetzt „Hey Friday, öffne Safari und suche nach Test“."
                } else {
                    try await voice?.rearm()
                    try Task.checkCancellation()
                    guard generation == token, !shuttingDown else { throw CancellationError() }
                    phase = wakeEnabled ? .listening : .idle
                    status = "Probe \(wakeTrainingCount)/3 aufgenommen. Nächste Sprachprobe starten."
                }
            } catch is CancellationError {
                return
            } catch {
                guard generation == token, !shuttingDown else { return }
                clearTrainingFiles()
                phase = .failed; status = "Anlernen bitte wiederholen"
                response = error.localizedDescription
                try? await voice?.rearm()
            }
        }
    }

    private func clearTrainingFiles() {
        for file in wakeTrainingFiles { try? FileManager.default.removeItem(at: file) }
        wakeTrainingFiles.removeAll(); wakeTrainingCount = 0
    }

    func resetPersonalWake() {
        guard !shuttingDown, !isWorking, voice != nil else { return }
        isWorking = true
        task = Task {
            defer { isWorking = false; task = nil }
            do {
                try await voice?.clearWakeProfile()
                clearTrainingFiles(); personalWakeReady = false
                try await voice?.rearm()
                status = "Persönliches Klangmuster gelöscht"
            } catch { response = error.localizedDescription; phase = .failed }
        }
    }

    private func run(text: String?, mode submittedMode: InputMode, audioFile: URL? = nil, stripWake: Bool = false) {
        let token = UUID(); generation = token
        let shouldSpeak = speakResponses
        speech.stop()
        clearTranscript()
        replayText = nil; canReplayAnswer = false
        isWorking = true
        response = ""
        status = "Verarbeite …"
        task = Task {
            defer {
                if let audioFile { try? FileManager.default.removeItem(at: audioFile) }
                if generation == token { isWorking = false; task = nil }
            }
            do {
                await voice?.suspend()
                var submittedInput = text ?? ""
                if let audioFile, let hex {
                    phase = .transcribing; status = "Hex versteht deinen Befehl …"
                    submittedInput = try await hex.transcribe(audioFile: audioFile)
                    if stripWake { submittedInput = Self.removeWakePrefix(submittedInput) }
                    try Task.checkCancellation()
                    guard generation == token else { throw CancellationError() }
                    input = submittedInput
                }
                showTranscript(submittedInput)
                let result = try await router.handle(submittedInput, mode: submittedMode) { [weak self] phase in
                    await self?.showPhase(phase, token: token)
                }
                try Task.checkCancellation()
                guard generation == token else { throw CancellationError() }
                response = result.text
                if result.route == .reasoning { replayText = result.text; canReplayAnswer = true }
                switch result.route {
                case .fastAction: status = isLive ? "Aktion ausgeführt" : "Schnelle Aktion · Vorschau"
                case .reasoning: status = isLive ? "Antwort · \(reasoningLabel)" : "LLM-Fallback · Platzhalter"
                case .dictation: status = "Diktat · Textvorschau"
                }
                // Computer actions finish visually; only requested LLM answers are spoken.
                if shouldSpeak && result.route == .reasoning {
                    phase = .speaking
                    try await speech.speak(result.text)
                }
                try Task.checkCancellation()
                phase = .idle
            } catch is CancellationError {
                guard generation == token else { return }
                status = "Abgebrochen"
                phase = .idle
            } catch {
                guard generation == token else { return }
                let failedDuringReasoning = phase == .reasoning
                status = "Fehler"
                response = error.localizedDescription
                phase = .failed
                if shouldSpeak && failedDuringReasoning {
                    try? await speech.speak(response)
                }
            }
            await rearmVoice(token: token)
            if generation == token { expireTranscript() }
        }
    }

    private func rearmVoice(token: UUID) async {
        guard generation == token, !shuttingDown else { return }
        do { try await voice?.rearm() }
        catch {
            guard generation == token, !shuttingDown else { return }
            wakeEnabled = false; try? await voice?.setEnabled(false)
            guard generation == token else { return }
            status = "Wake-Erkennung gestoppt"; response = error.localizedDescription
        }
    }

    private func showPhase(_ phase: AssistantPhase, token: UUID) {
        guard generation == token else { return }
        self.phase = phase
        switch phase {
        case .deciding: status = isLive ? "Laya entscheidet …" : "Entscheidung · Demo"
        case .acting: status = isLive ? "Computeraktion läuft …" : "Computeraktion · Vorschau"
        case .reasoning: status = isLive ? "\(reasoningLabel) antwortet …" : "LLM · Demo"
        default: break
        }
    }

    func cancel() {
        guard !shuttingDown else { return }
        let speechOnly = phase == .speaking
        task?.cancel()
        microphoneTask?.cancel()
        speech.stop()
        clearTranscript()
        isTrainingWake = false
        clearTrainingFiles()
        if voice != nil {
            let token = UUID(); generation = token
            isWorking = true
            let pendingTask = task
            task = Task {
                if !speechOnly { await hex?.stop(); await layaWorker?.stop() }
                await pendingTask?.value
                guard generation == token, !shuttingDown else { return }
                if !wakeEnabled { try? await voice?.setEnabled(false) }
                await voice?.cancel()
                guard generation == token, !shuttingDown else { return }
                isRecording = false; isWorking = false
                if !wakeEnabled { phase = .idle }
                status = wakeEnabled ? "Höre auf „Friday“ oder „Hey Friday“ · lokal" : "Abgebrochen"
                task = nil
            }
        }
    }

    func setWakeEnabled(_ value: Bool) {
        guard !shuttingDown, isReady, !isWorking else { return }
        isWorking = true
        wakeEnabled = value
        microphoneTask?.cancel()
        microphoneTask = Task {
            defer { if !isRecording { isWorking = false } }
            do { try await voice?.setEnabled(value); if !value { phase = .idle; status = "Bereit · lokal" } }
            catch { wakeEnabled = false; phase = .failed; response = error.localizedDescription }
        }
    }

    func startRecording() {
        guard !shuttingDown, isReady, !isWorking else { return }
        isWorking = true
        microphoneTask = Task {
            do { try await voice?.manualRecording() }
            catch { isWorking = false; phase = .failed; response = error.localizedDescription }
        }
    }

    func stopRecording() {
        do { try voice?.finishRecording() }
        catch { isWorking = false; isRecording = false; isTrainingWake = false; phase = .failed; response = error.localizedDescription }
    }

    func shutdown() async {
        shuttingDown = true
        clearTranscript()
        clearTrainingFiles()
        generation = UUID()
        startupTask?.cancel(); microphoneTask?.cancel(); task?.cancel(); speech.stop()
        await voice?.shutdown(); await hex?.stop(); await layaWorker?.stop()
        await startupTask?.value; await microphoneTask?.value; await task?.value
        await voice?.shutdown(); await hex?.stop(); await layaWorker?.stop()
    }

    static func removeWakePrefix(_ text: String) -> String {
        // Called only after confirmed audio wake detection. German Whisper may spell Friday as Friede.
        text.replacingOccurrences(of: #"^\s*(?:(?:hey|hi|hei|he|hej)\s*[,!]?\s*)?(?:friday|friede|freitag|fridey|freidei)\b\s*[,.:;!?-]*\s*"#,
                                  with: "", options: [.regularExpression, .caseInsensitive])
    }
}
