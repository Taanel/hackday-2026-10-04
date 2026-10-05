import Testing
import Foundation
@testable import FridayAdapters

private func replay(_ impacts: [(Double, Double, Double)], suppressed: ClosedRange<Double>? = nil,
                    movement: Bool = false) -> Int {
    var detector = DoubleTapDetector()
    var triggers = 0
    for n in 0..<900 {
        let t = Double(n) / 200
        let pulse = impacts.reduce(0.0) { value, impact in
            value + ((impact.0..<(impact.0 + impact.2)).contains(t) ? impact.1 : 0)
        }
        let slow = movement ? 0.25 * sin(t * 1.5) : 0
        if detector.accept(time: t, x: 0, y: 0, z: 1 + pulse + slow, suppressed: suppressed?.contains(t) ?? false) { triggers += 1 }
    }
    return triggers
}

@Test func chassisDoubleTapRequiresTwoDistinctShortImpulses() {
    #expect(replay([(1, 0.25, 0.015), (1.22, 0.25, 0.015)]) == 1)
    #expect(replay([(1, 0.25, 0.015)]) == 0)
    #expect(replay([(1, 0.25, 0.015), (1.7, 0.25, 0.015)]) == 0)
    #expect(replay([(1, 0.25, 0.015), (1.06, 0.25, 0.015)]) == 0)
}

@Test func chassisTypingGateRejectsBothImmediateAndLateKeyboardEvents() {
    let taps: [(Double, Double, Double)] = [(1, 0.3, 0.015), (1.22, 0.3, 0.015)]
    #expect(replay(taps, suppressed: 0.9...1.5) == 0)
    #expect(replay(taps, suppressed: 1.28...1.4) == 0)
    #expect(replay([(1, 0.3, 0.015), (1.22, 0.3, 0.015), (2, 0.3, 0.015)], suppressed: 1.1...1.18) == 0)
}

@Test func chassisMovementRingingAndTinyVibrationsDoNotActivate() {
    #expect(replay([], movement: true) == 0)
    #expect(replay([(1, 0.3, 0.25), (1.4, 0.3, 0.25)]) == 0)
    #expect(replay([(1, 0.03, 0.015), (1.22, 0.03, 0.015)]) == 0)
    #expect(replay([(1, 2, 0.015), (1.22, 2, 0.015)]) == 0)
    #expect(replay([(1, 0.25, 0.015), (1.16, 0.25, 0.015), (1.32, 0.25, 0.015)]) == 0)
}

@Test func chassisCooldownCannotStartMultipleRecordingsFromOneBurst() {
    #expect(replay([(1, 0.25, 0.015), (1.22, 0.25, 0.015), (1.8, 0.25, 0.015), (2.02, 0.25, 0.015)]) == 1)
}

@Test func chassisSensorGapsAndInvalidValuesDiscardPendingGesture() {
    var detector = DoubleTapDetector()
    for n in 0..<260 {
        let t = Double(n) / 200
        _ = detector.accept(time: t, x: 0, y: 0, z: (1..<1.015).contains(t) ? 1.25 : 1)
    }
    let afterGap = detector.accept(time: 2, x: 0, y: 0, z: 1.25)
    let invalid = detector.accept(time: 2.005, x: .nan, y: 0, z: 1)
    let afterInvalid = detector.accept(time: 2.01, x: 0, y: 0, z: 1)
    #expect(!afterGap); #expect(!invalid); #expect(!afterInvalid)
}
