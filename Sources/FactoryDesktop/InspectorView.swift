import FactoryDesktopCore
import SwiftUI

struct RightToolsInspectorView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var workspaceState: TaskWorkspaceState
    @State private var workerExpanded = true
    @State private var aiExpanded = true
    @State private var qualityExpanded = true
    @State private var reviewExpanded = true
    @State private var terminalExpanded = false
    @State private var browserExpanded = false
    @State private var filesExpanded = false
    @State private var proposalPrompt = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if shouldShowTaskInspector {
                    aiWorkerSection
                    aiAssistSection
                    briefQualitySection
                    reviewSection
                    terminalSection
                    browserSection
                    filesSection
                } else {
                    projectPlaceholder
                }
            }
            .padding(12)
        }
        .onAppear(perform: syncWorkspaceState)
        .onChange(of: store.selectedTask?.id) { _, _ in
            syncWorkspaceState()
        }
    }

    private var shouldShowTaskInspector: Bool {
        switch store.selectedWorkspaceScope {
        case .task:
            return inspectorTask != nil
        case .kanban:
            return inspectorTask != nil
        case .project:
            return false
        }
    }

    private var inspectorTask: FactoryTask? {
        guard let task = store.selectedTask else { return nil }
        guard task.projectId == store.selectedProject?.id else { return nil }
        return task
    }

    private var selectedEditorAssistProviderIsAvailable: Bool {
        store.editorAssistProviderOptions.first { $0.provider == store.selectedEditorAssistProvider }?.isAvailable == true
    }

    private var aiWorkerSection: some View {
        InspectorToolSectionView(
            icon: "sparkles",
            title: "AI Worker",
            isExpanded: $workerExpanded
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    inspectorActionButton("Assign", systemImage: "sparkles") {
                        Task { await store.assignSelectedTaskToAIWorker() }
                    }
                    inspectorActionButton("Resume", systemImage: "play.circle") {
                        Task { await store.resumeWorker() }
                    }
                    .disabled(store.selectedRunnerSession == nil || store.isWorking)
                }

                HStack {
                    inspectorActionButton("Review Report", systemImage: "doc.text.magnifyingglass") {
                        store.reviewLatestWorkerReport()
                    }
                    .disabled(store.latestWorkerReport == nil || store.isWorking)
                    inspectorActionButton("View Logs", systemImage: "doc.plaintext") {
                        store.viewLatestWorkerLogs()
                    }
                    .disabled(store.latestRunnerExecution?.logPath == nil || store.isWorking)
                }

                inspectorActionButton("Create Proposed Tasks", systemImage: "plus.square.on.square") {
                    store.createAllProposedTasks()
                }
                .disabled(!store.taskProposals.contains { $0.status == .proposed } || store.isWorking)

                Divider()

                if let workspace = store.selectedRunnerWorkspace {
                    InspectorMetricRow(label: "Workspace", value: workspace.worktreePath)
                    InspectorMetricRow(label: "Branch", value: workspace.branchName)
                } else {
                    Text("No runner workspace yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let session = store.selectedRunnerSession {
                    InspectorMetricRow(label: "Session", value: session.externalSessionId ?? session.id.shortID)
                    InspectorMetricRow(label: "Provider", value: session.provider.displayName)
                    InspectorMetricRow(label: "Status", value: session.status.displayName)
                }

                if let execution = store.latestRunnerExecution {
                    InspectorMetricRow(label: "Latest Execution", value: "\(execution.status.displayName) · \(execution.runReason)")
                }

                if let report = store.latestWorkerReport {
                    Divider()
                    InspectorMetricRow(label: "Report", value: report.status.displayName)
                    if !report.summary.isEmpty {
                        Text(report.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    workerList("Files Changed", values: report.filesChanged)
                    workerList("Tests Run", values: report.testsRun)
                    workerList("Risks", values: report.risks)
                    workerList("Blockers", values: report.blockers)
                    if !report.nextRecommendedAction.isEmpty {
                        InspectorMetricRow(label: "Next Recommended Action", value: report.nextRecommendedAction)
                    }
                }

                let proposed = store.taskProposals.filter { $0.status == .proposed }
                if !proposed.isEmpty {
                    Divider()
                    Text("Proposed Follow-up Tasks")
                        .font(.caption.weight(.semibold))
                    ForEach(proposed) { proposal in
                        proposalRow(proposal)
                    }
                    HStack {
                        Button("Create All") {
                            store.createAllProposedTasks()
                        }
                        .buttonStyle(.bordered)
                        Button("Dismiss All") {
                            store.dismissAllTaskProposals()
                        }
                        .buttonStyle(.borderless)
                    }
                    .controlSize(.small)
                }

                if let snapshot = store.latestLifecycleSnapshot {
                    Divider()
                    InspectorMetricRow(label: "Lifecycle Recommendation", value: snapshot.recommendedAction)
                    HStack(spacing: 8) {
                        CompactStatusChip(label: "Worktree", value: snapshot.worktreeExists ? "Exists" : "Missing")
                        CompactStatusChip(label: "Branch", value: snapshot.branchExists ? "Exists" : "Missing")
                        CompactStatusChip(label: "Proposals", value: "\(snapshot.proposedTasksCount)")
                    }
                }
            }
        }
    }

    private var aiAssistSection: some View {
        InspectorToolSectionView(
            icon: "sparkles.rectangle.stack",
            title: "AI Assist",
            isExpanded: $aiExpanded
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Provider", selection: $store.selectedEditorAssistProvider) {
                    ForEach(store.editorAssistProviderOptions) { option in
                        Text(option.isAvailable ? option.provider.displayName : "\(option.provider.displayName) · \(option.detail)")
                            .tag(option.provider)
                            .disabled(!option.isAvailable)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                targetSummary

                LazyVGrid(columns: [GridItem(.flexible())], spacing: 7) {
                    ForEach(inspectorActions) { action in
                        Button {
                            runAssist(action: action)
                        } label: {
                            Label(action.displayName, systemImage: editorAssistIcon(for: action))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!selectedEditorAssistProviderIsAvailable || store.isEditorAssistRunning)
                    }
                }

                if store.isEditorAssistRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Generating suggestion…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let proposal = store.latestAIAssistProposal {
                    Divider()
                    Text(proposal.summary)
                        .font(.caption.weight(.semibold))
                    InspectorMetricRow(label: "Target", value: proposal.target.label)
                    ScrollView {
                        Text(editorAssistPreviewText(for: proposal))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 92, maxHeight: 180)
                    .padding(8)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))

                    HStack {
                        Button("Accept") {
                            workspaceState.applyProposal(proposal, insertOnly: proposal.target.kind == .cursorInsertionPoint)
                            store.clearEditorAssistSuggestion()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Replace Target") {
                            workspaceState.applyProposal(proposal, insertOnly: false)
                            store.clearEditorAssistSuggestion()
                        }
                        .buttonStyle(.bordered)

                        Button("Insert Below") {
                            workspaceState.applyProposal(proposal, insertOnly: true)
                            store.clearEditorAssistSuggestion()
                        }
                        .buttonStyle(.bordered)
                    }

                    TextField("Refine or custom ask", text: $proposalPrompt, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)

                    HStack {
                        Button("Retry") {
                            runAssist(action: proposal.action, customInstruction: proposal.customInstruction)
                        }
                        .buttonStyle(.bordered)

                        Button("Refine") {
                            let instruction = proposalPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !instruction.isEmpty else { return }
                            runAssist(action: proposal.action, customInstruction: instruction)
                            proposalPrompt = ""
                        }
                        .buttonStyle(.bordered)

                        Button("Dismiss") {
                            proposalPrompt = ""
                            store.clearEditorAssistSuggestion()
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                } else if !selectedEditorAssistProviderIsAvailable {
                    Text("Selected provider is not configured yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Run an AI action to generate a proposal here. The editor will not change until you accept one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !workspaceState.customInlinePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.latestAIAssistProposal == nil {
                    Divider()
                    TextField("Custom ask", text: $workspaceState.customInlinePrompt, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)

                    Button("Run Custom Ask") {
                        let instruction = workspaceState.customInlinePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !instruction.isEmpty else { return }
                        runAssist(action: .customAsk, customInstruction: instruction)
                        workspaceState.customInlinePrompt = ""
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var briefQualitySection: some View {
        let quality = DraftQuality(brief: workspaceState.draft.brief, acceptanceText: workspaceState.acceptanceText)
        let hasBriefContent = !workspaceState.draft.brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !workspaceState.acceptanceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return InspectorToolSectionView(
            icon: "checklist",
            title: "Brief Quality",
            isExpanded: $qualityExpanded
        ) {
            if hasBriefContent {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("\(quality.score)/4")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(quality.color.opacity(0.16), in: Capsule())
                            .foregroundStyle(quality.color)
                        Spacer()
                    }

                    ForEach(quality.checks) { check in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: check.isComplete ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(check.isComplete ? Color.green : .secondary)
                            Text(check.title)
                                .font(.caption)
                                .foregroundStyle(check.isComplete ? .primary : .secondary)
                        }
                    }
                }
            } else {
                Text("No task brief yet. Start writing in the main editor to score goal, context, scope, and acceptance quality.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var reviewSection: some View {
        InspectorToolSectionView(
            icon: "list.bullet.clipboard",
            title: "Review / State",
            isExpanded: $reviewExpanded
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    inspectorActionButton("Review State", systemImage: "list.bullet.clipboard") {
                        Task { await store.reviewTaskState() }
                    }
                    inspectorActionButton("Preflight", systemImage: "checklist.checked") {
                        Task { await store.runPreflightCheck() }
                    }
                }

                inspectorActionButton("Sync Lifecycle", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await store.syncSelectedTaskLifecycle() }
                }

                if let review = store.latestTaskStateReview {
                    InspectorMetricRow(label: "Recommended", value: review.recommendedAction.displayName)
                    Text(review.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        CompactStatusChip(label: "Plan", value: review.hasPlan ? "Yes" : "No")
                        CompactStatusChip(label: "Review", value: review.hasPlanReview ? "Yes" : "No")
                        CompactStatusChip(label: "Tests", value: review.hasTestOutput ? "Yes" : "No")
                    }

                    HStack(spacing: 8) {
                        CompactStatusChip(label: "Diff", value: review.hasDiffReview ? "Yes" : "No")
                        CompactStatusChip(label: "Changes", value: review.hasImplementationChanges ? "Yes" : "No")
                        CompactStatusChip(label: "Preflight", value: review.hasPreflight ? (review.hasRiskyPreflight ? "Risk" : "Yes") : "No")
                    }
                } else {
                    Text("Run Review State to summarize the current plan, tests, diff, and recommended next action.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LifecycleSyncSummaryView(
                    result: store.latestLifecycleSyncResult,
                    emptyMessage: "No lifecycle sync details yet."
                )
            }
        }
    }

    private var terminalSection: some View {
        InspectorToolSectionView(
            icon: "terminal",
            title: "Terminal",
            isExpanded: $terminalExpanded
        ) {
            if let session = store.selectedTaskRunnerSessionLink {
                VStack(alignment: .leading, spacing: 8) {
                    InspectorMetricRow(label: "Session", value: session.sessionID)
                    InspectorMetricRow(label: "Status", value: session.status.displayName)
                    InspectorMetricRow(label: "Workspace", value: session.workspacePath)
                }
            } else {
                Text("No task terminal session yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var browserSection: some View {
        InspectorToolSectionView(
            icon: "safari",
            title: "Browser",
            isExpanded: $browserExpanded
        ) {
            Text("No browser session attached.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var filesSection: some View {
        InspectorToolSectionView(
            icon: "doc.on.doc",
            title: "Files",
            isExpanded: $filesExpanded
        ) {
            if store.artifacts.isEmpty {
                Text("No file context attached.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    InspectorMetricRow(label: "Attached Artifacts", value: "\(store.artifacts.count)")
                    Text("Task artifacts remain available in the Artifacts stage of the main workspace.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var projectPlaceholder: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.selectedWorkspaceScope == .project ? "Project Inspector" : "Task Inspector")
                .font(.headline)
            Text(placeholderCopy)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private var placeholderCopy: String {
        switch store.selectedWorkspaceScope {
        case .project:
            return "The right inspector stays quiet on the project dashboard. Select a task or switch to the task workspace to open task tools."
        case .kanban:
            return "Select a task card in Kanban to show its AI, quality, and review tools here."
        case .task:
            return "Select a task to show its inspector tools."
        }
    }

    private func syncWorkspaceState() {
        guard let task = inspectorTask else { return }
        workspaceState.loadIfNeeded(task)
    }

    private var inspectorActions: [EditorAssistAction] {
        [
            .askAI,
            .rewriteSelection,
            .makeClearer,
            .makeShorter,
            .continueWriting,
            .generateAcceptanceCriteria,
            .tightenGoal,
            .findAmbiguity,
            .splitTask
        ]
    }

    private var targetSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            InspectorMetricRow(label: "Target", value: workspaceState.currentAssistTarget.label)
            if workspaceState.selectionState.hasSelection {
                Label("Selection ready", systemImage: "text.cursor")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                Text("Select text in the brief editor, place the cursor in a section, or run AI against the full brief.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func runAssist(action: EditorAssistAction, customInstruction: String = "") {
        workspaceState.inspectorPresented = true
        Task {
            await store.runEditorAssist(
                action: action,
                documentMarkdown: workspaceState.editorDocumentMarkdown,
                target: workspaceState.currentAssistTarget,
                customInstruction: customInstruction
            )
        }
    }

    private func editorAssistIcon(for action: EditorAssistAction) -> String {
        switch action {
        case .askAI: "sparkles"
        case .rewriteSelection: "wand.and.stars"
        case .makeClearer: "text.alignleft"
        case .makeShorter: "arrow.down.to.line.compact"
        case .continueWriting: "text.badge.plus"
        case .tightenGoal: "target"
        case .findAmbiguity: "questionmark.bubble"
        case .generateAcceptanceCriteria: "checklist"
        case .splitTask: "square.split.2x1"
        case .customAsk: "ellipsis.bubble"
        }
    }

    private func editorAssistPreviewText(for proposal: AIAssistProposal) -> String {
        let replacement = proposal.replacementMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if !replacement.isEmpty {
            return replacement
        }

        let rawOutput = proposal.rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return rawOutput.isEmpty ? "No generated result was returned." : rawOutput
    }

    private func workerList(_ title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            if values.isEmpty {
                Text("None")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(values.prefix(5), id: \.self) { value in
                    Text(value)
                        .font(.caption)
                        .lineLimit(2)
                }
            }
        }
    }

    private func proposalRow(_ proposal: TaskProposal) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(proposal.title)
                .font(.caption.weight(.semibold))
            Text(proposal.reasonDiscovered)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            HStack(spacing: 8) {
                CompactStatusChip(label: "Priority", value: proposal.suggestedPriority.displayName)
                CompactStatusChip(label: "Stage", value: proposal.suggestedStage.displayName)
            }
            if !proposal.acceptanceCriteria.isEmpty {
                Text(proposal.acceptanceCriteria.joined(separator: " | "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack {
                Button("Create Task") {
                    store.createTask(from: proposal)
                }
                .buttonStyle(.bordered)
                Button("Dismiss") {
                    store.dismissTaskProposal(proposal)
                }
                .buttonStyle(.borderless)
            }
            .controlSize(.small)
        }
        .padding(.vertical, 6)
    }

    private func inspectorActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(store.selectedTask == nil || store.isWorking)
    }
}

private struct InspectorToolSectionView<Content: View>: View {
    var icon: String
    var title: String
    @Binding var isExpanded: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator.opacity(0.55))
        )
    }
}

private struct InspectorMetricRow: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
        }
    }
}

private struct CompactStatusChip: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }
}
