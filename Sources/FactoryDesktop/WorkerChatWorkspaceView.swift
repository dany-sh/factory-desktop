import FactoryDesktopCore
import MarkdownUI
import SwiftUI

struct WorkerChatWorkspaceView: View {
    @EnvironmentObject private var store: AppStore

    let task: FactoryTask
    var openDiff: () -> Void

    @State private var composerText = ""
    @State private var selectedInspectorTab: WorkerInspectorTab = .evidence

    private var timeline: WorkerTimeline {
        store.workerTimelineV2
    }

    private var isRunning: Bool {
        store.workerComposerState.phase == .running ||
            store.workerComposerState.phase == .sending ||
            store.workerComposerState.phase == .stopping ||
            store.latestRunnerExecution?.status == .running
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                sessionRail
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 280, maxHeight: .infinity)
                centerWorkspace
                    .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
                inspector
                    .frame(minWidth: 300, idealWidth: 360, maxWidth: 480, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator.opacity(0.55))
        )
        .task(id: task.id) {
            store.prepareWorkerRunDetailForWorkspace()
            await store.refreshActiveWorkerProcesses()
            composerText = store.workerComposerState.draft
        }
        .onChange(of: store.workerComposerState.taskId) { _, _ in
            composerText = store.workerComposerState.draft
        }
        .onChange(of: store.workerComposerState.draft) { _, draft in
            if draft != composerText {
                composerText = draft
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "person.text.rectangle")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(task.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    WorkerPill("TASK-\(task.id.shortID.uppercased())")
                    WorkerPill(store.workerComposerState.phase.displayName)
                }
                HStack(spacing: 8) {
                    WorkerPill(store.selectedRunnerSession?.provider.displayName ?? "No runner")
                    WorkerPill(store.selectedRunnerProjectLink?.preferredModelProfile?.modelName ?? store.selectedModel)
                    WorkerPill(workspaceSummary)
                    if let execution = store.latestRunnerExecution {
                        WorkerPill(execution.status.displayName)
                    }
                }
            }

            Spacer(minLength: 12)

            primaryAction
        }
        .padding(16)
    }

    private var primaryAction: some View {
        Group {
            if store.workerRunIsCancellable(store.latestRunnerExecution) {
                Button {
                    Task { await store.stopWorkerFromComposer() }
                } label: {
                    Label("Stop", systemImage: "stop.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(store.workerComposerState.phase == .stopping)
            } else {
                Button {
                    Task {
                        if composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            store.updateWorkerComposerDraft(defaultInstruction)
                        }
                        await store.submitWorkerComposerDraft()
                    }
                } label: {
                    Label(store.selectedRunnerSession == nil ? "Start Worker" : "Continue", systemImage: store.selectedRunnerSession == nil ? "sparkles" : "play.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isWorking)
            }
        }
        .controlSize(.regular)
    }

    private var workspaceSummary: String {
        if let branch = store.selectedRunnerWorkspace?.branchName, !branch.isEmpty {
            return branch
        }
        if let path = store.selectedRunnerWorkspace?.worktreePath, !path.isEmpty {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        return "No worktree"
    }

    private var defaultInstruction: String {
        "Start work on this task. Preserve safety gates and report changed files, checks, risks, and next action."
    }

    private var sessionRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sessions")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let session = store.selectedRunnerSession {
                railCard(
                    title: "Active Run",
                    subtitle: session.provider.displayName,
                    status: session.status.displayName,
                    systemImage: "play.circle"
                )
            } else {
                railCard(
                    title: "No Session",
                    subtitle: "Start the worker from this workspace.",
                    status: "Idle",
                    systemImage: "pause.circle"
                )
            }

            if !store.workerMessageQueue.filter({ $0.status == .queued }).isEmpty {
                Text("Queue")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(store.workerMessageQueue.filter { $0.status == .queued }) { item in
                    queuedMessageRow(item)
                }
            }

            if !store.runnerWorkspaces.isEmpty {
                Text("Workspaces")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(store.runnerWorkspaces.prefix(5)) { workspace in
                    railCard(
                        title: workspace.branchName,
                        subtitle: URL(fileURLWithPath: workspace.worktreePath).lastPathComponent,
                        status: workspace.cleaned ? "Cleaned" : (workspace.archived ? "Archived" : "Active"),
                        systemImage: "folder"
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.bar.opacity(0.45))
    }

    private func railCard(title: String, subtitle: String, status: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            WorkerPill(status)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.45))
        )
    }

    private func queuedMessageRow(_ item: WorkerMessageQueueItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(item.body)
                .font(.caption)
                .lineLimit(4)
            HStack(spacing: 8) {
                Button {
                    Task { await store.sendQueuedWorkerMessageNow(item) }
                } label: {
                    Image(systemName: "paperplane")
                }
                .help("Send now")
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    store.deleteQueuedWorkerMessage(item)
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete queued message")
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
        .padding(9)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.45))
        )
    }

    private var centerWorkspace: some View {
        VStack(spacing: 0) {
            timelineHeader
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if timeline.truncatedCount > 0 {
                        WorkerNotice(text: "\(timeline.truncatedCount) older timeline item\(timeline.truncatedCount == 1 ? "" : "s") hidden. Use logs or artifacts for full history.")
                    }
                    if timeline.items.isEmpty {
                        ContentUnavailableView(
                            "Worker Timeline",
                            systemImage: "sparkles",
                            description: Text("Start a worker session or send an instruction to build a readable task timeline.")
                        )
                        .padding(.top, 80)
                    } else {
                        ForEach(timeline.items) { item in
                            timelineItemView(item)
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: 860, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            Divider()
            composer
        }
    }

    private var timelineHeader: some View {
        HStack(spacing: 10) {
            Label("Worker Timeline", systemImage: "text.bubble")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if timeline.hiddenRawLogCount > 0 {
                WorkerPill("\(timeline.hiddenRawLogCount) raw log event\(timeline.hiddenRawLogCount == 1 ? "" : "s") in Logs")
            }
            Spacer()
            Button {
                openDiff()
            } label: {
                Label("Diff", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button {
                Task { await store.openWorkerWorktree() }
            } label: {
                Label("Worktree", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(store.selectedRunnerWorkspace?.worktreePath == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func timelineItemView(_ item: WorkerTimelineItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint(for: item.kind))
                .frame(width: 24, height: 24)
                .background(.background, in: Circle())
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                    if let status = item.status, !status.isEmpty {
                        WorkerPill(status)
                    }
                    Spacer()
                    Text(item.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if !item.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Markdown(item.body)
                        .textSelection(.enabled)
                }
                if !item.metadata.isEmpty {
                    FlowMetadata(items: item.metadata)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator.opacity(0.5))
            )
        }
    }

    private func tint(for kind: WorkerTimelineItem.Kind) -> Color {
        switch kind {
        case .message: .accentColor
        case .command, .tool: .secondary
        case .fileChange: .blue
        case .check: .green
        case .report: .accentColor
        case .warning, .approval, .question: .orange
        case .error: .red
        case .fallback: .secondary
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !store.workerComposerState.parsedMentions.isEmpty {
                FlowMetadata(items: store.workerComposerState.parsedMentions.map {
                    WorkerTimelineMetadata(label: $0.kind.rawValue, value: $0.rawText)
                })
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField(composerPlaceholder, text: $composerText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...6)
                    .onChange(of: composerText) { _, text in
                        store.updateWorkerComposerDraft(text)
                    }

                Button {
                    Task { await store.submitWorkerComposerDraft() }
                } label: {
                    Image(systemName: isRunning ? "text.badge.plus" : "paperplane.fill")
                }
                .help(isRunning ? "Queue message" : "Send message")
                .buttonStyle(.borderedProminent)
                .disabled(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.workerComposerState.phase == .sending)

                Button {
                    Task { await store.stopWorkerFromComposer() }
                } label: {
                    Image(systemName: "stop.circle")
                }
                .help("Stop active worker run")
                .buttonStyle(.bordered)
                .disabled(!store.workerRunIsCancellable(store.latestRunnerExecution))
            }
        }
        .padding(12)
        .background(.bar)
    }

    private var composerPlaceholder: String {
        isRunning ? "Queue a follow-up, or wait for the active run to finish..." : "Ask the worker to continue, review, run checks, or focus context..."
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("Inspector", selection: $selectedInspectorTab) {
                ForEach(WorkerInspectorTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch selectedInspectorTab {
                    case .evidence:
                        evidenceInspector
                    case .changes:
                        changesInspector
                    case .checks:
                        checksInspector
                    case .logs:
                        logsInspector
                    case .context:
                        contextInspector
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(.bar.opacity(0.32))
    }

    private var evidenceInspector: some View {
        VStack(alignment: .leading, spacing: 10) {
            inspectorTitle("Evidence", "doc.text.magnifyingglass")
            if let report = store.latestWorkerReport {
                inspectorRow("Report", report.status.displayName)
                Text(report.summary.isEmpty ? "No summary recorded." : report.summary)
                    .font(.caption)
                    .textSelection(.enabled)
                list("Risks", report.risks)
                list("Blockers", report.blockers)
                if !report.nextRecommendedAction.isEmpty {
                    inspectorRow("Next", report.nextRecommendedAction)
                }
            }
            if !store.runnerNotifications.isEmpty {
                Divider()
                list("Warnings", store.runnerNotifications.map(\.message))
            }
            if !store.workerEvidence.isEmpty {
                Divider()
                ForEach(store.workerEvidence.prefix(8)) { evidence in
                    inspectorRow(evidence.kind.rawValue.capitalized, evidence.title)
                }
            }
            if store.latestWorkerReport == nil && store.workerEvidence.isEmpty && store.runnerNotifications.isEmpty {
                emptyInspectorText("No worker evidence yet.")
            }
        }
    }

    private var changesInspector: some View {
        VStack(alignment: .leading, spacing: 10) {
            inspectorTitle("Changes", "doc.on.doc")
            let files = store.gitSnapshot.changedFiles.isEmpty ? (store.latestWorkerReport?.filesChanged ?? []) : store.gitSnapshot.changedFiles
            if files.isEmpty && store.gitSnapshot.diffStat.isEmpty {
                emptyInspectorText("No changed files recorded.")
            } else {
                inspectorRow("Files", "\(files.count)")
                list("Changed Files", files)
                if !store.gitSnapshot.diffStat.isEmpty {
                    Text(store.gitSnapshot.diffStat)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                HStack {
                    Button {
                        openDiff()
                    } label: {
                        Label("Open Diff", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button {
                        Task { await store.openWorkerWorktree() }
                    } label: {
                        Label("Open Worktree", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(store.selectedRunnerWorkspace?.worktreePath == nil)
                }
            }
        }
    }

    private var checksInspector: some View {
        VStack(alignment: .leading, spacing: 10) {
            inspectorTitle("Checks", "checkmark.seal")
            if let execution = store.latestRunnerExecution {
                inspectorRow("Execution", execution.status.displayName)
                inspectorRow("Exit Code", execution.exitCode.map(String.init) ?? "not recorded")
                if let command = execution.command {
                    Text(command)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            if !store.workflowCheckSummaries.isEmpty {
                Divider()
                ForEach(store.workflowCheckSummaries) { summary in
                    inspectorRow(summary.kind.displayName, summary.status.displayName)
                    if let command = summary.command {
                        Text(command)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            } else if store.latestRunnerExecution == nil {
                emptyInspectorText("No checks recorded yet.")
            }
            if let tests = store.latestWorkerReport?.testsRun, !tests.isEmpty {
                Divider()
                list("Worker-Recorded Checks", tests)
            }
        }
    }

    private var logsInspector: some View {
        VStack(alignment: .leading, spacing: 10) {
            inspectorTitle("Logs", "doc.plaintext")
            if timeline.hiddenRawLogCount > 0 {
                inspectorRow("Hidden from Timeline", "\(timeline.hiddenRawLogCount) raw event\(timeline.hiddenRawLogCount == 1 ? "" : "s")")
            }
            if let log = store.latestRunnerExecution?.logPath ?? store.selectedRunnerSession?.transcriptPath {
                inspectorRow("Raw Log", log)
                Button {
                    Task { await store.openWorkerLog() }
                } label: {
                    Label("Open Log", systemImage: "doc.plaintext")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                emptyInspectorText("No raw log is available.")
            }
        }
    }

    private var contextInspector: some View {
        VStack(alignment: .leading, spacing: 10) {
            inspectorTitle("Context", "paperclip")
            if let snapshot = store.workerPromptSnapshots.first {
                inspectorRow("Provider", snapshot.provider.displayName)
                inspectorRow("Model", snapshot.model ?? "unknown")
                inspectorRow("Tokens", "\(snapshot.tokenCount) / \(snapshot.budget)")
                inspectorRow("Snapshot", snapshot.id.shortID)
            } else {
                emptyInspectorText("No prompt snapshot has been captured yet.")
            }
            if !store.workerContextItems.isEmpty {
                Divider()
                ForEach(store.workerContextItems.prefix(12)) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(item.title)
                                .font(.caption.weight(.semibold))
                            Spacer()
                            WorkerPill(item.included ? "Included" : "Excluded")
                        }
                        Text(item.kind.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let path = item.path, !path.isEmpty {
                            Text(path)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .padding(8)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func inspectorTitle(_ text: String, _ systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
    }

    private func inspectorRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func list(_ title: String, _ values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            if values.isEmpty {
                Text("None")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(values.prefix(10), id: \.self) { value in
                    Text(value)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func emptyInspectorText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private enum WorkerInspectorTab: String, CaseIterable, Identifiable {
    case evidence
    case changes
    case checks
    case logs
    case context

    var id: String { rawValue }

    var title: String {
        switch self {
        case .evidence: "Evidence"
        case .changes: "Changes"
        case .checks: "Checks"
        case .logs: "Logs"
        case .context: "Context"
        }
    }
}

private struct WorkerPill: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.48), in: Capsule())
    }
}

private struct WorkerNotice: View {
    var text: String

    var body: some View {
        Label(text, systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator.opacity(0.45))
            )
    }
}

private struct FlowMetadata: View {
    var items: [WorkerTimelineMetadata]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(item.value)
                        .font(.caption2)
                        .lineLimit(2)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }
}
