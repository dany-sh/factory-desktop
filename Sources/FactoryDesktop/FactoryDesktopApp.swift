import FactoryDesktopCore
import SwiftUI

@main
struct FactoryDesktopApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(router)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings") {
                    router.openSettings(.general)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            CommandGroup(after: .newItem) {
                Button("Refresh Git Status") {
                    Task { await store.refreshGitStatus() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}
