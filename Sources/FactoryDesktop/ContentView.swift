import FactoryDesktopCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingProjectSheet = false
    @State private var showingTaskSheet = false
    @State private var showingSettings = false

    var body: some View {
        NavigationSplitView {
            SidebarView(
                showingProjectSheet: $showingProjectSheet,
                showingTaskSheet: $showingTaskSheet,
                showingSettings: $showingSettings
            )
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } content: {
            TaskDetailView()
                .navigationSplitViewColumnWidth(min: 460, ideal: 680)
        } detail: {
            InspectorView()
                .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
        }
        .sheet(isPresented: $showingProjectSheet) {
            RegisterProjectView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showingTaskSheet) {
            NewTaskView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(store)
                .padding()
                .frame(width: 560, height: 520)
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
}
