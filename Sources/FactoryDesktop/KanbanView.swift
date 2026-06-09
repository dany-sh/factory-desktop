import FactoryDesktopCore
import SwiftUI

struct KanbanView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingTaskPanel = false

    var body: some View {
        Group {
            if let project = store.selectedProject {
                ZStack(alignment: .trailing) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            header(project: project)
                            nextTasksPanel
                            taskQueuePanel
                            kanbanPanel
                        }
                        .padding(24)
                        .padding(.trailing, showingTaskPanel ? 556 : 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(.easeInOut(duration: 0.2), value: showingTaskPanel)
                    }

                    if showingTaskPanel, let task = selectedKanbanTask {
                        taskPanel(task: task)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: showingTaskPanel)
                .onChange(of: store.selectedProjectID) { _, _ in
                    dismissTaskPanel()
                }
                .onChange(of: store.selectedTaskID) { _, _ in
                    if showingTaskPanel, selectedKanbanTask == nil {
                        dismissTaskPanel()
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Project Selected",
                    systemImage: "square.grid.3x3.topleft.filled",
                    description: Text("Select a project to review its queue and kanban flow.")
                )
            }
        }
    }

    private var selectedKanbanTask: FactoryTask? {
        guard let task = store.selectedTask, task.projectId == store.selectedProject?.id else {
            return nil
        }
        return task
    }

    private func header(project: Project) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Kanban")
                        .font(.title2.weight(.semibold))
                    HStack(spacing: 8) {
                        badge(project.name)
                        badge(project.type.displayName)
                    }
                    Text("Showing tasks for the selected project only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        store.showProjectWorkspace()
                    } label: {
                        Label("Project", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { await store.createTask() }
                    } label: {
                        Label("New Task", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.selectedProject == nil)
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

    private var nextTasksPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top 3 Next Tasks")
                .font(.headline)

            if store.nextWorkItems.isEmpty {
                Text("No queued tasks yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(store.nextWorkItems.prefix(3))) { item in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.body.weight(.semibold))
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(item.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(item.primaryAction.displayName) {
                            trigger(item)
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Details") {
                            open(item)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 3)
                    if item.id != store.nextWorkItems.prefix(3).last?.id {
                        Divider()
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

    private var taskQueuePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Task Queue")
                .font(.headline)

            if store.backlogTasksForSelectedProject.isEmpty {
                Text("No queued tasks for this project yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.backlogTasksForSelectedProject) { task in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(task.title)
                                .font(.body.weight(.semibold))
                            Text("\(task.kind.displayName) · \(task.priorityLabel.displayName) · \(task.triageStatus.displayName) · \(task.readiness.displayName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !task.recommendedNextAction.isEmpty {
                                Text(task.recommendedNextAction)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Details") {
                            open(task)
                        }
                        .buttonStyle(.bordered)

                        Button(nextActionTitle(for: task)) {
                            selectForKanban(task.id)
                            if task.readiness == .executable {
                                Task { await store.dispatchTask() }
                            } else {
                                Task { await store.scopeWorkItem() }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(task.triageStatus == .done || task.triageStatus == .archived)
                    }
                    .padding(.vertical, 3)
                    if task.id != store.backlogTasksForSelectedProject.last?.id {
                        Divider()
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

    private var kanbanPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Board")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(FactoryTaskTriageStatus.kanbanColumns) { status in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(status.displayName)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(tasks(for: status).count)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(tasks(for: status)) { task in
                                kanbanCard(task)
                            }
                            if tasks(for: status).isEmpty {
                                Text("No cards")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                            }
                        }
                        .frame(width: 220, alignment: .topLeading)
                        .padding(10)
                        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
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

    private func kanbanCard(_ task: FactoryTask) -> some View {
        let isSelected = selectedKanbanTask?.id == task.id
        let borderColor: Color = isSelected ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.25)
        return Button {
            open(task)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text("\(task.kind.displayName) · \(task.priorityLabel.displayName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(task.readiness.displayName) · \(nextActionTitle(for: task))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func taskPanel(task: FactoryTask) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Task Details")
                        .font(.headline)
                    Text(task.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    store.showTaskWorkspace()
                } label: {
                    Label("Open Full View", systemImage: "arrow.right.square")
                }
                .buttonStyle(.bordered)

                Button {
                    dismissTaskPanel()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
            .background(.bar)

            Divider()

            TaskDetailView()
                .environmentObject(store)
        }
        .frame(width: 520)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(.separator.opacity(0.6))
        )
        .shadow(color: .black.opacity(0.12), radius: 18, x: -4, y: 0)
        .padding(.trailing, 20)
        .padding(.vertical, 20)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.5), in: Capsule())
    }

    private func tasks(for triageStatus: FactoryTaskTriageStatus) -> [FactoryTask] {
        store.tasksForSelectedProject
            .filter { $0.triageStatus == triageStatus }
            .sorted { left, right in
                if left.priorityLabel.sortOrder != right.priorityLabel.sortOrder {
                    return left.priorityLabel.sortOrder < right.priorityLabel.sortOrder
                }
                return left.updatedAt > right.updatedAt
            }
    }

    private func nextActionTitle(for task: FactoryTask) -> String {
        if store.runnerSessionLinks.contains(where: { $0.taskId == task.id }) {
            return "Continue Run"
        }
        switch task.readiness {
        case .executable:
            return "Dispatch"
        case .raw, .needsScoping, .scoped:
            return "Scope"
        }
    }

    private func open(_ item: BacklogNextWorkItem) {
        switch item.kind {
        case .task(let task):
            open(task)
        }
    }

    private func open(_ task: FactoryTask) {
        selectForKanban(task.id)
        showingTaskPanel = true
    }

    private func selectForKanban(_ taskID: String?) {
        store.selectTask(taskID, openWorkspace: false)
    }

    private func dismissTaskPanel() {
        showingTaskPanel = false
        store.selectTask(nil, openWorkspace: false)
    }

    private func trigger(_ item: BacklogNextWorkItem) {
        switch item.primaryAction {
        case .scope:
            if case .task(let task) = item.kind {
                open(task)
                Task { await store.scopeWorkItem() }
            }
        case .dispatch:
            if case .task(let task) = item.kind {
                open(task)
                Task { await store.dispatchTask() }
            }
        case .continueRun:
            if case .task(let task) = item.kind {
                open(task)
                Task { await store.continueRunnerSession() }
            }
        case .reviewDiff, .runTests, .syncLifecycle, .needsManualReview, .noAction:
            open(item)
        }
    }
}
