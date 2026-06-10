import FactoryDesktopCore
import MarkdownUI
import SwiftUI

struct WorkerRunDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let detail: WorkerRunDetail
    @State private var followUpText = ""
    @State private var rawLogsExpanded: Bool

    init(detail: WorkerRunDetail, rawLogsInitiallyExpanded: Bool = false) {
        self.detail = detail
        _rawLogsExpanded = State(initialValue: rawLogsInitiallyExpanded)
    }

    private var conversation: WorkerConversation {
        WorkerConversationBuilder.build(
            detail: detail,
            processStatus: store.workerProcessStatus(for: detail.execution)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            WorkerConversationView(
                conversation: conversation,
                rawLogsExpanded: $rawLogsExpanded,
                createProposal: { store.createTask(from: $0) },
                dismissProposal: { store.dismissTaskProposal($0) },
                openLog: { Task { await store.openWorkerLog() } },
                openWorktree: { Task { await store.openWorkerWorktree() } }
            )
            Divider()
            WorkerComposerView(
                text: $followUpText,
                isWorking: store.isWorking,
                isCancellable: store.workerRunIsCancellable(detail.execution),
                submitTitle: detail.session == nil ? "Assign" : "Resume",
                submitSystemImage: detail.session == nil ? "sparkles" : "play.circle",
                onSubmit: submitFollowUp,
                onStop: { Task { await store.cancelWorkerRun() } }
            )
        }
        .frame(minWidth: 820, minHeight: 720)
        .task {
            await store.refreshActiveWorkerProcesses()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                Text("AI Worker Conversation")
                    .font(.title3.weight(.semibold))
                Text("\(conversation.preview.statusLine) · \(detail.task.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            HStack(spacing: 8) {
                if detail.workspace?.worktreePath != nil {
                    Button {
                        Task { await store.openWorkerWorktree() }
                    } label: {
                        Label("Worktree", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close")
            }
        }
        .padding(20)
    }

    private func submitFollowUp(_ text: String) {
        let instruction = text.trimmingCharacters(in: .whitespacesAndNewlines)
        followUpText = ""
        Task {
            if detail.session == nil {
                await store.assignSelectedTaskToAIWorker(additionalInstruction: instruction)
            } else {
                await store.resumeWorker(additionalInstruction: instruction)
            }
        }
    }
}

struct WorkerWorkspaceView: View {
    @EnvironmentObject private var store: AppStore

    let task: FactoryTask
    var openDiff: () -> Void

    @State private var followUpText = ""
    @State private var rawLogsExpanded = false

    private var detail: WorkerRunDetail? {
        guard store.workerRunDetail?.task.id == task.id else { return nil }
        return store.workerRunDetail
    }

    var body: some View {
        VStack(spacing: 0) {
            if let detail {
                let conversation = WorkerConversationBuilder.build(
                    detail: detail,
                    processStatus: store.workerProcessStatus(for: detail.execution)
                )
                header(detail: detail, conversation: conversation)
                Divider()
                WorkerConversationView(
                    conversation: conversation,
                    rawLogsExpanded: $rawLogsExpanded,
                    createProposal: { store.createTask(from: $0) },
                    dismissProposal: { store.dismissTaskProposal($0) },
                    openLog: { Task { await store.openWorkerLog() } },
                    openWorktree: { Task { await store.openWorkerWorktree() } }
                )
                Divider()
                WorkerComposerView(
                    text: $followUpText,
                    isWorking: store.isWorking,
                    isCancellable: store.workerRunIsCancellable(detail.execution),
                    submitTitle: detail.session == nil ? "Assign Worker" : "Resume Worker",
                    submitSystemImage: detail.session == nil ? "sparkles" : "play.circle",
                    onSubmit: submitFollowUp,
                    onStop: { Task { await store.cancelWorkerRun() } }
                )
            } else {
                loadingState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator.opacity(0.55))
        )
        .task(id: task.id) {
            rawLogsExpanded = store.workerRawLogsInitiallyExpanded
            store.prepareWorkerRunDetailForWorkspace(expandRawLogs: store.workerRawLogsInitiallyExpanded)
            await store.refreshActiveWorkerProcesses()
        }
        .onChange(of: store.workerRawLogsInitiallyExpanded) { _, expanded in
            if expanded {
                rawLogsExpanded = true
            }
        }
    }

    private func header(detail: WorkerRunDetail, conversation: WorkerConversation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        StatusPill(detail.session?.provider.displayName ?? "AI Worker")
                        StatusPill(reportStatusText(for: detail, conversation: conversation))
                    }
                    Text(task.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    Text("TASK-\(task.id.shortID.uppercased()) · \(workspaceSummary(for: detail))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 12)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        submitFollowUp(followUpText)
                    } label: {
                        Label(detail.session == nil ? "Assign Worker" : "Resume Worker", systemImage: detail.session == nil ? "sparkles" : "play.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(store.isWorking)

                    Button {
                        openDiff()
                    } label: {
                        Label("Review Diff", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        rawLogsExpanded = true
                    } label: {
                        Label("View Logs", systemImage: "doc.plaintext")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!conversation.preview.hasRawLogs)

                    Button {
                        Task { await store.openWorkerWorktree() }
                    } label: {
                        Label("Open Worktree", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(detail.workspace?.worktreePath == nil)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Label(conversation.preview.latestMeaningfulMessage, systemImage: "text.bubble")
                    .lineLimit(2)
                HStack(spacing: 12) {
                    Label(conversation.preview.verificationDigest, systemImage: "checkmark.seal")
                        .lineLimit(1)
                    Label(conversation.preview.changedFilesSummary, systemImage: "doc.on.doc")
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !conversation.preview.nextRecommendedAction.isEmpty {
                Label(conversation.preview.nextRecommendedAction, systemImage: "arrow.right.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(18)
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 14) {
            ContentUnavailableView(
                "Worker Workspace",
                systemImage: "sparkles",
                description: Text("Preparing the worker conversation for this task.")
            )
            WorkerComposerView(
                text: $followUpText,
                isWorking: store.isWorking,
                isCancellable: false,
                submitTitle: "Assign Worker",
                submitSystemImage: "sparkles",
                onSubmit: submitFollowUp,
                onStop: {}
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func reportStatusText(for detail: WorkerRunDetail, conversation: WorkerConversation) -> String {
        if let report = detail.report {
            return report.status.displayName
        }
        if let execution = detail.execution {
            return execution.status.displayName
        }
        return conversation.preview.statusLine
    }

    private func workspaceSummary(for detail: WorkerRunDetail) -> String {
        var parts: [String] = []
        if let branchName = detail.workspace?.branchName, !branchName.isEmpty {
            parts.append(branchName)
        }
        if let worktreePath = detail.workspace?.worktreePath, !worktreePath.isEmpty {
            parts.append(URL(fileURLWithPath: worktreePath).lastPathComponent)
        }
        return parts.isEmpty ? "No worker worktree yet" : parts.joined(separator: " · ")
    }

    private func submitFollowUp(_ text: String) {
        let instruction = text.trimmingCharacters(in: .whitespacesAndNewlines)
        followUpText = ""
        Task {
            if detail?.session == nil {
                await store.assignSelectedTaskToAIWorker(additionalInstruction: instruction)
            } else {
                await store.resumeWorker(additionalInstruction: instruction)
            }
        }
    }
}

private struct WorkerConversationView: View {
    var conversation: WorkerConversation
    @Binding var rawLogsExpanded: Bool
    var createProposal: (TaskProposal) -> Void
    var dismissProposal: (TaskProposal) -> Void
    var openLog: () -> Void
    var openWorktree: () -> Void

    var body: some View {
        ScrollView {
            ConversationTimelineView(
                events: conversation.events,
                rawLogsExpanded: $rawLogsExpanded,
                createProposal: createProposal,
                dismissProposal: dismissProposal,
                openLog: openLog,
                openWorktree: openWorktree
            )
            .padding(20)
            .frame(maxWidth: 920, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.72))
    }
}

private struct ConversationTimelineView: View {
    var events: [WorkerConversationEvent]
    @Binding var rawLogsExpanded: Bool
    var createProposal: (TaskProposal) -> Void
    var dismissProposal: (TaskProposal) -> Void
    var openLog: () -> Void
    var openWorktree: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(events) { event in
                HStack(alignment: .top, spacing: 12) {
                    timelineMarker(for: event.kind)
                    eventView(event)
                }
            }
        }
    }

    @ViewBuilder
    private func eventView(_ event: WorkerConversationEvent) -> some View {
        switch event.kind {
        case let .assignment(assignment):
            WorkerMessageBubble(role: "Factory", systemImage: "building.2", text: assignment.summary)
        case let .workerMessage(message):
            WorkerMessageBubble(role: message.isFinal ? "Worker" : "Worker Update", systemImage: "sparkles", text: message.text)
        case let .toolSummary(summary):
            ToolSummaryCard(summary: summary)
        case let .checkResult(result):
            VerificationCard(result: result)
        case let .changedFiles(changedFiles):
            ChangedFilesCard(changedFiles: changedFiles, openWorktree: openWorktree)
        case let .report(report):
            WorkerReportCard(report: report)
        case let .proposedTask(proposedTask):
            ProposedTaskCard(
                proposal: proposedTask.proposal,
                createProposal: createProposal,
                dismissProposal: dismissProposal
            )
        case let .automationEvent(automation):
            AutomationEventCard(event: automation)
        case let .warning(warning):
            WarningCard(warning: warning)
        case let .rawLogReference(reference):
            RawLogsDisclosure(
                reference: reference,
                isExpanded: $rawLogsExpanded,
                openLog: openLog
            )
        }
    }

    private func timelineMarker(for kind: WorkerConversationEvent.Kind) -> some View {
        let image: String
        let tint: Color
        switch kind {
        case .assignment:
            image = "building.2"
            tint = .accentColor
        case .workerMessage:
            image = "sparkles"
            tint = .accentColor
        case .toolSummary:
            image = "terminal"
            tint = .secondary
        case .checkResult:
            image = "checkmark.seal"
            tint = .green
        case .changedFiles:
            image = "doc.on.doc"
            tint = .blue
        case .report:
            image = "doc.text.magnifyingglass"
            tint = .accentColor
        case .proposedTask:
            image = "plus.square.on.square"
            tint = .purple
        case .automationEvent:
            image = "gearshape"
            tint = .secondary
        case .warning:
            image = "exclamationmark.triangle"
            tint = .orange
        case .rawLogReference:
            image = "ladybug"
            tint = .secondary
        }
        return Image(systemName: image)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 26, height: 26)
            .background(.background, in: Circle())
    }
}

private struct WorkerMessageBubble: View {
    var role: String
    var systemImage: String
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(role, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Markdown(text)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(cardStroke)
    }
}

private struct ToolSummaryCard: View {
    var summary: WorkerConversationEvent.ToolSummary

    var body: some View {
        CompactConversationCard(systemImage: "terminal", title: summary.title) {
            HStack(spacing: 8) {
                StatusPill(summary.status)
                Text(summary.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }
}

private struct VerificationCard: View {
    var result: WorkerConversationEvent.CheckResult

    var body: some View {
        CompactConversationCard(systemImage: "checkmark.seal", title: "Verification") {
            Text(result.summary)
                .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(result.rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: row.status == "Failed" ? "xmark.circle" : "checkmark.circle")
                            .foregroundStyle(row.status == "Failed" ? Color.red : Color.green)
                        Text(row.label)
                            .font(.caption)
                            .textSelection(.enabled)
                        Spacer()
                        StatusPill(row.status)
                    }
                }
            }
        }
    }
}

private struct ChangedFilesCard: View {
    var changedFiles: WorkerConversationEvent.ChangedFiles
    var openWorktree: () -> Void

    var body: some View {
        CompactConversationCard(systemImage: "doc.on.doc", title: "Changed Files") {
            HStack {
                Text(changedFiles.summary)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    openWorktree()
                } label: {
                    Label("Open", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            if !changedFiles.files.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(changedFiles.files.prefix(8), id: \.self) { file in
                        Text(file)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    if changedFiles.files.count > 8 {
                        Text("+ \(changedFiles.files.count - 8) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if !changedFiles.diffStat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(changedFiles.diffStat)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct WorkerReportCard: View {
    var report: WorkerConversationEvent.Report

    var body: some View {
        CompactConversationCard(systemImage: "doc.text.magnifyingglass", title: "Worker Report") {
            HStack(spacing: 8) {
                StatusPill(report.status.displayName)
                StatusPill("Parse: \(report.parseStatus.displayName)")
            }
            if let parseError = report.parseError, !parseError.isEmpty {
                Label(parseError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if !report.summary.isEmpty {
                Markdown(report.summary)
                    .textSelection(.enabled)
            }
            valueList(title: "Risks", values: report.risks)
            valueList(title: "Blockers", values: report.blockers)
            if !report.nextRecommendedAction.isEmpty {
                LabeledValue(label: "Next", value: report.nextRecommendedAction)
            }
        }
    }

    private func valueList(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if values.isEmpty {
                Text("None")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

private struct ProposedTaskCard: View {
    var proposal: TaskProposal
    var createProposal: (TaskProposal) -> Void
    var dismissProposal: (TaskProposal) -> Void

    var body: some View {
        CompactConversationCard(systemImage: "plus.square.on.square", title: "Proposed Task") {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(proposal.title)
                        .font(.subheadline.weight(.semibold))
                    Text(proposal.reasonDiscovered)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    HStack(spacing: 8) {
                        StatusPill(proposal.suggestedPriority.displayName)
                        StatusPill(proposal.suggestedStage.displayName)
                        StatusPill(proposal.status.rawValue.capitalized)
                    }
                }
                Spacer()
                if proposal.status == .proposed {
                    VStack(spacing: 6) {
                        Button("Create Task") {
                            createProposal(proposal)
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Dismiss") {
                            dismissProposal(proposal)
                        }
                        .buttonStyle(.borderless)
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}

private struct AutomationEventCard: View {
    var event: WorkerConversationEvent.AutomationEvent

    var body: some View {
        CompactConversationCard(systemImage: "gearshape", title: event.title) {
            if let previous = event.previousStatus, let new = event.newStatus {
                Text("\(previous.displayName) -> \(new.displayName)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if !event.message.isEmpty {
                Text(event.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct WarningCard: View {
    var warning: WorkerConversationEvent.Warning

    var body: some View {
        CompactConversationCard(systemImage: warning.level == .error ? "xmark.octagon" : "exclamationmark.triangle", title: warning.level.rawValue.capitalized) {
            Text(warning.message)
                .font(.caption)
                .foregroundStyle(warning.level == .error ? Color.red : Color.orange)
                .textSelection(.enabled)
        }
    }
}

private struct RawLogsDisclosure: View {
    var reference: WorkerConversationEvent.RawLogReference
    @Binding var isExpanded: Bool
    var openLog: () -> Void
    @State private var logText: String?

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                if let logPath = reference.logPath {
                    HStack {
                        LabeledValue(label: "Log", value: URL(fileURLWithPath: logPath).lastPathComponent)
                        Spacer()
                        Button {
                            openLog()
                        } label: {
                            Label("Open Log", systemImage: "doc.plaintext")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    rawTextBlock(logText ?? "Loading raw log...")
                        .onAppear(perform: loadLogIfNeeded)
                }
                if !reference.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    debugSection(title: "Prompt Snapshot", text: reference.prompt)
                }
                if !reference.rawReport.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    debugSection(title: "Raw Report", text: reference.rawReport)
                }
            }
            .padding(.top, 10)
        } label: {
            Label(isExpanded ? "Hide Raw Logs" : "View Raw Logs / Show Raw Output", systemImage: "ladybug")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(cardStroke)
    }

    private func debugSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            rawTextBlock(text)
        }
    }

    private func rawTextBlock(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .frame(minHeight: 90, maxHeight: 220)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func loadLogIfNeeded() {
        guard logText == nil, let logPath = reference.logPath else { return }
        logText = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? "Log file is unavailable."
    }
}

private struct WorkerComposerView: View {
    @Binding var text: String
    var isWorking: Bool
    var isCancellable: Bool
    var submitTitle: String
    var submitSystemImage: String
    var onSubmit: (String) -> Void
    var onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                TextField("Add optional follow-up instruction...", text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                Button {
                    onSubmit(text)
                } label: {
                    Label(submitTitle, systemImage: submitSystemImage)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking)
                if isCancellable {
                    Button {
                        onStop()
                    } label: {
                        Label("Stop", systemImage: "stop.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
            Text("Follow-up text is appended to the next worker turn; the worker report format remains required.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.bar)
    }
}

private struct CompactConversationCard<Content: View>: View {
    var systemImage: String
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(cardStroke)
    }
}

private struct StatusPill: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.5), in: Capsule())
    }
}

private struct LabeledValue: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .lineLimit(3)
                .textSelection(.enabled)
        }
    }
}

private var cardStroke: some View {
    RoundedRectangle(cornerRadius: 8)
        .stroke(.separator.opacity(0.55))
}
