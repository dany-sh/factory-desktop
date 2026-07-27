import FactoryDesktopCore
import AppKit
import ApplicationServices
import SwiftUI

@main
struct FactoryDesktopApp: App {
    @NSApplicationDelegateAdaptor(FactoryDesktopAppDelegate.self) private var appDelegate
    @StateObject private var conveyorStore = ConveyorBoardStore()
    @StateObject private var store = AppStore(appTerminator: {
        NSApp.terminate(nil)
    })

    var body: some Scene {
        WindowGroup {
            ConveyorBoardView(store: conveyorStore)
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
            CommandGroup(after: .newItem) {
                Button("Refresh Conveyor") {
                    Task { await conveyorStore.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("Toggle Sidebar") {
                    conveyorStore.isSidebarVisible.toggle()
                }
                Button("Toggle Inspector") {
                    conveyorStore.toggleInspector()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
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

    func applicationDidBecomeActive(_ notification: Notification) {
        NSApp.windows.forEach(Self.fitWindowToCurrentDisplay)
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        NSApp.windows.forEach(Self.fitWindowToCurrentDisplay)
    }

    static func activate(window: NSWindow?) {
        becomeForegroundApplication()
        NSApp.activate(ignoringOtherApps: true)

        guard let window else { return }
        fitWindowToCurrentDisplay(window)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private static func fitWindowToCurrentDisplay(_ window: NSWindow) {
        guard let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame else { return }

        let currentFrame = window.frame
        let fittedSize = NSSize(
            width: min(currentFrame.width, visibleFrame.width),
            height: min(currentFrame.height, visibleFrame.height)
        )
        let fittedOrigin = NSPoint(
            x: min(max(currentFrame.minX, visibleFrame.minX), visibleFrame.maxX - fittedSize.width),
            y: min(max(currentFrame.minY, visibleFrame.minY), visibleFrame.maxY - fittedSize.height)
        )
        let fittedFrame = NSRect(origin: fittedOrigin, size: fittedSize)

        if fittedFrame != currentFrame {
            window.setFrame(fittedFrame, display: true)
        }
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
