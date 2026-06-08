import FactoryDesktopCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: AppRouter
    @State private var showingProjectSheet = false
    @State private var showingTaskSheet = false

    var body: some View {
        Group {
            switch router.screen {
            case .main:
                mainView
            case .settings:
                SettingsView()
            }
        }
        .frame(minWidth: 1040, minHeight: 680)
        .sheet(isPresented: $showingProjectSheet) {
            RegisterProjectView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showingTaskSheet) {
            NewTaskView()
                .environmentObject(store)
        }
        .sheet(
            isPresented: Binding(
                get: { store.selectedMarkdownDocument != nil },
                set: { presented in
                    if !presented {
                        store.requestCloseMarkdownDocument()
                    }
                }
            )
        ) {
            MarkdownViewerEditorView()
                .environmentObject(store)
        }
        .alert(
            "Factory Desktop",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK") {
                store.errorMessage = nil
            }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .confirmationDialog(
            "You have unsaved markdown changes.",
            isPresented: Binding(
                get: { store.pendingMarkdownDecision != nil },
                set: { presented in
                    if !presented {
                        store.cancelPendingMarkdownDecision()
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Save") {
                store.resolvePendingMarkdownDecision(saveChanges: true)
            }
            Button("Discard Changes", role: .destructive) {
                store.resolvePendingMarkdownDecision(saveChanges: false, discardChanges: true)
            }
            Button("Cancel", role: .cancel) {
                store.resolvePendingMarkdownDecision(saveChanges: nil)
            }
        } message: {
            Text("Save, discard, or cancel before switching documents or closing the viewer.")
        }
        .task {
            await store.refreshGitStatus()
        }
    }

    private var mainView: some View {
        NavigationSplitView {
            SidebarView(
                showingProjectSheet: $showingProjectSheet,
                showingTaskSheet: $showingTaskSheet
            )
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } content: {
            Group {
                if store.selectedWorkspaceScope == .project {
                    ProjectDashboardView()
                } else {
                    TaskDetailView()
                }
            }
            .navigationSplitViewColumnWidth(min: 460, ideal: 680)
        } detail: {
            InspectorView()
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 440)
        }
    }
}
