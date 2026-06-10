import FactoryDesktopCore
import SwiftUI

struct WorkerRunDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let detail: WorkerRunDetail

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    controls
                    summaryGrid
                    promptSection
                    reportSection
                    proposalsSection
                    lifecycleSection
                    notificationsSection
                    eventsSection
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 760, minHeight: 720)
        .task {
            await store.refreshActiveWorkerProcesses()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text("Worker Run Detail")
                    .font(.title3.weight(.semibold))
                Text("\(detail.task.title) · \(detail.task.id.shortID)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Close")
        }
        .padding(20)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    Task { await store.openWorkerLog() }
                } label: {
                    Label("Open Log", systemImage: "doc.plaintext")
                }
                .disabled(detail.execution?.logPath == nil)

                Button {
                    Task { await store.openWorkerWorktree() }
                } label: {
                    Label("Open Worktree", systemImage: "folder")
                }
                .disabled(detail.workspace?.worktreePath == nil)

                Button {
                    Task { await store.resumeWorker() }
                } label: {
                    Label("Resume Worker", systemImage: "play.circle")
                }
                .disabled(detail.session == nil || store.isWorking)

                Button {
                    Task { await store.retryWorkerRun() }
                } label: {
                    Label("Retry Run", systemImage: "arrow.clockwise")
                }
                .disabled(store.isWorking)
            }
            HStack(spacing: 8) {
                Button {
                    store.markWorkerRunFailed()
                } label: {
                    Label("Mark Failed", systemImage: "exclamationmark.octagon")
                }
                .disabled(detail.execution == nil || store.isWorking)

                Button {
                    store.markWorkerNeedsReview()
                } label: {
                    Label("Mark Needs Review", systemImage: "eye")
                }
                .disabled(store.isWorking)

                Button {
                    store.retryParseWorkerReport()
                } label: {
                    Label("Retry Parse", systemImage: "text.magnifyingglass")
                }
                .disabled(detail.report?.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

                Button {
                    Task { await store.cancelWorkerRun() }
                } label: {
                    Label("Stop", systemImage: "stop.circle")
                }
                .disabled(!store.workerRunIsCancellable(detail.execution))
                .help("Stop is unavailable for completed or detached runs.")
            }
            Text(store.workerRunIsCancellable(detail.execution) ? "Stop sends a graceful termination request, then force-kills only if the worker does not exit." : "Stop is unavailable for completed or detached runs.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .controlSize(.small)
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], alignment: .leading, spacing: 10) {
            detailRow("Task", "\(detail.task.title) · \(detail.task.id.shortID)")
            detailRow("Workspace", detail.workspace?.worktreePath ?? "Unavailable")
            detailRow("Attempt", detail.execution?.runReason ?? "Unavailable")
            detailRow("Provider", detail.session?.provider.displayName ?? "Unavailable")
            detailRow("Execution Status", detail.execution?.status.displayName ?? "Unavailable")
            detailRow("Process Status", store.workerProcessStatus(for: detail.execution).displayName)
            detailRow("Command", detail.execution?.command ?? "Unavailable", monospace: true)
            detailRow("Started", detail.execution?.startedAt.formatted(date: .abbreviated, time: .standard) ?? "Unavailable")
            detailRow("Ended", detail.execution?.endedAt?.formatted(date: .abbreviated, time: .standard) ?? "Still running or unavailable")
            detailRow("Exit Code", detail.execution?.exitCode.map(String.init) ?? "Unavailable")
            detailRow("Log Path", detail.execution?.logPath ?? "Unavailable", monospace: true)
        }
    }

    private var promptSection: some View {
        detailTextSection(
            title: "Prompt Sent to Codex",
            text: detail.prompt,
            emptyText: "No prompt was recorded for this session."
        )
    }

    @ViewBuilder
    private var reportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Worker Report")
            if let report = detail.report {
                HStack(spacing: 8) {
                    WorkerDetailChip(label: "Report", value: report.status.displayName)
                    WorkerDetailChip(label: "Parse", value: report.parseStatus.displayName)
                    if let recommended = report.recommendedTaskStatus {
                        WorkerDetailChip(label: "Recommended", value: recommended.displayName)
                    }
                }
                if let parseError = report.parseError, !parseError.isEmpty {
                    Label(parseError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if !report.summary.isEmpty {
                    Text(report.summary)
                        .font(.body)
                        .textSelection(.enabled)
                }
                valueList("Files Changed", values: report.filesChanged)
                valueList("Tests Run", values: report.testsRun)
                valueList("Risks", values: report.risks)
                valueList("Blockers", values: report.blockers)
                if !report.nextRecommendedAction.isEmpty {
                    detailRow("Next Recommended Action", report.nextRecommendedAction)
                }
                detailTextSection(title: "Raw Report Text", text: report.rawText, emptyText: "No raw report text was captured.")
            } else {
                Text("No worker report was recorded.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var proposalsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Proposed Follow-up Tasks")
            let proposed = detail.proposals.filter { $0.status == .proposed }
            if proposed.isEmpty {
                Text("No proposed follow-up tasks.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(proposed) { proposal in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(proposal.title)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Button("Create Task") {
                                store.createTask(from: proposal)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        Text(proposal.reasonDiscovered)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !proposal.sourceFiles.isEmpty {
                            Text(proposal.sourceFiles.joined(separator: ", "))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    @ViewBuilder
    private var lifecycleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Lifecycle Snapshots")
            if detail.lifecycleSnapshots.isEmpty {
                Text("No lifecycle snapshots yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(detail.lifecycleSnapshots) { snapshot in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            WorkerDetailChip(label: "Worktree", value: snapshot.worktreeExists ? "Exists" : "Missing")
                            WorkerDetailChip(label: "Branch", value: snapshot.branchExists ? "Exists" : "Missing")
                            WorkerDetailChip(label: "Dirty", value: snapshot.dirtyState)
                            Text(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Text(snapshot.recommendedAction)
                            .font(.caption.weight(.semibold))
                        valueList("Evidence", values: snapshot.evidence)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    @ViewBuilder
    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Notifications")
            if detail.notifications.isEmpty {
                Text("No worker notifications.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(detail.notifications) { notification in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: notification.level == .error ? "xmark.octagon" : "exclamationmark.triangle")
                            .foregroundStyle(notification.level == .error ? Color.red : Color.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(notification.message)
                                .font(.caption)
                                .textSelection(.enabled)
                            Text(notification.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button(notification.isRead ? "Dismissed" : "Dismiss") {
                            store.dismissRunnerNotification(notification)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .disabled(notification.isRead)
                    }
                    .padding(.vertical, 5)
                }
            }
        }
    }

    @ViewBuilder
    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Automation and Task Events")
            if detail.events.isEmpty {
                Text("No task events recorded.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(detail.events) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(event.kind.displayName)
                                .font(.subheadline.weight(.semibold))
                            if let previous = event.previousStatus, let new = event.newStatus {
                                Text("\(previous.displayName) -> \(new.displayName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(event.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if !event.message.isEmpty {
                            Text(event.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
        }
    }

    private func detailRow(_ label: String, _ value: String, monospace: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(monospace ? .system(.caption, design: .monospaced) : .caption)
                .lineLimit(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private func detailTextSection(title: String, text: String, emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(title)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    Text(text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(minHeight: 120, maxHeight: 260)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func valueList(_ title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
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

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
    }
}

private struct WorkerDetailChip: View {
    var label: String
    var value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.5), in: Capsule())
    }
}
