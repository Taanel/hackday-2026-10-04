import Foundation

/// Streaming chassis impulse detector. Times are monotonic seconds. No timers,
/// keystroke contents, recordings, network calls or model inference are needed.
public struct DoubleTapDetector: Sendable {
    public var threshold: Double
    public private(set) var acceptedTaps = 0
    public private(set) var rejectedPulses = 0
    public private(set) var lastStrength = 0.0
    private var baseline: (Double, Double, Double)?
    private var lastTime: Double?
    private var warmUntil = 0.0
    private var noise = 0.002
    private var pulseStart: Double?
    private var pulsePeak = 0.0
    private var pulseBlocked = false
    private var lastTap = -Double.infinity
    private var firstTap: Double?
    private var secondTap: Double?
    private var cooldownUntil = 0.0

    public init(threshold: Double = 0.12) { self.threshold = threshold }

    public mutating func reset() {
        let value = threshold
        self = DoubleTapDetector(threshold: value)
    }

    public mutating func accept(time: Double, x: Double, y: Double, z: Double,
                                suppressed: Bool = false) -> Bool {
        guard [time, x, y, z].allSatisfy(\.isFinite) else { reset(); return false }
        guard let previous = lastTime, let b = baseline, time > previous, time - previous < 0.1 else {
            reset(); baseline = (x, y, z); lastTime = time; warmUntil = time + 0.6
            return false
        }
        let dt = time - previous
        lastTime = time
        let blend = 1 - exp(-dt / 0.15)
        let dx = x - b.0, dy = y - b.1, dz = z - b.2
        let strength = sqrt(dx * dx + dy * dy + dz * dz)
        baseline = (b.0 + blend * dx, b.1 + blend * dy, b.2 + blend * dz)
        let limit = max(min(0.4, max(0.04, threshold)), noise * 7)
        // Clipping avoids teaching the noise floor that deliberate taps are noise.
        noise += min(1, dt / 2) * (min(strength, limit * 0.3) - noise)
        if suppressed || time < warmUntil || time < cooldownUntil {
            firstTap = nil; secondTap = nil
            if pulseStart != nil { pulseBlocked = true }
        }
        if strength >= limit {
            if pulseStart == nil { pulseStart = time; pulsePeak = 0; pulseBlocked = suppressed || time < warmUntil || time < cooldownUntil }
            pulsePeak = max(pulsePeak, strength)
        } else if strength < limit * 0.45, let start = pulseStart {
            let duration = time - start
            lastStrength = pulsePeak
            // A movement or long ringing signal is not a short chassis tap.
            if !pulseBlocked, duration <= 0.09, pulsePeak < 1.5, start - lastTap >= 0.10 {
                acceptedTaps += 1; lastTap = start
                if secondTap != nil { firstTap = nil; secondTap = nil; cooldownUntil = time + 0.8 }
                else if let first = firstTap, (0.12...0.42).contains(start - first) { secondTap = time }
                else { firstTap = start }
            } else { rejectedPulses += 1; firstTap = nil; secondTap = nil }
            pulseStart = nil; pulsePeak = 0; pulseBlocked = false
        }
        // Wait briefly for late keyboard events / another impact before dispatch.
        if let second = secondTap, pulseStart == nil, time - second >= 0.18, !suppressed {
            firstTap = nil; secondTap = nil; cooldownUntil = time + 1.2
            return true
        }
        if let first = firstTap, secondTap == nil, time - first > 0.42 { firstTap = nil }
        return false
    }
}
