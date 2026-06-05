import FactoryDesktopCore
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: AppStore
    @Binding var showingProjectSheet: Bool
    @Binding var showingTaskSheet: Bool
    @Binding var showingSettings: Bool

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

                Section("Tasks") {
                    if store.selectedProject == nil {
                        Text("Register or select a project first.")
                            .foregroundStyle(.secondary)
                    } else if store.tasksForSelectedProject.isEmpty {
                        Text("No tasks yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.tasksForSelectedProject) { task in
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
            .listStyle(.sidebar)

            VStack(spacing: 8) {
                Button {
                    showingProjectSheet = true
                } label: {
                    Label("Register Project", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    store.registerSelfProject()
                } label: {
                    Label("Register This App", systemImage: "app.badge")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    showingTaskSheet = true
                } label: {
                    Label("New Task", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .disabled(store.selectedProject == nil)

                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .padding()

            if !store.statusMessage.isEmpty {
                Text(store.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding([.horizontal, .bottom])
            }
        }
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
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}
