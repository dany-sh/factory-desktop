import FactoryDesktopCore
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Factory")
                                .font(.title2.weight(.semibold))
                            Text("Local-first orchestration")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }

                Section("Projects") {
                    if store.projects.isEmpty {
                        Text("No projects registered yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.projects) { project in
                        SidebarRow(
                            title: project.name,
                            subtitle: project.type.displayName,
                            isSelected: store.selectedProjectID == project.id
                        ) {
                            store.selectProject(project.id)
                        }
                    }
                }

                Section("Views") {
                    workspaceRow(title: "Project", subtitle: "Repo health, docs, cleanup", scope: .project) {
                        store.showProjectWorkspace()
                    }
                    workspaceRow(title: "Kanban", subtitle: "Queue, backlog, task flow", scope: .kanban) {
                        store.showKanbanWorkspace()
                    }
                    workspaceRow(title: "Task", subtitle: store.selectedTask?.title ?? "Open the selected task", scope: .task) {
                        store.showTaskWorkspace()
                    }
                    .disabled(store.selectedTask == nil)
                }

                Section("Active Tasks") {
                    if store.selectedProject == nil {
                        Text("Register or select a project first.")
                            .foregroundStyle(.secondary)
                    } else if activeTasks.isEmpty {
                        Text(archivedTasks.isEmpty ? "No tasks yet." : "No active tasks.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(activeTasks) { task in
                        SidebarRow(
                            title: task.title,
                            subtitle: "\(task.status.displayName) · \(task.type.displayName)",
                            isSelected: store.selectedTaskID == task.id
                        ) {
                            store.selectTask(task.id)
                        }
                    }
                }

                if !archivedTasks.isEmpty {
                    Section("Archived Tasks") {
                        ForEach(archivedTasks) { task in
                            SidebarRow(
                                title: task.title,
                                subtitle: "\(task.status.displayName) · \(task.type.displayName)",
                                isSelected: store.selectedTaskID == task.id
                            ) {
                                store.selectTask(task.id)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 0, maxWidth: .infinity)

            VStack(spacing: 8) {
                if store.appUpdateStatus.isUpdateAvailable || store.appUpdateStatus.isApplying {
                    Button {
                        if store.appUpdateStatus.isUpdateAvailable {
                            Task { await store.applyAppUpdate() }
                        } else {
                            router.openSettings(.updates)
                        }
                    } label: {
                        Label(
                            store.appUpdateStatus.isApplying ? "Updating Factory Desktop" : "Update Factory Desktop",
                            systemImage: "arrow.trianglehead.clockwise"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(store.appUpdateStatus.isApplying)

                    Text(store.appUpdateStatus.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        .help(store.appUpdateStatus.message)
                }

                Button {
                    router.openSettings(.general)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .padding()

            Text(store.buildInfo.compactIdentity)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            if !store.statusMessage.isEmpty {
                Text(store.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .padding([.horizontal, .bottom])
                    .help(store.statusMessage)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var activeTasks: [FactoryTask] {
        store.tasksForSelectedProject.filter { !isArchivedLike($0) }
    }

    private var archivedTasks: [FactoryTask] {
        store.tasksForSelectedProject.filter(isArchivedLike)
    }

    private func isArchivedLike(_ task: FactoryTask) -> Bool {
        task.status == .archived || task.status == .done
    }

    @ViewBuilder
    private func workspaceRow(
        title: String,
        subtitle: String,
        scope: WorkspaceSelectionScope,
        action: @escaping () -> Void
    ) -> some View {
        SidebarRow(
            title: title,
            subtitle: subtitle,
            isSelected: store.selectedWorkspaceScope == scope,
            action: action
        )
    }
}

private struct SidebarRow: View {
    var title: String
    var subtitle: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}
