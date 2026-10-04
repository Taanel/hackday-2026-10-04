import Foundation
import Darwin

private final class LineDecoder: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()
    let emit: @Sendable (Data) -> Void

    init(emit: @escaping @Sendable (Data) -> Void) { self.emit = emit }
    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if !line.isEmpty { emit(line) }
        }
        // A malformed worker must not accumulate unlimited stdout.
        if buffer.count > 2_000_000 { buffer.removeAll() }
    }
}

/// Owns one direct child. JSON responses use IDs; unsolicited events use `events`.
public actor JSONLineProcess {
    public nonisolated let events: AsyncStream<Data>
    private let eventContinuation: AsyncStream<Data>.Continuation
    private let executable: String
    private let arguments: [String]
    private let directory: String?
    private let environment: [String: String]
    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var reader: Task<Void, Never>?
    private var startup: Task<Data, any Error>?
    private var stopping: Task<Void, Never>?
    private var ready: Data?
    private var readyWaiter: CheckedContinuation<Data, any Error>?
    private var pending: [String: CheckedContinuation<Data, any Error>] = [:]
    private var generation = UUID()

    public init(executable: String, arguments: [String], directory: String? = nil, environment: [String: String] = [:]) {
        self.executable = executable
        self.arguments = arguments
        self.directory = directory
        self.environment = environment
        (events, eventContinuation) = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingNewest(128))
    }

    public func start() async throws -> Data {
        try Task.checkCancellation()
        if let stopping { await stopping.value }
        try Task.checkCancellation()
        if let ready { return ready }
        let active: Task<Data, any Error>
        if let startup { active = startup }
        else {
            active = Task { try await self.launch() }
            startup = active
        }
        defer { self.startup = nil }
        let result = try await withTaskCancellationHandler {
            try await active.value
        } onCancel: { Task { await self.stop() } }
        try Task.checkCancellation()
        return result
    }

    public var isReady: Bool { ready != nil }
    public var sessionID: UUID { generation }

    private func launch() async throws -> Data {
        try Task.checkCancellation()
        let token = UUID()
        generation = token
        let child = Process()
        child.executableURL = URL(fileURLWithPath: executable)
        child.arguments = arguments
        if let directory { child.currentDirectoryURL = URL(fileURLWithPath: directory) }
        child.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        let input = Pipe(), output = Pipe()
        child.standardInput = input
        child.standardOutput = output
        // Worker diagnostics never share the JSON channel or include the Hex bearer token.
        child.standardError = FileHandle.nullDevice
        let (lines, continuation) = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingNewest(128))
        let decoder = LineDecoder { continuation.yield($0) }
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; continuation.finish() }
            else { decoder.append(data) }
        }
        child.terminationHandler = { [weak self] _ in
            continuation.finish()
            Task { await self?.ended(token) }
        }
        process = child
        stdin = input.fileHandleForWriting
        stdout = output.fileHandleForReading
        reader = Task { [weak self] in
            for await line in lines { await self?.receive(line, token: token) }
        }
        do { try Task.checkCancellation(); try child.run() }
        catch { await stop(reason: error); throw error }
        let deadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            await self?.expiredStartup(token)
        }
        defer { deadline.cancel() }
        return try await withCheckedThrowingContinuation { readyWaiter = $0 }
    }

    private struct Header: Decodable { let type: String?; let id: String?; let error: String? }

    private func receive(_ line: Data, token: UUID) {
        guard generation == token, let header = try? JSONDecoder().decode(Header.self, from: line) else { return }
        if header.type == "ready" {
            ready = line
            let waiter = readyWaiter; readyWaiter = nil
            waiter?.resume(returning: line)
        } else if let id = header.id, let waiter = pending.removeValue(forKey: id) {
            if let error = header.error { waiter.resume(throwing: AdapterError.unavailable(error)) }
            else { waiter.resume(returning: line) }
        } else {
            // Queued events can outlive a helper restart. Attach the transport
            // epoch; generation counters inside a new Python process restart.
            if var event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                event["transportSession"] = token.uuidString
                if let tagged = try? JSONSerialization.data(withJSONObject: event) { eventContinuation.yield(tagged) }
            }
        }
    }

    public func send(_ data: Data) throws {
        guard let stdin, process?.isRunning == true else { throw AdapterError.unavailable("Lokaler Helper ist nicht gestartet.") }
        var line = data; line.append(10)
        try stdin.write(contentsOf: line)
    }

    public func request(_ data: Data, id: String, timeout: Double = 20) async throws -> Data {
        _ = try await start()
        try Task.checkCancellation()
        let deadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            await self?.expireRequest(id)
        }
        defer { deadline.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { waiter in
                pending[id] = waiter
                do { try send(data) }
                catch { pending.removeValue(forKey: id)?.resume(throwing: error) }
            }
        } onCancel: { Task { await self.stop() } }
    }

    private func expireRequest(_ id: String) async {
        guard pending[id] != nil else { return }
        await stop(reason: AdapterError.timeout("Lokales Modell"))
    }
    private func expiredStartup(_ token: UUID) async {
        guard generation == token, ready == nil else { return }
        await stop(reason: AdapterError.timeout("Modellstart"))
    }
    private func ended(_ token: UUID) async {
        guard generation == token else { return }
        await stop(reason: AdapterError.unavailable("Lokaler Helper wurde beendet. Bitte erneut versuchen."))
    }

    public func stop(reason: any Error = CancellationError()) async {
        if let stopping { await stopping.value; return }
        generation = UUID()
        startup?.cancel(); startup = nil
        let child = process
        process = nil; ready = nil
        let waiter = readyWaiter; readyWaiter = nil
        waiter?.resume(throwing: reason)
        let requests = pending; pending.removeAll()
        for continuation in requests.values { continuation.resume(throwing: reason) }
        try? stdin?.close(); stdin = nil
        stdout?.readabilityHandler = nil
        try? stdout?.close(); stdout = nil
        reader?.cancel(); reader = nil
        guard let child, child.isRunning else { return }
        let cleanup = Task {
            child.terminate()
            for _ in 0..<50 where child.isRunning { try? await Task.sleep(for: .milliseconds(50)) }
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            child.waitUntilExit()
        }
        stopping = cleanup
        await cleanup.value
        stopping = nil
    }
}
