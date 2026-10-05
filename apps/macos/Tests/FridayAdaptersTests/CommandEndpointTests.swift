import Testing
@testable import FridayAdapters

@Test func quietSpeechInAQuietRoomDoesNotEndTheCommandEarly() {
    var endpoint = CommandEndpoint(preRollSamples: 16000, fast: true)
    let quietVoice = [Float](repeating: 0.003, count: 4000)
    for _ in 0..<8 { let ended = endpoint.accept(quietVoice); #expect(!ended) }
    let firstPause = endpoint.accept([Float](repeating: 0.0002, count: 4000)); #expect(!firstPause)
    let completed = endpoint.accept([Float](repeating: 0.0002, count: 4000)); #expect(completed)
}

@Test func backgroundNoiseDoesNotKeepACommandOpenAfterSpeech() {
    var endpoint = CommandEndpoint(preRollSamples: 16000, fast: true, backgroundRMS: 0.002)
    let speech = endpoint.accept([Float](repeating: 0.015, count: 8000)); #expect(!speech)
    let completed = endpoint.accept([Float](repeating: 0.006, count: 8000)); #expect(completed)
}

@Test func fastEndpointUses500MillisecondsWithoutEndingSilenceOnlyCapture() {
    var fast = CommandEndpoint(preRollSamples: 32000, fast: true)
    let before = fast.accept(Array(repeating: 0, count: 7999))
    let end = fast.accept([0])
    #expect(!before); #expect(end)
    var silence = CommandEndpoint(fast: true)
    let quiet = silence.accept(Array(repeating: 0, count: 16000))
    #expect(!quiet)
}

@Test func commandUsesCapturedWakeAudioWithoutWaitingAnotherMinimumDuration() {
    var endpoint = CommandEndpoint(preRollSamples: 32_000)
    let shortPause = endpoint.accept(Array(repeating: 0, count: 9_600))
    let end = endpoint.accept(Array(repeating: 0, count: 2_400))
    #expect(!shortPause) // A 600 ms thinking pause stays open.
    #expect(end) // End after 750 ms, not another 1.25 s.
}

@Test func aPauseInsideACompoundCommandDoesNotCutOffTheSecondPart() {
    var endpoint = CommandEndpoint()
    let blocks: [[Float]] = [Array(repeating: 0.1, count: 8_000), Array(repeating: 0, count: 8_000),
                            Array(repeating: 0.1, count: 12_000), Array(repeating: 0, count: 11_999), [0]]
    let endings = blocks.map { endpoint.accept($0) }
    #expect(endings == [false, false, false, false, true])
}

@Test func silenceAloneCannotFinishACommandBeforeTheRecordingLimit() {
    var endpoint = CommandEndpoint()
    let shortSilence = endpoint.accept(Array(repeating: 0, count: 32_000))
    let recordingLimit = endpoint.accept(Array(repeating: 0, count: 448_000))
    #expect(!shortSilence)
    #expect(recordingLimit)
}
