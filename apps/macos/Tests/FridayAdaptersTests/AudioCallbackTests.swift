import AVFoundation
import Dispatch
import Testing
@testable import FridayAdapters

/// The native audio tap and its buffer are deliberately handed to one serial
/// background callback, exactly as AVAudioEngine invokes them.
private struct AudioTapInvocation: @unchecked Sendable {
    let tap: @convention(block) (AVAudioPCMBuffer, AVAudioTime) -> Void
    let buffer: AVAudioPCMBuffer
    func call() {
        tap(buffer, AVAudioTime(sampleTime: 0, atRate: buffer.format.sampleRate))
    }
}

@MainActor @Test func microphoneTapCanRunOnAnAudioThread() async throws {
    let audio = AudioInput()
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800)!
    buffer.frameLength = 4_800
    buffer.floatChannelData![0].initialize(repeating: 0, count: 4_800)
    let invocation = AudioTapInvocation(tap: try audio.makeTap(format: format), buffer: buffer)
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
        DispatchQueue(label: "Friday.AudioCallbackRegression").async {
            invocation.call()
            done.resume()
        }
    }
    // The test never opens the microphone. Its callback must return normally
    // rather than trigger Swift's MainActor executor assertion.
    #expect(audio.totalSamples == 0)
}
