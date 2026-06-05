import FactoryDesktopCore
import AppKit
import ApplicationServices
import SwiftUI

@main
struct FactoryDesktopApp: App {
    @NSApplicationDelegateAdaptor(FactoryDesktopAppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()
    @StateObject private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(router)
                .background(WindowAccessor { window in
                    FactoryDesktopAppDelegate.activate(window: window)
                })
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

final class FactoryDesktopAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        Self.becomeForegroundApplication()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.activate(window: NSApp.windows.first)
    }

    static func activate(window: NSWindow?) {
        becomeForegroundApplication()
        NSApp.activate(ignoringOtherApps: true)

        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private static func becomeForegroundApplication() {
        var process = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kCurrentProcess))
        _ = TransformProcessType(&process, ProcessApplicationTransformState(kProcessTransformToForegroundApplication))
        NSApp.setActivationPolicy(.regular)
    }
}

private struct WindowAccessor: NSViewRepresentable {
    var onResolve: (NSWindow) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                context.coordinator.resolve(window, onResolve: onResolve)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                context.coordinator.resolve(window, onResolve: onResolve)
            }
        }
    }

    final class Coordinator {
        private var resolvedWindowID: ObjectIdentifier?

        func resolve(_ window: NSWindow, onResolve: (NSWindow) -> Void) {
            let windowID = ObjectIdentifier(window)
            guard resolvedWindowID != windowID else { return }
            resolvedWindowID = windowID
            onResolve(window)
        }
    }
}
