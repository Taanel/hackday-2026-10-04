import SwiftUI
import ThinkingOrbsKit

@main
struct FridayApp: App {
    @NSApplicationDelegateAdaptor(FridayAppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            FridayMenu(open: delegate.showAssistant)
        } label: {
            Image(nsImage: FridayMenuIcon.image).accessibilityLabel("Friday")
        }
    }
}

@MainActor private enum FridayMenuIcon {
    static let image: NSImage = {
        let renderer = ImageRenderer(content: ThinkingOrb(state: .searching, size: .px20, theme: .light, paused: true))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "globe", accessibilityDescription: "Friday")!
        image.isTemplate = true
        return image
    }()
}

private struct FridayMenu: View {
    let open: () -> Void

    var body: some View {
        Button("Friday öffnen", action: open)
        Divider()
        Button("Beenden") { NSApp.terminate(nil) }
    }
}
