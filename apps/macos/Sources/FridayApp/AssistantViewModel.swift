import Foundation
import FridayCore
import FridayAdapters

@MainActor final class AssistantViewModel: ObservableObject {
    @Published var input = "Öffne Safari"
    @Published var mode: InputMode = .assistant
    @Published var speakResponses = false
    @Published private(set) var response = ""
    @Published private(set) var status = "Bereit · Demo"
    @Published private(set) var isWorking = false
    @Published private(set) var phase: AssistantPhase = .idle
    @Published private(set) var isReady = true
    @Published private(set) var wakeEnabled = false
    @Published private(set) var isRecording = false

    private let router: AssistantRouter
    private let speech: any SpeechOutput
    private var voice: VoiceController?
    private var hex: HexService?
    private var layaWorker: JSONLineProcess?
    private var startupTask: Task<Void, Never>?
    private var microphoneTask: Task<Void, Never>?
    private var generation = UUID()
    private var isLive = false
    private var shuttingDown = false
    private(set) var task: Task<Void, Never>?

    init(
        router: AssistantRouter = AssistantRouter(
            decisions: DemoDecisionEngine(),
            reasoning: DemoReasoningEngine(),
            tools: PreviewToolExecutor()
        ),
        speech: any SpeechOutput = SystemSpeechOutput()
    ) {
        self.router = router
        self.speech = speech
    }

    static func live() -> AssistantViewModel {
        do {
            let configuration = try RuntimeConfiguration.load()
            let laya = configuration.worker("laya")
            let wake = MoonshineWakeWordDetector(worker: configuration.worker("wake"))
            let hex = HexService(configuration: configuration)
            let model = AssistantViewModel(router: AssistantRouter(
                decisions: LayaDecisionEngine(worker: laya),
                reasoning: OllamaReasoningEngine(model: configuration.ollamaModel),
                tools: MacToolExecutor(), minimumConfidence: 0.75
            ))
            model.isLive = true; model.isReady = false
            model.hex = hex; model.layaWorker = laya
            let voice = VoiceController(wake: wake)
            model.voice = voice
            voice.onPhase = { [weak model] phase in
                guard let model else { return }
                model.phase = phase
                model.isRecording = phase == .recording
                model.isWorking = phase == .recording
                if phase == .listening { model.status = "Höre auf „Hey Friday“ · lokal" }
                else if phase == .recording { model.status = "Sprich deinen Befehl. Eine Pause beendet die Aufnahme." }
            }
            voice.onCommand = { [weak model] file, stripWake in model?.processRecording(file, stripWake: stripWake) }
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
        guard task == nil, isReady else { try? FileManager.default.removeItem(at: file); return }
        isRecording = false
        run(text: nil, mode: mode, audioFile: file, stripWake: stripWake)
    }

    private func run(text: String?, mode submittedMode: InputMode, audioFile: URL? = nil, stripWake: Bool = false) {
        let token = UUID(); generation = token
        let shouldSpeak = speakResponses
        speech.stop()
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
                let result = try await router.handle(submittedInput, mode: submittedMode) { [weak self] phase in
                    await self?.showPhase(phase, token: token)
                }
                try Task.checkCancellation()
                guard generation == token else { throw CancellationError() }
                response = result.text
                switch result.route {
                case .fastAction: status = isLive ? "Aktion ausgeführt" : "Schnelle Aktion · Vorschau"
                case .reasoning: status = isLive ? "LLM-Antwort · lokal" : "LLM-Fallback · Platzhalter"
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
                status = "Fehler"
                response = error.localizedDescription
                phase = .failed
            }
            if generation == token, !shuttingDown {
                do { try await voice?.rearm() }
                catch { wakeEnabled = false; try? await voice?.setEnabled(false); status = "Wake-Erkennung gestoppt"; response = error.localizedDescription }
            }
        }
    }

    private func showPhase(_ phase: AssistantPhase, token: UUID) {
        guard generation == token else { return }
        self.phase = phase
        switch phase {
        case .deciding: status = isLive ? "Laya entscheidet …" : "Entscheidung · Demo"
        case .acting: status = isLive ? "Computeraktion läuft …" : "Computeraktion · Vorschau"
        case .reasoning: status = isLive ? "Lokales LLM denkt nach …" : "LLM · Demo"
        default: break
        }
    }

    func cancel() {
        guard !shuttingDown else { return }
        task?.cancel()
        microphoneTask?.cancel()
        speech.stop()
        if voice != nil {
            let token = UUID(); generation = token
            isWorking = true
            let pendingTask = task
            task = Task {
                await hex?.stop()
                await layaWorker?.stop()
                await pendingTask?.value
                guard generation == token, !shuttingDown else { return }
                if !wakeEnabled { try? await voice?.setEnabled(false) }
                await voice?.cancel()
                guard generation == token, !shuttingDown else { return }
                isRecording = false; isWorking = false
                if !wakeEnabled { phase = .idle }
                status = wakeEnabled ? "Höre auf „Hey Friday“ · lokal" : "Abgebrochen"
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
        catch { isWorking = false; isRecording = false; phase = .failed; response = error.localizedDescription }
    }

    func shutdown() async {
        shuttingDown = true
        generation = UUID()
        startupTask?.cancel(); microphoneTask?.cancel(); task?.cancel(); speech.stop()
        await voice?.shutdown(); await hex?.stop(); await layaWorker?.stop()
        await startupTask?.value; await microphoneTask?.value; await task?.value
        await voice?.shutdown(); await hex?.stop(); await layaWorker?.stop()
    }

    static func removeWakePrefix(_ text: String) -> String {
        // Called only after confirmed audio wake detection. German Whisper may spell Friday as Friede.
        text.replacingOccurrences(of: #"^\s*(?:hey|hi|hei|he|hej)\s*[,!]?\s*(?:friday|friede|freitag|fridey|freidei)\b\s*[,.:;!?-]*\s*"#,
                                  with: "", options: [.regularExpression, .caseInsensitive])
    }
}
