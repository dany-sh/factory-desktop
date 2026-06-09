import FactoryDesktopCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: AppRouter
    @State private var showingProjectSheet = false

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
        .task {
            await store.refreshGitStatus()
        }
    }

    private var mainView: some View {
        Group {
            if store.selectedWorkspaceScope == .task {
                taskSplitView
            } else {
                workspaceSplitView
            }
        }
    }

    private var workspaceSplitView: some View {
        NavigationSplitView {
            SidebarView(showingProjectSheet: $showingProjectSheet)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            workspaceContent
                .navigationSplitViewColumnWidth(min: 760, ideal: 1120)
        }
    }

    private var taskSplitView: some View {
        NavigationSplitView {
            SidebarView(showingProjectSheet: $showingProjectSheet)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } content: {
            TaskDetailView()
                .navigationSplitViewColumnWidth(min: 460, ideal: 680)
        } detail: {
            InspectorView()
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 440)
        }
    }

    @ViewBuilder
    private var workspaceContent: some View {
        switch store.selectedWorkspaceScope {
        case .project:
            ProjectDashboardView()
        case .kanban:
            KanbanView()
        case .task:
            TaskDetailView()
        }
    }
}
