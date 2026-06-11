import FactoryDesktopCore
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: AppRouter
    @StateObject private var taskWorkspaceState = TaskWorkspaceState()

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
        .sheet(isPresented: $router.isRegisterProjectPresented) {
            RegisterProjectView()
                .environmentObject(store)
        }
        .sheet(isPresented: $store.isWorkerRunDetailPresented) {
            if let detail = store.workerRunDetail {
                WorkerRunDetailView(detail: detail, rawLogsInitiallyExpanded: store.workerRawLogsInitiallyExpanded)
                    .environmentObject(store)
            }
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
            store.startAppUpdateMonitoring()
            await store.refreshAppUpdateStatus()
            await store.refreshGitStatus()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await store.refreshAppUpdateStatus() }
        }
    }

    private var mainView: some View {
        workspaceSplitView
    }

    private var workspaceSplitView: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            workspaceShell
                .navigationSplitViewColumnWidth(min: 760, ideal: 1180)
        }
        .navigationTitle(workspaceTitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    taskWorkspaceState.inspectorPresented.toggle()
                } label: {
                    Image(systemName: "sidebar.trailing")
                }
                .help(taskWorkspaceState.inspectorPresented ? "Hide Inspector" : "Show Inspector")
            }
        }
    }

    private var workspaceShell: some View {
        HSplitView {
            workspaceContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if taskWorkspaceState.inspectorPresented && taskWorkspaceState.selectedStage != .worker {
                RightToolsInspectorView()
                    .environmentObject(taskWorkspaceState)
                    .frame(minWidth: 320, idealWidth: 420, maxWidth: 760, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var workspaceContent: some View {
        Group {
            switch store.selectedWorkspaceScope {
            case .project:
                ProjectDashboardView()
            case .kanban:
                KanbanView()
            case .task:
                TaskDetailView()
            }
        }
        .environmentObject(taskWorkspaceState)
    }

    private var workspaceTitle: String {
        switch store.selectedWorkspaceScope {
        case .project:
            if let project = store.selectedProject {
                return "factory-desktop / Project / \(project.name)"
            }
            return "factory-desktop / Project"
        case .kanban:
            if let project = store.selectedProject {
                return "factory-desktop / Kanban / \(project.name)"
            }
            return "factory-desktop / Kanban"
        case .task:
            return ""
        }
    }
}
