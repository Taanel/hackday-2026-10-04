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
    let model = AssistantViewModel()
    private var mascotPanel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 88, height: 112),
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
        panel.setFrameOrigin(NSPoint(x: frame.maxX - 108, y: frame.maxY - 132))
    }

    private func showAssistant() {
        Self.openAssistant?()
    }
}

private struct FloatingAssistant: View {
    @ObservedObject var model: AssistantViewModel
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(spacing: 4) {
                MascotImage().frame(width: 68, height: 68)
                AssistantOrb(phase: model.phase, size: .px20)
                    .padding(6)
                    .background(.regularMaterial, in: Capsule())
            }
            .frame(width: 88, height: 112)
        }
        .buttonStyle(.plain)
        .help("Friday öffnen · \(model.phase.label)")
        .accessibilityLabel("Friday öffnen. \(model.phase.label)")
    }
}
