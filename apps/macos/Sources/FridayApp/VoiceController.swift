import Foundation
import FridayCore
import FridayAdapters

@MainActor protocol VoiceAudioInput: AnyObject {
    var onFrames: (([Float]) -> Void)? { get set }
    var onRecordingEnded: ((URL) -> Void)? { get set }
    var onError: ((any Error) -> Void)? { get set }
    var isRecording: Bool { get }
    var totalSamples: Int { get }
    var hasRecordedSpeech: Bool { get }
    func start() async throws
    func stop()
    func beginRecording(fromSample: Int?)
    func finishRecording() throws -> URL?
    func cancelRecording()
}
extension VoiceAudioInput { var hasRecordedSpeech: Bool { false } }
extension AudioInput: VoiceAudioInput {}

/// Owns listening/capture. Processing belongs to the ViewModel, which rearms after completion.
@MainActor final class VoiceController {
    var onPhase: ((AssistantPhase) -> Void)?
    var onCommand: ((URL, Bool) -> Void)?
    var onError: ((any Error) -> Void)?
    var onWakeRecovery: (() -> Void)?
    var onFollowUpTimeout: (() -> Void)?
    var onWakeTranscript: ((String) -> Void)?
    var onAudioLevel: ((Double) -> Void)?
    var onSoundDiagnostics: ((SoundGestureDiagnostics) -> Void)?
    var onSoundError: ((any Error) -> Void)?
    private var levelSamples = 0
    private var levelEnergy = 0.0
    private(set) var followingReply = false
    private var followUpTimeout: Task<Void, Never>?
    private let audio: any VoiceAudioInput
    private let wake: MoonshineWakeWordDetector
    private let sound: any SoundActivationInput
    private var awaitingSound = false
    private var soundOrigin = 0
    private var needsBackgroundAudio: Bool { enabled || sound.isEnabled }
    private var enabled = false
    private var closed = false
    private var awaitingWake = false
    private var wakeOrigin = 0
    private var generation = UUID()
    private var wakeGeneration = 0
    private var wakeSession = UUID()
    private var wakeTriggered = false
    private var startingRecording = false
    private var frameContinuation: AsyncStream<[Float]>.Continuation?
    private var feedTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var recovering = false
    private var recoveries: [Date] = []

    init(wake: MoonshineWakeWordDetector, audio: any VoiceAudioInput = AudioInput(), sound: any SoundActivationInput = SoundGestureActivation()) {
        self.wake = wake; self.audio = audio; self.sound = sound
        sound.onDiagnostics = { [weak self] report in self?.onSoundDiagnostics?(report) }
        sound.onError = { [weak self] error in
            guard let self else { return }
            self.sound.stop(); self.awaitingSound = false
            if !self.enabled, !self.audio.isRecording { self.audio.stop() }
            self.onSoundError?(error)
        }
        sound.onActivate = { [weak self] detection in self?.detectedSound(detection) }
        audio.onFrames = { [weak self] samples in
            guard let self, !self.closed else { return }
            if self.awaitingSound, !self.audio.isRecording { self.sound.accept(samples) }
            guard self.awaitingWake || self.awaitingSound else { return }
            self.levelSamples += samples.count
            self.levelEnergy += samples.reduce(0) { $0 + Double($1) * Double($1) }
            if self.levelSamples >= 16000 {
                self.onAudioLevel?(sqrt(self.levelEnergy / Double(self.levelSamples)))
                self.levelSamples = 0; self.levelEnergy = 0
            }
            if self.awaitingWake { self.frameContinuation?.yield(samples) }
        }
        audio.onRecordingEnded = { [weak self] file in
            guard let self else { return }
            self.followUpTimeout?.cancel(); self.followUpTimeout = nil; self.followingReply = false
            if !self.needsBackgroundAudio { self.audio.stop() }
            self.onCommand?(file, self.wakeTriggered)
        }
        audio.onError = { [weak self] error in self?.onError?(error) }
    }

    func setSoundOptions(_ options: SoundActivationOptions) async throws {
        guard !closed else { throw CancellationError() }
        await suspend()
        try Task.checkCancellation()
        guard !closed else { throw CancellationError() }
        do { try await sound.configure(options); try await rearm() }
        catch {
            // Failed microphone startup must not leave gestures enabled behind
            // an unchanged settings toggle, even when manual capture later works.
            sound.stop(); awaitingSound = false; onSoundError?(error)
            try? await rearm(); throw error
        }
    }

    private func detectedSound(_ detection: SoundGestureDetection) {
        guard !closed, awaitingSound, sound.isEnabled, !startingRecording, !audio.isRecording else { return }
        let from = soundOrigin + detection.commandStartSample
        guard from >= soundOrigin, from <= audio.totalSamples, audio.totalSamples - from <= 128_000 else { return }
        awaitingSound = false; awaitingWake = false; startingRecording = true
        wakeTriggered = false
        // Capture already buffered speech after the second sound, including
        // syllables spoken while the local classifier was finishing.
        audio.beginRecording(fromSample: from)
        onPhase?(.recording)
        let token = generation
        Task {
            guard !self.closed, self.generation == token, self.audio.isRecording else {
                self.startingRecording = false; return
            }
            await self.suspend(); self.startingRecording = false
        }
    }

    func setEnabled(_ value: Bool) async throws {
        guard !closed else { throw CancellationError() }
        enabled = value
        if !value { await suspend(); if !audio.isRecording { try await rearm() }; return }
        do {
        let token = generation
        try await wake.start()
        try Task.checkCancellation()
        guard enabled, generation == token else { return }
        if eventTask == nil {
            let events = await wake.events
            eventTask = Task { [weak self] in
                for await data in events {
                    guard !Task.isCancelled else { return }
                    guard let detection = try? JSONDecoder().decode(WakeDetection.self, from: data) else { continue }
                    if detection.type == "transcript", let text = detection.text {
                        guard let self, self.awaitingWake, detection.transportSession == self.wakeSession,
                              detection.generation == self.wakeGeneration else { continue }
                        self.onWakeTranscript?(text)
                        continue
                    }
                    if detection.type == "error", let error = detection.error {
                        guard let self, self.awaitingWake, detection.transportSession == self.wakeSession,
                              detection.generation == nil || detection.generation == self.wakeGeneration else { continue }
                        await self.recoverWake(AdapterError.unavailable(error))
                        continue
                    }
                    await self?.detected(detection)
                }
            }
        }
        try await audio.start()
        try Task.checkCancellation()
        guard enabled, generation == token else {
            if !needsBackgroundAudio, !audio.isRecording { audio.stop() }
            return
        }
        try await rearm()
        } catch {
            enabled = false
            await suspend()
            try? await rearm()
            throw error
        }
    }

    func rearm() async throws {
        try Task.checkCancellation()
        guard !closed else { throw CancellationError() }
        guard needsBackgroundAudio, !audio.isRecording else { if !audio.isRecording { audio.stop() }; return }
        let token = generation
        try await audio.start()
        try Task.checkCancellation()
        guard needsBackgroundAudio, !closed, generation == token, !audio.isRecording else { return }
        if enabled {
        try await wake.start()
        try Task.checkCancellation()
        guard enabled, !closed, generation == token, !audio.isRecording else { return }
        wakeGeneration = try await wake.resume()
        wakeSession = await wake.sessionID
        try Task.checkCancellation()
        guard enabled, !closed, generation == token, !audio.isRecording else { return }
        let (frames, continuation) = AsyncStream<[Float]>.makeStream(bufferingPolicy: .bufferingNewest(80))
        frameContinuation?.finish(); feedTask?.cancel()
        frameContinuation = continuation
        wakeOrigin = audio.totalSamples
        awaitingWake = true
        feedTask = Task { [weak self] in
            for await samples in frames {
                guard let self, !Task.isCancelled, self.awaitingWake else { return }
                do { try await self.wake.feed(samples) }
                catch {
                    if !Task.isCancelled { Task { await self.recoverWake(error) } }
                    return
                }
            }
        }
        }
        soundOrigin = audio.totalSamples
        sound.resume(); awaitingSound = sound.isEnabled
        onPhase?(.listening)
    }

    private func recoverWake(_ error: any Error) async {
        guard enabled, !closed, awaitingWake, !recovering else { return }
        recovering = true
        defer { recovering = false }
        recoveries = recoveries.filter { Date().timeIntervalSince($0) < 60 }
        guard recoveries.count < 3 else {
            enabled = false
            await suspend(); try? await rearm(); onError?(error)
            return
        }
        recoveries.append(Date())
        onWakeRecovery?()
        await suspend()
        // Only restart the wake helper. Hex and Laya stay warm.
        await wake.stop()
        do {
            try await Task.sleep(for: .milliseconds(200))
            guard enabled, !closed else { return }
            try await rearm()
        } catch {
            guard enabled, !closed else { return }
            enabled = false; try? await rearm(); onError?(error)
        }
    }

    func enrollWake(files: [URL]) async throws {
        try await wake.start()
        try await wake.enroll(files: files)
    }

    func clearWakeProfile() async throws {
        await suspend()
        try await wake.start()
        try await wake.clearProfile()
    }

    private func detected(_ detection: WakeDetection) async {
        guard detection.type == "wake", detection.generation == wakeGeneration,
              detection.transportSession == wakeSession,
              enabled, awaitingWake, !startingRecording, !audio.isRecording else { return }
        awaitingWake = false
        recoveries.removeAll()
        let from = detection.startSample.map { wakeOrigin + $0 } ?? max(0, audio.totalSamples - 32_000)
        wakeTriggered = true
        audio.beginRecording(fromSample: from)
        onPhase?(.recording)
        await suspend()
    }

    func manualRecording() async throws {
        try Task.checkCancellation()
        guard !closed else { throw CancellationError() }
        guard !startingRecording, !audio.isRecording else { return }
        startingRecording = true
        defer { startingRecording = false }
        let token = generation
        // Start capture before waiting for the worker's final decode/pause ACK.
        // A click must not lose the first syllables or accept another wake.
        awaitingWake = false; awaitingSound = false; sound.suspend()
        do {
            try await audio.start()
            try Task.checkCancellation()
            guard !closed, generation == token else { throw CancellationError() }
            wakeTriggered = false
            audio.beginRecording(fromSample: nil)
            onPhase?(.recording)
            await suspend()
        } catch {
            audio.stop()
            await suspend()
            throw error
        }
    }

    func followUpRecording(timeout: Duration = .seconds(8)) async throws {
        try await manualRecording()
        followingReply = true
        let token = generation
        followUpTimeout = Task { [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            guard let self, self.generation == token, !self.closed, self.followingReply,
                  self.audio.isRecording, !self.audio.hasRecordedSpeech else { return }
            self.followingReply = false
            self.audio.cancelRecording()
            do { try await self.rearm() } catch { self.onError?(error) }
            guard self.generation == token, !self.closed, !Task.isCancelled else { return }
            self.onFollowUpTimeout?()
        }
    }

    func finishRecording() throws {
        defer { if !needsBackgroundAudio { audio.stop() } }
        if let file = try audio.finishRecording() {
            if !needsBackgroundAudio { audio.stop() }
            onCommand?(file, wakeTriggered)
        }
    }

    func suspend() async {
        followUpTimeout?.cancel(); followUpTimeout = nil; followingReply = false
        awaitingWake = false
        awaitingSound = false; sound.suspend()
        frameContinuation?.finish(); frameContinuation = nil
        feedTask?.cancel(); feedTask = nil
        try? await wake.pause()
    }

    func cancel() async {
        generation = UUID()
        audio.cancelRecording()
        await suspend()
        if needsBackgroundAudio { try? await rearm() } else { audio.stop() }
    }

    func shutdown() async {
        followUpTimeout?.cancel(); followUpTimeout = nil; followingReply = false
        closed = true; enabled = false; generation = UUID()
        awaitingSound = false; sound.stop()
        audio.stop()
        frameContinuation?.finish()
        feedTask?.cancel(); eventTask?.cancel()
        await wake.stop()
    }
}
