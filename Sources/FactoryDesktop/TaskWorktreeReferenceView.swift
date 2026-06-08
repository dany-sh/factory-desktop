import FactoryDesktopCore
import SwiftUI

struct TaskWorktreeReferenceView: View {
    @EnvironmentObject private var store: AppStore
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
                Text(display.recommendedAction)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            if display.state == .missingPath {
                Text("This task references a worktree path that no longer exists.")
                    .font(.caption)
                    .foregroundStyle(.red)
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

            repairButtons
        }
        .padding(.vertical, 4)
    }

    private var repairButtons: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(display.repairActions) { action in
                Button(action.displayName) {
                    store.performWorktreeRepairAction(action, displayID: display.id)
                }
                .controlSize(.small)
                .disabled(store.isWorking || !shouldEnable(action))
                .help(help(for: action))
            }
        }
    }

    private func shouldEnable(_ action: WorktreeRepairAction) -> Bool {
        guard store.canPerformWorktreeRepairAction(action) else { return false }
        switch action {
        case .refreshLifecycleScan:
            return true
        case .removeStaleWorktreeReference, .markWorktreeCleaned:
            return display.state == .missingPath
        case .archiveTask:
            return store.selectedTask != nil
        case .recreateWorktreeFromBranch, .relinkExistingWorktree:
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
        case .recreateWorktreeFromBranch, .relinkExistingWorktree:
            return "Foundation-only placeholder in P0."
        }
    }

    private var stateColor: Color {
        switch display.state {
        case .healthy: .green
        case .missingPath: .red
        case .removedCleaned: .orange
        case .dirtyRisk: .orange
        case .unknown: .secondary
        }
    }
}
