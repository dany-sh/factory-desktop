import FactoryDesktopCore
import SwiftUI

struct TaskDetailView: View {
    @EnvironmentObject private var store: AppStore
    @State private var draft = TaskDraft()
    @State private var acceptanceText = ""
    @State private var loadedTaskID: String?
    @State private var selectedStage: TaskWorkspaceStage = .overview
    @State private var isTaskBriefExpanded = false
    @State private var showAllArtifacts = false
    @FocusState private var focusedField: TaskEditorField?

    var body: some View {
        Group {
            if let task = store.selectedTask {
                VStack(alignment: .leading, spacing: 18) {
                    header(task: task)
                    Picker("Stage", selection: $selectedStage) {
                        ForEach(TaskWorkspaceStage.allCases) { stage in
                            Text(stage.title).tag(stage)
                        }
                    }
                    .pickerStyle(.segmented)

                    ScrollView {
                        taskWorkspaceContent(task: task)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollDismissesKeyboard(.never)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Button("Save Task") {
                            save(task)
                        }
                        .keyboardShortcut("s", modifiers: [.command])

                        if draft.hasChanges(comparedTo: task, acceptanceText: acceptanceText) {
                            Text("Unsaved changes")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }

                        Spacer()

                        Button("Delete", role: .destructive) {
                            store.deleteSelectedTask()
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.bar)
                }
                .onAppear {
                    loadIfNeeded(task)
                }
                .onChange(of: task.id) { _, _ in
                    loadIfNeeded(task)
                }
            } else {
                ContentUnavailableView(
                    "No Task Selected",
                    systemImage: "tray",
                    description: Text("Create a task to start intake, planning, handoff, and review.")
                )
                .onAppear {
                    loadedTaskID = nil
                    draft = TaskDraft()
                    acceptanceText = ""
                    focusedField = nil
                }
            }
        }
    }

    private func header(task: FactoryTask) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(task.title)
                        .font(.title2.weight(.semibold))
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        statusMenu(task: task)
                        Button {
                            store.showProjectWorkspace()
                        } label: {
                            StatusPill(text: "Project View")
                        }
                        .buttonStyle(.plain)
                        StatusPill(text: task.type.displayName)
                        StatusPill(text: task.priority.displayName)
                        Text(task.id.shortID)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    worktreeSummaryLine
                }
                Spacer()
                if store.isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
                compactPrimaryAction
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator.opacity(0.6))
        )
    }

    private func statusMenu(task: FactoryTask) -> some View {
        Menu {
            ForEach(TaskStatus.allCases.sorted { $0.sortOrder < $1.sortOrder }) { status in
                Button {
                    store.updateSelectedTaskStatus(status)
                } label: {
                    if status == task.status {
                        Label(status.displayName, systemImage: "checkmark")
                    } else {
                        Text(status.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(task.status.category.color)
                    .frame(width: 7, height: 7)
                Text(task.status.displayName)
                    .font(.caption.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(task.status.category.color.opacity(0.14), in: Capsule())
            .foregroundStyle(task.status.category.color)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Task status")
    }

    private func taskForm(task: FactoryTask) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Title", text: $draft.title)
                .font(.title3)
                .focused($focusedField, equals: .title)

            HStack {
                Picker("Type", selection: $draft.type) {
                    ForEach(TaskType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                Picker("Priority", selection: $draft.priority) {
                    ForEach(TaskPriority.allCases) { priority in
                        Text(priority.displayName).tag(priority)
                    }
                }
            }

            LabeledTextEditor(
                title: "Goal",
                text: $draft.goal,
                minHeight: 90,
                focusedField: $focusedField,
                field: .goal
            )
            LabeledTextEditor(
                title: "Context",
                text: $draft.context,
                minHeight: 110,
                focusedField: $focusedField,
                field: .context
            )
            LabeledTextEditor(
                title: "Acceptance criteria (one per line)",
                text: $acceptanceText,
                minHeight: 90,
                focusedField: $focusedField,
                field: .acceptanceCriteria
            )
        }
    }

    private func save(_ task: FactoryTask) {
        store.saveTask(draft.task(updating: task, acceptanceText: acceptanceText))
    }

    @ViewBuilder
    private func taskWorkspaceContent(task: FactoryTask) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            switch selectedStage {
            case .overview:
                overviewSection(task: task)
            case .planReview:
                planReviewSection
            case .buildTest:
                buildTestSection
            case .diff:
                diffSection
            case .artifacts:
                artifactsSection
            }
        }
        .padding(.bottom, 28)
    }

    private var compactPrimaryAction: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Next Action")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let task = store.selectedTask, task.status == .archived || task.status == .done {
                completedTaskNextAction(task)
            } else if let review = store.latestTaskStateReview {
                primaryActionButton(review.recommendedAction)
            } else {
                Button {
                    Task { await store.reviewTaskState() }
                } label: {
                    Label("Review Task State", systemImage: "list.bullet.clipboard")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.selectedTask == nil || store.isWorking)
            }
        }
        .frame(minWidth: 210, alignment: .leading)
    }

    private func completedTaskNextAction(_ task: FactoryTask) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.status == .archived ? "Archived" : "No action required")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Button("Reopen Task") {}
                .disabled(true)
                .help("Foundation-only placeholder.")
        }
    }

    private var worktreeSummaryLine: some View {
        let displays = store.selectedTaskWorktreeDisplays
        return Group {
            if displays.isEmpty {
                Text("Task worktree: missing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if displays.contains(where: { $0.state == .missingPath }) {
                Text("Missing Worktree")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            } else {
                Text(displays.map { "\($0.label): \($0.branch ?? "no branch") (\($0.state.displayName))" }.joined(separator: "  |  "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var selectedCodeWorktreeUnavailable: Bool {
        store.selectedProject?.type == .codeRepo && !store.selectedTaskCanUseWorktree
    }

    private func overviewSection(task: FactoryTask) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            taskStatePanel
            workflowHealthPanel
            recentEventsPanel
            projectStatusPanel
            taskWorktreePanel
            preflightPanel
            DisclosureGroup("Task Brief", isExpanded: $isTaskBriefExpanded) {
                taskForm(task: task)
            }
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.separator.opacity(0.6))
            )
        }
    }

    private var projectStatusPanel: some View {
        let summary = store.taskProjectStatusSummary
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Project Status")
                        .font(.headline)
                    Text("Task view stays focused on task execution. Open the project workspace for repo-wide cleanup, archived references, branches, and artifact waste.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(summary.hygieneSeverity.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(hygieneSeverityColor(summary.hygieneSeverity))
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                InfoChip(label: "Project Cleanup", value: "\(summary.projectCleanupCount)")
                InfoChip(label: "Blockers", value: "\(summary.blockerCount)")
                InfoChip(label: "Preflight", value: store.projectStatusSummary.preflightStatus)
                InfoChip(label: "Repo", value: store.projectStatusSummary.workingTreeState)
            }

            Text(summary.message)
                .font(summary.hasProjectIssue ? .subheadline.weight(.semibold) : .caption)
                .foregroundStyle(summary.blockerCount > 0 ? .red : .secondary)

            HStack {
                Button {
                    store.showProjectWorkspace()
                } label: {
                    Label("Open Project Workspace", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await store.refreshLifecycleScan() }
                } label: {
                    Label("Refresh Scan", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(store.selectedProject == nil || store.isWorking)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator.opacity(0.6))
        )
    }

    private func hygieneSeverityColor(_ severity: HygieneSeverity) -> Color {
        switch severity {
        case .safe: .green
        case .warning: .orange
        case .blocked: .red
        case .informational: .secondary
        }
    }

    private var workflowHealthPanel: some View {
        let health = store.taskWorkflowHealth
        return VStack(alignment: .leading, spacing: 12) {
            Text("Workflow Health")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                InfoChip(label: "Task Status", value: store.selectedTask?.status.displayName ?? "Unknown")
                InfoChip(label: "Worktree", value: health.worktree)
                InfoChip(label: "Preflight", value: health.preflight)
                InfoChip(label: "Plan", value: health.plan)
                InfoChip(label: "Implementation", value: health.implementation)
                InfoChip(label: "Tests", value: health.tests)
                InfoChip(label: "Diff Review", value: health.diffReview)
                InfoChip(label: "Next", value: health.nextAction)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator.opacity(0.6))
        )
    }

    private var recentEventsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Events")
                .font(.headline)
            if store.taskEvents.isEmpty {
                Text("No task events yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.taskEvents.prefix(6)) { event in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: event.source == .manual ? "person.crop.circle" : "gearshape")
                            .foregroundStyle(event.source == .manual ? Color.accentColor : .secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(event.kind.displayName)
                                    .font(.subheadline.weight(.semibold))
                                if let newStatus = event.newStatus {
                                    Text(newStatus.displayName)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(newStatus.category.color)
                                }
                            }
                            if !event.message.isEmpty {
                                Text(event.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Text(event.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
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

    private var taskWorktreePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Task Worktree")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await store.createWorktree(flavor: .local) }
                } label: {
                    Label("Create Task Worktree", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .disabled(store.selectedTask == nil || store.selectedTask?.localWorktreePath != nil || store.isWorking)
                Button {
                    Task { await store.createWorktree(flavor: .codex) }
                } label: {
                    Label("Create Alternate Worktree", systemImage: "terminal")
                }
                .disabled(store.selectedTask == nil || store.selectedTask?.codexWorktreePath != nil || store.isWorking)
            }

            if store.selectedTaskWorktreeDisplays.isEmpty {
                Text("No task worktree exists yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.selectedTaskWorktreeDisplays) { display in
                    TaskWorktreeReferenceView(display: display)
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

    private var workflowBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Controlled Workflow")
                .font(.headline)
            HStack {
                Picker("Planner model", selection: $store.selectedModel) {
                    ForEach(ModelPolicy.recommendedModels) { model in
                        Text("\(model.id) · \(model.role)").tag(model.id)
                    }
                }
                .frame(maxWidth: 340)

                Button {
                    Task { await store.runPreflightCheck() }
                } label: {
                    Label("Preflight Check", systemImage: "checklist.checked")
                }
                .disabled(store.isWorking)

                Button {
                    Task { await store.reviewTaskState() }
                } label: {
                    Label("Review Task State", systemImage: "list.bullet.clipboard")
                }
                .disabled(store.isWorking)

                Button {
                    Task { await store.planLocally() }
                } label: {
                    Label("Plan Locally", systemImage: "brain")
                }
                .disabled(store.isWorking || !store.canPlanSelectedTaskLocally)

                Button {
                    store.generateCodexPlanReviewHandoff()
                } label: {
                    Label("Generate Codex Plan Review Handoff", systemImage: "doc.text.magnifyingglass")
                }
                .disabled(store.isWorking || store.latestPlanArtifact == nil)
            }
            Text("Factory v0.1 plans and records. It does not autonomously edit files.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let warning = store.selectedTaskWorktreeWarning {
                Text(warning)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.separator.opacity(0.6))
        )
    }

    private var preflightPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Preflight")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await store.runPreflightCheck() }
                } label: {
                    Label("Run", systemImage: "checklist.checked")
                }
                .disabled(store.isWorking)
            }

            if let report = store.latestPreflightReport {
                HStack(spacing: 16) {
                    InfoChip(label: "Recommendation", value: report.overallRecommendation.displayName)
                    InfoChip(label: "Dirty", value: "\(report.dirtyTargetCount)")
                    InfoChip(label: "Missing", value: "\(report.missingPathCount)")
                    InfoChip(label: "Unpushed", value: "\(report.unpushedCount)")
                }
            } else {
                Text("Run Preflight Check to inspect the project repo and task worktrees.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.separator.opacity(0.6))
        )
    }

    private var taskStatePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Task State Review")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await store.syncSelectedTaskLifecycle() }
                } label: {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(store.isWorking)
                Button {
                    Task { await store.reviewTaskState() }
                } label: {
                    Label("Review", systemImage: "list.bullet.clipboard")
                }
                .disabled(store.isWorking)
            }

            if let review = store.latestTaskStateReview {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Primary Next Action")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(review.recommendedAction.displayName)
                        .font(.title3.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                HStack(spacing: 16) {
                    InfoChip(label: "Next", value: review.recommendedAction.displayName)
                    InfoChip(label: "Plan", value: review.hasPlan ? "yes" : "no")
                    InfoChip(label: "Review", value: review.hasPlanReview ? "yes" : "no")
                    InfoChip(label: "Preflight", value: review.hasPreflight ? (review.hasRiskyPreflight ? "risk" : "yes") : "no")
                    InfoChip(label: "Tests", value: review.hasTestOutput ? "yes" : "no")
                    InfoChip(label: "Diff", value: review.hasDiffReview ? "yes" : "no")
                }
                Text(review.summary)
                    .foregroundStyle(.secondary)
                if review.hasPlan && !review.hasPlanReview {
                    Text("Plan exists but has not been reviewed.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            } else if !store.latestTaskStateReviewText.isEmpty {
                ScrollView {
                    Text(store.latestTaskStateReviewText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(minHeight: 180)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            } else {
                Text("Review Task State to summarize artifacts, worktrees, preflight, tests, diff review, and the next action.")
                    .foregroundStyle(.secondary)
            }

            LifecycleSyncSummaryView(
                result: store.latestLifecycleSyncResult,
                emptyMessage: "Sync lifecycle to inspect Git-backed lifecycle facts."
            )
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.separator.opacity(0.6))
        )
    }

    private var planPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Plan")
                    .font(.headline)
                Spacer()
                if let artifact = store.latestPlanArtifact {
                    Text(artifact.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if store.latestPlanText.isEmpty {
                Text("No saved plan yet. Run Plan Locally to create plan.md.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    Text(store.latestPlanText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(minHeight: 260)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            }

            if !store.latestPlanReviewText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Latest Plan Review")
                        .font(.subheadline.weight(.semibold))
                    ScrollView {
                        Text(store.latestPlanReviewText)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .frame(minHeight: 180)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.separator.opacity(0.6))
        )
    }

    private var planReviewSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(store.latestApprovedPlanArtifact == nil ? "Current Plan" : "Approved Plan")
                        .font(.headline)
                    Spacer()
                    if let artifact = store.currentPlanArtifact {
                        artifactPath(artifact)
                    }
                }

                if store.currentPlanText.isEmpty {
                    Text("No saved plan yet.")
                        .foregroundStyle(.secondary)
                } else {
                    markdownBox(store.currentPlanText, minHeight: 320)
                }

                if !store.latestPlanReviewText.isEmpty {
                    Divider()
                    HStack {
                        Text("Latest Plan Review")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(AppStore.parsePlanReviewDecision(from: store.latestPlanReviewText).rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(store.latestApprovedPlanArtifact == nil ? .secondary : .tertiary)
                    }
                    if store.latestApprovedPlanArtifact != nil {
                        Text("Approved plan is the current planning signal; older review decisions are history.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    markdownBox(store.latestPlanReviewText, minHeight: 180)
                }
            }
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.separator.opacity(0.6))
            )

            actionPanel(title: "Plan Actions") {
                actionButton("Plan Locally", systemImage: "brain", prominent: store.latestTaskStateReview?.recommendedAction == .planLocally) {
                    Task { await store.planLocally() }
                }
                .disabled(store.isWorking || !store.canPlanSelectedTaskLocally)
                actionButton("Review Plan Locally", systemImage: "checklist", prominent: store.latestTaskStateReview?.recommendedAction == .reviewPlanLocally) {
                    Task { await store.reviewPlanLocally() }
                }
                .disabled(store.isWorking || store.latestPlanArtifact == nil)
                actionButton("Generate Codex Plan Review Handoff", systemImage: "doc.text.magnifyingglass") {
                    store.generateCodexPlanReviewHandoff()
                }
                .disabled(store.isWorking || store.latestPlanArtifact == nil)
                actionButton("Approve Plan", systemImage: "hand.thumbsup", prominent: store.latestTaskStateReview?.recommendedAction == .approvePlan) {
                    store.approvePlan()
                }
                .disabled(store.isWorking || store.latestPlanArtifact == nil)
            }
        }
    }

    private var buildTestSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Build & Test Status")
                        .font(.headline)
                    Spacer()
                    InfoChip(label: "Changed", value: "\(store.gitSnapshot.changedFiles.count)")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                    ForEach(store.workflowCheckSummaries) { summary in
                        WorkflowCheckCard(summary: summary)
                    }
                }
                changedFilesList
            }
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.separator.opacity(0.6))
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Latest Test Output")
                        .font(.headline)
                    Spacer()
                    if let artifact = store.latestTestOutputArtifact {
                        artifactPath(artifact)
                    }
                }
                if store.latestTestOutputText.isEmpty {
                    Text("No test output artifact yet.")
                        .foregroundStyle(.secondary)
                } else {
                    markdownBox(store.latestTestOutputText, minHeight: 240)
                }
            }
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.separator.opacity(0.6))
            )

            actionPanel(title: "Build & Test Actions") {
                let hasChanges = store.latestTaskStateReview?.hasImplementationChanges == true || !store.gitSnapshot.changedFiles.isEmpty
                actionButton("Build", systemImage: "hammer", prominent: store.latestTaskStateReview?.recommendedAction == .buildLocally && !hasChanges) {
                    Task { await store.runWorkflowCommand(.build) }
                }
                .disabled(store.isWorking || selectedCodeWorktreeUnavailable)
                actionButton("Unit Tests", systemImage: "checkmark.seal", prominent: store.latestTaskStateReview?.recommendedAction == .runTests || hasChanges) {
                    Task { await store.runWorkflowCommand(.unitTests) }
                }
                .disabled(store.isWorking || selectedCodeWorktreeUnavailable)
                actionButton("Integration Tests", systemImage: "checklist", prominent: false) {
                    Task { await store.runWorkflowCommand(.integrationTests) }
                }
                .disabled(store.isWorking || selectedCodeWorktreeUnavailable)
                actionButton("E2E Tests", systemImage: "rectangle.connected.to.line.below", prominent: false) {
                    Task { await store.runWorkflowCommand(.e2eTests) }
                }
                .disabled(store.isWorking || selectedCodeWorktreeUnavailable)
                actionButton("Visual QC", systemImage: "eye", prominent: false) {
                    Task { await store.runWorkflowCommand(.visualQC) }
                }
                .disabled(store.isWorking || selectedCodeWorktreeUnavailable)
                actionButton("Generate Codex Build Handoff", systemImage: "paperplane") {
                    store.generateCodexHandoff()
                }
                .disabled(store.isWorking || store.selectedTask == nil || selectedCodeWorktreeUnavailable)
            }
        }
    }

    private var diffSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Diff Summary")
                    .font(.headline)
                HStack(spacing: 12) {
                    InfoChip(label: "Changed", value: "\(store.gitSnapshot.changedFiles.count)")
                    InfoChip(label: "Tests", value: store.taskWorkflowHealth.tests)
                    InfoChip(label: "Diff Review", value: store.taskWorkflowHealth.diffReview)
                    InfoChip(label: "Readiness", value: store.latestTaskStateReview?.recommendedAction == .commitAndMerge ? "ready" : "not ready")
                }
                changedFilesList
                Text(store.gitSnapshot.diffStat.isEmpty ? "(empty)" : store.gitSnapshot.diffStat)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.separator.opacity(0.6))
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Latest Diff Review")
                        .font(.headline)
                    Spacer()
                    if let artifact = store.latestDiffReviewArtifact {
                        artifactPath(artifact)
                    }
                }
                if store.latestDiffReviewText.isEmpty {
                    Text("No diff review artifact yet.")
                        .foregroundStyle(.secondary)
                } else {
                    markdownBox(store.latestDiffReviewText, minHeight: 240)
                }
            }
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.separator.opacity(0.6))
            )

            actionPanel(title: "Diff Actions") {
                actionButton("Review Diff Locally", systemImage: "doc.text.magnifyingglass", prominent: store.latestTaskStateReview?.recommendedAction == .reviewDiff) {
                    Task { await store.reviewDiffLocally() }
                }
                .disabled(store.isWorking || store.gitSnapshot.changedFiles.isEmpty || selectedCodeWorktreeUnavailable)
                actionButton("Generate Codex Diff Review Handoff", systemImage: "paperplane") {
                    store.askCodexToReviewDiff()
                }
                .disabled(store.isWorking || store.gitSnapshot.changedFiles.isEmpty || selectedCodeWorktreeUnavailable)
                actionButton("Generate Commit Note", systemImage: "doc.badge.clock") {
                    store.generateReviewNote()
                }
                .disabled(store.isWorking || store.gitSnapshot.changedFiles.isEmpty)
                Text("Commit and merge remain outside this workspace flow.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var artifactsSection: some View {
        let groups = store.artifactDisplayGroups
        return VStack(alignment: .leading, spacing: 18) {
            Toggle("Show All Artifacts", isOn: $showAllArtifacts)
                .toggleStyle(.switch)

            artifactGroup(title: "Current", artifacts: groups.current, initiallyExpanded: true)
            artifactGroup(title: "History", artifacts: groups.history, initiallyExpanded: showAllArtifacts)
            artifactGroup(title: "Raw Logs / Prompts", artifacts: groups.rawLogs, initiallyExpanded: showAllArtifacts)
        }
    }

    private var changedFilesList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Changed Files")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if store.gitSnapshot.changedFiles.isEmpty {
                Text("No changed files detected.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.gitSnapshot.changedFiles, id: \.self) { file in
                    Text(file)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var runLog: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Run Log")
                .font(.headline)

            if store.runsForSelectedTask.isEmpty {
                Text("No runs yet. Local planner output, test output, and future executor runs will appear here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.runsForSelectedTask) { run in
                    Button {
                        store.loadRunOutput(run)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(run.summary.isEmpty ? run.executor : run.summary)
                                    .font(.body)
                                Text("\(run.executor) \(run.model ?? "") · \(run.status.rawValue) · \(run.id.shortID)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    Text("Started \(run.startedAt.formatted(date: .abbreviated, time: .shortened))")
                                    Text("Duration \(run.durationText)")
                                    if let outputPath = run.outputPath {
                                        Text(URL(fileURLWithPath: outputPath).lastPathComponent)
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Text(run.status.rawValue.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }

            if !store.selectedRunOutput.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected Output")
                        .font(.subheadline.weight(.semibold))
                    ScrollView {
                        Text(store.selectedRunOutput)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .frame(minHeight: 220)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    @ViewBuilder
    private func primaryActionButton(_ action: TaskStateRecommendedAction) -> some View {
        switch action {
        case .createWorktree:
            actionButton("Create Task Worktree", systemImage: "point.3.connected.trianglepath.dotted", prominent: true) {
                Task { await store.createWorktree(flavor: .local) }
            }
        case .runPreflight, .inspectPreflightFixGitState:
            actionButton(action.displayName, systemImage: "checklist.checked", prominent: true) {
                Task { await store.runPreflightCheck() }
            }
        case .planLocally, .revisePlan:
            actionButton(action.displayName, systemImage: "brain", prominent: true) {
                Task { await store.planLocally() }
            }
            .disabled(store.isWorking || !store.canPlanSelectedTaskLocally)
        case .reviewPlanLocally:
            actionButton("Review Plan", systemImage: "checklist", prominent: true) {
                Task { await store.reviewPlanLocally() }
            }
        case .askCodexToReviewPlan:
            actionButton("Generate Plan Review Handoff", systemImage: "doc.text.magnifyingglass", prominent: true) {
                store.generateCodexPlanReviewHandoff()
            }
        case .approvePlan:
            actionButton(action.displayName, systemImage: "hand.thumbsup", prominent: true) {
                store.approvePlan()
            }
        case .buildLocally:
            actionButton("Build", systemImage: "hammer", prominent: true) {
                Task { await store.runWorkflowCommand(.build) }
            }
            .disabled(selectedCodeWorktreeUnavailable)
        case .runTests:
            actionButton(action.displayName, systemImage: "checkmark.seal", prominent: true) {
                Task { await store.runWorkflowCommand(.unitTests) }
            }
            .disabled(selectedCodeWorktreeUnavailable)
        case .reviewDiff:
            actionButton(action.displayName, systemImage: "doc.text.magnifyingglass", prominent: true) {
                Task { await store.reviewDiffLocally() }
            }
            .disabled(selectedCodeWorktreeUnavailable)
        case .commitAndMerge:
            Text("Ready to Commit")
                .font(.headline)
        case .archive:
            Text("Archive")
                .font(.headline)
        case .noActionRequired:
            VStack(alignment: .leading, spacing: 6) {
                Text(store.selectedTask?.status == .archived ? "Archived" : "No action required")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Button("Reopen Task") {}
                    .disabled(true)
                    .help("Foundation-only placeholder.")
            }
        case .investigate:
            actionButton(action.displayName, systemImage: "list.bullet.clipboard", prominent: true) {
                Task { await store.reviewTaskState() }
            }
        }
    }

    private func actionPanel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], alignment: .leading, spacing: 10) {
                content()
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator.opacity(0.6))
        )
    }

    @ViewBuilder
    private func actionButton(_ title: String, systemImage: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        if prominent {
            Button(action: action) {
                Label(title, systemImage: systemImage)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button(action: action) {
                Label(title, systemImage: systemImage)
            }
            .buttonStyle(.bordered)
        }
    }

    private func markdownBox(_ text: String, minHeight: CGFloat) -> some View {
        ScrollView {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .frame(minHeight: minHeight)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private func artifactPath(_ artifact: Artifact) -> some View {
        Button {
            Task { await store.openArtifact(artifact) }
        } label: {
            Label("Open Artifact", systemImage: "arrow.up.forward.app")
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private func artifactGroup(title: String, artifacts: [Artifact], initiallyExpanded: Bool) -> some View {
        if initiallyExpanded {
            artifactGroupBody(title: title, artifacts: artifacts)
        } else {
            DisclosureGroup(title) {
                artifactRows(artifacts)
                    .padding(.top, 8)
            }
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.separator.opacity(0.6))
            )
        }
    }

    private func artifactGroupBody(title: String, artifacts: [Artifact]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            artifactRows(artifacts)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator.opacity(0.6))
        )
    }

    @ViewBuilder
    private func artifactRows(_ artifacts: [Artifact]) -> some View {
        if artifacts.isEmpty {
            Text("No artifacts.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(artifacts) { artifact in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(artifact.artifactType?.displayName ?? artifact.type)
                            .font(.subheadline.weight(.semibold))
                        Text(artifact.path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    artifactPath(artifact)
                }
                .padding(.vertical, 5)
                if artifact.id != artifacts.last?.id {
                    Divider()
                }
            }
        }
    }

    private func loadIfNeeded(_ task: FactoryTask) {
        guard loadedTaskID != task.id else { return }
        load(task)
    }

    private func load(_ task: FactoryTask) {
        draft = TaskDraft(task: task)
        acceptanceText = task.acceptanceCriteria.joined(separator: "\n")
        loadedTaskID = task.id
        focusedField = nil
    }
}

private enum TaskEditorField: Hashable {
    case title
    case goal
    case context
    case acceptanceCriteria
}

private enum TaskWorkspaceStage: String, CaseIterable, Identifiable {
    case overview
    case planReview
    case buildTest
    case diff
    case artifacts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .planReview: "Plan & Review"
        case .buildTest: "Build & Test"
        case .diff: "Diff"
        case .artifacts: "Artifacts"
        }
    }
}

private struct LabeledTextEditor: View {
    var title: String
    @Binding var text: String
    var minHeight: CGFloat
    var focusedField: FocusState<TaskEditorField?>.Binding
    var field: TaskEditorField

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.body)
                .focused(focusedField, equals: field)
                .frame(height: minHeight)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct StatusPill: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.14), in: Capsule())
            .foregroundStyle(Color.accentColor)
    }
}

private struct WorkflowCheckCard: View {
    var summary: WorkflowCheckSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(summary.kind.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Circle()
                    .fill(summary.status.color)
                    .frame(width: 7, height: 7)
            }
            Text(summary.status.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(summary.status.color)
            if let run = summary.run {
                Text("\(run.id.shortID) · \(run.durationText)\(run.exitCode.map { " · exit \($0)" } ?? "")")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            } else if let command = summary.command, !command.isEmpty {
                Text(command)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            } else {
                Text("No runner")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct InfoChip: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .frame(minWidth: 74, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }
}

private extension TaskStatusCategory {
    var color: Color {
        switch self {
        case .queue:
            return .secondary
        case .planning:
            return .blue
        case .active:
            return .orange
        case .attention:
            return .red
        case .review:
            return .purple
        case .complete:
            return .green
        case .archive:
            return .gray
        }
    }
}

private extension WorkflowCheckStatus {
    var color: Color {
        switch self {
        case .notConfigured, .notRun, .unknown:
            return .secondary
        case .running:
            return .orange
        case .passed:
            return .green
        case .failed, .cancelled:
            return .red
        }
    }
}

private extension RunRecord {
    var durationText: String {
        guard let endedAt else { return "running" }
        let interval = max(0, endedAt.timeIntervalSince(startedAt))
        if interval < 1 { return "<1s" }
        if interval < 60 { return "\(Int(interval))s" }
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return "\(minutes)m \(seconds)s"
    }
}

private struct TaskDraft {
    var title = ""
    var type: TaskType = .coding
    var priority: TaskPriority = .normal
    var goal = ""
    var context = ""

    init() {}

    init(task: FactoryTask) {
        title = task.title
        type = task.type
        priority = task.priority
        goal = task.goal
        context = task.context
    }

    func task(updating task: FactoryTask, acceptanceText: String) -> FactoryTask {
        var updated = task
        updated.title = title
        updated.type = type
        updated.priority = priority
        updated.goal = goal
        updated.context = context
        updated.acceptanceCriteria = Self.acceptanceCriteria(from: acceptanceText)
        return updated
    }

    func hasChanges(comparedTo task: FactoryTask, acceptanceText: String) -> Bool {
        title != task.title ||
            type != task.type ||
            priority != task.priority ||
            goal != task.goal ||
            context != task.context ||
            Self.acceptanceCriteria(from: acceptanceText) != task.acceptanceCriteria
    }

    private static func acceptanceCriteria(from acceptanceText: String) -> [String] {
        acceptanceText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
