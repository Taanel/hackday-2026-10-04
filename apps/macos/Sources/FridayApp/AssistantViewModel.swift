import Foundation
import FridayCore
import FridayAdapters

@MainActor final class AssistantViewModel: ObservableObject {
    @Published var input = "Öffne Safari"
    @Published var mode: InputMode = .assistant
    @Published var speakResponses = true
    @Published var conversationMode = UserDefaults.standard.object(forKey: "Friday.conversationMode") as? Bool ?? true {
        didSet { UserDefaults.standard.set(conversationMode, forKey: "Friday.conversationMode") }
    }
    @Published var allowBareWake = UserDefaults.standard.bool(forKey: "Friday.allowBareWake") {
        didSet { UserDefaults.standard.set(allowBareWake, forKey: "Friday.allowBareWake") }
    }
    @Published var allowPersonalWake = UserDefaults.standard.bool(forKey: "Friday.allowPersonalWake") {
        didSet { UserDefaults.standard.set(allowPersonalWake, forKey: "Friday.allowPersonalWake") }
    }
    @Published var fastEndpoint = UserDefaults.standard.bool(forKey: "Friday.fastEndpoint") {
        didSet { UserDefaults.standard.set(fastEndpoint, forKey: "Friday.fastEndpoint") }
    }
    let homeSettings: HomeAssistantSettings
    @Published var geminiKeyInput = ""
    @Published private(set) var geminiKeyConfigured = false
    @Published private(set) var geminiKeyStatus = ""
    @Published var ttsKeyInputs = Array(repeating: "", count: 4)
    @Published private(set) var configuredTTSKeySlots: Set<Int> = []
    @Published private(set) var ttsKeyStatus = ""
    @Published private(set) var overlayTranscript = ""
    @Published private(set) var canReplayAnswer = false
    @Published private(set) var response = ""
    @Published private(set) var answerSources: [AnswerSource] = []
    @Published private(set) var projectMatches: [ProjectMatch] = []
    @Published private(set) var weatherOverview: WeatherForecast?
    @Published private(set) var weatherOverlay: WeatherForecast?
    private var weatherExpiry: Task<Void, Never>?
    private var weatherGeneration = UUID()
    @Published var ttsVoice = UserDefaults.standard.string(forKey: "Friday.ttsVoice") ?? "Kore" {
        didSet {
            cloudSpeech?.voiceName = ttsVoice
            UserDefaults.standard.set(ttsVoice, forKey: "Friday.ttsVoice")
        }
    }
    @Published var ttsProvider = UserDefaults.standard.string(forKey: "Friday.ttsProvider") ?? "gemini" {
        didSet {
            adaptiveSpeech?.preferLocal = ttsProvider != "gemini"
            adaptiveSpeech?.resetCloudAvailability()
            cloudSpeech?.resetModelAvailability()
            speechNotice = ttsProvider == "gemini" ? "Gemini-Stimme · Piper nur als Ersatz" : "Piper · Thorsten High · lokal und kostenlos"
            UserDefaults.standard.set(ttsProvider, forKey: "Friday.ttsProvider")
        }
    }
    @Published private(set) var speechNotice = ""
    @Published private(set) var lastWakeTranscript = ""
    @Published private(set) var microphoneLevel = 0.0
    @Published private(set) var localDecisionSummary = "Noch kein Auftrag geprüft"
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
    @Published private(set) var chassisEnabled = false
    @Published private(set) var chassisTesting = false
    @Published private(set) var chassisStatus = "Optional · ausgeschaltet"
    @Published private(set) var chassisPairs = 0
    @Published private(set) var chassisRejected = 0
    @Published private(set) var chassisStrength = 0.0
    @Published var chassisThreshold = UserDefaults.standard.object(forKey: "Friday.chassisThreshold") as? Double ?? 0.12 {
        didSet {
            chassis.threshold = chassisThreshold
            UserDefaults.standard.set(chassisThreshold, forKey: "Friday.chassisThreshold")
        }
    }
    private let chassis = ChassisActivation()
    private var chassisTestTask: Task<Void, Never>?

    private let router: AssistantRouter
    private let speech: any SpeechOutput
    private var cloudSpeech: GeminiSpeechOutput?
    private var adaptiveSpeech: AdaptiveSpeechOutput?
    private var ttsWorker: JSONLineProcess?
    private var projectLocator: MacProjectLocator?
    var usesCloudSpeech: Bool { cloudSpeech != nil }
    private let keyStore: LocalGeminiKeyStore
    private let ttsKeyStore: LocalGeminiTTSKeyStore
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
        keyStore: LocalGeminiKeyStore = LocalGeminiKeyStore(),
        ttsKeyStore: LocalGeminiTTSKeyStore = LocalGeminiTTSKeyStore(),
        homeAssistant: HomeAssistantClient = HomeAssistantClient()
    ) {
        self.router = router
        self.speech = speech
        self.keyStore = keyStore
        self.ttsKeyStore = ttsKeyStore
        self.homeSettings = HomeAssistantSettings(client: homeAssistant)
        geminiKeyConfigured = keyStore.isConfigured
        configuredTTSKeySlots = ttsKeyStore.configuredSlots
        chassis.threshold = chassisThreshold
        chassis.canActivate = { [weak self] in
            guard let self else { return false }
            return !self.shuttingDown && self.isReady && !self.isWorking && !self.isRecording
        }
        chassis.onActivate = { [weak self] in self?.startRecording() }
        chassis.onDiagnostics = { [weak self] pairs, rejected, strength in
            guard let self, self.chassisTesting || OrbWindowActivity.shared.active else { return }
            self.chassisPairs = pairs; self.chassisRejected = rejected; self.chassisStrength = strength
        }
        chassis.onError = { [weak self] error in
            self?.chassisEnabled = false; self?.chassisTesting = false; self?.chassisStatus = error
        }
    }

    func setChassisEnabled(_ value: Bool) {
        guard !shuttingDown, isReady, !isWorking else { return }
        chassisTestTask?.cancel(); chassisTestTask = nil; chassisTesting = false
        chassis.stop(); chassisEnabled = false
        UserDefaults.standard.set(false, forKey: "Friday.chassisEnabled")
        guard value else { chassisStatus = "Optional · ausgeschaltet"; return }
        do {
            chassis.testOnly = false
            try chassis.start()
            chassisEnabled = true
            UserDefaults.standard.set(true, forKey: "Friday.chassisEnabled")
            chassisStatus = "Doppeltippen aktiviert das Mikrofon · lokal"
        } catch { chassisStatus = error.localizedDescription }
    }

    func testChassis() {
        guard !shuttingDown, isReady, !isWorking, !chassisTesting else { return }
        do {
            chassis.stop(); chassis.testOnly = true
            try chassis.start()
            chassisPairs = 0; chassisRejected = 0; chassisStrength = 0
            chassisTesting = true
            chassisStatus = "30 Sekunden testen · keine Aufnahme durch Tippen"
            chassisTestTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                self?.finishChassisTest()
            }
        } catch { chassisEnabled = false; chassisStatus = error.localizedDescription }
    }

    func finishChassisTest() {
        chassisTestTask?.cancel(); chassisTestTask = nil
        chassis.stop(); chassisTesting = false; chassis.testOnly = false
        chassisStatus = "Test beendet · \(chassisPairs) Doppeltipps erkannt"
        if chassisEnabled {
            do { try chassis.start(); chassisStatus += " · Aktivierung wieder an" }
            catch { chassisEnabled = false; chassisStatus = error.localizedDescription }
        }
    }

    func updateTTSKey(slot: Int, remove: Bool = false) async {
        guard !shuttingDown, !isWorking, ttsKeyInputs.indices.contains(slot) else { return }
        isWorking = true; defer { isWorking = false }
        do {
            if remove { try ttsKeyStore.remove(slot: slot) }
            else { try ttsKeyStore.save(ttsKeyInputs[slot], slot: slot) }
            await cloudSpeech?.invalidateCredentials()
            adaptiveSpeech?.resetCloudAvailability()
            ttsKeyInputs[slot] = ""
            configuredTTSKeySlots = ttsKeyStore.configuredSlots
            ttsKeyStatus = "Lokal gespeichert · nur für Sprachausgabe."
        } catch { ttsKeyStatus = error.localizedDescription }
    }

    func saveGeminiKey() async {
        guard !shuttingDown, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try keyStore.save(geminiKeyInput)
            await gemini?.invalidateCredentials()
            await cloudSpeech?.invalidateCredentials()
            adaptiveSpeech?.resetCloudAvailability()
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

    func showWeather(_ forecast: WeatherForecast?) {
        dismissWeatherOverlay()
        weatherOverview = forecast; weatherOverlay = forecast
    }

    func dismissWeatherOverlay() {
        weatherGeneration = UUID()
        weatherExpiry?.cancel(); weatherExpiry = nil
        weatherOverlay = nil
    }

    func expireWeather(after duration: Duration = .seconds(40)) {
        guard weatherOverlay != nil else { return }
        weatherExpiry?.cancel()
        let token = weatherGeneration
        weatherExpiry = Task { [weak self] in
            do { try await Task.sleep(for: duration) } catch { return }
            guard let self, self.weatherGeneration == token else { return }
            self.dismissWeatherOverlay()
        }
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
            let cloudSpeech = configuration.reasoningProvider == "gemini" ? GeminiSpeechOutput() : nil
            let ttsWorker = configuration.worker("tts")
            let localSpeech = LocalPiperSpeechOutput(worker: ttsWorker)
            let adaptiveSpeech = AdaptiveSpeechOutput(local: localSpeech, cloud: cloudSpeech)
            let projectLocator = MacProjectLocator()
            let homeAssistant = HomeAssistantClient()
            let model = AssistantViewModel(router: AssistantRouter(
                decisions: CachedDecisionEngine(engine: LayaDecisionEngine(worker: laya, parser: parser), epoch: { await laya.sessionID }),
                reasoning: reasoning,
                tools: MacToolExecutor(projectLocator: projectLocator, homeAssistant: homeAssistant), minimumConfidence: 0.75
            ), speech: adaptiveSpeech, homeAssistant: homeAssistant)
            model.isLive = true; model.isReady = false
            model.gemini = gemini
            model.cloudSpeech = cloudSpeech
            model.adaptiveSpeech = adaptiveSpeech; model.ttsWorker = ttsWorker
            adaptiveSpeech.preferLocal = model.ttsProvider != "gemini"
            adaptiveSpeech.onNotice = { [weak model, weak cloudSpeech] notice in
                if notice == "Gemini-Stimme", let selected = cloudSpeech?.lastModel {
                    model?.speechNotice = "Gemini · \(selected)"
                } else { model?.speechNotice = notice }
            }
            model.speechNotice = adaptiveSpeech.preferLocal ? "Piper · Thorsten High · lokal und kostenlos" : "Gemini 3.8 TTS · Piper als Ersatz"
            model.projectLocator = projectLocator
            cloudSpeech?.voiceName = model.ttsVoice
            model.reasoningLabel = reasoningLabel
            model.hex = hex; model.layaWorker = laya
            let voice = VoiceController(wake: wake)
            voice.onWakeTranscript = { [weak model] text in
                if OrbWindowActivity.shared.active { model?.lastWakeTranscript = text }
            }
            voice.onAudioLevel = { [weak model] level in
                if OrbWindowActivity.shared.active { model?.microphoneLevel = level }
            }
            model.voice = voice
            voice.onPhase = { [weak model] phase in
                guard let model else { return }
                model.phase = phase
                model.isRecording = phase == .recording
                model.isWorking = phase == .recording
                if phase == .listening { model.status = model.allowBareWake ? "Höre auf „Hey Friday“, „Hi Friday“ oder „Friday“ · lokal" : "Höre auf „Hey Friday“ oder „Hi Friday“ · lokal" }
                else if phase == .recording {
                    model.clearTranscript()
                    model.dismissWeatherOverlay()
                    model.status = "Sprich deinen Befehl. Eine Pause beendet die Aufnahme."
                }
            }
            voice.onCommand = { [weak model] file, stripWake in model?.processRecording(file, stripWake: stripWake) }
            voice.onFollowUpTimeout = { [weak model] in
                guard let model else { return }
                model.isRecording = false; model.isWorking = false
                model.phase = model.wakeEnabled ? .listening : .idle
                model.status = "Rückfrage abgelaufen · wieder Wake-Wort nötig"
            }
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
                if UserDefaults.standard.bool(forKey: "Friday.chassisEnabled") { setChassisEnabled(true) }
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
        showWeather(nil)
        replayText = nil; canReplayAnswer = false
        isWorking = true
        response = ""
        answerSources = []
        projectMatches = []
        status = "Verarbeite …"
        task = Task {
            var successfulAction = false
            var offerFollowUp = false
            defer {
                if let audioFile { try? FileManager.default.removeItem(at: audioFile) }
                if generation == token { isWorking = isRecording; task = nil }
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
                    // A wake phrase spoken on its own opens a command window;
                    // it must not send an empty question to the router/LLM.
                    if stripWake, wakeEnabled, submittedInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let voice {
                        try await voice.followUpRecording()
                        status = "Ich höre · sag jetzt deinen Auftrag · 8 Sekunden"
                        showTranscript("Sag jetzt deinen Auftrag")
                        return
                    }
                }
                showTranscript(submittedInput)
                if Self.endsConversation(submittedInput) {
                    response = "Alles klar."; phase = .idle; status = "Gespräch beendet"
                    await rearmVoice(token: token); expireTranscript(after: .seconds(1)); return
                }
                let result = try await router.handleReportingDecision(submittedInput, mode: submittedMode, onDecision: { [weak self] summary in
                    await self?.showDecision(summary, token: token)
                }) { [weak self] phase in
                    await self?.showPhase(phase, token: token)
                }
                try Task.checkCancellation()
                guard generation == token else { throw CancellationError() }
                let matches = await projectLocator?.matches ?? []
                try Task.checkCancellation()
                guard generation == token else { return }
                response = result.text
                answerSources = result.sources
                showWeather(result.weather)
                projectMatches = matches
                successfulAction = result.route == .fastAction
                if result.route == .reasoning { replayText = result.text; canReplayAnswer = true }
                switch result.route {
                case .fastAction: status = isLive ? "Aktion ausgeführt" : "Schnelle Aktion · Vorschau"
                case .reasoning: status = isLive ? "Antwort · \(reasoningLabel)" : "LLM-Fallback · Platzhalter"
                case .dictation: status = "Diktat · Textvorschau"
                }
                // Computer actions finish visually; only requested LLM answers are spoken.
                if shouldSpeak && result.route == .reasoning {
                    phase = .speaking
                    do {
                        try await speech.speak(result.text)
                        offerFollowUp = conversationMode && wakeEnabled && submittedMode == .assistant && Self.isFollowUpQuestion(result.text)
                    }
                    catch is CancellationError { throw CancellationError() }
                    catch { speechNotice = error.localizedDescription; status = "Antwort erhalten · Sprachausgabe: \(error.localizedDescription)" }
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
            if offerFollowUp, generation == token, !shuttingDown, let voice {
                do {
                    try Task.checkCancellation()
                    try await voice.followUpRecording()
                    status = "Antworte auf die Rückfrage · 8 Sekunden · kein Wake-Wort nötig"
                    showTranscript("Du kannst jetzt direkt antworten · Stop beendet das Zuhören")
                } catch { await rearmVoice(token: token) }
            } else { await rearmVoice(token: token) }
            if generation == token {
                expireTranscript(after: successfulAction ? .seconds(1) : .seconds(8))
                expireWeather()
            }
        }
    }

    static func isFollowUpQuestion(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?")
    }
    static func endsConversation(_ text: String) -> Bool {
        let value = String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
        return ["neeistegal", "neinistegal", "istegal", "abbrechen", "gesprächbeenden", "dankedaswars", "stop", "stopp"].contains(value)
    }
    func clearConversation() async { await gemini?.clearConversation(); status = "Gesprächskontext gelöscht" }

    func focusProjectMatch(_ id: UUID) {
        guard !shuttingDown, !isWorking, let projectLocator else { return }
        let token = UUID(); generation = token
        isWorking = true; phase = .acting; status = "Fokussiere den gewählten Treffer …"
        task = Task {
            defer { if generation == token { isWorking = false; task = nil } }
            do {
                await voice?.suspend()
                try Task.checkCancellation()
                let result = try await projectLocator.focus(id)
                guard generation == token else { return }
                response = result; projectMatches = []; phase = .idle; status = "Projekt gefunden"
            } catch is CancellationError {
                guard generation == token else { return }
                phase = .idle; status = "Abgebrochen"
            } catch {
                guard generation == token else { return }
                response = error.localizedDescription; phase = .failed; status = "Treffer nicht verfügbar"
            }
            await rearmVoice(token: token)
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

    private func showDecision(_ summary: String, token: UUID) {
        guard generation == token else { return }
        localDecisionSummary = summary
    }

    func cancel() {
        guard !shuttingDown else { return }
        let speechOnly = phase == .speaking
        task?.cancel()
        microphoneTask?.cancel()
        speech.stop()
        clearTranscript()
        dismissWeatherOverlay()
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
                status = wakeEnabled ? "Höre auf „Hey Friday“ oder „Hi Friday“ · lokal" : "Abgebrochen"
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
        guard !shuttingDown, isReady, !isWorking, !isRecording else { return }
        dismissWeatherOverlay()
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
        dismissWeatherOverlay()
        shuttingDown = true
        chassisTestTask?.cancel(); chassis.stop()
        clearTranscript()
        clearTrainingFiles()
        generation = UUID()
        startupTask?.cancel(); microphoneTask?.cancel(); task?.cancel(); speech.stop()
        await voice?.shutdown(); await hex?.stop(); await layaWorker?.stop(); await ttsWorker?.stop()
        await startupTask?.value; await microphoneTask?.value; await task?.value
        await voice?.shutdown(); await hex?.stop(); await layaWorker?.stop(); await ttsWorker?.stop()
    }

    static func removeWakePrefix(_ text: String) -> String {
        // Called only after confirmed audio wake detection. German Whisper may spell Friday as Friede.
        text.replacingOccurrences(of: #"^\s*(?:(?:hey|hi|hei|he|hej)\s*[,!]?\s*)?(?:friday|frida|freda|friede|freitag|fridey|freidei|fida|fidder)\b\s*[,.:;!?-]*\s*"#,
                                  with: "", options: [.regularExpression, .caseInsensitive])
    }
}
