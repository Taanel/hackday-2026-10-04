import Foundation
import Testing
@testable import FridayAdapters

private func soundPCM(_ times: [Double], length: Double = 2, duration: Double = 0.015) -> [Float] {
    (0..<Int(length * 16_000)).map { n in
        let t = Double(n) / 16_000
        return times.contains { ($0..<($0 + duration)).contains(t) } ? (n % 2 == 0 ? 0.3 : -0.3) : 0
    }
}

private func soundCandidates(_ pcm: [Float], chunk: Int = 1365, suppressed: Bool = false) -> [SoundGestureCandidate] {
    var detector = SoundGestureDetector()
    var results: [SoundGestureCandidate] = []
    for start in stride(from: 0, to: pcm.count, by: chunk) {
        if let value = detector.accept(Array(pcm[start..<min(pcm.count, start + chunk)]), suppressed: suppressed) { results.append(value) }
    }
    return results
}

@Test(arguments: [160, 1365]) func soundGestureRequiresTwoSeparatedPCMImpulses(chunk: Int) {
    #expect(soundCandidates(soundPCM([0.5, 0.8]), chunk: chunk).count == 1)
    #expect(soundCandidates(soundPCM([0.5]), chunk: chunk).isEmpty)
    #expect(soundCandidates(soundPCM([0.5, 0.56]), chunk: chunk).isEmpty)
    #expect(soundCandidates(soundPCM([0.5, 1.5]), chunk: chunk).isEmpty)
}

@Test func soundGestureRejectsSustainedNoiseSuppressionAndThreeImpulses() {
    #expect(soundCandidates(soundPCM([0.5, 1.1], duration: 0.3)).isEmpty)
    #expect(soundCandidates(soundPCM([0.5, 0.8]), suppressed: true).isEmpty)
    #expect(soundCandidates(soundPCM([0.5, 0.8, 0.95])).isEmpty)
    #expect(soundCandidates(Array(repeating: 0.0001, count: 32_000)).isEmpty)
}

@Test func soundGestureAcceptsShortOnsetsWithAudibleReverberation() {
    var pcm = [Float](repeating: 0, count: 32_000)
    for start in [8_000, 14_400] {
        for n in 0..<4_000 {
            let strength = Float(0.3 * exp(-Double(n) / 500))
            pcm[start+n] = n % 2 == 0 ? strength : -strength
        }
    }
    #expect(soundCandidates(pcm).count == 1)
}

@Test(arguments: [0.85, 0.92], [0.14, 0.4]) func soundGestureKeepsPairWhenCommandSpeechStartsImmediately(speechStart: Double, duration: Double) throws {
    var pcm = soundPCM([0.5, 0.8])
    let start = Int(speechStart * 16_000)
    for n in start..<start + Int(duration * 16_000) { pcm[n] = n % 2 == 0 ? 0.2 : -0.2 }
    let pair = try #require(soundCandidates(pcm).first)
    #expect(pair.commandStartSample < start)
    // The classifier must not confuse command speech with the gesture itself.
    #expect(pair.startSample + pair.samples.count <= start)
}

@Test func soundGestureIsolatedClipsNeverContainTheOtherImpulse() throws {
    let candidate = try #require(soundCandidates(soundPCM([0.5, 0.7])).first)
    for index in 0..<2 {
        let clip = candidate.isolatedImpulse(index)
        #expect(clip.count == 8_000)
        // 15 ms per impact; isolation must not include the other impact.
        #expect(clip.filter { abs($0) > 0.1 }.count <= 241)
        #expect(clip.filter { abs($0) > 0.1 }.count >= 230)
    }
    #expect(candidate.commandStartSample > candidate.impulses[1])
}

@Test(arguments: [SoundGesture.clap, .snap]) func soundGestureNeedsBothIndependentClassifications(gesture: SoundGesture) {
    let good = SoundClassification(scores: [gesture.rawValue: 0.9, "speech": 0.02])
    #expect(SoundGestureVerifier.identify([good, good], enabled: [gesture]) == gesture)
    #expect(SoundGestureVerifier.identify([good], enabled: [gesture]) == nil)
    #expect(SoundGestureVerifier.identify([good, good], enabled: []) == nil)
    let keyboard = SoundClassification(scores: ["typing_computer_keyboard": 0.9, gesture.rawValue: 0.05])
    #expect(SoundGestureVerifier.identify([good, keyboard], enabled: [gesture]) == nil)
}

@Test func soundGestureRejectsMixedGesturesSpeechAndLowConfidence() {
    let clap = SoundClassification(scores: ["clapping": 0.9])
    let snap = SoundClassification(scores: ["finger_snapping": 0.9])
    #expect(SoundGestureVerifier.identify([clap, snap], enabled: [.clap, .snap]) == nil)
    let speech = SoundClassification(scores: ["clapping": 0.7, "speech": 0.69])
    #expect(SoundGestureVerifier.identify([speech, speech], enabled: [.clap]) == nil)
    let weak = SoundClassification(scores: ["finger_snapping": 0.4])
    #expect(SoundGestureVerifier.identify([weak, weak], enabled: [.snap]) == nil)
}

@Test func soundGestureUsesJointEvidenceWithoutLettingOneClapHideAKeyboardTap() {
    let joint = SoundClassification(scores: ["clapping": 0.9, "applause": 0.8])
    let shortClap = SoundClassification(scores: ["clapping": 0.33, "applause": 0.1])
    #expect(SoundGestureVerifier.identify([shortClap, shortClap], pair: joint, enabled: [.clap]) == .clap)
    let keyboard = SoundClassification(scores: ["typing": 0.9, "clapping": 0.04])
    #expect(SoundGestureVerifier.identify([shortClap, keyboard], pair: joint, enabled: [.clap]) == nil)
    let weakJoint = SoundClassification(scores: ["clapping": 0.4])
    #expect(SoundGestureVerifier.identify([shortClap, shortClap], pair: weakJoint, enabled: [.clap]) == nil)
}

private actor SoundClassifierStub: SoundClipClassifying {
    var calls = 0
    let delay: Duration
    init(delay: Duration = .zero) { self.delay = delay }
    func prepare() {}
    func classify(_ samples: [Float]) async throws -> SoundClassification {
        calls += 1
        if delay != .zero { try? await Task.sleep(for: delay) }
        return SoundClassification(scores: ["clapping": 0.9, "speech": 0.01])
    }
}

@Test @MainActor func soundActivationTestModeCountsWithoutStartingCommandsOrIdleInference() async throws {
    let classifier = SoundClassifierStub()
    let activation = SoundGestureActivation(classifier: classifier)
    var starts = 0, claps = 0
    activation.onActivate = { _ in starts += 1 }
    activation.onDiagnostics = { claps = $0.claps }
    try await activation.configure(SoundActivationOptions(gestures: [.clap], testOnly: true))
    activation.resume()
    activation.accept(Array(repeating: 0, count: 16_000))
    #expect(await classifier.calls == 0)
    activation.accept(soundPCM([0.5, 0.8]))
    for _ in 0..<100 where claps == 0 { try await Task.sleep(for: .milliseconds(5)) }
    #expect(claps == 1)
    #expect(starts == 0)
    #expect(await classifier.calls == 3)
    activation.stop()
}

@Test @MainActor func soundActivationDropsClassificationAfterSuspendAndRearm() async throws {
    let activation = SoundGestureActivation(classifier: SoundClassifierStub(delay: .milliseconds(50)))
    var starts = 0
    activation.onActivate = { _ in starts += 1 }
    try await activation.configure(SoundActivationOptions(gestures: [.clap]))
    activation.resume(); activation.accept(soundPCM([0.5, 0.8]))
    await Task.yield()
    activation.suspend(); activation.resume()
    try await Task.sleep(for: .milliseconds(180))
    #expect(starts == 0)
    activation.stop()
}
