import FactoryDesktopCore
import AppKit
import ApplicationServices
import SwiftUI

@main
struct FactoryDesktopApp: App {
    @NSApplicationDelegateAdaptor(FactoryDesktopAppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore(appTerminator: {
        NSApp.terminate(nil)
    })
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

        WindowGroup("Markdown", id: "markdown-document", for: String.self) { documentPathBinding in
            if let documentPath = documentPathBinding.wrappedValue {
                MarkdownViewerEditorView(documentPath: documentPath)
                    .environmentObject(store)
                    .background(WindowAccessor { window in
                        FactoryDesktopAppDelegate.activate(window: window)
                    })
            } else {
                ContentUnavailableView(
                    "No Markdown Document",
                    systemImage: "doc.text",
                    description: Text("Choose a markdown file from Factory Desktop to open it in a separate window.")
                )
            }
        }
        .defaultSize(width: 940, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Task") {
                    Task { await store.createTask() }
                }
                .keyboardShortcut("n", modifiers: [.command])
                .disabled(store.selectedProject == nil)

                Divider()

                Button("Register Project...") {
                    router.showRegisterProject()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Register This App") {
                    store.registerSelfProject()
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
            }

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

                Button("Check App Updates") {
                    Task { await store.refreshAppUpdateStatus() }
                }

                Button("Update Factory Desktop") {
                    Task { await store.applyAppUpdate() }
                }
                .disabled(!store.appUpdateStatus.isUpdateAvailable || store.appUpdateStatus.isApplying)
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

struct WindowAccessor: NSViewRepresentable {
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
