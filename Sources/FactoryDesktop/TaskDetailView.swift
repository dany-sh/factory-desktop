import FactoryDesktopCore
import MarkdownUI
import SwiftUI

struct TaskDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow
    @State private var draft = TaskDraft()
    @State private var acceptanceText = ""
    @State private var loadedTaskID: String?
    @State private var selectedStage: TaskWorkspaceStage = .write
    @State private var showTaskMetadata = false
    @State private var showAllArtifacts = false
    @State private var editorSelectionText = ""
    @FocusState private var focusedField: TaskEditorField?

    var body: some View {
        Group {
            if let task = store.selectedTask {
                VStack(alignment: .leading, spacing: 18) {
                    header(task: task)
                    taskCommandBar(task: task)
                    Picker("Stage", selection: $selectedStage) {
                        ForEach(TaskWorkspaceStage.allCases) { stage in
                            Text(stage.title).tag(stage)
                        }
                    }
                    .pickerStyle(.segmented)

                    if selectedStage == .write {
                        taskWorkspaceContent(task: task)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else {
                        ScrollView {
                            taskWorkspaceContent(task: task)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .scrollDismissesKeyboard(.never)
                    }
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
                        StatusPill(text: task.readiness.displayName)
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
                if selectedStage == .write {
                    editorStatusSummary(task: task)
                } else {
                    compactPrimaryAction
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

    private func editorStatusSummary(task: FactoryTask) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Editor")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if draft.hasChanges(comparedTo: task, acceptanceText: acceptanceText) {
                Label("Unsaved changes", systemImage: "pencil.and.outline")
                    .foregroundStyle(.orange)
            } else {
                Label("Saved", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }
            Text("Press Command-S to save.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 190, alignment: .leading)
    }

    private var taskBriefPanel: some View {
        HStack(alignment: .top, spacing: 18) {
            taskEditorCanvas
                .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            writingAssistPanel
                .frame(width: 250, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var taskEditorCanvas: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Task Editor")
                    .font(.headline)
                TextField("Task title", text: $draft.title)
                    .font(.largeTitle.weight(.semibold))
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .title)
                primaryMetadataPickerGrid
            }

            richTaskEditorCanvas

            DisclosureGroup("Details, dependencies, and scope guards", isExpanded: $showTaskMetadata) {
                taskMetadataEditor
                    .padding(.top, 12)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.separator.opacity(0.6))
        )
    }

    private var primaryMetadataPickerGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Type", selection: $draft.type) {
                    ForEach(TaskType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                Picker("Kind", selection: $draft.kind) {
                    ForEach(FactoryTaskKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
            }

            HStack {
                Picker("Priority", selection: $draft.priorityLabel) {
                    ForEach(FactoryTaskPriorityLabel.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                Picker("Readiness", selection: $draft.readiness) {
                    ForEach(FactoryTaskReadiness.allCases) { readiness in
                        Text(readiness.displayName).tag(readiness)
                    }
                }
            }

            HStack {
                Picker("Effort", selection: $draft.effort) {
                    ForEach(FactoryTaskEffort.allCases) { effort in
                        Text(effort.displayName).tag(effort)
                    }
                }
                Picker("Risk", selection: $draft.risk) {
                    ForEach(FactoryTaskRisk.allCases) { risk in
                        Text(risk.displayName).tag(risk)
                    }
                }
            }
        }
        .controlSize(.small)
    }

    private var taskMetadataEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Category", text: $draft.category)
            TextField("Source", text: $draft.source)

            LabeledTextEditor(
                title: "Dependencies",
                text: $draft.dependencies,
                minHeight: 80,
                focusedField: $focusedField,
                field: .dependencies
            )
            LabeledTextEditor(
                title: "Non-goals",
                text: $draft.nonGoals,
                minHeight: 80,
                focusedField: $focusedField,
                field: .nonGoals
            )
            LabeledTextEditor(
                title: "Suggested split",
                text: $draft.suggestedSplit,
                minHeight: 80,
                focusedField: $focusedField,
                field: .suggestedSplit
            )
            LabeledTextEditor(
                title: "Recommended next action",
                text: $draft.recommendedNextAction,
                minHeight: 80,
                focusedField: $focusedField,
                field: .recommendedNextAction
            )
        }
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
            RichTaskEditorView(markdown: editorDocumentBinding, selectedText: $editorSelectionText)
                .frame(minHeight: 520)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.separator.opacity(0.55))
                }
        }
    }

    private var writingAssistPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            editorAssistCard
            writingScoreCard
            sectionStarterCard
        }
    }

    private var editorAssistCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("AI Assist")
                    .font(.headline)
                Spacer()
                if store.isEditorAssistRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Picker("Provider", selection: $store.selectedEditorAssistProvider) {
                ForEach(store.editorAssistProviderOptions) { option in
                    Text(option.isAvailable ? option.provider.displayName : "\(option.provider.displayName) · \(option.detail)")
                        .tag(option.provider)
                        .disabled(!option.isAvailable)
                }
            }
            .labelsHidden()

            LazyVGrid(columns: [GridItem(.flexible())], spacing: 7) {
                ForEach(EditorAssistAction.allCases) { action in
                    assistButton(action.displayName, systemImage: editorAssistIcon(for: action)) {
                        Task {
                            await store.runEditorAssist(
                                action: action,
                                documentMarkdown: editorDocumentMarkdown,
                                selectedText: editorSelectionText
                            )
                        }
                    }
                    .disabled(!selectedEditorAssistProviderIsAvailable || store.isEditorAssistRunning)
                }
            }

            if let suggestion = store.latestEditorAssistSuggestion {
                Divider()
                Text(suggestion.summary)
                    .font(.caption.weight(.semibold))
                ScrollView {
                    Text(suggestion.replacementMarkdown)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .padding(8)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                HStack {
                    Button("Accept") {
                        applyEditorSuggestion(suggestion, insertOnly: false)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Insert Below") {
                        applyEditorSuggestion(suggestion, insertOnly: true)
                    }
                    .buttonStyle(.bordered)
                }
                Button("Reject") {
                    store.clearEditorAssistSuggestion()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            } else if !selectedEditorAssistProviderIsAvailable {
                Text("Selected provider is not configured yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.separator.opacity(0.55))
        )
    }

    private var writingScoreCard: some View {
        let quality = DraftQuality(brief: draft.brief, acceptanceText: acceptanceText)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Brief Quality")
                    .font(.headline)
                Spacer()
                Text("\(quality.score)/4")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(quality.color.opacity(0.16), in: Capsule())
                    .foregroundStyle(quality.color)
            }
            ForEach(quality.checks) { check in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: check.isComplete ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(check.isComplete ? Color.green : .secondary)
                    Text(check.title)
                        .font(.caption)
                        .foregroundStyle(check.isComplete ? .primary : .secondary)
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.separator.opacity(0.55))
        )
    }

    private var sectionStarterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Fast Inserts")
                .font(.headline)
            assistButton("Goal", systemImage: "scope") {
                appendBriefSection("Goal", body: "Define the outcome in one sentence.")
            }
            assistButton("Context", systemImage: "text.book.closed") {
                appendBriefSection("Context", body: "What changed, what exists today, and why this matters.")
            }
            assistButton("Scoping", systemImage: "ruler") {
                appendBriefSection("Scoping", body: "In scope:\n- \n\nOut of scope:\n- ")
            }
            assistButton("Acceptance", systemImage: "checklist") {
                appendAcceptanceCriteria()
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.separator.opacity(0.55))
        )
    }

    private var editorDocumentMarkdown: String {
        TaskEditorDocument.markdown(brief: draft.brief, acceptanceText: acceptanceText)
    }

    private var editorDocumentBinding: Binding<String> {
        Binding(
            get: { editorDocumentMarkdown },
            set: { updateEditorDocumentMarkdown($0) }
        )
    }

    private var selectedEditorAssistProviderIsAvailable: Bool {
        store.editorAssistProviderOptions.first { $0.provider == store.selectedEditorAssistProvider }?.isAvailable == true
    }

    private func updateEditorDocumentMarkdown(_ markdown: String) {
        let document = TaskEditorDocument.parse(markdown)
        draft.brief = document.brief
        acceptanceText = document.acceptanceText
    }

    private func applyEditorSuggestion(_ suggestion: EditorAssistSuggestion, insertOnly: Bool) {
        let current = editorDocumentMarkdown
        let replacement = suggestion.replacementMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !replacement.isEmpty else { return }

        if insertOnly {
            let separator = current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
            updateEditorDocumentMarkdown(current + separator + replacement)
        } else {
            let selection = editorSelectionText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !selection.isEmpty, let range = current.range(of: selection) {
                var updated = current
                updated.replaceSubrange(range, with: replacement)
                updateEditorDocumentMarkdown(updated)
            } else {
                updateEditorDocumentMarkdown(replacement)
            }
        }
        store.clearEditorAssistSuggestion()
    }

    private func editorAssistIcon(for action: EditorAssistAction) -> String {
        switch action {
        case .rewriteSelection: "wand.and.stars"
        case .tightenGoal: "target"
        case .findAmbiguity: "questionmark.bubble"
        case .generateAcceptanceCriteria: "checklist"
        case .splitTask: "square.split.2x1"
        }
    }

    private func save(_ task: FactoryTask) {
        store.saveTask(draft.task(updating: task, acceptanceText: acceptanceText))
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
            Text("Task worktree: missing")
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
            taskBriefPanel
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
                    Text("No saved plan yet.")
                        .foregroundStyle(.secondary)
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

    private func loadIfNeeded(_ task: FactoryTask) {
        guard loadedTaskID != task.id else { return }
        load(task)
    }

    private func load(_ task: FactoryTask) {
        draft = TaskDraft(task: task)
        acceptanceText = task.acceptanceCriteria.joined(separator: "\n")
        loadedTaskID = task.id
        focusedField = nil
        editorSelectionText = ""
    }

    private func appendBriefSection(_ title: String, body: String) {
        let heading = "## \(title)"
        if draft.brief.localizedCaseInsensitiveContains(heading) {
            focusedField = .brief
            return
        }
        let separator = draft.brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
        draft.brief += "\(separator)\(heading)\n\(body)"
        focusedField = .brief
    }

    private func appendAcceptanceCriteria() {
        let starter = [
            "User-facing behavior is clear and task-centered.",
            "No duplicate inspector/main-panel status blocks.",
            "Changes are verified with the relevant local checks."
        ]
        let existing = acceptanceText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let additions = starter.filter { !existing.contains($0) }
        guard !additions.isEmpty else {
            focusedField = .acceptanceCriteria
            return
        }
        let separator = acceptanceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n"
        acceptanceText += "\(separator)\(additions.joined(separator: "\n"))"
        focusedField = .acceptanceCriteria
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
    case dependencies
    case nonGoals
    case suggestedSplit
    case recommendedNextAction
}

private enum TaskWorkspaceStage: String, CaseIterable, Identifiable {
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

private struct DraftQuality {
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

private struct TaskDraft {
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
