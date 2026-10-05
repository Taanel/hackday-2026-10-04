import Foundation

public struct SoundActivationOptions: Sendable {
    public var gestures: Set<SoundGesture>
    public var testOnly: Bool
    public var minimumRMS: Double
    public var confidence: Double
    public init(gestures: Set<SoundGesture> = [], testOnly: Bool = false, minimumRMS: Double = 0.004, confidence: Double = 0.65) {
        self.gestures = gestures; self.testOnly = testOnly; self.minimumRMS = minimumRMS; self.confidence = confidence
    }
}

public struct SoundGestureDetection: Sendable {
    public let gesture: SoundGesture
    public let commandStartSample: Int
    public init(gesture: SoundGesture, commandStartSample: Int) { self.gesture = gesture; self.commandStartSample = commandStartSample }
}

public struct SoundGestureDiagnostics: Sendable {
    public let attempts: Int
    public let claps: Int
    public let snaps: Int
    public let message: String
    public let confidence: Double
}

@MainActor public protocol SoundActivationInput: AnyObject {
    var onActivate: ((SoundGestureDetection) -> Void)? { get set }
    var onDiagnostics: ((SoundGestureDiagnostics) -> Void)? { get set }
    var onError: ((any Error) -> Void)? { get set }
    var isEnabled: Bool { get }
    func configure(_ options: SoundActivationOptions) async throws
    func resume()
    func accept(_ samples: [Float])
    func suspend()
    func stop()
}

/// No sound model runs at idle. Analyze two isolated clips and their pair only
/// after two transients, using copied samples from the existing microphone stream.
@MainActor public final class SoundGestureActivation: SoundActivationInput {
    public var onActivate: ((SoundGestureDetection) -> Void)?
    public var onDiagnostics: ((SoundGestureDiagnostics) -> Void)?
    public var onError: ((any Error) -> Void)?
    public var isEnabled: Bool { !options.gestures.isEmpty }
    private let classifier: any SoundClipClassifying
    private var options = SoundActivationOptions()
    private var detector = SoundGestureDetector()
    private var listening = false
    private var epoch = UUID()
    private var analysis: Task<Void, Never>?
    private var attempts = 0, claps = 0, snaps = 0
    public init(classifier: any SoundClipClassifying = BuiltinSoundClassifier()) { self.classifier = classifier }
    public func configure(_ value: SoundActivationOptions) async throws {
        suspend()
        if !value.gestures.isEmpty { try await classifier.prepare(); try Task.checkCancellation() }
        options = value; attempts = 0; claps = 0; snaps = 0
        report("Warte auf zwei Klatscher oder Schnipser.")
    }
    public func resume() {
        suspend(); listening = isEnabled
        detector = SoundGestureDetector(minimumRMS: options.minimumRMS)
    }
    public func accept(_ samples: [Float]) {
        guard listening, isEnabled else { return }
        guard let candidate = detector.accept(samples, suppressed: analysis != nil) else { return }
        attempts += 1; report("Zwei Impulse · Geräuschtyp wird lokal geprüft.")
        let token = epoch, options = options
        analysis = Task { [weak self, classifier] in
            do {
                let first = try await classifier.classify(candidate.isolatedImpulse(0))
                let second = try await classifier.classify(candidate.isolatedImpulse(1))
                try Task.checkCancellation()
                var pairSamples = candidate.samples
                if pairSamples.count < 8_000 { pairSamples += Array(repeating: 0, count: 8_000 - pairSamples.count) }
                let pair = try await classifier.classify(pairSamples)
                try Task.checkCancellation()
                guard let self, self.epoch == token, self.listening else { return }
                self.analysis = nil
                let score = SoundGesture.allCases.map { gesture in
                    pair.scores[gesture.rawValue] ?? 0
                }.max() ?? 0
                guard let gesture = SoundGestureVerifier.identify([first, second], pair: pair, enabled: options.gestures, confidence: options.confidence) else {
                    self.report("Ignoriert: zwei passende Klatscher/Schnipser nicht sicher erkannt.", confidence: score); return
                }
                if gesture == .clap { self.claps += 1 } else { self.snaps += 1 }
                self.report(gesture == .clap ? "Doppeltklatschen erkannt." : "Doppelschnipsen erkannt.", confidence: score)
                if !options.testOnly { self.onActivate?(SoundGestureDetection(gesture: gesture, commandStartSample: candidate.commandStartSample)) }
            } catch is CancellationError {}
            catch {
                guard let self, self.epoch == token else { return }
                self.analysis = nil; self.onError?(error)
            }
        }
    }
    private func report(_ message: String, confidence: Double = 0) {
        onDiagnostics?(SoundGestureDiagnostics(attempts: attempts, claps: claps, snaps: snaps, message: message, confidence: confidence))
    }
    public func suspend() { listening = false; epoch = UUID(); analysis?.cancel(); analysis = nil }
    public func stop() { suspend(); options = SoundActivationOptions() }
}
