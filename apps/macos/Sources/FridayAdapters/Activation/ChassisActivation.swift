import AppKit
import CoreGraphics
import Foundation
import FridayMotion

@MainActor public final class ChassisActivation {
    public var onActivate: (() -> Void)?
    public var onDiagnostics: ((Int, Int, Double) -> Void)?
    public var onError: ((String) -> Void)?
    public var canActivate: (() -> Bool)?
    public var testOnly = false
    public var threshold = 0.12 { didSet { detector.threshold = threshold } }
    public private(set) var isRunning = false
    private var session: OpaquePointer?
    private var detector = DoubleTapDetector()
    private var samples = 0
    private var pairs = 0
    private var lastDiagnostics = 0.0
    private var lastInputCheck = 0.0
    private var inputRecent = false
    private var watchdog: Task<Void, Never>?

    public init() {}
    isolated deinit { stop() }
    public static var hasInputPermission: Bool { CGPreflightListenEventAccess() }
    public static func requestInputPermission() { _ = CGRequestListenEventAccess() }
    public static func openInputSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") { NSWorkspace.shared.open(url) }
    }

    public func start() throws {
        guard !isRunning else { return }
        guard Self.hasInputPermission else {
            throw AdapterError.unavailable("Bitte Friday unter Datenschutz → Eingabeüberwachung erlauben. Danach erneut einschalten; macOS kann einen Neustart von Friday verlangen.")
        }
        detector = DoubleTapDetector(threshold: threshold)
        samples = 0; pairs = 0; lastDiagnostics = 0; lastInputCheck = 0
        var error = [CChar](repeating: 0, count: 256)
        let context = Unmanaged.passUnretained(self).toOpaque()
        session = FridayMotionStart({ context, time, x, y, z in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<ChassisActivation>.fromOpaque(context).takeUnretainedValue().receive(time: time, x: x, y: y, z: z)
            }
        }, context, &error, error.count)
        guard session != nil else {
            throw AdapterError.unavailable(String(decoding: error.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
        }
        isRunning = true
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                guard let self, self.isRunning else { return }
                guard self.samples > 0, Self.hasInputPermission else {
                    self.stop(); self.onError?("Gehäusesensor liefert keine Daten. Eingabeüberwachung und Mac-Unterstützung prüfen."); return
                }
                self.samples = 0
            }
        }
    }

    private static func recentInput() -> Bool {
        // Only age of input activity; no event tap, key codes or typed text.
        let kinds: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp,
                                  .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .scrollWheel]
        return kinds.contains { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) < 0.35 }
    }

    private func receive(time: Double, x: Double, y: Double, z: Double) {
        guard isRunning else { return }
        samples += 1
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastInputCheck >= 0.025 { inputRecent = Self.recentInput(); lastInputCheck = now }
        let blocked = inputRecent || !(canActivate?() ?? true)
        if detector.accept(time: time, x: x, y: y, z: z, suppressed: blocked) {
            pairs += 1
            // Check again at dispatch, including input arriving behind the sensor.
            if !testOnly, Self.hasInputPermission, !Self.recentInput(), canActivate?() ?? true { onActivate?() }
        }
        if now - lastDiagnostics >= 1 {
            lastDiagnostics = now
            onDiagnostics?(pairs, detector.rejectedPulses, detector.lastStrength)
        }
    }

    public func stop() {
        isRunning = false; watchdog?.cancel(); watchdog = nil
        if let session { FridayMotionStop(session) }
        session = nil; detector.reset()
    }
}
