import Foundation

public enum ProjectType: String, CaseIterable, Codable, Identifiable {
    case codeRepo = "code_repo"
    case writingProject = "writing_project"
    case researchProject = "research_project"
    case jobSearch = "job_search"
    case legalAdmin = "legal_admin"
    case automation
    case generic

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .codeRepo: "Code repo"
        case .writingProject: "Writing"
        case .researchProject: "Research"
        case .jobSearch: "Job search"
        case .legalAdmin: "Legal/admin"
        case .automation: "Automation"
        case .generic: "Generic"
        }
    }
}

public enum TaskStatus: String, CaseIterable, Codable, Identifiable {
    case inbox
    case planning
    case planReady = "plan_ready"
    case planReview = "plan_review"
    case planApproved = "plan_approved"
    case planRejected = "plan_rejected"
    case escalationRecommended = "escalation_recommended"
    case building
    case built
    case testing
    case needsReview = "needs_review"
    case readyToCommit = "ready_to_commit"
    case done
    case blocked

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .inbox: "Inbox"
        case .planning: "Planning"
        case .planReady: "Plan ready"
        case .planReview: "Plan review"
        case .planApproved: "Plan approved"
        case .planRejected: "Plan rejected"
        case .escalationRecommended: "Escalation recommended"
        case .building: "Building"
        case .built: "Built"
        case .testing: "Testing"
        case .needsReview: "Needs review"
        case .readyToCommit: "Ready to commit"
        case .done: "Done"
        case .blocked: "Blocked"
        }
    }

    public static func storedValue(_ value: String?) -> TaskStatus {
        switch value {
        case "approved": .planApproved
        case "running": .building
        default: TaskStatus(rawValue: value ?? "") ?? .inbox
        }
    }
}

public enum ArtifactType: String, CaseIterable, Codable, Identifiable {
    case plannerPrompt = "planner_prompt"
    case plan
    case localPlanReview = "local_plan_review"
    case codexPlanReviewHandoff = "codex_plan_review_handoff"
    case codexPlanReview = "codex_plan_review"
    case approvedPlan = "approved_plan"
    case implementationLog = "implementation_log"
    case testOutput = "test_output"
    case localDiffReview = "local_diff_review"
    case codexDiffReviewHandoff = "codex_diff_review_handoff"
    case finalReview = "final_review"

    public var id: String { rawValue }

    public var displayName: String {
        rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

public enum TaskType: String, CaseIterable, Codable, Identifiable {
    case coding
    case debugging
    case research
    case writing
    case planning
    case review
    case admin
    case general

    public var id: String { rawValue }

    public var displayName: String {
        rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

public enum TaskPriority: String, CaseIterable, Codable, Identifiable {
    case low
    case normal
    case high
    case urgent

    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }
}

public enum RunStatus: String, CaseIterable, Codable, Identifiable {
    case queued
    case running
    case succeeded
    case failed

    public var id: String { rawValue }
}

public enum PlanReviewDecision: String, CaseIterable, Codable, Identifiable {
    case approve
    case revise
    case reject
    case escalateToCodexBuild = "escalate_to_codex_build"
    case unknown

    public var id: String { rawValue }
}

public struct Project: Identifiable, Equatable, Codable {
    public var id: String
    public var name: String
    public var type: ProjectType
    public var path: String
    public var defaultBranch: String
    public var testCommands: [String]
    public var metadata: [String: String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        type: ProjectType,
        path: String,
        defaultBranch: String = "main",
        testCommands: [String] = [],
        metadata: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.path = path
        self.defaultBranch = defaultBranch
        self.testCommands = testCommands
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct FactoryTask: Identifiable, Equatable, Codable {
    public var id: String
    public var projectId: String
    public var title: String
    public var type: TaskType
    public var status: TaskStatus
    public var priority: TaskPriority
    public var goal: String
    public var context: String
    public var acceptanceCriteria: [String]
    public var localBranch: String?
    public var codexBranch: String?
    public var localWorktreePath: String?
    public var codexWorktreePath: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        projectId: String,
        title: String,
        type: TaskType = .coding,
        status: TaskStatus = .inbox,
        priority: TaskPriority = .normal,
        goal: String = "",
        context: String = "",
        acceptanceCriteria: [String] = [],
        localBranch: String? = nil,
        codexBranch: String? = nil,
        localWorktreePath: String? = nil,
        codexWorktreePath: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.type = type
        self.status = status
        self.priority = priority
        self.goal = goal
        self.context = context
        self.acceptanceCriteria = acceptanceCriteria
        self.localBranch = localBranch
        self.codexBranch = codexBranch
        self.localWorktreePath = localWorktreePath
        self.codexWorktreePath = codexWorktreePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct RunRecord: Identifiable, Equatable, Codable {
    public var id: String
    public var taskId: String
    public var executor: String
    public var model: String?
    public var status: RunStatus
    public var promptPath: String?
    public var outputPath: String?
    public var summary: String
    public var startedAt: Date
    public var endedAt: Date?

    public init(
        id: String = UUID().uuidString,
        taskId: String,
        executor: String,
        model: String? = nil,
        status: RunStatus,
        promptPath: String? = nil,
        outputPath: String? = nil,
        summary: String = "",
        startedAt: Date = Date(),
        endedAt: Date? = nil
    ) {
        self.id = id
        self.taskId = taskId
        self.executor = executor
        self.model = model
        self.status = status
        self.promptPath = promptPath
        self.outputPath = outputPath
        self.summary = summary
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

public struct Artifact: Identifiable, Equatable, Codable {
    public var id: String
    public var taskId: String
    public var runId: String?
    public var type: String
    public var path: String
    public var description: String
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        taskId: String,
        runId: String? = nil,
        type: String,
        path: String,
        description: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.taskId = taskId
        self.runId = runId
        self.type = type
        self.path = path
        self.description = description
        self.createdAt = createdAt
    }

    public init(
        id: String = UUID().uuidString,
        taskId: String,
        runId: String? = nil,
        type: ArtifactType,
        path: String,
        description: String = "",
        createdAt: Date = Date()
    ) {
        self.init(
            id: id,
            taskId: taskId,
            runId: runId,
            type: type.rawValue,
            path: path,
            description: description,
            createdAt: createdAt
        )
    }
}

public struct GitSnapshot: Equatable {
    public var statusText: String
    public var diffStat: String
    public var changedFiles: [String]
    public var currentBranch: String?
    public var worktreePath: String

    public init(
        statusText: String = "",
        diffStat: String = "",
        changedFiles: [String] = [],
        currentBranch: String? = nil,
        worktreePath: String = ""
    ) {
        self.statusText = statusText
        self.diffStat = diffStat
        self.changedFiles = changedFiles
        self.currentBranch = currentBranch
        self.worktreePath = worktreePath
    }
}
