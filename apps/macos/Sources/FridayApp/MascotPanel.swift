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
    private var mascotPanel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 76, height: 76),
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
        panel.contentView = NSHostingView(rootView: Button(action: showAssistant) {
            MascotImage().frame(width: 76, height: 76)
        }.buttonStyle(.plain).help("Friday öffnen"))
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
        panel.setFrameOrigin(NSPoint(x: frame.maxX - 96, y: frame.maxY - 96))
    }

    private func showAssistant() {
        Self.openAssistant?()
    }
}
