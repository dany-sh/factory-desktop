import FactoryDesktopCore
import MarkdownUI
import SwiftUI

struct TaskDetailView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var workspaceState: TaskWorkspaceState
    @Environment(\.openWindow) private var openWindow
    @FocusState private var focusedField: TaskEditorField?
    @StateObject private var editorBridge = RichTaskEditorBridge()

    var body: some View {
        Group {
            if let task = store.selectedTask {
                VStack(alignment: .leading, spacing: 18) {
                    workspaceBreadcrumb(task: task)
                    header(task: task)
                    taskCommandBar(task: task)
                    Picker("Stage", selection: stageSelection) {
                        ForEach(TaskWorkspaceStage.allCases) { stage in
                            Text(stage.title).tag(stage)
                        }
                    }
                    .pickerStyle(.segmented)
                    taskWorkspaceLayout(task: task)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Button("Save Task") {
                            syncEditorStateIfNeeded {
                                if let currentTask = store.selectedTask {
                                    save(currentTask)
                                }
                            }
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
                    editorBridge.dismissInlineAI = {
                        workspaceState.customInlinePrompt = ""
                    }
                    editorBridge.openInlineAI = {
                        handleInlineAction(.askAI)
                    }
                    editorBridge.runInlineAction = handleInlineAction
                    workspaceState.loadIfNeeded(task)
                }
                .onChange(of: task.id) { _, _ in
                    workspaceState.loadIfNeeded(task)
                }
            } else {
                ContentUnavailableView(
                    "No Task Selected",
                    systemImage: "tray",
                    description: Text("Create a task to start intake, planning, handoff, and review.")
                )
                .onAppear {
                    editorBridge.dismissInlineAI = nil
                    editorBridge.openInlineAI = nil
                    editorBridge.runInlineAction = nil
                    workspaceState.reset()
                    focusedField = nil
                }
            }
        }
    }

    private var draft: TaskDraft {
        get { workspaceState.draft }
        nonmutating set { workspaceState.draft = newValue }
    }

    private var acceptanceText: String {
        get { workspaceState.acceptanceText }
        nonmutating set { workspaceState.acceptanceText = newValue }
    }

    private var selectedStage: TaskWorkspaceStage {
        get { workspaceState.selectedStage }
        nonmutating set { workspaceState.selectedStage = newValue }
    }

    private var showAllArtifacts: Bool {
        get { workspaceState.showAllArtifacts }
        nonmutating set { workspaceState.showAllArtifacts = newValue }
    }

    private var editorSelectionText: String {
        get { workspaceState.selectionState.selectedText }
        nonmutating set {
            var selectionState = workspaceState.selectionState
            selectionState.selectedText = newValue
            workspaceState.selectionState = selectionState
        }
    }

    private var draftTitleBinding: Binding<String> {
        Binding(
            get: { draft.title },
            set: { draft.title = $0 }
        )
    }

    private var editorSelectionBinding: Binding<TaskEditorSelectionState> {
        Binding(
            get: { workspaceState.selectionState },
            set: { workspaceState.updateSelectionState($0) }
        )
    }

    private var showAllArtifactsBinding: Binding<Bool> {
        Binding(
            get: { showAllArtifacts },
            set: { showAllArtifacts = $0 }
        )
    }

    private func draftBinding<Value>(_ keyPath: WritableKeyPath<TaskDraft, Value>) -> Binding<Value> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { newValue in
                var updated = draft
                updated[keyPath: keyPath] = newValue
                draft = updated
            }
        )
    }

    private var stageSelection: Binding<TaskWorkspaceStage> {
        Binding(
            get: { selectedStage },
            set: { nextStage in
                guard nextStage != selectedStage else { return }
                syncEditorStateIfNeeded {
                    selectedStage = nextStage
                }
            }
        )
    }

    private func workspaceBreadcrumb(task: FactoryTask) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Workspace")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Button {
                    store.showProjectWorkspace()
                } label: {
                    Text(store.selectedProject?.name ?? "Project")
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .help("Open project page")
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                HStack(spacing: 8) {
                    Text(taskIdentityKey(for: task))
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                    Text(task.title)
                        .lineLimit(1)
                }
            }
            .font(.title3.weight(.semibold))
        }
    }

    private func taskIdentityKey(for task: FactoryTask) -> String {
        "TASK-\(task.id.shortID.uppercased())"
    }

    private func header(task: FactoryTask) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Untitled Task", text: draftTitleBinding)
                        .font(.title2.weight(.semibold))
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .title)
                    metadataHeaderRow(task: task)
                    worktreeSummaryLine
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 10) {
                    HStack(spacing: 10) {
                        Button {
                            store.showProjectWorkspace()
                        } label: {
                            Label("Project View", systemImage: "square.grid.2x2")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        if store.isWorking {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if selectedStage == .write {
                        editorStatusSummary(task: task)
                    } else {
                        compactPrimaryAction
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

    private func taskCommandBar(task: FactoryTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Label("Actions", systemImage: "bolt.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    primaryCommandControl(task: task)

                    Divider()
                        .frame(height: 24)

                    actionButton("Assign to AI Worker", systemImage: "sparkles") {
                        Task { await store.assignSelectedTaskToAIWorker() }
                    }
                    .disabled(store.selectedTask == nil || store.isWorking)

                    actionButton("Resume Worker", systemImage: "play.circle") {
                        Task { await store.resumeWorker() }
                    }
                    .disabled(store.selectedRunnerSession == nil || store.isWorking)

                    actionButton("Review Worker Report", systemImage: "doc.text.magnifyingglass") {
                        store.reviewLatestWorkerReport()
                    }
                    .disabled(store.latestWorkerReport == nil || store.isWorking)

                    actionButton("Create Proposed Tasks", systemImage: "plus.square.on.square") {
                        store.createAllProposedTasks()
                    }
                    .disabled(!store.taskProposals.contains { $0.status == .proposed } || store.isWorking)

                    Divider()
                        .frame(height: 24)

                    actionButton("Review State", systemImage: "list.bullet.clipboard") {
                        Task { await store.reviewTaskState() }
                    }
                    .disabled(store.selectedTask == nil || store.isWorking)

                    actionButton("Preflight", systemImage: "checklist.checked") {
                        Task { await store.runPreflightCheck() }
                    }
                    .disabled(store.selectedTask == nil || store.isWorking)

                    actionButton("Task Worktree", systemImage: "point.3.connected.trianglepath.dotted") {
                        Task { await store.createWorktree(flavor: .local) }
                    }
                    .disabled(store.selectedTask == nil || task.localWorktreePath != nil || store.isWorking)

                    actionButton("Alternate Worktree", systemImage: "terminal") {
                        Task { await store.createWorktree(flavor: .codex) }
                    }
                    .disabled(store.selectedTask == nil || task.codexWorktreePath != nil || store.isWorking)

                    actionButton("Open VS Code", systemImage: "curlybraces.square") {
                        Task { await store.openVSCodeForSelectedTask() }
                    }
                    .disabled(store.selectedTask == nil || selectedCodeWorktreeUnavailable || store.isWorking)

                    actionButton("Codex Handoff", systemImage: "paperplane") {
                        store.generateCodexHandoff()
                    }
                    .disabled(!canSendToCodexBuild)
                }
            }
            .controlSize(.small)

            if let warning = store.selectedTaskWorktreeWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator.opacity(0.55))
        )
    }

    @ViewBuilder
    private func primaryCommandControl(task: FactoryTask) -> some View {
        if task.status == .archived || task.status == .done {
            completedTaskNextAction(task)
        } else if store.selectedRunnerSession != nil {
            actionButton("Resume Worker", systemImage: "play.circle", prominent: true) {
                Task { await store.resumeWorker() }
            }
            .disabled(store.isWorking)
        } else if task.readiness == .executable || task.status == .ready || task.status == .approved {
            actionButton("Assign to AI Worker", systemImage: "sparkles", prominent: true) {
                Task { await store.assignSelectedTaskToAIWorker() }
            }
            .disabled(store.isWorking)
        } else if let review = store.latestTaskStateReview {
            primaryActionButton(review.recommendedAction)
        } else if store.canPlanSelectedTaskLocally {
            actionButton("Plan Locally", systemImage: "brain", prominent: true) {
                Task { await store.planLocally() }
            }
            .disabled(store.isWorking)
        } else {
            actionButton("Create Task Worktree", systemImage: "point.3.connected.trianglepath.dotted", prominent: true) {
                Task { await store.createWorktree(flavor: .local) }
            }
            .disabled(store.selectedTask == nil || task.localWorktreePath != nil || store.isWorking)
        }
    }

    private var canSendToCodexBuild: Bool {
        guard let status = store.selectedTask?.status else { return false }
        return !store.isWorking && status == .approved && !selectedCodeWorktreeUnavailable
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

    private func metadataHeaderRow(task: FactoryTask) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                statusMenu(task: task)
                metadataMenu("Task type", selection: draftBinding(\.type), options: TaskType.allCases.sorted { $0.displayName < $1.displayName }, label: \.displayName)
                metadataMenu("Priority", selection: draftBinding(\.priorityLabel), options: FactoryTaskPriorityLabel.allCases.sorted { $0.sortOrder < $1.sortOrder }, label: \.displayName)
                metadataMenu("Readiness", selection: draftBinding(\.readiness), options: FactoryTaskReadiness.allCases.sorted { $0.sortOrder < $1.sortOrder }, label: \.displayName)
                if draft.effort != .unknown {
                    metadataMenu("Effort", selection: draftBinding(\.effort), options: FactoryTaskEffort.allCases.sorted { $0.sortOrder < $1.sortOrder }, label: effortLabel(for:))
                }
                if draft.risk != .unknown {
                    metadataMenu("Risk", selection: draftBinding(\.risk), options: FactoryTaskRisk.allCases.sorted { $0.sortOrder < $1.sortOrder }, label: riskLabel(for:))
                }
            }
        }
    }

    private func metadataMenu<Value: Identifiable & Hashable>(
        _ title: String,
        selection: Binding<Value>,
        options: [Value],
        label: @escaping (Value) -> String
    ) -> some View {
        Menu {
            ForEach(options) { option in
                Button {
                    selection.wrappedValue = option
                } label: {
                    if selection.wrappedValue == option {
                        Label(label(option), systemImage: "checkmark")
                    } else {
                        Text(label(option))
                    }
                }
            }
        } label: {
            HeaderMetadataChip(text: label(selection.wrappedValue))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(title)
    }

    private func effortLabel(for effort: FactoryTaskEffort) -> String {
        switch effort {
        case .unknown: "Effort Unknown"
        default: effort.displayName
        }
    }

    private func riskLabel(for risk: FactoryTaskRisk) -> String {
        switch risk {
        case .unknown: "Risk Unknown"
        default: risk.displayName
        }
    }

    private func editorStatusSummary(task: FactoryTask) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Editor")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if draft.hasChanges(comparedTo: task, acceptanceText: acceptanceText) {
                Label("Unsaved changes", systemImage: "pencil.and.outline")
                    .foregroundStyle(.orange)
            } else {
                Label("All changes saved", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }
        }
        .frame(minWidth: 190, alignment: .leading)
    }

    private var taskEditorCanvas: some View {
        VStack(alignment: .leading, spacing: 14) {
            richTaskEditorCanvas
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.separator.opacity(0.6))
        )
    }

    private var richTaskEditorCanvas: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Task Brief")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if editorSelectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Select text to make AI edits more targeted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Selection ready")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
            RichTaskEditorView(markdown: editorDocumentBinding, selectionState: editorSelectionBinding, bridge: editorBridge)
                .frame(minHeight: 520)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.separator.opacity(0.55))
                }
        }
    }

    private var editorDocumentMarkdown: String {
        workspaceState.editorDocumentMarkdown
    }

    private var editorDocumentBinding: Binding<String> {
        Binding(
            get: { editorDocumentMarkdown },
            set: { workspaceState.updateEditorDocumentMarkdown($0) }
        )
    }

    private func handleInlineAction(_ action: EditorAssistAction) {
        workspaceState.inspectorPresented = true
        if action == .customAsk {
            workspaceState.customInlinePrompt = workspaceState.selectionState.hasSelection ? "Focus on this selection and improve it." : "Write the next part for this section."
            return
        }

        Task {
            await store.runEditorAssist(
                action: action,
                documentMarkdown: editorDocumentMarkdown,
                target: workspaceState.currentAssistTarget
            )
        }
    }

    private func save(_ task: FactoryTask) {
        let updated = draft.task(updating: task, acceptanceText: acceptanceText)
        store.saveTask(updated)
        workspaceState.load(updated)
    }

    private func syncEditorStateIfNeeded(_ completion: @escaping () -> Void) {
        guard selectedStage == .write else {
            completion()
            return
        }
        guard let requestLatestMarkdown = editorBridge.requestLatestMarkdown else {
            completion()
            return
        }
        requestLatestMarkdown { markdown in
            workspaceState.updateEditorDocumentMarkdown(markdown)
            completion()
        }
    }

    @ViewBuilder
    private func taskWorkspaceLayout(task: FactoryTask) -> some View {
        Group {
            if selectedStage == .write {
                taskWorkspaceContent(task: task)
            } else {
                ScrollView {
                    taskWorkspaceContent(task: task)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.never)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func taskWorkspaceContent(task: FactoryTask) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            switch selectedStage {
            case .write:
                writeSection(task: task)
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

    @ViewBuilder
    private var worktreeSummaryLine: some View {
        let displays = store.selectedTaskWorktreeDisplays
        let isCompletedTask = store.selectedTask?.status == .archived || store.selectedTask?.status == .done
        if displays.isEmpty {
            Text(store.selectedTaskCanUseWorktree ? "No worktree yet" : "Worktree optional")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if displays.contains(where: { $0.state == .missingPath }) {
            Text(isCompletedTask ? "Archived Worktree Reference" : "Missing Worktree")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isCompletedTask ? Color.secondary : Color.red)
        } else {
            Text(displays.map { "\($0.label): \($0.branch ?? "no branch") (\($0.state.displayName))" }.joined(separator: "  |  "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var selectedCodeWorktreeUnavailable: Bool {
        store.selectedProject?.type == .codeRepo && !store.selectedTaskCanUseWorktree
    }

    private func writeSection(task: FactoryTask) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            taskEditorCanvas
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    VStack(alignment: .leading, spacing: 10) {
                        Text("No saved plan yet.")
                            .foregroundStyle(.secondary)
                        Text("Current Task Brief")
                            .font(.subheadline.weight(.semibold))
                        primaryMarkdownBox(editorDocumentMarkdown, minHeight: 220)
                    }
                } else {
                    primaryMarkdownBox(store.currentPlanText, minHeight: 320)
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
                    if let artifact = store.latestPlanReviewArtifact {
                        HStack {
                            Text("Open the full review in a separate markdown window.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            artifactPath(artifact)
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
                    Text("Test output is available as a separate artifact window instead of an inline dump.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    Text("Diff review is available as a separate markdown window instead of an inline duplicate.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            Toggle("Show All Artifacts", isOn: showAllArtifactsBinding)
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

    private func primaryMarkdownBox(_ text: String, minHeight: CGFloat) -> some View {
        ScrollView {
            Markdown(text)
                .markdownTheme(.gitHub)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .frame(minHeight: minHeight)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private func artifactPath(_ artifact: Artifact) -> some View {
        Button {
            if AppStore.isMarkdownPath(artifact.path) {
                openWindow(id: "markdown-document", value: AppStore.normalizedMarkdownPath(artifact.path))
            } else {
                Task { await store.openArtifact(artifact) }
            }
        } label: {
            Label(
                AppStore.isMarkdownPath(artifact.path) ? "Open Markdown" : "Open Artifact",
                systemImage: AppStore.isMarkdownPath(artifact.path) ? "doc.text" : "arrow.up.forward.app"
            )
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

    private func assistButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

private enum TaskEditorField: Hashable {
    case title
    case brief
    case acceptanceCriteria
}

enum TaskWorkspaceStage: String, CaseIterable, Identifiable {
    case write
    case planReview
    case buildTest
    case diff
    case artifacts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .write: "Write"
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

private struct HeaderMetadataChip: View {
    var text: String

    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.6), in: Capsule())
        .foregroundStyle(.primary)
    }
}

struct DraftQuality {
    struct Check: Identifiable {
        var id: String { title }
        var title: String
        var isComplete: Bool
    }

    var checks: [Check]

    init(brief: String, acceptanceText: String) {
        let normalized = brief.lowercased()
        let acceptanceCount = acceptanceText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
        checks = [
            Check(title: "Goal names the desired outcome", isComplete: normalized.contains("## goal") && brief.wordCount >= 8),
            Check(title: "Context explains why now", isComplete: normalized.contains("## context")),
            Check(title: "Scope or non-goals are explicit", isComplete: normalized.contains("## scoping") || normalized.contains("out of scope")),
            Check(title: "Acceptance criteria are testable", isComplete: acceptanceCount >= 2)
        ]
    }

    var score: Int {
        checks.filter(\.isComplete).count
    }

    var color: Color {
        switch score {
        case 0...1: .orange
        case 2...3: .blue
        default: .green
        }
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

private extension String {
    var wordCount: Int {
        split { $0.isWhitespace || $0.isNewline }.count
    }
}

struct TaskDraft {
    var title = ""
    var type: TaskType = .planning
    var kind: FactoryTaskKind = .task
    var readiness: FactoryTaskReadiness = .needsScoping
    var priorityLabel: FactoryTaskPriorityLabel = .normal
    var category = ""
    var source = ""
    var effort: FactoryTaskEffort = .unknown
    var risk: FactoryTaskRisk = .unknown
    var brief = ""
    var dependencies = ""
    var nonGoals = ""
    var suggestedSplit = ""
    var recommendedNextAction = ""

    init() {}

    init(task: FactoryTask) {
        title = task.title
        type = task.type
        kind = task.kind
        readiness = task.readiness
        priorityLabel = task.priorityLabel
        category = task.category
        source = task.source
        effort = task.effort
        risk = task.risk
        brief = Self.briefText(goal: task.goal, context: task.context, scopingNotes: task.scopingNotes)
        dependencies = task.dependencies
        nonGoals = task.nonGoals
        suggestedSplit = task.suggestedSplit
        recommendedNextAction = task.recommendedNextAction
    }

    func task(updating task: FactoryTask, acceptanceText: String) -> FactoryTask {
        var updated = task
        let sections = Self.parseBrief(brief)
        updated.title = title
        updated.type = type
        updated.kind = kind
        updated.readiness = readiness
        updated.priorityLabel = priorityLabel
        updated.priority = priorityLabel.taskPriority
        updated.triageStatus = FactoryTaskTriageStatus.fromLegacyStatus(updated.status)
        updated.category = category
        updated.source = source
        updated.effort = effort
        updated.risk = risk
        updated.goal = sections.goal
        updated.context = sections.context
        updated.scopingNotes = sections.scopingNotes
        updated.dependencies = dependencies
        updated.nonGoals = nonGoals
        updated.suggestedSplit = suggestedSplit
        updated.recommendedNextAction = recommendedNextAction
        updated.acceptanceCriteria = Self.acceptanceCriteria(from: acceptanceText)
        return updated
    }

    func hasChanges(comparedTo task: FactoryTask, acceptanceText: String) -> Bool {
        title != task.title ||
            type != task.type ||
            kind != task.kind ||
            readiness != task.readiness ||
            priorityLabel != task.priorityLabel ||
            category != task.category ||
            source != task.source ||
            effort != task.effort ||
            risk != task.risk ||
            brief != Self.briefText(goal: task.goal, context: task.context, scopingNotes: task.scopingNotes) ||
            dependencies != task.dependencies ||
            nonGoals != task.nonGoals ||
            suggestedSplit != task.suggestedSplit ||
            recommendedNextAction != task.recommendedNextAction ||
            Self.acceptanceCriteria(from: acceptanceText) != task.acceptanceCriteria
    }

    private static func acceptanceCriteria(from acceptanceText: String) -> [String] {
        acceptanceText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func briefText(goal: String, context: String, scopingNotes: String) -> String {
        [
            briefSection(title: "Goal", body: goal),
            briefSection(title: "Context", body: context),
            briefSection(title: "Scoping", body: scopingNotes)
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    private static func briefSection(title: String, body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return "## \(title)\n\(trimmed)"
    }

    private static func parseBrief(_ brief: String) -> (goal: String, context: String, scopingNotes: String) {
        var parsed = ParsedBrief()
        var currentHeading: String?
        var currentBody: [String] = []

        func flush() {
            guard let currentHeading else { return }
            let body = currentBody
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            switch currentHeading {
            case "Goal":
                parsed.goal = body
            case "Context":
                parsed.context = body
            case "Scoping":
                parsed.scopingNotes = body
            default:
                break
            }
        }

        for rawLine in brief.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("## ") {
                flush()
                let heading = String(trimmed.dropFirst(3))
                if heading == "Goal" || heading == "Context" || heading == "Scoping" {
                    currentHeading = heading
                    currentBody = []
                    continue
                }
            }

            if currentHeading == nil {
                currentHeading = "Goal"
            }
            currentBody.append(rawLine)
        }

        flush()
        return (parsed.goal, parsed.context, parsed.scopingNotes)
    }
}

private struct ParsedBrief {
    var goal = ""
    var context = ""
    var scopingNotes = ""
}

struct TaskEditorSelectionState: Equatable {
    var selectedText = ""
    var isFocused = false
    var activeSection: EditorAssistSection?
    var cursorAtInsertionPoint = false
    var changeToken = 0

    var hasSelection: Bool {
        !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

final class TaskWorkspaceState: ObservableObject {
    @Published var draft = TaskDraft()
    @Published var acceptanceText = ""
    @Published var loadedTaskID: String?
    @Published var selectedStage: TaskWorkspaceStage = .write
    @Published var showAllArtifacts = false
    @Published var selectionState = TaskEditorSelectionState()
    @Published var inspectorPresented = true
    @Published var customInlinePrompt = ""

    var editorDocumentMarkdown: String {
        TaskEditorDocument.markdown(brief: draft.brief, acceptanceText: acceptanceText)
    }

    var currentAssistTarget: EditorAssistTarget {
        if selectionState.hasSelection {
            return EditorAssistTarget(
                kind: .selectedText,
                selectedText: selectionState.selectedText,
                activeSection: selectionState.activeSection
            )
        }

        if let activeSection = selectionState.activeSection {
            if selectionState.cursorAtInsertionPoint {
                return EditorAssistTarget(kind: .cursorInsertionPoint, activeSection: activeSection)
            }
            return EditorAssistTarget(kind: .section(activeSection), activeSection: activeSection)
        }

        if selectionState.isFocused {
            return EditorAssistTarget(kind: .cursorInsertionPoint)
        }

        return EditorAssistTarget(kind: .fullBrief)
    }

    func reset() {
        draft = TaskDraft()
        acceptanceText = ""
        loadedTaskID = nil
        selectedStage = .write
        showAllArtifacts = false
        selectionState = TaskEditorSelectionState()
        customInlinePrompt = ""
    }

    func loadIfNeeded(_ task: FactoryTask) {
        guard loadedTaskID != task.id else { return }
        load(task)
    }

    func load(_ task: FactoryTask) {
        draft = TaskDraft(task: task)
        acceptanceText = task.acceptanceCriteria.joined(separator: "\n")
        loadedTaskID = task.id
        selectionState = TaskEditorSelectionState()
        customInlinePrompt = ""
    }

    func updateEditorDocumentMarkdown(_ markdown: String) {
        let document = TaskEditorDocument.parse(markdown)
        draft.brief = document.brief
        acceptanceText = document.acceptanceText
    }

    func updateSelectionState(_ next: TaskEditorSelectionState) {
        let selectionChanged = next.selectedText != selectionState.selectedText
            || next.activeSection != selectionState.activeSection
            || next.isFocused != selectionState.isFocused
            || next.cursorAtInsertionPoint != selectionState.cursorAtInsertionPoint
        guard selectionChanged else { return }
        selectionState = next
    }

    func applyProposal(_ proposal: AIAssistProposal, insertOnly: Bool) {
        let current = editorDocumentMarkdown
        let replacement = proposal.replacementMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !replacement.isEmpty else { return }

        if insertOnly {
            updateEditorDocumentMarkdown(insertMarkdown(replacement, into: current, target: proposal.target))
            return
        }

        switch proposal.target.kind {
        case .selectedText:
            let selection = proposal.target.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !selection.isEmpty, let range = current.range(of: selection) {
                var updated = current
                updated.replaceSubrange(range, with: replacement)
                updateEditorDocumentMarkdown(updated)
            } else {
                updateEditorDocumentMarkdown(replacement)
            }
        case .section(let section):
            updateEditorDocumentMarkdown(replaceSection(section, in: current, with: replacement))
        case .cursorInsertionPoint:
            if let section = proposal.target.activeSection {
                updateEditorDocumentMarkdown(insertMarkdown(replacement, into: current, target: .init(kind: .section(section), activeSection: section)))
            } else {
                updateEditorDocumentMarkdown(insertMarkdown(replacement, into: current, target: proposal.target))
            }
        case .fullBrief:
            updateEditorDocumentMarkdown(replacement)
        }
    }

    private func insertMarkdown(_ replacement: String, into markdown: String, target: EditorAssistTarget) -> String {
        switch target.kind {
        case .section(let section):
            let original = sectionBody(in: markdown, section: section) ?? ""
            let combined = [original, replacement]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n")
            return replaceSection(section, in: markdown, with: combined)
        case .cursorInsertionPoint, .fullBrief, .selectedText:
            let separator = markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
            return markdown + separator + replacement
        }
    }

    private func replaceSection(_ section: EditorAssistSection, in markdown: String, with replacement: String) -> String {
        let normalizedReplacement = stripMatchingHeading(from: replacement, section: section)
        let heading = heading(for: section)
        let lines = markdown.components(separatedBy: .newlines)
        guard let headingIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(heading) == .orderedSame }) else {
            let separator = markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
            return markdown + separator + heading + "\n" + normalizedReplacement
        }

        var endIndex = lines.count
        if let nextIndex = lines[(headingIndex + 1)...].firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("## ") }) {
            endIndex = nextIndex
        }

        var updatedLines = Array(lines[..<headingIndex])
        updatedLines.append(lines[headingIndex])
        if !normalizedReplacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updatedLines.append(contentsOf: normalizedReplacement.components(separatedBy: .newlines))
        }
        if endIndex < lines.count {
            updatedLines.append(contentsOf: lines[endIndex...])
        }
        return updatedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sectionBody(in markdown: String, section: EditorAssistSection) -> String? {
        let lines = markdown.components(separatedBy: .newlines)
        let heading = heading(for: section)
        guard let headingIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(heading) == .orderedSame }) else {
            return nil
        }
        let bodyStart = headingIndex + 1
        let endIndex = lines[bodyStart...].firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("## ") }) ?? lines.count
        return lines[bodyStart..<endIndex].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripMatchingHeading(from replacement: String, section: EditorAssistSection) -> String {
        let heading = heading(for: section)
        let lines = replacement.components(separatedBy: .newlines)
        guard let first = lines.first,
              first.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(heading) == .orderedSame else {
            return replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func heading(for section: EditorAssistSection) -> String {
        switch section {
        case .goal: "## Goal"
        case .context: "## Context"
        case .scoping: "## Scoping"
        case .acceptanceCriteria: "## Acceptance Criteria"
        }
    }
}
