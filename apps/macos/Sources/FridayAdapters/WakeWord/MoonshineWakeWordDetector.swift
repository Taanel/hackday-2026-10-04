import Foundation

public struct WakeDetection: Decodable, Sendable {
    public let type: String
    public let text: String?
    public let startSample: Int?
    public let audioSamples: Int?
    public let generation: Int?
    public let error: String?
}

public actor MoonshineWakeWordDetector {
    public let worker: JSONLineProcess
    public init(worker: JSONLineProcess) { self.worker = worker }
    public var events: AsyncStream<Data> { worker.events }
    public func start() async throws { _ = try await worker.start() }
    public func feed(_ samples: [Float]) async throws {
        let data = samples.withUnsafeBytes { Data($0) }
        try await worker.send(JSONEncoder().encode(AudioMessage(pcm: data.base64EncodedString())))
    }
    private struct AudioMessage: Encodable { let op = "audio"; let pcm: String }
    public func pause() async throws {
        guard await worker.isReady else { return }
        struct Control: Encodable { let id: String; let op = "pause" }
        let id = UUID().uuidString
        _ = try await worker.request(JSONEncoder().encode(Control(id: id)), id: id)
    }
    public func resume() async throws -> Int {
        struct Control: Encodable { let id: String; let op = "resume" }
        struct Reply: Decodable { let generation: Int }
        let id = UUID().uuidString
        let data = try await worker.request(JSONEncoder().encode(Control(id: id)), id: id)
        return try JSONDecoder().decode(Reply.self, from: data).generation
    }
    public func stop() async { await worker.stop() }
}
