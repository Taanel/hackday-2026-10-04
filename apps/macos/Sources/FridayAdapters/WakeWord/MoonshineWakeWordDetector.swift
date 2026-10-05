import Foundation

public struct WakeDetection: Decodable, Sendable {
    public let type: String
    public let text: String?
    public let startSample: Int?
    public let audioSamples: Int?
    public let generation: Int?
    public let error: String?
    public let transportSession: UUID?
}

public actor MoonshineWakeWordDetector {
    public let worker: JSONLineProcess
    public init(worker: JSONLineProcess) { self.worker = worker }
    public var events: AsyncStream<Data> { worker.events }
    public var sessionID: UUID { get async { await worker.sessionID } }
    public func start() async throws { _ = try await worker.start() }
    public func feed(_ samples: [Float]) async throws {
        // Resampling can overshoot full scale even when microphone PCM is
        // valid. Do not let one loud sample terminate wake recognition.
        for offset in stride(from: 0, to: samples.count, by: 16_000) {
            let block = samples[offset..<min(offset + 16_000, samples.count)]
                .map { $0.isFinite ? min(1, max(-1, $0)) : 0 }
            let data = block.withUnsafeBytes { Data($0) }
            try await worker.send(JSONEncoder().encode(AudioMessage(pcm: data.base64EncodedString())))
        }
    }
    private struct AudioMessage: Encodable { let op = "audio"; let pcm: String }
    public func pause() async throws {
        guard await worker.isReady else { return }
        struct Control: Encodable { let id: String; let op = "pause" }
        let id = UUID().uuidString
        _ = try await worker.request(JSONEncoder().encode(Control(id: id)), id: id)
    }
    public func resume() async throws -> Int {
        struct Control: Encodable { let id: String; let op = "resume"; let allowBare: Bool; let allowPersonal: Bool }
        struct Reply: Decodable { let generation: Int }
        let id = UUID().uuidString
        let data = try await worker.request(JSONEncoder().encode(Control(id: id,
            allowBare: UserDefaults.standard.bool(forKey: "Friday.allowBareWake"),
            allowPersonal: UserDefaults.standard.bool(forKey: "Friday.allowPersonalWake"))), id: id)
        return try JSONDecoder().decode(Reply.self, from: data).generation
    }
    public func enroll(files: [URL]) async throws {
        struct Enrollment: Encodable { let id: String; let op = "enroll"; let paths: [String] }
        let id = UUID().uuidString
        _ = try await worker.request(JSONEncoder().encode(Enrollment(id: id, paths: files.map(\.path))), id: id)
    }
    public func clearProfile() async throws {
        struct Control: Encodable { let id: String; let op = "clear_profile" }
        let id = UUID().uuidString
        _ = try await worker.request(JSONEncoder().encode(Control(id: id)), id: id)
    }
    public func stop() async { await worker.stop() }
}
