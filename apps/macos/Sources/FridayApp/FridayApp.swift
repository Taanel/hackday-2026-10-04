import SwiftUI

@main
struct FridayApp: App {
    @NSApplicationDelegateAdaptor(FridayAppDelegate.self) private var delegate
    @StateObject private var model = AssistantViewModel()

    var body: some Scene {
        WindowGroup("Friday", id: "assistant") {
            AssistantView(model: model)
        }
        .defaultSize(width: 500, height: 430)

        MenuBarExtra("Friday", systemImage: "sparkles") {
            FridayMenu()
        }
    }
}

private struct FridayMenu: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Friday öffnen") {
            openWindow(id: "assistant")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Beenden") { NSApp.terminate(nil) }
    }
}
