import Foundation

public struct TaskStateReview: Codable, Equatable, Identifiable {
    public var id: String
    public var projectId: String
    public var taskId: String
    public var createdAt: Date
    public var status: TaskStatus
    public var summary: String
    public var latestArtifacts: [TaskArtifactSummary]
    public var worktreeSummaries: [TaskWorktreeSummary]
    public var latestPlanDecision: PlanReviewDecision?
    public var hasPlan: Bool
    public var hasPlanReview: Bool
    public var hasApprovedPlan: Bool
    public var hasPreflight: Bool
    public var hasRiskyPreflight: Bool
    public var hasImplementationChanges: Bool
    public var hasTestOutput: Bool
    public var hasPassingTestOutput: Bool
    public var hasDiffReview: Bool
    public var hasStalePreflight: Bool
    public var blockingIssues: [String]
    public var warningIssues: [String]
    public var recommendedAction: TaskStateRecommendedAction
    public var markdown: String

    public init(
        id: String = UUID().uuidString,
        projectId: String,
        taskId: String,
        createdAt: Date = Date(),
        status: TaskStatus,
        summary: String,
        latestArtifacts: [TaskArtifactSummary],
        worktreeSummaries: [TaskWorktreeSummary],
        latestPlanDecision: PlanReviewDecision?,
        hasPlan: Bool,
        hasPlanReview: Bool,
        hasApprovedPlan: Bool,
        hasPreflight: Bool,
        hasRiskyPreflight: Bool,
        hasImplementationChanges: Bool,
        hasTestOutput: Bool,
        hasPassingTestOutput: Bool = false,
        hasDiffReview: Bool,
        hasStalePreflight: Bool = false,
        blockingIssues: [String],
        warningIssues: [String] = [],
        recommendedAction: TaskStateRecommendedAction,
        markdown: String = ""
    ) {
        self.id = id
        self.projectId = projectId
        self.taskId = taskId
        self.createdAt = createdAt
        self.status = status
        self.summary = summary
        self.latestArtifacts = latestArtifacts
        self.worktreeSummaries = worktreeSummaries
        self.latestPlanDecision = latestPlanDecision
        self.hasPlan = hasPlan
        self.hasPlanReview = hasPlanReview
        self.hasApprovedPlan = hasApprovedPlan
        self.hasPreflight = hasPreflight
        self.hasRiskyPreflight = hasRiskyPreflight
        self.hasImplementationChanges = hasImplementationChanges
        self.hasTestOutput = hasTestOutput
        self.hasPassingTestOutput = hasPassingTestOutput
        self.hasDiffReview = hasDiffReview
        self.hasStalePreflight = hasStalePreflight
        self.blockingIssues = blockingIssues
        self.warningIssues = warningIssues
        self.recommendedAction = recommendedAction
        self.markdown = markdown
    }
}

public struct TaskArtifactSummary: Codable, Equatable, Identifiable {
    public var id: String
    public var type: ArtifactType
    public var path: String
    public var exists: Bool
    public var createdAt: Date
    public var decision: PlanReviewDecision?
    public var summary: String?

    public init(
        id: String = UUID().uuidString,
        type: ArtifactType,
        path: String,
        exists: Bool,
        createdAt: Date,
        decision: PlanReviewDecision? = nil,
        summary: String? = nil
    ) {
        self.id = id
        self.type = type
        self.path = path
        self.exists = exists
        self.createdAt = createdAt
        self.decision = decision
        self.summary = summary
    }
}

public struct TaskWorktreeSummary: Codable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var path: String
    public var exists: Bool
    public var branch: String?
    public var headSHA: String?
    public var isClean: Bool?
    public var stagedCount: Int
    public var unstagedCount: Int
    public var untrackedCount: Int
    public var hasImplementationChanges: Bool
    public var latestChangeAt: Date?

    public init(
        id: String = UUID().uuidString,
        label: String,
        path: String,
        exists: Bool,
        branch: String? = nil,
        headSHA: String? = nil,
        isClean: Bool? = nil,
        stagedCount: Int = 0,
        unstagedCount: Int = 0,
        untrackedCount: Int = 0,
        hasImplementationChanges: Bool = false,
        latestChangeAt: Date? = nil
    ) {
        self.id = id
        self.label = label
        self.path = path
        self.exists = exists
        self.branch = branch
        self.headSHA = headSHA
        self.isClean = isClean
        self.stagedCount = stagedCount
        self.unstagedCount = unstagedCount
        self.untrackedCount = untrackedCount
        self.hasImplementationChanges = hasImplementationChanges
        self.latestChangeAt = latestChangeAt
    }
}

public enum TaskStateRecommendedAction: String, Codable, CaseIterable, Identifiable {
    case createWorktree
    case runPreflight
    case inspectPreflightFixGitState
    case planLocally
    case reviewPlanLocally
    case askCodexToReviewPlan
    case revisePlan
    case approvePlan
    case buildLocally
    case runTests
    case reviewDiff
    case commitAndMerge
    case archive
    case noActionRequired = "no_action_required"
    case investigate

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .createWorktree: "Create Task Worktree"
        case .runPreflight: "Run Preflight"
        case .inspectPreflightFixGitState: "Inspect Preflight / Fix Git State"
        case .planLocally: "Plan Locally"
        case .reviewPlanLocally: "Review Plan Locally"
        case .askCodexToReviewPlan: "Generate Codex Plan Review Handoff"
        case .revisePlan: "Revise Plan"
        case .approvePlan: "Approve Plan"
        case .buildLocally: "Build Locally"
        case .runTests: "Run Tests"
        case .reviewDiff: "Review Diff"
        case .commitAndMerge: "Ready to Commit"
        case .archive: "Archive"
        case .noActionRequired: "No Action Required"
        case .investigate: "Investigate"
        }
    }
}

public struct TaskStateRecommendationInput: Equatable {
    public var taskType: TaskType
    public var status: TaskStatus
    public var hasExistingWorktree: Bool
    public var hasPreflight: Bool
    public var hasRiskyPreflight: Bool
    public var hasStalePreflight: Bool
    public var hasPlan: Bool
    public var hasPlanReview: Bool
    public var latestPlanDecision: PlanReviewDecision?
    public var hasApprovedPlan: Bool
    public var hasImplementationChanges: Bool
    public var hasTestOutput: Bool
    public var hasPassingTestOutput: Bool
    public var hasDiffReview: Bool
    public var appearsMerged: Bool

    public init(
        taskType: TaskType = .coding,
        status: TaskStatus = .backlog,
        hasExistingWorktree: Bool = false,
        hasPreflight: Bool = false,
        hasRiskyPreflight: Bool = false,
        hasStalePreflight: Bool = false,
        hasPlan: Bool = false,
        hasPlanReview: Bool = false,
        latestPlanDecision: PlanReviewDecision? = nil,
        hasApprovedPlan: Bool = false,
        hasImplementationChanges: Bool = false,
        hasTestOutput: Bool = false,
        hasPassingTestOutput: Bool = false,
        hasDiffReview: Bool = false,
        appearsMerged: Bool = false
    ) {
        self.taskType = taskType
        self.status = status
        self.hasExistingWorktree = hasExistingWorktree
        self.hasPreflight = hasPreflight
        self.hasRiskyPreflight = hasRiskyPreflight
        self.hasStalePreflight = hasStalePreflight
        self.hasPlan = hasPlan
        self.hasPlanReview = hasPlanReview
        self.latestPlanDecision = latestPlanDecision
        self.hasApprovedPlan = hasApprovedPlan
        self.hasImplementationChanges = hasImplementationChanges
        self.hasTestOutput = hasTestOutput
        self.hasPassingTestOutput = hasPassingTestOutput
        self.hasDiffReview = hasDiffReview
        self.appearsMerged = appearsMerged
    }
}

public enum TaskStateRecommendationEvaluator {
    public static func recommend(_ input: TaskStateRecommendationInput) -> (TaskStateRecommendedAction, String) {
        if input.status == .archived {
            return (.noActionRequired, "Task is archived.")
        }
        if input.status == .done || input.appearsMerged {
            return (.noActionRequired, "Task is complete. No action required.")
        }
        if input.taskType == .coding && !input.hasExistingWorktree {
            return (.createWorktree, "No task worktree exists yet.")
        }
        if input.hasRiskyPreflight {
            return (.inspectPreflightFixGitState, "Canonical repo preflight or live status reported dirty or risky Git state.")
        }
        if input.hasExistingWorktree && !input.hasPreflight && !input.hasImplementationChanges {
            return (.runPreflight, "Task worktree exists but no preflight report has been run yet.")
        }
        if !input.hasPlan {
            return (.planLocally, "No plan exists yet.")
        }
        if input.hasPlan && !input.hasPlanReview {
            return (.reviewPlanLocally, "Plan exists but has not been reviewed.")
        }
        if !input.hasApprovedPlan, input.latestPlanDecision == .revise {
            return (.revisePlan, "Latest plan review requested revisions.")
        }
        if !input.hasApprovedPlan, input.latestPlanDecision == .reject {
            return (.investigate, "Latest plan review rejected the plan.")
        }
        if !input.hasApprovedPlan, input.latestPlanDecision == .escalateToCodexBuild {
            return (.askCodexToReviewPlan, "Latest plan review recommended escalation.")
        }
        if !input.hasApprovedPlan, input.latestPlanDecision == .approve {
            return (.approvePlan, "Plan review approved the plan, but the plan has not been marked approved.")
        }
        if input.hasImplementationChanges && !input.hasTestOutput {
            return (.runTests, "Implementation changes exist but tests have not been run.")
        }
        if input.hasTestOutput && input.hasImplementationChanges && !input.hasDiffReview {
            return (.reviewDiff, "Tests were run; diff review is still needed.")
        }
        if input.hasDiffReview && input.hasImplementationChanges && input.hasPassingTestOutput {
            return (.commitAndMerge, "Task appears ready for commit and merge.")
        }
        if input.hasDiffReview && input.hasImplementationChanges {
            return (.investigate, "Diff review exists, but passing test output was not found.")
        }
        if input.hasExistingWorktree && (!input.hasPreflight || input.hasStalePreflight) {
            return (.runPreflight, input.hasStalePreflight ? "Preflight is stale relative to newer implementation or test state." : "Task worktree exists but no preflight report has been run yet.")
        }
        if input.hasApprovedPlan && !input.hasImplementationChanges {
            return (.buildLocally, "Plan is approved and no implementation changes exist yet.")
        }
        return (.investigate, "Task state is unclear.")
    }
}
