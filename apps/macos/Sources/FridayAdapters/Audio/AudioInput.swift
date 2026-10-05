import AVFoundation
import Foundation

private final class Resampler: @unchecked Sendable {
    // AVAudioConverter invokes its input block synchronously within convert().
    private final class ConversionInput: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
        var supplied = false
        init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    }
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    init(input: AVAudioFormat) throws {
        outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: input, to: outputFormat) else {
            throw AdapterError.unavailable("Dieses Mikrofonformat wird nicht unterstützt.")
        }
        self.converter = converter
    }
    // Used exclusively by the input node's serial tap callback.
    func convert(_ input: AVAudioPCMBuffer) throws -> [Float] {
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * 16_000 / input.format.sampleRate) + 16)
        let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity)!
        let source = ConversionInput(input)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if source.supplied { state.pointee = .noDataNow; return nil }
            source.supplied = true; state.pointee = .haveData; return source.buffer
        }
        if status == .error { throw error ?? AdapterError.unavailable("Audio-Konvertierung fehlgeschlagen.") as NSError }
        guard let pointer = output.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: pointer, count: Int(output.frameLength)))
    }
}

/// Single microphone owner. Its PCM stream feeds wake recognition and command capture.
@MainActor public final class AudioInput {
    public var onFrames: (([Float]) -> Void)?
    public var onRecordingEnded: ((URL) -> Void)?
    public var onError: ((any Error) -> Void)?
    public private(set) var totalSamples = 0
    public private(set) var isRecording = false
    private let engine = AVAudioEngine()
    private var started = false
    private var generation = UUID()
    private var ring: [Float] = []
    private var recording: [Float] = []
    private var endpoint = CommandEndpoint()
    public var hasRecordedSpeech: Bool { endpoint.hasSpeech }

    public init() {}

    public func start() async throws {
        if started { return }
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        try Task.checkCancellation()
        if started { return }
        guard granted else { throw AdapterError.unavailable("Bitte Mikrofonzugriff für Friday in den Systemeinstellungen erlauben.") }
        let node = engine.inputNode
        let format = node.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AdapterError.unavailable("Kein Mikrofon verfügbar.") }
        generation = UUID()
        node.installTap(onBus: 0, bufferSize: 4096, format: format, block: try makeTap(format: format))
        do { engine.prepare(); try engine.start(); started = true }
        catch { node.removeTap(onBus: 0); throw error }
    }

    func makeTap(format: AVAudioFormat) throws -> AVAudioNodeTapBlock {
        let resampler = try Resampler(input: format)
        let token = generation
        // AVAudioNodeTapBlock lacks Sendable annotations. Its callback runs on
        // an audio thread and must not inherit this object's MainActor.
        return { @Sendable [weak self] buffer, _ in
            do {
                let samples = try resampler.convert(buffer)
                Task { @MainActor [weak self] in
                    guard self?.generation == token else { return }
                    self?.receive(samples)
                }
            } catch { Task { @MainActor [weak self] in
                guard self?.generation == token else { return }
                self?.onError?(error)
            } }
        }
    }

    private func receive(_ samples: [Float]) {
        guard started, !samples.isEmpty else { return }
        totalSamples += samples.count
        ring.append(contentsOf: samples)
        if ring.count > 128_000 { ring.removeFirst(ring.count - 128_000) }
        if isRecording {
            recording.append(contentsOf: samples)
            // A brief pause ends a spoken command. A bounded recording avoids a lost endpoint.
            if endpoint.accept(samples) {
                do { if let file = try finishRecording() { onRecordingEnded?(file) } }
                catch { onError?(error) }
            }
        }
        onFrames?(samples)
    }

    public func beginRecording(fromSample: Int? = nil) {
        guard started, !isRecording else { return }
        let count = fromSample.map { max(0, min(ring.count, totalSamples - $0)) } ?? 0
        recording = Array(ring.suffix(count))
        isRecording = true
        endpoint = CommandEndpoint(preRollSamples: count, fast: UserDefaults.standard.bool(forKey: "Friday.fastEndpoint"))
    }

    public func finishRecording() throws -> URL? {
        guard isRecording else { return nil }
        isRecording = false
        defer { recording.removeAll(keepingCapacity: true) }
        guard recording.count >= 1600 else { throw AdapterError.unavailable("Die Aufnahme war zu kurz. Bitte erneut sprechen.") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("friday-\(UUID().uuidString).wav")
        try WAVEncoder.encode(recording).write(to: url, options: .atomic)
        return url
    }

    public func cancelRecording() { isRecording = false; recording.removeAll() }
    public func stop() {
        generation = UUID()
        cancelRecording()
        guard started else { return }
        started = false
        engine.stop(); engine.inputNode.removeTap(onBus: 0)
        ring.removeAll(); totalSamples = 0
    }
}
