import Foundation

public struct RuntimeConfiguration: Codable, Sendable {
    public var pythonExecutable: String
    public var workerDirectory: String
    public var layaModelDirectory: String
    public var wakeModelDirectory: String
    public var hexExecutable: String
    public var hexSupportDirectory: String
    public var ollamaModel: String

    public static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Friday", isDirectory: true)
    }

    public static func load() throws -> Self {
        let url = supportDirectory.appendingPathComponent("runtime.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AdapterError.unavailable("Lokales Setup fehlt. Bitte scripts/setup-local-runtime.sh ausführen.")
        }
        var config = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        if let resources = Bundle.main.resourceURL {
            let bundled = resources.appendingPathComponent("LocalRuntime")
            if FileManager.default.fileExists(atPath: bundled.appendingPathComponent("friday_runtime").path) {
                config.workerDirectory = bundled.path
            }
        }
        for path in [config.pythonExecutable, config.hexExecutable] {
            guard FileManager.default.isExecutableFile(atPath: path) else {
                throw AdapterError.unavailable("Lokale Runtime fehlt: \(URL(fileURLWithPath: path).lastPathComponent). Setup erneut ausführen.")
            }
        }
        return config
    }

    public func worker(_ mode: String) -> JSONLineProcess {
        JSONLineProcess(
            executable: pythonExecutable,
            arguments: ["-u", "-m", "friday_runtime", mode, "--model-dir", mode == "laya" ? layaModelDirectory : wakeModelDirectory],
            directory: workerDirectory,
            environment: ["HF_HUB_OFFLINE": "1", "TOKENIZERS_PARALLELISM": "false", "PYTHONUNBUFFERED": "1"]
        )
    }
}

public enum AdapterError: Error, LocalizedError, Sendable {
    case unavailable(String)
    case timeout(String)
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let text), .invalidResponse(let text): text
        case .timeout(let provider): "\(provider) antwortet nicht. Bitte erneut versuchen."
        }
    }
}
