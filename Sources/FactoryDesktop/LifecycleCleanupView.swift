import FactoryDesktopCore
import SwiftUI

struct LifecycleCleanupView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let report = store.latestLifecycleReport {
                let summary = store.projectHygieneSummary
                currentRepoStatus(report)
                taskLifecycleSyncSection
                preflightChecks(report.preflightGate)
                presentationGroups(summary)
                hygieneEvents(report)
            } else {
                Text("Run a lifecycle scan to inspect repo hygiene, Factory worktrees, branch cleanup candidates, and tracked artifact waste.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator.opacity(0.6))
        )
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Project Hygiene")
                    .font(.headline)
                Text(store.latestLifecycleReport.map { "Repo hygiene: \($0.preflightGate.level.displayName)" } ?? "No scan yet")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(gateColor(store.latestLifecycleReport?.preflightGate.level))
            }
            Spacer()
            Button {
                Task { await store.refreshLifecycleScan() }
            } label: {
                Label("Refresh Scan", systemImage: "arrow.clockwise")
            }
            .disabled(store.selectedProject == nil || store.isWorking)
        }
    }

    private func currentRepoStatus(_ report: RepoHygieneReport) -> some View {
        LifecycleSection(title: "Current Repo Status") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                LifecycleMetric(label: "Canonical", value: report.canonicalRepoPath)
                LifecycleMetric(label: "Branch", value: report.currentBranch ?? "unknown")
                LifecycleMetric(label: "HEAD", value: report.currentHEAD ?? "unknown")
                LifecycleMetric(label: "Default", value: report.defaultBranch)
                LifecycleMetric(label: "Origin default", value: report.originDefaultBranch ?? "unknown")
                LifecycleMetric(label: "Clean", value: report.workingTreeClean.map { $0 ? "yes" : "no" } ?? "unknown")
                LifecycleMetric(label: "Ahead / behind", value: "\(report.defaultAheadOfOrigin.map(String.init) ?? "unknown") / \(report.defaultBehindOrigin.map(String.init) ?? "unknown")")
            }
            if report.runnerEnvironment.hasGitOverrides {
                Text("Runner Git vars: GIT_DIR \(report.runnerEnvironment.gitDir ?? "unset"), GIT_WORK_TREE \(report.runnerEnvironment.gitWorkTree ?? "unset"), GIT_COMMON_DIR \(report.runnerEnvironment.gitCommonDir ?? "unset"), GIT_PREFIX \(report.runnerEnvironment.gitPrefix ?? "unset")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

    private var taskLifecycleSyncSection: some View {
        LifecycleSection(title: "Selected Task Lifecycle Sync") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Repo hygiene covers cleanup and safety for the repository. Lifecycle sync covers the selected task's status decision and Git-backed facts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if store.selectedTask != nil {
                    Button {
                        Task { await store.syncSelectedTaskLifecycle() }
                    } label: {
                        Label("Sync lifecycle", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.selectedTask == nil || store.isWorking)

                    LifecycleSyncSummaryView(
                        result: store.latestLifecycleSyncResult,
                        emptyMessage: "Run lifecycle sync to inspect task-specific Git facts."
                    )
                } else {
                    Text("Select a task to compare repo hygiene with task lifecycle facts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func preflightChecks(_ gate: LifecyclePreflightGate) -> some View {
        LifecycleSection(title: "Preflight Checks") {
            ForEach(gate.checks) { check in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(gateColor(check.level))
                        .frame(width: 8, height: 8)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(check.label)
                            .font(.subheadline.weight(.semibold))
                        Text(check.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(check.level.rawValue.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(gateColor(check.level))
                }
            }
        }
    }

    private func presentationGroups(_ summary: ProjectHygieneSummary) -> some View {
        LifecycleSection(title: "Cleanup Groups") {
            if summary.presentationGroups.isEmpty {
                Text("No lifecycle cleanup or artifact waste items in the latest scan.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(summary.presentationGroups) { group in
                    CleanupPresentationGroupView(group: group)
                        .environmentObject(store)
                }
            }
        }
    }

    private func hygieneEvents(_ report: RepoHygieneReport) -> some View {
        LifecycleSection(title: "Recent Hygiene Events") {
            ForEach(report.hygieneEvents, id: \.self) { event in
                Text(event)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func gateColor(_ level: LifecycleGateLevel?) -> Color {
        switch level {
        case .green: .green
        case .yellow: .orange
        case .red: .red
        case nil: .secondary
        }
    }
}

private struct CleanupPresentationGroupView: View {
    @EnvironmentObject private var store: AppStore
    var group: CleanupPresentationGroup
    @State private var isExpanded: Bool

    init(group: CleanupPresentationGroup) {
        self.group = group
        _isExpanded = State(initialValue: !group.collapsedByDefault)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if !group.lifecycleItems.isEmpty {
                    ForEach(group.lifecycleItems.prefix(12)) { item in
                        LifecycleItemRow(item: item)
                            .environmentObject(store)
                        if item.id != group.lifecycleItems.prefix(12).last?.id {
                            Divider()
                        }
                    }
                    if group.lifecycleItems.count > 12 {
                        Text("\(group.lifecycleItems.count - 12) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !group.artifactGroups.isEmpty {
                    ForEach(group.artifactGroups) { artifactGroup in
                        ArtifactWasteGroupRow(group: artifactGroup)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title)
                        .font(.subheadline.weight(.semibold))
                    Text("\(group.scope.displayName) · \(group.count) item\(group.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(group.severity.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(severityColor)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var severityColor: Color {
        switch group.severity {
        case .safe: .green
        case .warning: .orange
        case .blocked: .red
        case .informational: .secondary
        }
    }
}

private struct ArtifactWasteGroupRow: View {
    var group: ArtifactWasteGroup
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(group.items.prefix(10)) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Text("Age \(item.ageDays.map { "\($0)d" } ?? "unknown") · size \(item.sizeBytes.map(ByteCountFormatter.string) ?? "unknown") · linked \(item.isLinkedToActiveTaskOrRun ? "yes" : "no")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            HStack {
                Text(group.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(group.artifactType) x\(group.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct LifecycleSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }
}

private struct LifecycleMetric: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(label.lowercased().contains("canonical") ? .system(.caption, design: .monospaced) : .caption.weight(.semibold))
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct LifecycleItemRow: View {
    @EnvironmentObject private var store: AppStore
    var item: LifecycleItem
    @State private var pendingConfirmationAction: LifecycleSafeAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                        .font(.subheadline.weight(.semibold))
                    Text("\(item.classification.displayName) · \(item.state.displayName)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(classificationColor)
                }
                Spacer()
                Text(item.recommendation.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if let path = item.path {
                Text(path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Text("Branch \(item.branch ?? "unknown") · HEAD \(item.head ?? "unknown") · clean \(item.isClean.map { $0 ? "yes" : "no" } ?? "unknown") · ahead/behind \(item.ahead.map(String.init) ?? "unknown")/\(item.behind.map(String.init) ?? "unknown")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(item.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !item.blockedActions.isEmpty {
                Text(item.blockedActions.map { "\($0.action.displayName): \($0.reason)" }.joined(separator: "  "))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            actionButtons
        }
        .padding(.vertical, 4)
        .alert(item: $pendingConfirmationAction) { action in
            Alert(
                title: Text(action.displayName),
                message: Text(confirmationMessage(for: action)),
                primaryButton: .default(Text(confirmLabel(for: action))) {
                    Task { await store.performLifecycleAction(action, item: item) }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            ForEach(item.allowedActions.prefix(4)) { action in
                Button(action.displayName) {
                    if action.requiresConfirmation {
                        pendingConfirmationAction = action
                    } else {
                        Task { await store.performLifecycleAction(action, item: item) }
                    }
                }
                .controlSize(.small)
                .disabled(store.isWorking)
                .help(help(for: action))
            }
        }
    }

    private var classificationColor: Color {
        switch item.classification {
        case .healthy, .alreadyMerged:
            .green
        case .active, .outdated, .readyToMerge, .duplicateEquivalent, .staleCandidate, .removedCleaned:
            .orange
        case .dirtyRisk, .unpushedRisk, .backupProtected, .orphanedMetadata, .unknownRisk, .missingPath:
            .red
        }
    }

    private func help(for action: LifecycleSafeAction) -> String {
        switch action {
        case .refreshScan:
            return "Refresh the lifecycle scan."
        case .inspectDiff:
            return "Preview the current diff or divergence against the default branch."
        case .refreshFromMain:
            return "Fast-forward this clean task worktree to the latest default branch and update the stored base commit."
        case .rebaseOntoMain:
            return "Replay the task commits on top of the latest default branch after confirmation."
        case .stashWorktreeChanges:
            return "Stash tracked and untracked worktree changes before refreshing."
        case .createWIPBackupCommit:
            return "Create a WIP commit inside the task worktree so the branch can be updated safely."
        default:
            return action.isFoundationOnly ? "Foundation-only action." : action.displayName
        }
    }

    private func confirmationMessage(for action: LifecycleSafeAction) -> String {
        switch action {
        case .rebaseOntoMain:
            return "This task branch is \(item.ahead ?? 0) commit(s) ahead and \(item.behind ?? 0) behind the default branch. Factory will run git rebase inside the selected task worktree."
        case .stashWorktreeChanges:
            return "Factory will run git stash push -u only inside the selected task worktree."
        case .createWIPBackupCommit:
            return "Factory will run git add -A and git commit only inside the selected task worktree."
        default:
            return item.reason
        }
    }

    private func confirmLabel(for action: LifecycleSafeAction) -> String {
        switch action {
        case .rebaseOntoMain:
            return "Rebase"
        case .stashWorktreeChanges:
            return "Stash"
        case .createWIPBackupCommit:
            return "Commit WIP"
        default:
            return "Continue"
        }
    }
}

private extension ByteCountFormatter {
    static func string(from bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
