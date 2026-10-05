import Foundation
import Testing
import FridayCore
import FridayAdapters
@testable import FridayApp

@MainActor private final class MicrophoneStub: VoiceAudioInput {
    var onFrames: (([Float]) -> Void)?
    var onRecordingEnded: ((URL) -> Void)?
    var onError: ((any Error) -> Void)?
    var isRecording = false
    var totalSamples = 0
    func start() async throws {}
    func stop() { isRecording = false }
    func beginRecording(fromSample: Int?) { isRecording = true }
    func finishRecording() throws -> URL? { isRecording = false; return nil }
    func cancelRecording() { isRecording = false }
    func emit() { totalSamples += 1600; onFrames?(Array(repeating: 0, count: 1600)) }
}

@Test @MainActor func wakeFailureRecoversAndStillAcceptsTheNextWake() async throws {
    let marker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: marker) }
    let code = #"""
import sys,json,pathlib
marker=pathlib.Path(sys.argv[1]); generation=0
print(json.dumps({'type':'ready'}),flush=True)
for line in sys.stdin:
 r=json.loads(line)
 if r['op']=='resume': generation+=1
 if 'id' in r: print(json.dumps({'id':r['id'],'generation':generation}),flush=True)
 elif r['op']=='audio':
  if not marker.exists():
   marker.write_text('failed'); print(json.dumps({'type':'error','generation':generation,'error':'Wake failed once'})+'\n'+json.dumps({'type':'wake','generation':generation,'startSample':0}),flush=True)
  else: print(json.dumps({'type':'wake','generation':generation,'startSample':0}),flush=True)
"""#
    let worker = JSONLineProcess(executable: "/usr/bin/python3", arguments: ["-u", "-c", code, marker.path])
    let audio = MicrophoneStub()
    let voice = VoiceController(wake: MoonshineWakeWordDetector(worker: worker), audio: audio)
    var errors = 0, recoveries = 0, listens = 0
    voice.onError = { _ in errors += 1 }
    voice.onWakeRecovery = { recoveries += 1 }
    voice.onPhase = { if $0 == .listening { listens += 1 } }
    try await voice.setEnabled(true)
    audio.emit()
    for _ in 0..<200 where listens < 2 { try await Task.sleep(for: .milliseconds(10)) }
    #expect(recoveries == 1)
    #expect(listens == 2)
    #expect(errors == 0)
    #expect(!audio.isRecording)
    audio.emit()
    for _ in 0..<100 where !audio.isRecording { try await Task.sleep(for: .milliseconds(10)) }
    #expect(audio.isRecording)
    await voice.shutdown()
}

@Test @MainActor func followUpSilenceReturnsToWakeAndCancelCannotReopenTheMicrophone() async throws {
    let audio=MicrophoneStub()
    let worker=JSONLineProcess(executable:"/nonexistent",arguments:[])
    let voice=VoiceController(wake:MoonshineWakeWordDetector(worker:worker),audio:audio)
    var expirations=0
    voice.onFollowUpTimeout={expirations+=1}
    try await voice.followUpRecording(timeout:.milliseconds(30))
    #expect(audio.isRecording)
    try await Task.sleep(for:.milliseconds(60))
    #expect(!audio.isRecording); #expect(expirations == 1)
    try await voice.followUpRecording(timeout:.milliseconds(30))
    await voice.cancel()
    try await Task.sleep(for:.milliseconds(60))
    #expect(!audio.isRecording); #expect(expirations == 1)
    await voice.shutdown()
}
