import FactoryDesktopCore
import SwiftUI

struct ProjectDashboardView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow
    @State private var showActiveTasks = false
    @State private var showArchivedTasks = false
    @State private var showNewBacklogIdeaSheet = false
    @State private var projectMarkdownFiles: [ProjectMarkdownFile] = []
    @State private var backlogDraft = BacklogIdeaDraft()
    @State private var loadedBacklogIdeaID: String?
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
        .onChange(of: store.selectedBacklogIdeaID) { _, _ in
            loadBacklogDraft()
        }
        .sheet(isPresented: $showNewBacklogIdeaSheet) {
            NewBacklogIdeaView()
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
                Text("No backlog ideas or active tasks yet.")
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
                Text("Backlog Queue + Runner Orchestration")
                    .font(.headline)
                Spacer()
                Button {
                    showNewBacklogIdeaSheet = true
                } label: {
                    Label("New Idea", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            if store.backlogIdeasForSelectedProject.isEmpty {
                Text("No backlog ideas for this project yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.backlogIdeasForSelectedProject) { idea in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(idea.title)
                                .font(.body.weight(.semibold))
                            Text("\(idea.priorityLevel.displayName) · \(idea.status.displayName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit") {
                            store.selectBacklogIdea(idea.id)
                        }
                        .buttonStyle(.bordered)
                        Button(idea.isReadyToPromote ? "Promote" : "Scope") {
                            if idea.isReadyToPromote {
                                Task { await store.promoteSelectedBacklogIdeaToTask() }
                            } else {
                                store.selectBacklogIdea(idea.id)
                                Task { await store.scopeBacklogIdea() }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 3)
                    if idea.id != store.backlogIdeasForSelectedProject.last?.id {
                        Divider()
                    }
                }
            }

            if store.selectedBacklogIdea != nil {
                Divider()
                backlogEditor
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator.opacity(0.6))
        )
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

    private var backlogEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Backlog Idea Editor")
                .font(.headline)
            TextField("Title", text: $backlogDraft.title)
            HStack {
                Picker("Priority", selection: $backlogDraft.priorityLevel) {
                    ForEach(BacklogPriorityLevel.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                Picker("Effort", selection: $backlogDraft.effort) {
                    ForEach(BacklogEffort.allCases) { effort in
                        Text(effort.displayName).tag(effort)
                    }
                }
                Picker("Risk", selection: $backlogDraft.risk) {
                    ForEach(BacklogRisk.allCases) { risk in
                        Text(risk.displayName).tag(risk)
                    }
                }
            }
            TextField("Category", text: $backlogDraft.category)
            TextField("Source", text: $backlogDraft.source)
            labeledEditor("Goal", text: $backlogDraft.goal, minHeight: 80)
            labeledEditor("Context", text: $backlogDraft.context, minHeight: 110)
            labeledEditor("Acceptance Criteria (one per line)", text: $acceptanceText, minHeight: 90)
            labeledEditor("Dependencies", text: $backlogDraft.dependencies, minHeight: 60)
            labeledEditor("Non-Goals", text: $backlogDraft.nonGoals, minHeight: 60)
            labeledEditor("Suggested Task Split", text: $backlogDraft.suggestedTaskSplit, minHeight: 60)
            labeledEditor("Recommended Next Action", text: $backlogDraft.recommendedNextAction, minHeight: 60)

            HStack {
                Button("Save") {
                    saveBacklogDraft()
                }
                .buttonStyle(.borderedProminent)
                Button("Scope") {
                    saveBacklogDraft()
                    Task { await store.scopeBacklogIdea() }
                }
                .buttonStyle(.bordered)
                Button("Promote") {
                    saveBacklogDraft()
                    Task { await store.promoteSelectedBacklogIdeaToTask() }
                }
                .buttonStyle(.bordered)
                .disabled(!draftIdea.isReadyToPromote)
                Button("Archive") {
                    store.archiveSelectedBacklogIdea()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var draftIdea: BacklogIdea {
        guard let idea = store.selectedBacklogIdea else {
            return BacklogIdea(projectId: store.selectedProject?.id ?? "", title: "")
        }
        return backlogDraft.idea(updating: idea, acceptanceText: acceptanceText)
    }

    private func loadBacklogDraft() {
        guard let idea = store.selectedBacklogIdea else {
            backlogDraft = BacklogIdeaDraft()
            acceptanceText = ""
            loadedBacklogIdeaID = nil
            return
        }
        guard loadedBacklogIdeaID != idea.id else { return }
        backlogDraft = BacklogIdeaDraft(idea: idea)
        acceptanceText = idea.acceptanceCriteria.joined(separator: "\n")
        loadedBacklogIdeaID = idea.id
    }

    private func saveBacklogDraft() {
        guard let idea = store.selectedBacklogIdea else { return }
        let updated = backlogDraft.idea(updating: idea, acceptanceText: acceptanceText)
        store.saveBacklogIdea(updated)
        loadedBacklogIdeaID = updated.id
    }

    private func open(_ item: BacklogNextWorkItem) {
        switch item.kind {
        case .idea(let idea):
            store.selectBacklogIdea(idea.id)
        case .task(let task):
            store.selectTask(task.id)
        }
    }

    private func trigger(_ item: BacklogNextWorkItem) {
        switch item.primaryAction {
        case .scopeIdea:
            if case .idea(let idea) = item.kind {
                store.selectBacklogIdea(idea.id)
                Task { await store.scopeBacklogIdea() }
            }
        case .promoteToTask:
            if case .idea(let idea) = item.kind {
                store.selectBacklogIdea(idea.id)
                Task { await store.promoteSelectedBacklogIdeaToTask() }
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

private struct BacklogIdeaDraft {
    var title = ""
    var priorityLevel: BacklogPriorityLevel = .p2
    var category = ""
    var source = ""
    var goal = ""
    var context = ""
    var effort: BacklogEffort = .unknown
    var risk: BacklogRisk = .unknown
    var dependencies = ""
    var nonGoals = ""
    var suggestedTaskSplit = ""
    var recommendedNextAction = ""

    init() {}

    init(idea: BacklogIdea) {
        title = idea.title
        priorityLevel = idea.priorityLevel
        category = idea.category
        source = idea.source
        goal = idea.goal
        context = idea.context
        effort = idea.effort
        risk = idea.risk
        dependencies = idea.dependencies
        nonGoals = idea.nonGoals
        suggestedTaskSplit = idea.suggestedTaskSplit
        recommendedNextAction = idea.recommendedNextAction
    }

    func idea(updating idea: BacklogIdea, acceptanceText: String) -> BacklogIdea {
        var updated = idea
        updated.title = title
        updated.priorityLevel = priorityLevel
        updated.category = category
        updated.source = source
        updated.goal = goal
        updated.context = context
        updated.effort = effort
        updated.risk = risk
        updated.dependencies = dependencies
        updated.nonGoals = nonGoals
        updated.suggestedTaskSplit = suggestedTaskSplit
        updated.recommendedNextAction = recommendedNextAction
        updated.acceptanceCriteria = acceptanceText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return updated
    }
}
