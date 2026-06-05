import FactoryDesktopCore
import SwiftUI

@main
struct FactoryDesktopApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Git Status") {
                    Task { await store.refreshGitStatus() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .padding()
                .frame(width: 560)
        }
    }
}
