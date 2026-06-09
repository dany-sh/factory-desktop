import FactoryDesktopCore
import SwiftUI
import UniformTypeIdentifiers

struct KanbanView: View {
    @EnvironmentObject private var store: AppStore
    @State private var dragTargetColumn: KanbanColumn?

    var body: some View {
        Group {
            if let project = store.selectedProject {
                VStack(alignment: .leading, spacing: 16) {
                    header(project: project)
                    kanbanPanel
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ContentUnavailableView(
                    "No Project Selected",
                    systemImage: "square.grid.3x3.topleft.filled",
                    description: Text("Select a project to review its task flow.")
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
                    Text("Project tasks grouped by work state.")
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
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator.opacity(0.6))
        )
    }

    private var kanbanPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Board")
                    .font(.headline)
                Spacer()
                Text("\(visibleTasks.count) tasks")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(KanbanColumn.allCases) { column in
                        kanbanColumn(column)
                    }
                }
                .frame(minWidth: 1320, maxHeight: .infinity, alignment: .topLeading)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator.opacity(0.6))
        )
    }

    private func kanbanColumn(_ column: KanbanColumn) -> some View {
        let columnTasks = tasks(for: column)
        let isDropTarget = dragTargetColumn == column
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(column.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(columnTasks.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(columnTasks) { task in
                        kanbanCard(task)
                    }
                    if columnTasks.isEmpty {
                        Text("Drop cards here")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
                            .padding(10)
                            .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.bottom, 10)
            }
        }
        .frame(minWidth: 240, idealWidth: 240, maxWidth: 240, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .background((isDropTarget ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.10)), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isDropTarget ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.18), lineWidth: isDropTarget ? 2 : 1)
        )
        .onDrop(
            of: [UTType.text],
            delegate: KanbanDropDelegate(
                column: column,
                dragTargetColumn: $dragTargetColumn,
                moveTask: moveTask
            )
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
                Text(task.status.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if !task.recommendedNextAction.isEmpty {
                    Text(task.recommendedNextAction)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
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
        .onDrag {
            NSItemProvider(object: task.id as NSString)
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.5), in: Capsule())
    }

    private var visibleTasks: [FactoryTask] {
        store.tasksForSelectedProject
            .filter { $0.status != .archived }
    }

    private func tasks(for column: KanbanColumn) -> [FactoryTask] {
        visibleTasks
            .filter { column.contains($0.status) }
            .sorted { left, right in
                if left.priorityLabel.sortOrder != right.priorityLabel.sortOrder {
                    return left.priorityLabel.sortOrder < right.priorityLabel.sortOrder
                }
                return left.updatedAt > right.updatedAt
            }
    }

    private func open(_ task: FactoryTask) {
        store.selectTask(task.id)
    }

    private func moveTask(taskID: String, to column: KanbanColumn) {
        guard let task = store.tasksForSelectedProject.first(where: { $0.id == taskID }) else { return }
        let status = column.targetStatus
        guard task.status != status else { return }
        store.updateTaskStatus(taskID: taskID, status: status)
    }
}

private enum KanbanColumn: String, CaseIterable, Identifiable {
    case backlog
    case ready
    case inProgress
    case needsReview
    case blocked
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .backlog: "Backlog"
        case .ready: "Ready"
        case .inProgress: "In Progress"
        case .needsReview: "Needs Review"
        case .blocked: "Blocked"
        case .done: "Done"
        }
    }

    func contains(_ status: TaskStatus) -> Bool {
        switch self {
        case .backlog:
            return status == .backlog
        case .ready:
            return status == .ready || status == .planning || status == .planReview || status == .approved
        case .inProgress:
            return status == .building || status == .testing
        case .needsReview:
            return status == .readyForReview
        case .blocked:
            return status == .needsFixes || status == .blocked
        case .done:
            return status == .done
        }
    }

    var targetStatus: TaskStatus {
        switch self {
        case .backlog: .backlog
        case .ready: .ready
        case .inProgress: .building
        case .needsReview: .readyForReview
        case .blocked: .blocked
        case .done: .done
        }
    }
}

private struct KanbanDropDelegate: DropDelegate {
    var column: KanbanColumn
    @Binding var dragTargetColumn: KanbanColumn?
    var moveTask: (String, KanbanColumn) -> Void

    func dropEntered(info: DropInfo) {
        dragTargetColumn = column
    }

    func dropExited(info: DropInfo) {
        if dragTargetColumn == column {
            dragTargetColumn = nil
        }
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text])
    }

    func performDrop(info: DropInfo) -> Bool {
        dragTargetColumn = nil
        guard let provider = info.itemProviders(for: [UTType.text]).first else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
            let taskID: String?
            if let data = item as? Data {
                taskID = String(data: data, encoding: .utf8)
            } else if let text = item as? String {
                taskID = text
            } else if let text = item as? NSString {
                taskID = text as String
            } else {
                taskID = nil
            }
            guard let taskID else { return }
            Task { @MainActor in
                moveTask(taskID, column)
            }
        }
        return true
    }
}
