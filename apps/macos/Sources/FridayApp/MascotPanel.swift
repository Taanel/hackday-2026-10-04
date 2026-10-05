import AppKit
import SwiftUI
import Combine

struct MascotImage: View {
    private var resourceBundle: Bundle {
        // Packaged app resources must work without SwiftPM's absolute build path.
        if let url = Bundle.main.url(forResource: "Friday_FridayApp", withExtension: "bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }

    private var artwork: NSImage? {
        guard let url = resourceBundle.url(forResource: "mascot", withExtension: "png", subdirectory: "Resources") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        Group {
            if let artwork {
                Image(nsImage: artwork).resizable().scaledToFit()
            } else {
                Image(systemName: "sparkles").resizable().scaledToFit().padding(12)
                    .foregroundStyle(.indigo)
            }
        }
        .accessibilityLabel("Friday-Maskottchen")
    }
}

@MainActor final class FridayAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AssistantViewModel.live()
    private var assistantWindow: NSWindow?
    private var mascotPanel: NSPanel?
    private var overlaySubscription: AnyCancellable?
    private var projectSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.prepare()
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 96, height: 96),
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
        overlaySubscription = model.$overlayTranscript.combineLatest(model.$isRecording).sink { [weak self] text, recording in
            self?.layoutMascot(transcript: text, recording: recording)
        }
        projectSubscription = model.$projectMatches.dropFirst().sink { [weak self] matches in
            if !matches.isEmpty { self?.showAssistant() }
        }
        positionMascot()
        panel.orderFrontRegardless()
        NotificationCenter.default.addObserver(
            self, selector: #selector(positionMascot),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    @objc private func positionMascot() {
        layoutMascot(transcript: model.overlayTranscript, recording: model.isRecording)
    }

    private func layoutMascot(transcript: String, recording: Bool) {
        guard let panel = mascotPanel, let frame = NSScreen.main?.visibleFrame else { return }
        let size = transcript.isEmpty ? NSSize(width: 96, height: recording ? 132 : 96) : NSSize(width: 280, height: 164)
        panel.setFrame(NSRect(x: frame.maxX - 20 - size.width, y: frame.maxY - 20 - size.height,
                             width: size.width, height: size.height), display: true)
    }

    func showAssistant() {
        if assistantWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 660),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Friday"
            window.delegate = self
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: AssistantView(model: model))
            window.minSize = NSSize(width: 500, height: 520)
            window.center()
            assistantWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        assistantWindow?.makeKeyAndOrderFront(nil)
    }
    func windowDidBecomeKey(_ notification: Notification) { OrbWindowActivity.shared.active = true }
    func windowDidResignKey(_ notification: Notification) { OrbWindowActivity.shared.active = false }
    func windowWillClose(_ notification: Notification) { OrbWindowActivity.shared.active = false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { await model.shutdown(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}

struct FloatingAssistant: View {
    @ObservedObject var model: AssistantViewModel
    let open: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Button { model.startRecording() } label: {
                AssistantOrb(phase: model.phase, size: .px64)
                    .padding(8)
            }.buttonStyle(.plain)
                .disabled(!model.isReady || model.isWorking || model.isRecording)
                .help("Klicken und sprechen · Einstellungen per Rechtsklick")
                .accessibilityLabel("Sprachaufnahme starten")
            if model.isRecording {
                Button("Stop") { model.stopRecording() }.buttonStyle(.bordered).frame(width: 80)
            }
            if !model.overlayTranscript.isEmpty {
                OverlayTranscriptBubble(text: model.overlayTranscript)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .contextMenu {
            Button("Einstellungen und Antworten öffnen", action: open)
            Divider()
            Button(model.wakeEnabled ? "Wake ausschalten" : "Hey Friday aktivieren") { model.setWakeEnabled(!model.wakeEnabled) }
                .disabled(!model.isReady || model.isWorking)
            Button("Sprechen") { model.startRecording() }.disabled(!model.isReady || model.isWorking)
            Button("Abbrechen") { model.cancel() }.disabled(!model.isWorking)
            Divider()
            Button("Beenden") { NSApp.terminate(nil) }
        }
    }
}

struct OverlayTranscriptBubble: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .lineLimit(3)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 10))
            .allowsHitTesting(false)
            .accessibilityLabel("Erkannt: \(text)")
    }
}
