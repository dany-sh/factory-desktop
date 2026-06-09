import FactoryDesktopCore
import SwiftUI

struct ProjectDashboardView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow
    @State private var showActiveTasks = false
    @State private var showArchivedTasks = false
    @State private var showNewWorkItemSheet = false
    @State private var projectMarkdownFiles: [ProjectMarkdownFile] = []
    @State private var workItemDraft = WorkItemDraft()
    @State private var loadedWorkItemID: String?
    @State private var acceptanceText = ""

    var body: some View {
        Group {
            if let project = store.selectedProject {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(project: project)
                        summaryPanel(project: project)
                        topNextWorkPanel
                        backlogPanel
                        kanbanPanel
                        projectDocsPanel(project: project)
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
        .onAppear {
            refreshProjectMarkdownFiles()
            loadBacklogDraft()
        }
        .onChange(of: store.selectedProject?.path) { _, _ in
            refreshProjectMarkdownFiles()
            loadBacklogDraft()
        }
        .onChange(of: store.selectedTaskID) { _, _ in
            loadBacklogDraft()
        }
        .sheet(isPresented: $showNewWorkItemSheet) {
            NewWorkItemView()
                .environmentObject(store)
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
                    DisclosureGroup(isExpanded: $showActiveTasks) {
                        taskList(tasks: activeTasks)
                            .padding(.top, 8)
                    } label: {
                        HStack {
                            Text("Active Tasks")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(activeTasks.count)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                if !archivedTasks.isEmpty {
                    DisclosureGroup(isExpanded: $showArchivedTasks) {
                        taskList(tasks: archivedTasks)
                            .padding(.top, 8)
                    } label: {
                        HStack {
                            Text("Archived / Completed")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(archivedTasks.count)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
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

    private var topNextWorkPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top 3 Next Work")
                .font(.headline)

            if store.nextWorkItems.isEmpty {
                Text("No backlog work items or active tasks yet.")
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
                        Button("Open") {
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

    private var backlogPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Backlog Queue")
                    .font(.headline)
                Spacer()
                Button {
                    showNewWorkItemSheet = true
                } label: {
                    Label("New Work Item", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            if store.backlogTasksForSelectedProject.isEmpty {
                Text("No backlog work items for this project yet.")
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
                        Button("Edit") {
                            store.selectTask(task.id)
                        }
                        .buttonStyle(.bordered)
                        Button(nextActionTitle(for: task)) {
                            store.selectTask(task.id)
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

            if selectedEditableWorkItem != nil {
                Divider()
                workItemEditor
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
            Text("Kanban")
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
        Button {
            store.selectTask(task.id)
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
                    .stroke(.separator.opacity(0.45))
            )
        }
        .buttonStyle(.plain)
    }

    private func projectDocsPanel(project: Project) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Project Docs")
                    .font(.headline)
                Spacer()
                Button {
                    refreshProjectMarkdownFiles()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if projectMarkdownFiles.isEmpty {
                Text("No root-level markdown files found for this project yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(projectMarkdownFiles) { file in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(file.name)
                                .font(.body.weight(.semibold))
                            Text(file.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Button("Open") {
                            openWindow(id: "markdown-document", value: AppStore.normalizedMarkdownPath(file.path))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 3)
                    if file.id != projectMarkdownFiles.last?.id {
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

    private func taskList(tasks: [FactoryTask]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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

    private var activeTasks: [FactoryTask] {
        store.tasksForSelectedProject.filter { $0.status != .done && $0.status != .archived }
    }

    private var archivedTasks: [FactoryTask] {
        store.tasksForSelectedProject.filter { $0.status == .done || $0.status == .archived }
    }

    private func refreshProjectMarkdownFiles() {
        guard let project = store.selectedProject else {
            projectMarkdownFiles = []
            return
        }

        let root = URL(fileURLWithPath: project.path)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            projectMarkdownFiles = []
            return
        }

        projectMarkdownFiles = urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .map { ProjectMarkdownFile(path: $0.path) }
    }

    private var workItemEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Work Item Editor")
                .font(.headline)
            TextField("Title", text: $workItemDraft.title)
            HStack {
                Picker("Kind", selection: $workItemDraft.kind) {
                    ForEach(FactoryTaskKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                Picker("Triage", selection: $workItemDraft.triageStatus) {
                    ForEach(FactoryTaskTriageStatus.allCases) { status in
                        Text(status.displayName).tag(status)
                    }
                }
                Picker("Readiness", selection: $workItemDraft.readiness) {
                    ForEach(FactoryTaskReadiness.allCases) { readiness in
                        Text(readiness.displayName).tag(readiness)
                    }
                }
            }
            HStack {
                Picker("Priority", selection: $workItemDraft.priorityLabel) {
                    ForEach(FactoryTaskPriorityLabel.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                Picker("Effort", selection: $workItemDraft.effort) {
                    ForEach(FactoryTaskEffort.allCases) { effort in
                        Text(effort.displayName).tag(effort)
                    }
                }
                Picker("Risk", selection: $workItemDraft.risk) {
                    ForEach(FactoryTaskRisk.allCases) { risk in
                        Text(risk.displayName).tag(risk)
                    }
                }
            }
            TextField("Category", text: $workItemDraft.category)
            TextField("Source", text: $workItemDraft.source)
            labeledEditor("Goal", text: $workItemDraft.goal, minHeight: 80)
            labeledEditor("Context", text: $workItemDraft.context, minHeight: 110)
            labeledEditor("Acceptance Criteria (one per line)", text: $acceptanceText, minHeight: 90)
            labeledEditor("Scoping Notes", text: $workItemDraft.scopingNotes, minHeight: 60)
            labeledEditor("Dependencies", text: $workItemDraft.dependencies, minHeight: 60)
            labeledEditor("Non-Goals", text: $workItemDraft.nonGoals, minHeight: 60)
            labeledEditor("Suggested Split", text: $workItemDraft.suggestedSplit, minHeight: 60)
            labeledEditor("Recommended Next Action", text: $workItemDraft.recommendedNextAction, minHeight: 60)

            HStack {
                Button("Save") {
                    saveWorkItemDraft()
                }
                .buttonStyle(.borderedProminent)
                Button("Scope") {
                    saveWorkItemDraft()
                    Task { await store.scopeWorkItem() }
                }
                .buttonStyle(.bordered)
                Button("Dispatch") {
                    saveWorkItemDraft()
                    Task { await store.dispatchTask() }
                }
                .buttonStyle(.bordered)
                .disabled(draftWorkItem.readiness != .executable)
                Button("Archive") {
                    store.archiveSelectedWorkItem()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var selectedEditableWorkItem: FactoryTask? {
        guard let task = store.selectedTask, task.projectId == store.selectedProject?.id else {
            return nil
        }
        return task
    }

    private var draftWorkItem: FactoryTask {
        guard let task = selectedEditableWorkItem else {
            return FactoryTask(projectId: store.selectedProject?.id ?? "", title: "")
        }
        return workItemDraft.task(updating: task, acceptanceText: acceptanceText)
    }

    private func loadBacklogDraft() {
        guard let task = selectedEditableWorkItem else {
            workItemDraft = WorkItemDraft()
            acceptanceText = ""
            loadedWorkItemID = nil
            return
        }
        guard loadedWorkItemID != task.id else { return }
        workItemDraft = WorkItemDraft(task: task)
        acceptanceText = task.acceptanceCriteria.joined(separator: "\n")
        loadedWorkItemID = task.id
    }

    private func saveWorkItemDraft() {
        guard let task = selectedEditableWorkItem else { return }
        let updated = workItemDraft.task(updating: task, acceptanceText: acceptanceText)
        store.saveTask(updated)
        loadedWorkItemID = updated.id
    }

    private func open(_ item: BacklogNextWorkItem) {
        switch item.kind {
        case .task(let task):
            store.selectTask(task.id)
        }
    }

    private func trigger(_ item: BacklogNextWorkItem) {
        switch item.primaryAction {
        case .scope:
            if case .task(let task) = item.kind {
                store.selectTask(task.id)
                Task { await store.scopeWorkItem() }
            }
        case .dispatch:
            if case .task(let task) = item.kind {
                store.selectTask(task.id)
                Task { await store.dispatchTask() }
            }
        case .continueRun:
            if case .task(let task) = item.kind {
                store.selectTask(task.id)
                Task { await store.continueRunnerSession() }
            }
        case .reviewDiff, .runTests, .syncLifecycle, .needsManualReview, .noAction:
            open(item)
        }
    }

    private func labeledEditor(_ title: String, text: Binding<String>, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: text)
                .frame(minHeight: minHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator.opacity(0.5))
                )
        }
    }
}

private struct ProjectMarkdownFile: Identifiable, Equatable {
    var path: String

    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

private struct WorkItemDraft {
    var title = ""
    var kind: FactoryTaskKind = .idea
    var triageStatus: FactoryTaskTriageStatus = .backlog
    var readiness: FactoryTaskReadiness = .raw
    var priorityLabel: FactoryTaskPriorityLabel = .normal
    var category = ""
    var source = ""
    var goal = ""
    var context = ""
    var effort: FactoryTaskEffort = .unknown
    var risk: FactoryTaskRisk = .unknown
    var scopingNotes = ""
    var dependencies = ""
    var nonGoals = ""
    var suggestedSplit = ""
    var recommendedNextAction = ""

    init() {}

    init(task: FactoryTask) {
        title = task.title
        kind = task.kind
        triageStatus = task.triageStatus
        readiness = task.readiness
        priorityLabel = task.priorityLabel
        category = task.category
        source = task.source
        goal = task.goal
        context = task.context
        effort = task.effort
        risk = task.risk
        scopingNotes = task.scopingNotes
        dependencies = task.dependencies
        nonGoals = task.nonGoals
        suggestedSplit = task.suggestedSplit
        recommendedNextAction = task.recommendedNextAction
    }

    func task(updating task: FactoryTask, acceptanceText: String) -> FactoryTask {
        var updated = task
        updated.title = title
        updated.kind = kind
        updated.triageStatus = triageStatus
        updated.readiness = readiness
        updated.priorityLabel = priorityLabel
        updated.priority = priorityLabel.taskPriority
        updated.category = category
        updated.source = source
        updated.goal = goal
        updated.context = context
        updated.effort = effort
        updated.risk = risk
        updated.scopingNotes = scopingNotes
        updated.dependencies = dependencies
        updated.nonGoals = nonGoals
        updated.suggestedSplit = suggestedSplit
        updated.recommendedNextAction = recommendedNextAction
        updated.acceptanceCriteria = acceptanceText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return updated
    }
}
