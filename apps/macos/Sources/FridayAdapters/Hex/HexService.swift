import Foundation

public actor HexService {
    private let worker: JSONLineProcess
    private var endpoint: URL?
    private var token: String?
    private var prepared = false
    public let model = "whisper_large_v3_turbo"

    public init(configuration: RuntimeConfiguration) {
        worker = JSONLineProcess(
            executable: configuration.hexExecutable, arguments: ["service", "--embedded"],
            environment: ["HEX_APPLICATION_SUPPORT_DIR": configuration.hexSupportDirectory]
        )
    }

    init(worker: JSONLineProcess) { self.worker = worker }

    private struct Ready: Decodable { let url: String; let token: String; let apiVersion: String }
    private struct Model: Decodable { let id: String; let installed: Bool; let verified: Bool }
    private struct Transcript: Decodable { let transcript: String }

    public func start() async throws {
        if prepared, await worker.isReady { return }
        let ready = try JSONDecoder().decode(Ready.self, from: await worker.start())
        guard ready.apiVersion == "2", let url = URL(string: ready.url), url.host == "127.0.0.1", url.scheme == "http" else {
            await stop()
            throw AdapterError.invalidResponse("Hex meldet kein kompatibles lokales API-2-Protokoll.")
        }
        endpoint = url; token = ready.token
        let request = try makeRequest(path: "models", query: [URLQueryItem(name: "language", value: "de")])
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response)
        let models = try JSONDecoder().decode([Model].self, from: data)
        guard models.contains(where: { $0.id == model && $0.installed && $0.verified }) else {
            throw AdapterError.unavailable("Das deutsche Hex-Modell fehlt. Bitte das lokale Setup abschließen.")
        }
        // The models endpoint only verifies the file. Prepare loads and warms
        // Whisper before the microphone UI becomes ready, once per service.
        var warmup = try makeRequest(path: "models/\(model)/prepare", query: [URLQueryItem(name: "language", value: "de")])
        warmup.httpMethod = "POST"
        warmup.timeoutInterval = 120
        warmup.setValue("0", forHTTPHeaderField: "Content-Length")
        let (progress, warmupResponse) = try await URLSession.shared.data(for: warmup)
        try check(warmupResponse)
        struct Event: Decodable { let type: String }
        let events = String(decoding: progress, as: UTF8.self).split(separator: "\n").compactMap { line -> Event? in
            guard line.hasPrefix("data:") else { return nil }
            return try? JSONDecoder().decode(Event.self, from: Data(line.dropFirst(5).utf8))
        }
        guard events.last?.type == "ok" else {
            await stop()
            throw AdapterError.unavailable("Hex konnte das Sprachmodell nicht vorladen. Bitte erneut laden.")
        }
        try Task.checkCancellation()
        prepared = true
    }

    public func transcribe(audioFile: URL) async throws -> String {
        try await start()
        try Task.checkCancellation()
        var request = try makeRequest(path: "transcriptions", query: [
            URLQueryItem(name: "model", value: model), URLQueryItem(name: "language", value: "de")
        ])
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.httpBody = try Data(contentsOf: audioFile)
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.setValue(String(request.httpBody!.count), forHTTPHeaderField: "Content-Length")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            try check(response)
            let transcript = try JSONDecoder().decode(Transcript.self, from: data).transcript
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else { throw AdapterError.unavailable("Ich habe keinen Befehl verstanden. Bitte erneut sprechen.") }
            return transcript
        } catch {
            // URL cancellation alone does not stop native Hex inference.
            await stop()
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw error
        }
    }

    private func makeRequest(path: String, query: [URLQueryItem]) throws -> URLRequest {
        guard let endpoint, let token else { throw AdapterError.unavailable("Hex ist noch nicht bereit.") }
        var components = URLComponents(url: endpoint.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AdapterError.unavailable("Hex hat die Anfrage abgelehnt. Setup und Modell prüfen.")
        }
    }

    public func stop() async {
        prepared = false
        endpoint = nil; token = nil
        await worker.stop()
    }
}
