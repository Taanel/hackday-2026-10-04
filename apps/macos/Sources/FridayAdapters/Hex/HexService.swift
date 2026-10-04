import Foundation

public actor HexService {
    private let worker: JSONLineProcess
    private var endpoint: URL?
    private var token: String?
    public let model = "whisper_large_v3_turbo"

    public init(configuration: RuntimeConfiguration) {
        worker = JSONLineProcess(
            executable: configuration.hexExecutable, arguments: ["service", "--embedded"],
            environment: ["HEX_APPLICATION_SUPPORT_DIR": configuration.hexSupportDirectory]
        )
    }

    private struct Ready: Decodable { let url: String; let token: String; let apiVersion: String }
    private struct Model: Decodable { let id: String; let installed: Bool; let verified: Bool }
    private struct Transcript: Decodable { let transcript: String }

    public func start() async throws {
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
        endpoint = nil; token = nil
        await worker.stop()
    }
}
