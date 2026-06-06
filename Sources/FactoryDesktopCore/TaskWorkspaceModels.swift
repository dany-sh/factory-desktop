import Foundation

public struct TaskWorktreeDisplay: Equatable, Identifiable {
    public var id: String
    public var label: String
    public var branch: String?
    public var path: String?
    public var executionMode: String

    public init(id: String, label: String, branch: String?, path: String?, executionMode: String) {
        self.id = id
        self.label = label
        self.branch = branch
        self.path = path
        self.executionMode = executionMode
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
                executionMode: "Local"
            ),
            TaskWorktreeDisplay(
                id: "codex",
                label: "Task Worktree",
                branch: task.codexBranch,
                path: task.codexWorktreePath,
                executionMode: "Codex"
            )
        ].filter { $0.branch != nil || $0.path != nil }

        guard candidates.count > 1 else { return candidates }

        return candidates.enumerated().map { index, display in
            TaskWorktreeDisplay(
                id: display.id,
                label: index == 0 ? "Primary Task Worktree" : "Alternate Worktree",
                branch: display.branch,
                path: display.path,
                executionMode: display.executionMode
            )
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
        let hasWorktree = task.map { !TaskWorktreeDisplayMapper.displays(for: $0).isEmpty } ?? false
        let hasApprovedPlan = artifacts.contains { $0.artifactType == .approvedPlan }
        let hasPlan = artifacts.contains { $0.artifactType == .plan }
        let latestTest = groups.current.first { $0.artifactType == .testOutput }

        return TaskWorkflowHealth(
            worktree: worktreeState(hasWorktree: hasWorktree, review: review),
            preflight: preflightState(review: review, artifacts: artifacts),
            plan: planState(hasPlan: hasPlan, hasApprovedPlan: hasApprovedPlan, review: review),
            implementation: implementationState(review: review, gitSnapshot: gitSnapshot),
            tests: testsState(review: review, latestTest: latestTest),
            diffReview: review?.hasDiffReview == true ? "done" : "missing",
            nextAction: review?.recommendedAction.displayName ?? "Review Task State"
        )
    }

    private static func worktreeState(hasWorktree: Bool, review: TaskStateReview?) -> String {
        guard hasWorktree else { return "missing" }
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
            switch kind {
            case .build:
                return summary(
                    kind: kind,
                    runs: runs,
                    artifacts: artifacts,
                    command: nil,
                    configured: false
                )
            case .unitTests:
                return summary(
                    kind: kind,
                    runs: runs.filter { run in
                        run.executor == "command" && project?.testCommands.contains(run.summary.removingRunStatusPrefix) == true
                    },
                    artifacts: artifacts.filter { $0.artifactType == .testOutput },
                    command: project?.testCommands.first,
                    configured: project?.testCommands.isEmpty == false
                )
            case .integrationTests:
                return summary(kind: kind, runs: [], artifacts: [], command: nil, configured: false)
            case .e2eTests:
                return summary(kind: kind, runs: [], artifacts: [], command: nil, configured: false)
            case .visualQC:
                return summary(kind: kind, runs: [], artifacts: [], command: nil, configured: false)
            }
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
