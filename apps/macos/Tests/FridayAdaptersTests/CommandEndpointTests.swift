import Testing
@testable import FridayAdapters

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
