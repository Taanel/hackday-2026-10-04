import Foundation

/// Endpoint policy for 16 kHz command PCM. Count buffered wake/command audio
/// toward the minimum duration instead of waiting again after wake detection.
struct CommandEndpoint {
    var hasSpeech: Bool { heardSpeech }
    private var elapsed: Int
    private var silence = 0
    private var heardSpeech: Bool
    private let silenceSamples: Int
    private let speechThreshold: Double

    init(preRollSamples: Int = 0, fast: Bool = false, backgroundRMS: Double = 0.0005) {
        elapsed = max(0, preRollSamples)
        heardSpeech = preRollSamples > 0
        silenceSamples = fast ? 8_000 : 12_000
        let floor = backgroundRMS.isFinite ? max(0, backgroundRMS) : 0.0005
        speechThreshold = min(0.009, max(0.0008, floor * 4))
    }

    mutating func accept(_ samples: [Float]) -> Bool {
        guard !samples.isEmpty else { return false }
        elapsed += samples.count
        let rms = sqrt(samples.reduce(0) { $0 + Double($1 * $1) } / Double(samples.count))
        if rms > speechThreshold { heardSpeech = true; silence = 0 }
        else { silence += samples.count }
        return (elapsed >= 12_800 && silence >= silenceSamples && heardSpeech) || elapsed >= 480_000
    }
}
