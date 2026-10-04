import Foundation
import FridayCore
import FridayAdapters

/// Owns listening/capture. Processing belongs to the ViewModel, which rearms after completion.
@MainActor final class VoiceController {
    var onPhase: ((AssistantPhase) -> Void)?
    var onCommand: ((URL, Bool) -> Void)?
    var onError: ((any Error) -> Void)?
    private let audio = AudioInput()
    private let wake: MoonshineWakeWordDetector
    private var enabled = false
    private var closed = false
    private var awaitingWake = false
    private var wakeOrigin = 0
    private var generation = UUID()
    private var wakeGeneration = 0
    private var wakeTriggered = false
    private var frameContinuation: AsyncStream<[Float]>.Continuation?
    private var feedTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?

    init(wake: MoonshineWakeWordDetector) {
        self.wake = wake
        audio.onFrames = { [weak self] samples in
            guard let self, self.awaitingWake else { return }
            self.frameContinuation?.yield(samples)
        }
        audio.onRecordingEnded = { [weak self] file in
            guard let self else { return }
            if !self.enabled { self.audio.stop() }
            self.onCommand?(file, self.wakeTriggered)
        }
        audio.onError = { [weak self] error in self?.onError?(error) }
    }

    func setEnabled(_ value: Bool) async throws {
        guard !closed else { throw CancellationError() }
        enabled = value
        if !value { await suspend(); if !audio.isRecording { audio.stop() }; return }
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
                    if detection.type == "error", let error = detection.error {
                        self?.onError?(AdapterError.unavailable(error))
                        continue
                    }
                    await self?.detected(detection)
                }
            }
        }
        try await audio.start()
        try Task.checkCancellation()
        guard enabled, generation == token else { audio.stop(); return }
        try await rearm()
        } catch {
            enabled = false
            audio.stop()
            await suspend()
            throw error
        }
    }

    func rearm() async throws {
        try Task.checkCancellation()
        guard !closed else { throw CancellationError() }
        guard enabled, !audio.isRecording else { if !audio.isRecording { audio.stop() }; return }
        try await wake.start()
        wakeGeneration = try await wake.resume()
        let (frames, continuation) = AsyncStream<[Float]>.makeStream(bufferingPolicy: .bufferingNewest(80))
        frameContinuation?.finish(); feedTask?.cancel()
        frameContinuation = continuation
        wakeOrigin = audio.totalSamples
        awaitingWake = true
        feedTask = Task { [weak self] in
            for await samples in frames {
                guard let self, !Task.isCancelled, self.awaitingWake else { return }
                do { try await self.wake.feed(samples) }
                catch { if !Task.isCancelled { self.onError?(error) }; return }
            }
        }
        onPhase?(.listening)
    }

    private func detected(_ detection: WakeDetection) async {
        guard detection.type == "wake", detection.generation == wakeGeneration,
              enabled, awaitingWake, !audio.isRecording else { return }
        awaitingWake = false
        let from = detection.startSample.map { wakeOrigin + $0 } ?? max(0, audio.totalSamples - 32_000)
        wakeTriggered = true
        audio.beginRecording(fromSample: from)
        onPhase?(.recording)
        await suspend()
    }

    func manualRecording() async throws {
        try Task.checkCancellation()
        guard !closed else { throw CancellationError() }
        await suspend()
        do {
            try await audio.start()
            try Task.checkCancellation()
            guard !closed else { throw CancellationError() }
            wakeTriggered = false
            audio.beginRecording()
            onPhase?(.recording)
        } catch {
            audio.stop()
            throw error
        }
    }

    func finishRecording() throws {
        defer { if !enabled { audio.stop() } }
        if let file = try audio.finishRecording() {
            if !enabled { audio.stop() }
            onCommand?(file, wakeTriggered)
        }
    }

    func suspend() async {
        awaitingWake = false
        frameContinuation?.finish(); frameContinuation = nil
        feedTask?.cancel(); feedTask = nil
        try? await wake.pause()
    }

    func cancel() async {
        generation = UUID()
        audio.cancelRecording()
        await suspend()
        if enabled { try? await rearm() } else { audio.stop() }
    }

    func shutdown() async {
        closed = true; enabled = false; generation = UUID()
        audio.stop()
        frameContinuation?.finish()
        feedTask?.cancel(); eventTask?.cancel()
        await wake.stop()
    }
}
