import Foundation

public enum SoundGesture: String, Sendable, CaseIterable {
    case clap = "clapping"
    case snap = "finger_snapping"
}

public struct SoundGestureCandidate: Sendable {
    public let samples: [Float]
    public let startSample: Int
    public let impulses: [Int]
    public let commandStartSample: Int

    public init(samples: [Float], startSample: Int, impulses: [Int], commandStartSample: Int) {
        self.samples = samples; self.startSample = startSample
        self.impulses = impulses; self.commandStartSample = commandStartSample
    }

    public func isolatedImpulse(_ index: Int) -> [Float] {
        guard impulses.count == 2, (0..<2).contains(index) else { return [] }
        let center = impulses[index]
        let midpoint = (impulses[0] + impulses[1]) / 2
        let lower = max(startSample, center - 2_400, index == 1 ? midpoint : startSample)
        let upper = min(startSample + samples.count, center + 2_400, index == 0 ? midpoint : startSample + samples.count)
        var clip = [Float](repeating: 0, count: 8_000)
        guard lower < upper else { return clip }
        for frame in lower..<upper {
            let target = 4_000 + frame - center
            if clip.indices.contains(target) { clip[target] = samples[frame - startSample] }
        }
        return clip
    }
}

public struct SoundGestureDetector: Sendable {
    public var minimumRMS: Double
    public private(set) var totalSamples = 0
    public private(set) var noiseRMS = 0.0003
    private var ring: [Float] = []
    private var blockSamples = 0
    private var blockEnergy = 0.0
    private var blockPeak = 0.0
    private var processed = 0
    private var pulseStart: Int?
    private var pulseCenter = 0
    private var pulsePeak = 0.0
    private var pulseRMS = 0.0
    private var previousRMS = 0.0
    private var lastLoudSample = 0
    private var quietBlocks = 0
    private var first: Int?
    private var second: Int?
    private var secondEnd = 0
    private var trailingOnset: Int?
    private var lastImpulse = -16_000
    private var cooldownUntil = 0
    public init(minimumRMS: Double = 0.004) { self.minimumRMS = minimumRMS }
    public mutating func accept(_ samples: [Float], suppressed: Bool = false) -> SoundGestureCandidate? {
        guard !samples.isEmpty else { return nil }
        ring.append(contentsOf: samples); totalSamples += samples.count
        if ring.count > 32_000 { ring.removeFirst(ring.count - 32_000) }
        var result: SoundGestureCandidate?
        for value in samples {
            processed += 1; blockSamples += 1
            let sample = value.isFinite ? Double(value) : 0
            blockEnergy += sample * sample; blockPeak = max(blockPeak, abs(sample))
            guard blockSamples == 160 else { continue }
            let rms = sqrt(blockEnergy / 160)
            let peak = blockPeak
            let rising = rms >= max(0.001, previousRMS * 2.5)
            previousRMS = rms
            blockSamples = 0; blockEnergy = 0; blockPeak = 0
            let limit = max(0.001, minimumRMS, noiseRMS * 6)
            if rms < limit * 0.5 { noiseRMS += 0.01 * (rms - noiseRMS) }
            if suppressed || processed < 4_000 || processed < cooldownUntil {
                clearGesture(); continue
            }
            // A clap may reverberate above the room's noise floor. Track its
            // sharp onset and relative decay instead of requiring total silence.
            let pulseLimit = pulseStart == nil ? limit : max(limit, pulseRMS * 0.35)
            if rms >= pulseLimit, peak >= max(0.012, limit * 2), pulseStart != nil || rising {
                if pulseStart == nil {
                    pulseStart = processed - 160; pulsePeak = 0; pulseRMS = 0; quietBlocks = 0
                    if second != nil, trailingOnset == nil { trailingOnset = processed - 160 }
                }
                pulseRMS = max(pulseRMS, rms)
                if peak > pulsePeak { pulsePeak = peak; pulseCenter = processed - 80 }
                lastLoudSample = processed; quietBlocks = 0
            } else if pulseStart != nil {
                quietBlocks += 1
                if quietBlocks >= 2, let start = pulseStart {
                    pulseStart = nil; quietBlocks = 0
                    if lastLoudSample - start <= 1_920 {
                        let center = pulseCenter
                        if center - lastImpulse >= 1_920 {
                            lastImpulse = center
                            if second != nil { clearGesture(); cooldownUntil = processed + 8_000 }
                            else if let first, (2_400...12_800).contains(center - first) {
                                second = center; secondEnd = lastLoudSample
                            } else { first = center }
                        }
                    } else if second == nil { clearGesture() }
                }
            }
            let commandSpeech = second != nil && pulseStart.map { processed - $0 > 1_920 } == true
            if let first, let second, pulseStart == nil || commandSpeech, processed - secondEnd >= 3_200 {
                let start = max(totalSamples - ring.count, first - 4_000)
                // Command speech is retained by AudioInput, but excluded from
                // the gesture model. A sustained third onset is speech context;
                // a third short impulse still cancels the pair above.
                let end = min(totalSamples, trailingOnset ?? processed)
                result = SoundGestureCandidate(samples: Array(ring[(start - (totalSamples - ring.count))..<(end - (totalSamples - ring.count))]),
                    startSample: start, impulses: [first, second], commandStartSample: secondEnd + 160)
                clearGesture(); cooldownUntil = processed + 19_200
            } else if let first, second == nil, pulseStart == nil, processed - first > 12_800 { self.first = nil }
        }
        return result
    }

    private mutating func clearGesture() { first = nil; second = nil; trailingOnset = nil; pulseStart = nil; quietBlocks = 0 }
}

public struct SoundClassification: Sendable {
    public let scores: [String: Double]
    public init(scores: [String: Double]) { self.scores = scores }
}

public enum SoundGestureVerifier {
    public static func identify(_ results: [SoundClassification], pair: SoundClassification? = nil, enabled: Set<SoundGesture>,
                                confidence: Double = 0.65) -> SoundGesture? {
        guard results.count == 2 else { return nil }
        let competitors = ["speech", "typing", "typing_computer_keyboard", "typewriter", "tap", "knock"]
        return SoundGesture.allCases.first { gesture in
            if let pair {
                let score = pair.scores[gesture.rawValue] ?? 0
                let rival = (competitors + SoundGesture.allCases.filter { $0 != gesture }.map(\.rawValue))
                    .map { pair.scores[$0] ?? 0 }.max() ?? 0
                guard score.isFinite, score >= confidence, score - rival >= 0.12 else { return false }
            }
            return enabled.contains(gesture) && results.allSatisfy { result in
                let score = result.scores[gesture.rawValue] ?? 0
                let rival = (competitors + SoundGesture.allCases.filter { $0 != gesture }.map(\.rawValue))
                    .map { result.scores[$0] ?? 0 }.max() ?? 0
                // An isolated 150-ms sound plus silence has less context than
                // the whole pair; require supporting evidence independently.
                return score.isFinite && score >= (pair == nil ? confidence : max(0.2, confidence * 0.4)) && score - rival >= 0.12
            }
        }
    }
}
