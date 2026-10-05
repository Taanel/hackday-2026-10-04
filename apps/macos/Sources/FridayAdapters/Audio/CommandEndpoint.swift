import Foundation

/// Endpoint policy for 16 kHz command PCM. Count buffered wake/command audio
/// toward the minimum duration instead of waiting again after wake detection.
struct CommandEndpoint {
    var hasSpeech: Bool { heardSpeech }
    private var elapsed: Int
    private var silence = 0
    private var heardSpeech: Bool
    private let silenceSamples: Int

    init(preRollSamples: Int = 0, fast: Bool = false) {
        elapsed = max(0, preRollSamples)
        heardSpeech = preRollSamples > 0
        silenceSamples = fast ? 8_000 : 12_000
    }

    mutating func accept(_ samples: [Float]) -> Bool {
        guard !samples.isEmpty else { return false }
        elapsed += samples.count
        let rms = sqrt(samples.reduce(0) { $0 + Double($1 * $1) } / Double(samples.count))
        if rms > 0.009 { heardSpeech = true; silence = 0 }
        else { silence += samples.count }
        return (elapsed >= 12_800 && silence >= silenceSamples && heardSpeech) || elapsed >= 480_000
    }
}
