import Foundation

public enum TaskLifecycleCleanupSafetyState: String, CaseIterable, Codable, Identifiable {
    case safe
    case dirty
    case ambiguous
    case blocked
    case missingWorktree = "missing_worktree"
    case cleaned
    case unknown

    public var id: String { rawValue }

    public var blocksAutomaticStatusChange: Bool {
        switch self {
        case .safe, .cleaned:
            return false
        case .dirty, .ambiguous, .blocked, .missingWorktree, .unknown:
            return true
        }
    }
}

public struct TaskLifecycleFacts: Equatable, Codable {
    public var currentStatus: TaskStatus
    public var taskType: TaskType
    public var hasBranch: Bool
    public var hasWorktree: Bool
    public var worktreeIsDirty: Bool?
    public var hasCommits: Bool?
    public var appearsMergedIntoDefault: Bool?
    public var latestBuildStatus: WorkflowCheckStatus?
    public var latestTestStatus: WorkflowCheckStatus?
    public var latestVisualQCStatus: WorkflowCheckStatus?
    public var hasDiffReviewArtifact: Bool
    public var hasFinalReviewArtifact: Bool
    public var hasPlan: Bool
    public var hasPlanReview: Bool
    public var latestPlanDecision: PlanReviewDecision?
    public var hasApprovedPlan: Bool
    public var hasPreflight: Bool
    public var hasRiskyPreflight: Bool
    public var hasStalePreflight: Bool
    public var cleanupSafetyState: TaskLifecycleCleanupSafetyState

    public init(
        currentStatus: TaskStatus,
        taskType: TaskType = .coding,
        hasBranch: Bool = false,
        hasWorktree: Bool = false,
        worktreeIsDirty: Bool? = nil,
        hasCommits: Bool? = nil,
        appearsMergedIntoDefault: Bool? = nil,
        latestBuildStatus: WorkflowCheckStatus? = nil,
        latestTestStatus: WorkflowCheckStatus? = nil,
        latestVisualQCStatus: WorkflowCheckStatus? = nil,
        hasDiffReviewArtifact: Bool = false,
        hasFinalReviewArtifact: Bool = false,
        hasPlan: Bool = false,
        hasPlanReview: Bool = false,
        latestPlanDecision: PlanReviewDecision? = nil,
        hasApprovedPlan: Bool = false,
        hasPreflight: Bool = false,
        hasRiskyPreflight: Bool = false,
        hasStalePreflight: Bool = false,
        cleanupSafetyState: TaskLifecycleCleanupSafetyState = .unknown
    ) {
        self.currentStatus = currentStatus
        self.taskType = taskType
        self.hasBranch = hasBranch
        self.hasWorktree = hasWorktree
        self.worktreeIsDirty = worktreeIsDirty
        self.hasCommits = hasCommits
        self.appearsMergedIntoDefault = appearsMergedIntoDefault
        self.latestBuildStatus = latestBuildStatus
        self.latestTestStatus = latestTestStatus
        self.latestVisualQCStatus = latestVisualQCStatus
        self.hasDiffReviewArtifact = hasDiffReviewArtifact
        self.hasFinalReviewArtifact = hasFinalReviewArtifact
        self.hasPlan = hasPlan
        self.hasPlanReview = hasPlanReview
        self.latestPlanDecision = latestPlanDecision
        self.hasApprovedPlan = hasApprovedPlan
        self.hasPreflight = hasPreflight
        self.hasRiskyPreflight = hasRiskyPreflight
        self.hasStalePreflight = hasStalePreflight
        self.cleanupSafetyState = cleanupSafetyState
    }

    public var hasAnyDiffReviewArtifact: Bool {
        hasDiffReviewArtifact || hasFinalReviewArtifact
    }
}

public struct TaskLifecycleEvaluation: Equatable, Codable {
    public var recommendedStatus: TaskStatus
    public var recommendedAction: TaskStateRecommendedAction
    public var reason: String
    public var isAutomaticSafe: Bool
    public var requiredManualReview: Bool

    public init(
        recommendedStatus: TaskStatus,
        recommendedAction: TaskStateRecommendedAction,
        reason: String,
        isAutomaticSafe: Bool,
        requiredManualReview: Bool
    ) {
        self.recommendedStatus = recommendedStatus
        self.recommendedAction = recommendedAction
        self.reason = reason
        self.isAutomaticSafe = isAutomaticSafe
        self.requiredManualReview = requiredManualReview
    }
}

public struct TaskLifecycleSyncResult: Equatable, Codable {
    public var evaluation: TaskLifecycleEvaluation
    public var previousStatus: TaskStatus
    public var appliedStatus: TaskStatus?
    public var event: TaskEvent?

    public init(
        evaluation: TaskLifecycleEvaluation,
        previousStatus: TaskStatus,
        appliedStatus: TaskStatus? = nil,
        event: TaskEvent? = nil
    ) {
        self.evaluation = evaluation
        self.previousStatus = previousStatus
        self.appliedStatus = appliedStatus
        self.event = event
    }

    public var didApply: Bool {
        appliedStatus != nil
    }
}

public enum TaskLifecycleService {
    public static func evaluate(_ facts: TaskLifecycleFacts) -> TaskLifecycleEvaluation {
        if facts.currentStatus == .archived {
            return TaskLifecycleEvaluation(
                recommendedStatus: .archived,
                recommendedAction: .noActionRequired,
                reason: "Task is archived.",
                isAutomaticSafe: false,
                requiredManualReview: false
            )
        }

        if facts.currentStatus == .done {
            return TaskLifecycleEvaluation(
                recommendedStatus: .done,
                recommendedAction: .noActionRequired,
                reason: "Task is complete. No action required.",
                isAutomaticSafe: false,
                requiredManualReview: false
            )
        }

        if facts.latestBuildStatus == .failed || facts.latestTestStatus == .failed || facts.latestVisualQCStatus == .failed {
            return TaskLifecycleEvaluation(
                recommendedStatus: .needsFixes,
                recommendedAction: .investigate,
                reason: "Latest build, test, or visual QC status failed.",
                isAutomaticSafe: safeForAutomaticNonCompletionTransition(facts),
                requiredManualReview: !safeForAutomaticNonCompletionTransition(facts)
            )
        }

        if facts.latestBuildStatus == .running {
            return TaskLifecycleEvaluation(
                recommendedStatus: .building,
                recommendedAction: .buildLocally,
                reason: "Build is currently running.",
                isAutomaticSafe: true,
                requiredManualReview: false
            )
        }

        if facts.latestTestStatus == .running {
            return TaskLifecycleEvaluation(
                recommendedStatus: .testing,
                recommendedAction: .runTests,
                reason: "Tests are currently running.",
                isAutomaticSafe: true,
                requiredManualReview: false
            )
        }

        if facts.appearsMergedIntoDefault == true {
            if let blockReason = automaticCompletionBlockReason(facts) {
                return TaskLifecycleEvaluation(
                    recommendedStatus: facts.currentStatus,
                    recommendedAction: .investigate,
                    reason: "Task appears merged, but automatic completion is blocked. \(blockReason)",
                    isAutomaticSafe: false,
                    requiredManualReview: true
                )
            }

            return TaskLifecycleEvaluation(
                recommendedStatus: .done,
                recommendedAction: .noActionRequired,
                reason: "Task branch appears reachable from the default branch.",
                isAutomaticSafe: true,
                requiredManualReview: false
            )
        }

        if facts.hasCommits == true,
           facts.latestTestStatus == .passed,
           facts.hasAnyDiffReviewArtifact {
            if let blockReason = automaticCompletionBlockReason(facts) {
                return TaskLifecycleEvaluation(
                    recommendedStatus: facts.currentStatus,
                    recommendedAction: .investigate,
                    reason: "Task has reviewed, tested commits, but automatic ready-for-review is blocked. \(blockReason)",
                    isAutomaticSafe: false,
                    requiredManualReview: true
                )
            }

            return TaskLifecycleEvaluation(
                recommendedStatus: .readyForReview,
                recommendedAction: .commitAndMerge,
                reason: "Task has commits, passing tests, and diff review.",
                isAutomaticSafe: true,
                requiredManualReview: false
            )
        }

        let legacy = TaskStateRecommendationEvaluator.recommend(TaskStateRecommendationInput(
            taskType: facts.taskType,
            status: facts.currentStatus,
            hasExistingWorktree: facts.hasWorktree,
            hasPreflight: facts.hasPreflight,
            hasRiskyPreflight: facts.hasRiskyPreflight || facts.cleanupSafetyState == .blocked,
            hasStalePreflight: facts.hasStalePreflight,
            hasPlan: facts.hasPlan,
            hasPlanReview: facts.hasPlanReview,
            latestPlanDecision: facts.latestPlanDecision,
            hasApprovedPlan: facts.hasApprovedPlan,
            hasImplementationChanges: facts.worktreeIsDirty == true,
            hasTestOutput: facts.latestTestStatus.map(isConcreteCheckStatus) ?? false,
            hasPassingTestOutput: facts.latestTestStatus == .passed,
            hasDiffReview: facts.hasAnyDiffReviewArtifact,
            appearsMerged: false
        ))

        return TaskLifecycleEvaluation(
            recommendedStatus: facts.currentStatus,
            recommendedAction: legacy.0,
            reason: legacy.1,
            isAutomaticSafe: false,
            requiredManualReview: false
        )
    }

    public static func manualOverride(
        facts: TaskLifecycleFacts,
        requestedStatus: TaskStatus,
        reason: String = "Manual status override requested."
    ) -> TaskLifecycleEvaluation {
        TaskLifecycleEvaluation(
            recommendedStatus: requestedStatus,
            recommendedAction: .investigate,
            reason: reason,
            isAutomaticSafe: false,
            requiredManualReview: true
        )
    }

    private static func automaticCompletionBlockReason(_ facts: TaskLifecycleFacts) -> String? {
        if facts.worktreeIsDirty == true {
            return "Worktree has uncommitted changes."
        }
        if facts.worktreeIsDirty == nil, facts.hasWorktree {
            return "Worktree dirty state is unknown."
        }
        if facts.hasRiskyPreflight {
            return "Preflight reported risky Git state."
        }
        if facts.cleanupSafetyState.blocksAutomaticStatusChange {
            return "Cleanup safety state is \(facts.cleanupSafetyState.rawValue)."
        }
        return nil
    }

    private static func safeForAutomaticNonCompletionTransition(_ facts: TaskLifecycleFacts) -> Bool {
        facts.cleanupSafetyState != .ambiguous && facts.cleanupSafetyState != .unknown
    }

    private static func isConcreteCheckStatus(_ status: WorkflowCheckStatus) -> Bool {
        switch status {
        case .passed, .failed, .cancelled:
            return true
        case .notConfigured, .notRun, .running, .unknown:
            return false
        }
    }
}
