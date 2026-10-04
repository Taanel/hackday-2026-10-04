import Foundation
import FridayCore

public struct HexSpeechToText: SpeechToText {
    public let service: HexService
    public init(service: HexService) { self.service = service }
    public func transcribe(audioFile: URL) async throws -> String { try await service.transcribe(audioFile: audioFile) }
}
