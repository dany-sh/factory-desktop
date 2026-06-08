import FactoryDesktopCore
import SwiftUI

struct ProjectDashboardView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Group {
            if let project = store.selectedProject {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(project: project)
                        summaryPanel(project: project)
                        taskListsPanel
                        LifecycleCleanupView()
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView(
                    "No Project Selected",
                    systemImage: "folder",
                    description: Text("Register or select a project to review repo health, hygiene, and task history.")
                )
            }
        }
    }

    private func header(project: Project) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(project.name)
                        .font(.title2.weight(.semibold))
                    HStack(spacing: 8) {
                        projectBadge("Project View")
                        projectBadge(project.type.displayName)
                        Text(project.id.shortID)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Text(project.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Button {
                        Task { await store.refreshLifecycleScan() }
                    } label: {
                        Label("Refresh Project Scan", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isWorking)

                    if store.selectedTask != nil {
                        Button {
                            store.showTaskWorkspace()
                        } label: {
                            Label("Open Selected Task", systemImage: "arrow.right.circle")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator.opacity(0.6))
        )
    }

    private func summaryPanel(project: Project) -> some View {
        let summary = store.projectStatusSummary
        return VStack(alignment: .leading, spacing: 12) {
            Text("Project Summary")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                summaryChip(label: "Active Tasks", value: "\(summary.activeTaskCount)")
                summaryChip(label: "Archived", value: "\(summary.archivedTaskCount)")
                summaryChip(label: "Preflight", value: summary.preflightStatus)
                summaryChip(label: "Repo", value: summary.workingTreeState)
                summaryChip(label: "Cleanup", value: "\(summary.cleanupItemCount)")
                summaryChip(label: "Historical", value: "\(summary.historicalItemCount)")
                summaryChip(label: "Waste", value: "\(summary.artifactWasteItemCount)")
                summaryChip(label: "Events", value: "\(summary.recentHygieneEventCount)")
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                detailMetric(label: "Default Branch", value: summary.defaultBranch)
                detailMetric(label: "Current Branch", value: summary.currentBranch)
                detailMetric(label: "HEAD", value: summary.head)
                detailMetric(label: "Hygiene", value: summary.hygieneSeverity.displayName)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator.opacity(0.6))
        )
    }

    private var taskListsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Project Tasks")
                .font(.headline)

            if activeTasks.isEmpty && archivedTasks.isEmpty {
                Text("No tasks registered for this project.")
                    .foregroundStyle(.secondary)
            } else {
                if !activeTasks.isEmpty {
                    taskList(title: "Active Tasks", tasks: activeTasks)
                }
                if !archivedTasks.isEmpty {
                    taskList(title: "Archived / Completed", tasks: archivedTasks)
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator.opacity(0.6))
        )
    }

    private func taskList(title: String, tasks: [FactoryTask]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(tasks) { task in
                HStack(spacing: 10) {
                    Circle()
                        .fill(taskStatusColor(task))
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .font(.body.weight(.semibold))
                        Text("\(task.status.displayName) · \(task.type.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Task") {
                        store.selectTask(task.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.vertical, 3)
                if task.id != tasks.last?.id {
                    Divider()
                }
            }
        }
    }

    private func detailMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private func projectBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.5), in: Capsule())
    }

    private func summaryChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private func taskStatusColor(_ task: FactoryTask) -> Color {
        switch task.status.category {
        case .queue: .secondary
        case .planning: .blue
        case .active: .orange
        case .attention: .red
        case .review: .purple
        case .complete: .green
        case .archive: .gray
        }
    }

    private var activeTasks: [FactoryTask] {
        store.tasksForSelectedProject.filter { $0.status != .done && $0.status != .archived }
    }

    private var archivedTasks: [FactoryTask] {
        store.tasksForSelectedProject.filter { $0.status == .done || $0.status == .archived }
    }
}
