import Foundation
import Testing
import FridayCore
@testable import FridayAdapters

@MainActor private final class LocalSpeechProbe: SpeechOutput {
    var texts: [String] = []
    var failure: (any Error)?
    func speak(_ text: String) async throws { texts.append(text); if let failure { throw failure } }
    func stop() {}
}

@Test @MainActor func localSpeechNeverConsumesCloudQuotaByDefault() async throws {
    let local = LocalSpeechProbe(), cloud = LocalSpeechProbe()
    let speech = AdaptiveSpeechOutput(local: local, cloud: cloud)
    try await speech.speak("Hallo")
    #expect(local.texts == ["Hallo"]); #expect(cloud.texts.isEmpty)
}

@Test @MainActor func unavailableCloudVoiceFallsBackLocallyForTheSession() async throws {
    let local = LocalSpeechProbe(), cloud = LocalSpeechProbe()
    cloud.failure = AdapterError.unavailable("Sprachkontingent erreicht")
    let speech = AdaptiveSpeechOutput(local: local, cloud: cloud); speech.preferLocal = false
    try await speech.speak("Erste Antwort"); try await speech.speak("Zweite Antwort")
    #expect(cloud.texts == ["Erste Antwort"])
    #expect(local.texts == ["Erste Antwort", "Zweite Antwort"])
}

@Test @MainActor func cancellingCloudSpeechDoesNotStartALocalReply() async {
    let local = LocalSpeechProbe(), cloud = LocalSpeechProbe(); cloud.failure = CancellationError()
    let speech = AdaptiveSpeechOutput(local: local, cloud: cloud); speech.preferLocal = false
    await #expect(throws: CancellationError.self) { try await speech.speak("Hallo") }
    #expect(local.texts.isEmpty)
}

@Test @MainActor func localSpeechChunksKeepAllWordsAndRespectTheTransportBound() throws {
    let text = String(repeating: "Das ist ein längerer deutscher Satz. ", count: 80)
    let chunks = try LocalPiperSpeechOutput.chunks(text)
    #expect(chunks.allSatisfy { !$0.isEmpty && $0.count <= 300 })
    #expect(chunks.joined(separator: " ") == text.trimmingCharacters(in: .whitespaces))
    #expect(throws: AdapterError.self) { try LocalPiperSpeechOutput.chunks(String(repeating: "a", count: 301)) }
}
