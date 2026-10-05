import AVFoundation
import Foundation
@preconcurrency import SoundAnalysis

public protocol SoundClipClassifying: Sendable {
    func prepare() async throws
    func classify(_ samples: [Float]) async throws -> SoundClassification
}

private final class ClassificationObserver: NSObject, SNResultsObserving, @unchecked Sendable {
    private let lock = NSLock()
    private var scores: [String: Double] = [:]
    private var finished = false
    let completion: @Sendable (Result<SoundClassification, any Error>) -> Void
    init(completion: @escaping @Sendable (Result<SoundClassification, any Error>) -> Void) { self.completion = completion }
    func request(_ request: any SNRequest, didProduce result: any SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        lock.lock(); defer { lock.unlock() }
        guard !finished else { return }
        for classification in result.classifications { scores[classification.identifier] = max(scores[classification.identifier] ?? 0, classification.confidence) }
    }
    func request(_ request: any SNRequest, didFailWithError error: any Error) { finish(.failure(error)) }
    func requestDidComplete(_ request: any SNRequest) {
        lock.lock(); let result = SoundClassification(scores: scores); lock.unlock()
        finish(.success(result))
    }
    private func finish(_ result: Result<SoundClassification, any Error>) {
        lock.lock(); let shouldFinish = !finished; finished = true; lock.unlock()
        if shouldFinish { completion(result) }
    }
}

/// Framework objects stay on this actor; only copied PCM/scores cross its boundary.
public actor BuiltinSoundClassifier: SoundClipClassifying {
    private var request: SNClassifySoundRequest?
    private struct Job {
        let analyzer: SNAudioStreamAnalyzer
        let observer: ClassificationObserver
        let continuation: CheckedContinuation<SoundClassification, any Error>
        let timeout: Task<Void, Never>
    }
    private var jobs: [UUID: Job] = [:]
    public init() {}
    public func prepare() throws {
        guard request == nil else { return }
        let value = try SNClassifySoundRequest(classifierIdentifier: .version1)
        guard Set(value.knownClassifications).isSuperset(of: SoundGesture.allCases.map(\.rawValue)) else {
            throw AdapterError.unavailable("Dieser Mac unterstützt die Klatsch-/Schnipserkennung nicht.")
        }
        value.windowDuration = CMTime(value: 8_000, timescale: 16_000)
        value.overlapFactor = 0
        request = value
    }
    public func classify(_ samples: [Float]) async throws -> SoundClassification {
        try Task.checkCancellation(); try prepare()
        guard (8_000...32_000).contains(samples.count), jobs.isEmpty, let request,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)), let channel = buffer.floatChannelData?[0] else {
            throw AdapterError.unavailable("Ungültiges oder bereits laufendes Geräuschfenster.")
        }
        request.windowDuration = CMTime(value: Int64(samples.count), timescale: 16_000)
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let analyzer = SNAudioStreamAnalyzer(format: format)
                let observer = ClassificationObserver { result in Task { await self.finish(id, result: result) } }
                let timeout = Task {
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                    self.finish(id, result: .failure(AdapterError.unavailable("Geräuscherkennung hat zu lange gebraucht.")))
                }
                jobs[id] = Job(analyzer: analyzer, observer: observer, continuation: continuation, timeout: timeout)
                do { try analyzer.add(request, withObserver: observer); analyzer.analyze(buffer, atAudioFramePosition: 0); analyzer.completeAnalysis() }
                catch { finish(id, result: .failure(error)) }
            }
        } onCancel: { Task { await self.finish(id, result: .failure(CancellationError())) } }
    }
    private func finish(_ id: UUID, result: Result<SoundClassification, any Error>) {
        guard let job = jobs.removeValue(forKey: id) else { return }
        job.timeout.cancel(); job.analyzer.removeAllRequests()
        job.continuation.resume(with: result)
    }
}
