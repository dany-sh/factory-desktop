import Foundation

public enum TaskWorkspaceStage: CaseIterable, Identifiable, Hashable, Codable {
    case brief
    case buildTest
    case worker
    case review
    case artifacts

    public static let allCases: [TaskWorkspaceStage] = [
        .brief,
        .buildTest,
        .worker,
        .review,
        .artifacts
    ]

    public var id: String { rawValue }

    public var rawValue: String {
        switch self {
        case .brief: "brief"
        case .buildTest: "build_test"
        case .worker: "worker"
        case .review: "review"
        case .artifacts: "artifacts"
        }
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "brief", "write", "plan_review", "planReview":
            self = .brief
        case "build_test", "buildTest":
            self = .buildTest
        case "worker":
            self = .worker
        case "review", "diff":
            self = .review
        case "artifacts":
            self = .artifacts
        default:
            return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let stage = TaskWorkspaceStage(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown task workspace stage: \(rawValue)"
            )
        }
        self = stage
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var title: String {
        switch self {
        case .brief: "Brief"
        case .buildTest: "Build & Test"
        case .worker: "Worker"
        case .review: "Review"
        case .artifacts: "Artifacts"
        }
    }
}

public extension FactoryTask {
    mutating func markWorktreeReferenceCleaned(path removedPath: String) -> Bool {
        var changed = false
        if localWorktreePath == removedPath {
            localWorktreePath = nil
            changed = true
        }
        if codexWorktreePath == removedPath {
            codexWorktreePath = nil
            changed = true
        }
        if changed {
            updatedAt = Date()
        }
        return changed
    }

    mutating func setBaseBranchCommit(_ commit: String?, for flavor: WorktreeFlavor) {
        switch flavor {
        case .local:
            localBaseBranchCommit = commit
        case .codex:
            codexBaseBranchCommit = commit
        }
        updatedAt = Date()
    }
}

public struct TaskWorktreeDisplay: Equatable, Identifiable {
    public var id: String
    public var label: String
    public var branch: String?
    public var path: String?
    public var executionMode: String
    public var state: StoredWorktreeReferenceState
    public var recommendedAction: String
    public var repairActions: [WorktreeRepairAction]

    public init(
        id: String,
        label: String,
        branch: String?,
        path: String?,
        executionMode: String,
        state: StoredWorktreeReferenceState = .unknown,
        recommendedAction: String = "Refresh lifecycle scan",
        repairActions: [WorktreeRepairAction] = WorktreeRepairAction.p0Actions
    ) {
        self.id = id
        self.label = label
        self.branch = branch
        self.path = path
        self.executionMode = executionMode
        self.state = state
        self.recommendedAction = recommendedAction
        self.repairActions = repairActions
    }

    public var pathExists: Bool {
        state == .healthy || state == .dirtyRisk
    }

    public var canOpen: Bool {
        pathExists
    }
}

public enum StoredWorktreeReferenceState: String, CaseIterable, Codable, Identifiable {
    case healthy
    case missingPath = "missing_path"
    case removedCleaned = "removed_cleaned"
    case dirtyRisk = "dirty_risk"
    case unknown

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .healthy: "Healthy"
        case .missingPath: "Missing Path"
        case .removedCleaned: "Removed / Cleaned"
        case .dirtyRisk: "Dirty Risk"
        case .unknown: "Unknown"
        }
    }
}

public enum WorktreeRepairAction: String, CaseIterable, Codable, Identifiable {
    case refreshLifecycleScan = "refresh_lifecycle_scan"
    case removeStaleWorktreeReference = "remove_stale_worktree_reference"
    case markWorktreeCleaned = "mark_worktree_cleaned"
    case recreateWorktreeFromBranch = "recreate_worktree_from_branch"
    case relinkExistingWorktree = "relink_existing_worktree"
    case archiveTask = "archive_task"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .refreshLifecycleScan: "Refresh lifecycle scan"
        case .removeStaleWorktreeReference: "Remove stale worktree reference"
        case .markWorktreeCleaned: "Mark worktree cleaned"
        case .recreateWorktreeFromBranch: "Refresh worktree from default branch"
        case .relinkExistingWorktree: "Relink existing worktree"
        case .archiveTask: "Archive task"
        }
    }

    public var isFoundationOnly: Bool {
        switch self {
        case .refreshLifecycleScan, .removeStaleWorktreeReference, .markWorktreeCleaned, .archiveTask:
            return false
        case .recreateWorktreeFromBranch, .relinkExistingWorktree:
            return true
        }
    }

    public static var p0Actions: [WorktreeRepairAction] {
        [
            .refreshLifecycleScan,
            .removeStaleWorktreeReference,
            .markWorktreeCleaned,
            .recreateWorktreeFromBranch,
            .relinkExistingWorktree,
            .archiveTask
        ]
    }

    public static func visibleActions(
        for state: StoredWorktreeReferenceState,
        taskStatus: TaskStatus?,
        actions: [WorktreeRepairAction] = WorktreeRepairAction.p0Actions
    ) -> [WorktreeRepairAction] {
        let isCompleted = taskStatus == .archived || taskStatus == .done
        return actions.filter { action in
            if action == .archiveTask, taskStatus == .archived {
                return false
            }
            if isCompleted {
                return action != .archiveTask
            }
            if state == .removedCleaned {
                return action == .refreshLifecycleScan ||
                    action == .recreateWorktreeFromBranch ||
                    action == .relinkExistingWorktree ||
                    action == .archiveTask
            }
            return true
        }
    }
}

public enum TaskWorktreeDisplayMapper {
    public static func displays(for task: FactoryTask) -> [TaskWorktreeDisplay] {
        let candidates = [
            TaskWorktreeDisplay(
                id: "local",
                label: "Task Worktree",
                branch: task.localBranch,
                path: task.localWorktreePath,
                executionMode: "Local",
                state: state(for: task.localWorktreePath, branch: task.localBranch),
                recommendedAction: recommendedAction(for: state(for: task.localWorktreePath, branch: task.localBranch))
            ),
            TaskWorktreeDisplay(
                id: "codex",
                label: "Task Worktree",
                branch: task.codexBranch,
                path: task.codexWorktreePath,
                executionMode: "Codex",
                state: state(for: task.codexWorktreePath, branch: task.codexBranch),
                recommendedAction: recommendedAction(for: state(for: task.codexWorktreePath, branch: task.codexBranch))
            )
        ].filter { $0.branch != nil || $0.path != nil }

        guard candidates.count > 1 else { return candidates }

        return candidates.enumerated().map { index, display in
            TaskWorktreeDisplay(
                id: display.id,
                label: index == 0 ? "Primary Task Worktree" : "Alternate Worktree",
                branch: display.branch,
                path: display.path,
                executionMode: display.executionMode,
                state: display.state,
                recommendedAction: display.recommendedAction,
                repairActions: display.repairActions
            )
        }
    }

    public static func state(for path: String?, branch: String?, fileManager: FileManager = .default) -> StoredWorktreeReferenceState {
        guard let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return branch == nil ? .unknown : .removedCleaned
        }
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: path, isDirectory: &isDirectory) {
            return isDirectory.boolValue ? .healthy : .unknown
        }
        return .missingPath
    }

    private static func recommendedAction(for state: StoredWorktreeReferenceState) -> String {
        switch state {
        case .healthy: "Continue work"
        case .missingPath: "Remove stale reference or relink/recreate the worktree"
        case .removedCleaned: "No action required after cleanup"
        case .dirtyRisk: "Review diff"
        case .unknown: "Refresh lifecycle scan"
        }
    }
}

public struct TaskWorkflowHealth: Equatable {
    public var worktree: String
    public var preflight: String
    public var plan: String
    public var implementation: String
    public var tests: String
    public var diffReview: String
    public var nextAction: String

    public init(
        worktree: String,
        preflight: String,
        plan: String,
        implementation: String,
        tests: String,
        diffReview: String,
        nextAction: String
    ) {
        self.worktree = worktree
        self.preflight = preflight
        self.plan = plan
        self.implementation = implementation
        self.tests = tests
        self.diffReview = diffReview
        self.nextAction = nextAction
    }
}

public enum TaskWorkflowHealthBuilder {
    public static func build(
        task: FactoryTask?,
        review: TaskStateReview?,
        artifacts: [Artifact],
        gitSnapshot: GitSnapshot
    ) -> TaskWorkflowHealth {
        let groups = ArtifactGrouping.group(artifacts)
        let displays = task.map { TaskWorktreeDisplayMapper.displays(for: $0) } ?? []
        let hasUsableWorktree = displays.contains { $0.canOpen }
        let hasMissingWorktree = displays.contains { $0.state == .missingPath }
        let hasRemovedWorktree = displays.contains { $0.state == .removedCleaned }
        let hasApprovedPlan = artifacts.contains { $0.artifactType == .approvedPlan }
        let hasPlan = artifacts.contains { $0.artifactType == .plan }
        let latestTest = groups.current.first { $0.artifactType == .testOutput }

        return TaskWorkflowHealth(
            worktree: worktreeState(hasUsableWorktree: hasUsableWorktree, hasMissingWorktree: hasMissingWorktree, hasRemovedWorktree: hasRemovedWorktree, review: review),
            preflight: preflightState(review: review, artifacts: artifacts),
            plan: planState(hasPlan: hasPlan, hasApprovedPlan: hasApprovedPlan, review: review),
            implementation: implementationState(review: review, gitSnapshot: gitSnapshot),
            tests: testsState(review: review, latestTest: latestTest),
            diffReview: review?.hasDiffReview == true ? "done" : "missing",
            nextAction: nextActionState(task: task, review: review)
        )
    }

    private static func nextActionState(task: FactoryTask?, review: TaskStateReview?) -> String {
        if let review {
            return review.recommendedAction.displayName
        }
        switch task?.status {
        case .archived:
            return "Archived"
        case .done:
            return "No action required"
        default:
            return "Review Task State"
        }
    }

    private static func worktreeState(hasUsableWorktree: Bool, hasMissingWorktree: Bool, hasRemovedWorktree: Bool, review: TaskStateReview?) -> String {
        if hasMissingWorktree { return "missing path" }
        if hasRemovedWorktree { return "cleaned" }
        guard hasUsableWorktree else { return "missing" }
        if review?.hasImplementationChanges == true { return "dirty" }
        return "clean"
    }

    private static func preflightState(review: TaskStateReview?, artifacts: [Artifact]) -> String {
        guard artifacts.contains(where: { $0.artifactType == .preflight }) else { return "missing" }
        if review?.hasStalePreflight == true { return "stale" }
        if review?.hasRiskyPreflight == true { return "risky" }
        return "clean"
    }

    private static func planState(hasPlan: Bool, hasApprovedPlan: Bool, review: TaskStateReview?) -> String {
        if hasApprovedPlan || review?.hasApprovedPlan == true { return "approved" }
        if review?.latestPlanDecision == .revise { return "needs revision" }
        if hasPlan || review?.hasPlan == true { return "ready" }
        return "missing"
    }

    private static func implementationState(review: TaskStateReview?, gitSnapshot: GitSnapshot) -> String {
        if review?.hasImplementationChanges == true || !gitSnapshot.changedFiles.isEmpty {
            return "changes exist"
        }
        return "none"
    }

    private static func testsState(review: TaskStateReview?, latestTest: Artifact?) -> String {
        if review?.hasPassingTestOutput == true { return "passed" }
        if review?.hasTestOutput == true || latestTest != nil { return "unknown" }
        return "missing"
    }
}

public enum WorkflowCheckSummariesBuilder {
    public static func build(project: Project?, runs: [RunRecord], artifacts: [Artifact]) -> [WorkflowCheckSummary] {
        WorkflowRunKind.allCases.map { kind in
            let command = project?.commandConfiguration.command(for: kind)
            return summary(
                kind: kind,
                runs: matchingRuns(kind: kind, runs: runs, project: project),
                artifacts: artifactsFor(kind: kind, artifacts: artifacts),
                command: command,
                configured: command != nil
            )
        }
    }

    private static func matchingRuns(kind: WorkflowRunKind, runs: [RunRecord], project: Project?) -> [RunRecord] {
        let typedRuns = runs.filter { $0.runType == kind }
        if !typedRuns.isEmpty || kind != .unitTests {
            return typedRuns
        }
        return runs.filter { run in
            run.executor == "command" && project?.testCommands.contains(run.summary.removingRunStatusPrefix) == true
        }
    }

    private static func artifactsFor(kind: WorkflowRunKind, artifacts: [Artifact]) -> [Artifact] {
        switch kind {
        case .unitTests, .integrationTests, .e2eTests:
            return artifacts.filter { $0.artifactType == .testOutput }
        case .build:
            return artifacts.filter { $0.artifactType == .implementationLog }
        case .visualQC:
            return artifacts
        }
    }

    private static func summary(
        kind: WorkflowRunKind,
        runs: [RunRecord],
        artifacts: [Artifact],
        command: String?,
        configured: Bool
    ) -> WorkflowCheckSummary {
        guard configured else {
            return WorkflowCheckSummary(kind: kind, status: .notConfigured, command: command)
        }
        guard let run = runs.sorted(by: { $0.startedAt > $1.startedAt }).first else {
            return WorkflowCheckSummary(kind: kind, status: .notRun, command: command)
        }
        return WorkflowCheckSummary(
            kind: kind,
            status: status(for: run),
            run: run,
            command: command,
            artifact: artifacts.sorted(by: { $0.createdAt > $1.createdAt }).first
        )
    }

    private static func status(for run: RunRecord) -> WorkflowCheckStatus {
        switch run.status {
        case .queued:
            return .notRun
        case .running:
            return .running
        case .succeeded:
            return .passed
        case .failed:
            return .failed
        case .cancelled:
            return .cancelled
        }
    }
}

private extension String {
    var removingRunStatusPrefix: String {
        replacingOccurrences(of: "Passed: ", with: "")
            .replacingOccurrences(of: "Failed: ", with: "")
    }
}
