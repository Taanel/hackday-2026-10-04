import AppKit
import ImageIO
import SwiftUI
import FridayCore

private extension AssistantPhase {
    /// Artwork for a reaction; `nil` keeps the normal mascot.
    var reactionName: String? {
        switch self {
        case .idle, .listening, .speaking: nil
        case .recording, .reasoning: "mascot-curious"
        case .transcribing, .deciding: "mascot-focused"
        case .acting: "mascot-excited"
        case .failed: "mascot-worried"
        }
    }
}

/// Decoded frames of one mascot PNG; an animated PNG yields a loop.
struct MascotArtwork {
    let frames: [CGImage]
    let frameDuration: TimeInterval

    var loopDuration: TimeInterval { Double(frames.count) * frameDuration }

    /// Rests on the first frame for `rest` seconds before each loop.
    func frameIndex(at elapsed: TimeInterval, rest: TimeInterval) -> Int {
        let position = max(0, elapsed).truncatingRemainder(dividingBy: rest + loopDuration) - rest
        return position < 0 ? 0 : min(Int(position / frameDuration), frames.count - 1)
    }
}

@MainActor enum MascotLibrary {
    static let normal = "mascot"
    static let sleeping = "mascot-sleeping"
    static let hover = "mascot-hover"
    /// Being carried reuses the stretching reaction.
    static let held = "mascot-excited"

    static func isReaction(_ name: String) -> Bool { name != normal && name != sleeping }
    private static var cache: [String: MascotArtwork] = [:]

    private static var resourceBundle: Bundle {
        // Packaged app resources must work without SwiftPM's absolute build path.
        if let url = Bundle.main.url(forResource: "Friday_FridayApp", withExtension: "bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }

    /// Reaction artwork is optional; a missing file falls back to `mascot.png`.
    static func artwork(named name: String) -> MascotArtwork? {
        if let cached = cache[name] { return cached }
        let artwork = load(name) ?? (name == normal ? nil : artwork(named: normal))
        cache[name] = artwork
        return artwork
    }

    private static func load(_ name: String) -> MascotArtwork? {
        guard let url = resourceBundle.url(forResource: name, withExtension: "png", subdirectory: "Resources"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let frames = (0..<CGImageSourceGetCount(source)).compactMap {
            CGImageSourceCreateImageAtIndex(source, $0, nil)
        }
        guard !frames.isEmpty else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let png = properties?[kCGImagePropertyPNGDictionary] as? [CFString: Any]
        let delay = png?[kCGImagePropertyAPNGUnclampedDelayTime] as? Double ?? 0
        return MascotArtwork(frames: frames, frameDuration: delay > 0 ? delay : 0.04)
    }
}

/// Decides which pose the mascot shows and when it may change.
@MainActor final class MascotDirector: ObservableObject {
    @Published private(set) var pose = MascotLibrary.normal
    @Published private(set) var poseStart = Date()

    private var queue: [String] = []
    private var driver: Task<Void, Never>?
    private let loopDuration: @MainActor (String) -> TimeInterval
    private let dozeDelay: TimeInterval

    init(
        loopDuration: @escaping @MainActor (String) -> TimeInterval = {
            MascotLibrary.artwork(named: $0)?.loopDuration ?? 0
        },
        dozeDelay: TimeInterval = 60
    ) {
        self.loopDuration = loopDuration
        self.dozeDelay = dozeDelay
    }

    /// Queues the reaction to a phase; phases without one bring back the normal mascot.
    func react(to phase: AssistantPhase) {
        enqueue(phase.reactionName ?? MascotLibrary.normal)
        // A failure is shown once; the window keeps the error while the mascot calms down.
        if phase == .failed { enqueue(MascotLibrary.normal) }
    }

    /// Hovering plays one loop; it never interrupts the reaction to a request.
    func greet() {
        guard !MascotLibrary.isReaction(pose), queue.isEmpty else { return }
        show(MascotLibrary.hover)
        enqueue(MascotLibrary.normal)
    }

    /// Being picked up interrupts everything; letting go resumes with the current phase.
    func carry(_ isCarried: Bool, phase: AssistantPhase) {
        guard isCarried else {
            // A failure that was already shown is not replayed.
            return enqueue(phase == .failed ? MascotLibrary.normal : phase.reactionName ?? MascotLibrary.normal)
        }
        driver?.cancel()
        queue.removeAll()
        show(MascotLibrary.held)
    }

    private func enqueue(_ name: String) {
        guard name != queue.last ?? pose else { return }
        queue.append(name)
        driver?.cancel()
        driver = Task { await run() }
    }

    private func run() async {
        while let next = queue.first {
            // A reaction changes at the end of its loop, where it is back in its rest pose.
            if MascotLibrary.isReaction(pose) {
                let loop = loopDuration(pose)
                let played = Date().timeIntervalSince(poseStart)
                let remaining = loop > 0 ? loop - played.truncatingRemainder(dividingBy: loop) : 0
                try? await Task.sleep(for: .seconds(remaining))
                guard !Task.isCancelled else { return }
            }
            queue.removeFirst()
            show(next)
        }
        try? await Task.sleep(for: .seconds(dozeDelay))
        guard !Task.isCancelled, pose == MascotLibrary.normal else { return }
        show(MascotLibrary.sleeping)
    }

    private func show(_ name: String) {
        guard name != pose else { return }
        pose = name
        poseStart = Date()
    }
}

/// One pose on its own clock, so an outgoing pose keeps moving while it fades.
private struct MascotPose: View {
    let artwork: MascotArtwork
    let start: Date
    let rest: TimeInterval
    let isStill: Bool

    var body: some View {
        TimelineView(.animation(
            minimumInterval: artwork.frameDuration,
            paused: isStill || artwork.frames.count == 1
        )) { timeline in
            let elapsed = isStill ? 0 : timeline.date.timeIntervalSince(start)
            Image(decorative: artwork.frames[artwork.frameIndex(at: elapsed, rest: rest)], scale: 1)
                .resizable().interpolation(.high).scaledToFit()
        }
    }
}

/// Normal mascot that plays a reaction for each assistant phase and dozes off when unused.
struct MascotImage: View {
    @ObservedObject var model: AssistantViewModel
    /// Set for the desktop mascot: a click calls this and a drag moves its window.
    var onClick: (@MainActor () -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var director = MascotDirector()

    private let restBetweenLoops: TimeInterval = 4

    var body: some View {
        let isStill = reduceMotion
        ZStack {
            if let artwork = MascotLibrary.artwork(named: director.pose) {
                MascotPose(
                    artwork: artwork,
                    start: director.poseStart,
                    rest: MascotLibrary.isReaction(director.pose) ? 0 : restBetweenLoops,
                    isStill: isStill
                )
                .id(director.poseStart)
                // The new pose fades in on top before the old one leaves, so the body never turns see-through.
                .zIndex(director.poseStart.timeIntervalSinceReferenceDate)
                .transition(.asymmetric(
                    insertion: .opacity.animation(.easeOut(duration: 0.22)),
                    removal: .opacity.animation(.easeIn(duration: 0.2).delay(0.16))
                ))
            } else {
                Image(systemName: "sparkles").resizable().scaledToFit().padding(12)
                    .foregroundStyle(.indigo)
            }
        }
        .animation(.default, value: director.poseStart)
        .keyframeAnimator(initialValue: CGFloat(1), trigger: director.poseStart) { content, squash in
            content.scaleEffect(x: 1, y: isStill ? 1 : squash, anchor: .bottom)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(0.93, duration: 0.14)
                SpringKeyframe(1, duration: 0.4, spring: .bouncy)
            }
        }
        .onReceive(model.$phase) { director.react(to: $0) }
        .overlay(PointerSensor(
            entered: director.greet,
            carried: { director.carry($0, phase: model.phase) },
            clicked: onClick
        ))
        .accessibilityLabel("Friday-Maskottchen")
    }
}

/// SwiftUI's `onHover` needs an active app; the desktop mascot must notice the pointer regardless.
private struct PointerSensor: NSViewRepresentable {
    let entered: @MainActor () -> Void
    let carried: @MainActor (Bool) -> Void
    let clicked: (@MainActor () -> Void)?

    func makeNSView(context: Context) -> SensorView { SensorView() }

    func updateNSView(_ view: SensorView, context: Context) {
        view.entered = entered
        view.carried = carried
        view.clicked = clicked
    }

    final class SensorView: NSView {
        var entered: @MainActor () -> Void = {}
        var carried: @MainActor (Bool) -> Void = { _ in }
        var clicked: (@MainActor () -> Void)?
        private var grab: NSPoint?
        private var isCarried = false

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self
            ))
        }

        override func mouseEntered(with event: NSEvent) { entered() }

        // Without a click handler the mascot is decoration; secondary clicks reach SwiftUI's context menu.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard clicked != nil, let event = NSApp.currentEvent else { return nil }
            let isSecondary = event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            return isSecondary ? nil : super.hitTest(point)
        }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            grab = event.locationInWindow
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window, let grab else { return }
            if !isCarried {
                let position = event.locationInWindow
                guard hypot(position.x - grab.x, position.y - grab.y) > 3 else { return }
                isCarried = true
                carried(true)
            }
            let pointer = NSEvent.mouseLocation
            window.setFrameOrigin(NSPoint(x: pointer.x - grab.x, y: pointer.y - grab.y))
        }

        override func mouseUp(with event: NSEvent) {
            if isCarried { carried(false) } else { clicked?() }
            grab = nil
            isCarried = false
        }
    }
}

@MainActor final class FridayAppDelegate: NSObject, NSApplicationDelegate {
    static var openAssistant: (() -> Void)?
    let model = AssistantViewModel.live()
    private var mascotPanel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.prepare()
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 96, height: 110),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: FloatingAssistant(model: model, open: showAssistant))
        mascotPanel = panel
        positionMascot()
        panel.orderFrontRegardless()
        NotificationCenter.default.addObserver(
            self, selector: #selector(positionMascot),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    @objc private func positionMascot() {
        guard let panel = mascotPanel, let frame = NSScreen.main?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: frame.maxX - 116, y: frame.maxY - 130))
    }

    private func showAssistant() {
        Self.openAssistant?()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { await model.shutdown(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}

private struct FloatingAssistant: View {
    @ObservedObject var model: AssistantViewModel
    let open: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 4) {
            MascotImage(model: model, onClick: open).frame(width: 96, height: 78)
                .accessibilityLabel("Friday öffnen. \(model.phase.label)")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { open() }
            // The character stays clean; only an active recording needs a control.
            if model.isRecording {
                Button("Stop") { model.stopRecording() }.buttonStyle(.bordered)
            }
        }
        .frame(width: 96, height: 110, alignment: .top)
        .help("Friday öffnen · \(model.phase.label)")
        .contextMenu {
            Button(model.wakeEnabled ? "Hey Friday ausschalten" : "Hey Friday aktivieren") { model.setWakeEnabled(!model.wakeEnabled) }
                .disabled(!model.isReady || model.isWorking)
            Button("Sprechen") { model.startRecording() }.disabled(!model.isReady || model.isWorking)
            Button("Abbrechen") { model.cancel() }.disabled(!model.isWorking)
            Divider()
            Button("Beenden") { NSApp.terminate(nil) }
        }
    }
}
