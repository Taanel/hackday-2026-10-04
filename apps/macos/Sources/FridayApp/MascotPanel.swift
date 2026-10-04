import AppKit
import SwiftUI

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

@MainActor final class FridayAppDelegate: NSObject, NSApplicationDelegate {
    static var openAssistant: (() -> Void)?
    let model = AssistantViewModel.live()
    private var mascotPanel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.prepare()
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 96, height: 144),
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
        panel.setFrameOrigin(NSPoint(x: frame.maxX - 116, y: frame.maxY - 164))
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
    let open: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Button(action: open) {
                AssistantOrb(phase: model.phase, size: .px64, animateIdle: true)
                    .padding(8)
                    .background(.regularMaterial, in: Circle())
            }.buttonStyle(.plain)
            if model.isRecording {
                Button("Stop") { model.stopRecording() }.buttonStyle(.bordered)
            } else {
                Text(model.wakeEnabled ? "Hey Friday" : "Friday")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .frame(width: 96, height: 144)
        .help("Friday öffnen · \(model.phase.label)")
        .accessibilityLabel("Friday öffnen. \(model.phase.label)")
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
