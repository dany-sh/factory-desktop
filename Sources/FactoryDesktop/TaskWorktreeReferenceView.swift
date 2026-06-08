import FactoryDesktopCore
import SwiftUI

struct TaskWorktreeReferenceView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showAdvancedRecovery = false
    var display: TaskWorktreeDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(display.state == .missingPath ? "Missing Worktree" : display.label)
                        .font(.subheadline.weight(.semibold))
                    Text("\(display.executionMode) · \(display.state.displayName)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(stateColor)
                }
                Spacer()
                Text(displayRecommendation)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            if display.state == .missingPath {
                Text("This task references a worktree path that no longer exists.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if display.state == .removedCleaned {
                Text("This worktree was removed during cleanup.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Task branch: \(display.branch ?? "not created")")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(display.path ?? "No path linked")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)

            recoveryControls
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var recoveryControls: some View {
        if isCompletedTask {
            DisclosureGroup("Advanced recovery", isExpanded: $showAdvancedRecovery) {
                repairButtons
                    .padding(.top, 6)
            }
            .font(.caption)
        } else if display.state == .removedCleaned {
            DisclosureGroup("Advanced recovery", isExpanded: $showAdvancedRecovery) {
                repairButtons
                    .padding(.top, 6)
            }
            .font(.caption)
        } else {
            repairButtons
        }
    }

    private var repairButtons: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(visibleRepairActions) { action in
                Button(action.displayName) {
                    store.performWorktreeRepairAction(action, displayID: display.id)
                }
                .controlSize(.small)
                .disabled(store.isWorking || !shouldEnable(action))
                .help(help(for: action))
            }
        }
    }

    private var visibleRepairActions: [WorktreeRepairAction] {
        WorktreeRepairAction.visibleActions(
            for: display.state,
            taskStatus: store.selectedTask?.status,
            actions: display.repairActions
        )
    }

    private func shouldEnable(_ action: WorktreeRepairAction) -> Bool {
        guard store.canPerformWorktreeRepairAction(action, displayID: display.id) else { return false }
        switch action {
        case .refreshLifecycleScan:
            return true
        case .removeStaleWorktreeReference, .markWorktreeCleaned:
            return display.state == .missingPath && !isCompletedTask
        case .archiveTask:
            return store.selectedTask != nil && store.selectedTask?.status != .archived
        case .recreateWorktreeFromBranch:
            return !isCompletedTask && display.state != .dirtyRisk
        case .relinkExistingWorktree:
            return false
        }
    }

    private func help(for action: WorktreeRepairAction) -> String {
        if action.isFoundationOnly {
            return "Foundation-only placeholder in P0."
        }
        switch action {
        case .refreshLifecycleScan:
            return "Refresh repo and task worktree lifecycle state."
        case .removeStaleWorktreeReference:
            return "Clear the missing path from task metadata while preserving the branch."
        case .markWorktreeCleaned:
            return "Mark this stored worktree reference as cleaned by clearing the missing path."
        case .archiveTask:
            return "Archive the selected task."
        case .recreateWorktreeFromBranch:
            return "Safely replace a clean or missing task worktree with a fresh one from the current default branch."
        case .relinkExistingWorktree:
            return "Foundation-only placeholder in P0."
        }
    }

    private var stateColor: Color {
        switch display.state {
        case .healthy: .green
        case .missingPath: .red
        case .removedCleaned: .secondary
        case .dirtyRisk: .orange
        case .unknown: .secondary
        }
    }

    private var isCompletedTask: Bool {
        store.selectedTask?.status == .archived || store.selectedTask?.status == .done
    }

    private var displayRecommendation: String {
        if store.selectedTask?.status == .archived {
            return "Archived"
        }
        if store.selectedTask?.status == .done {
            return "No action required"
        }
        if display.state == .removedCleaned {
            return "No action required after cleanup"
        }
        return display.recommendedAction
    }
}
