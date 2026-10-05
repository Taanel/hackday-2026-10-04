import Testing
import Foundation
@testable import FridayAdapters

private func replay(_ impacts: [(Double, Double, Double)], suppressed: ClosedRange<Double>? = nil,
                    movement: Bool = false, threshold: Double? = nil) -> Int {
    var detector = threshold.map { DoubleTapDetector(threshold: $0) } ?? DoubleTapDetector()
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

@Test func chassisGentleFingerTapsCanUseALowerThreshold() {
    #expect(replay([(1, 0.025, 0.015), (1.24, 0.025, 0.015)], threshold: 0.015) == 1)
    #expect(replay([(1, 0.06, 0.015), (1.24, 0.06, 0.015)]) == 1)
}

@Test(arguments: [0.005, 0.015, 0.03])
func chassisLowThresholdStillRejectsNoiseMovementAndTypedTaps(threshold: Double) {
    #expect(replay([(1, 0.002, 0.015), (1.24, 0.002, 0.015)], threshold: threshold) == 0)
    #expect(replay([], movement: true, threshold: threshold) == 0)
    #expect(replay([(1, 0.05, 0.015), (1.24, 0.05, 0.015)],
                   suppressed: 0.9...1.5, threshold: threshold) == 0)
}

@Test func chassisShortAftershocksDoNotEraseTheFirstFingerTap() {
    let ringing: [(Double, Double, Double)] = [
        (1, 0.2, 0.015), (1.045, -0.14, 0.01), (1.075, 0.09, 0.01),
        (1.24, 0.2, 0.015), (1.285, -0.14, 0.01), (1.315, 0.09, 0.01)
    ]
    #expect(replay(ringing, threshold: 0.04) == 1)
    #expect(replay(Array(ringing.prefix(3)), threshold: 0.04) == 0)
}

@Test func chassisShortTapDoesNotBecomeLongMovementThroughGravityBaseline() {
    #expect(replay([(1, 0.3, 0.03), (1.24, 0.3, 0.03)], threshold: 0.04) == 1)
}

@Test func chassisSecondTapAtEdgeOfWindowCanFinishBeforeDispatch() {
    #expect(replay([(1, 0.1, 0.015), (1.41, 0.1, 0.03)], threshold: 0.04) == 1)
}

@Test func chassisDiagnosticsDistinguishTypingFromMovementAndAftershock() {
    var blocked = DoubleTapDetector()
    var movement = DoubleTapDetector()
    var ringing = DoubleTapDetector()
    for n in 0..<283 {
        let t = Double(n) / 200
        _ = blocked.accept(time: t, x: 0, y: 0, z: (1..<1.015).contains(t) ? 1.1 : 1,
                           suppressed: (0.9...1.1).contains(t))
        _ = movement.accept(time: t, x: 0, y: 0, z: (1..<1.2).contains(t) ? 1.1 : 1)
        let impact = (1..<1.015).contains(t) ? 0.1 : (1.05..<1.06).contains(t) ? -0.08 : 0
        _ = ringing.accept(time: t, x: 0, y: 0, z: 1 + impact)
    }
    #expect(blocked.lastEvent == .inputBlocked)
    #expect(movement.lastEvent == .longMovement)
    #expect(ringing.lastEvent == .aftershock)
    #expect(ringing.acceptedTaps == 1)
    #expect(ringing.ignoredAftershocks == 1)
    #expect(ringing.rejectedPulses == 0)
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
    #expect(replay([(1, 0.004, 0.015), (1.22, 0.004, 0.015)]) == 0)
    #expect(replay([(1, 0.03, 0.015), (1.22, 0.03, 0.015)], threshold: 0.12) == 0)
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
