import FactoryDesktopCore
import SwiftUI

struct LifecycleCleanupView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let report = store.latestLifecycleReport {
                currentRepoStatus(report)
                taskLifecycleSyncSection
                preflightChecks(report.preflightGate)
                lifecycleGroup("Active Worktrees", items: activeWorktrees(report))
                lifecycleGroup("Dirty / Risky Worktrees", items: riskyWorktrees(report))
                lifecycleGroup("Branch Lifecycle", items: branchLifecycle(report))
                lifecycleGroup("Branches Ready To Delete", items: readyToDelete(report))
                lifecycleGroup("Duplicate Equivalent Branches", items: duplicateBranches(report))
                lifecycleGroup("Backup Branches", items: backupBranches(report))
                artifactWaste(report)
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
                Text("Lifecycle & Cleanup")
                    .font(.headline)
                Text(store.latestLifecycleReport?.preflightGate.level.displayName ?? "No scan yet")
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
        LifecycleSection(title: "Task Lifecycle Sync") {
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

    private func lifecycleGroup(_ title: String, items: [LifecycleItem]) -> some View {
        LifecycleSection(title: title) {
            if items.isEmpty {
                Text("None.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items.prefix(10)) { item in
                    LifecycleItemRow(item: item)
                        .environmentObject(store)
                    if item.id != items.prefix(10).last?.id {
                        Divider()
                    }
                }
                if items.count > 10 {
                    Text("\(items.count - 10) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func artifactWaste(_ report: RepoHygieneReport) -> some View {
        LifecycleSection(title: "Artifact / Run Log Waste") {
            if report.artifactWasteItems.isEmpty {
                Text("No tracked artifacts for this project yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(report.artifactWasteItems.prefix(8)) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.classification.displayName)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(item.recommendation.displayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
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
                    .padding(.vertical, 4)
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

    private func activeWorktrees(_ report: RepoHygieneReport) -> [LifecycleItem] {
        report.lifecycleItems.filter { $0.kind == .worktree && [.healthy, .active].contains($0.classification) }
    }

    private func riskyWorktrees(_ report: RepoHygieneReport) -> [LifecycleItem] {
        report.lifecycleItems.filter { $0.kind == .worktree && [.dirtyRisk, .unknownRisk, .orphanedMetadata, .missingPath, .removedCleaned].contains($0.classification) }
    }

    private func branchLifecycle(_ report: RepoHygieneReport) -> [LifecycleItem] {
        report.lifecycleItems.filter { $0.kind == .branch }
    }

    private func readyToDelete(_ report: RepoHygieneReport) -> [LifecycleItem] {
        report.lifecycleItems.filter { [.alreadyMerged, .duplicateEquivalent].contains($0.classification) }
    }

    private func duplicateBranches(_ report: RepoHygieneReport) -> [LifecycleItem] {
        report.lifecycleItems.filter { $0.classification == .duplicateEquivalent }
    }

    private func backupBranches(_ report: RepoHygieneReport) -> [LifecycleItem] {
        report.lifecycleItems.filter { $0.classification == .backupProtected }
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
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            ForEach(item.allowedActions.prefix(4)) { action in
                Button(action.displayName) {
                    if action == .refreshScan {
                        Task { await store.refreshLifecycleScan() }
                    }
                }
                .controlSize(.small)
                .disabled(store.isWorking || action != .refreshScan)
                .help(action == .refreshScan ? "Refresh the lifecycle scan." : "Foundation-only safe action. Command helper exists; execution is not wired in P0.")
            }
        }
    }

    private var classificationColor: Color {
        switch item.classification {
        case .healthy, .alreadyMerged:
            .green
        case .active, .readyToMerge, .duplicateEquivalent, .staleCandidate, .removedCleaned:
            .orange
        case .dirtyRisk, .unpushedRisk, .backupProtected, .orphanedMetadata, .unknownRisk, .missingPath:
            .red
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
