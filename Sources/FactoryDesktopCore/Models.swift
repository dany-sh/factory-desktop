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
    case backlog
    case ready
    case planning
    case planReview = "plan_review"
    case approved
    case building
    case testing
    case needsFixes = "needs_fixes"
    case readyForReview = "ready_for_review"
    case done
    case blocked
    case archived

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .backlog: "Backlog"
        case .ready: "Ready"
        case .planning: "Planning"
        case .planReview: "Plan Review"
        case .approved: "Approved"
        case .building: "Building"
        case .testing: "Testing"
        case .needsFixes: "Needs Fixes"
        case .readyForReview: "Ready for Review"
        case .done: "Done"
        case .blocked: "Blocked"
        case .archived: "Archived"
        }
    }

    public var sortOrder: Int {
        switch self {
        case .backlog: 0
        case .ready: 10
        case .planning: 20
        case .planReview: 30
        case .approved: 40
        case .building: 50
        case .testing: 60
        case .needsFixes: 70
        case .readyForReview: 80
        case .done: 90
        case .blocked: 100
        case .archived: 110
        }
    }

    public var category: TaskStatusCategory {
        switch self {
        case .backlog, .ready:
            return .queue
        case .planning, .planReview, .approved:
            return .planning
        case .building, .testing:
            return .active
        case .needsFixes, .blocked:
            return .attention
        case .readyForReview:
            return .review
        case .done:
            return .complete
        case .archived:
            return .archive
        }
    }

    public static func storedValue(_ value: String?) -> TaskStatus {
        switch value {
        case "inbox", nil:
            return .backlog
        case "plan_ready", "plan_review":
            return .planReview
        case "approved", "plan_approved", "escalation_recommended":
            return .approved
        case "plan_rejected":
            return .needsFixes
        case "built", "needs_review", "ready_to_commit":
            return .readyForReview
        case "running":
            return .building
        default:
            return TaskStatus(rawValue: value ?? "") ?? .backlog
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Self.storedValue(try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum TaskStatusCategory: String, CaseIterable, Codable, Identifiable {
    case queue
    case planning
    case active
    case attention
    case review
    case complete
    case archive

    public var id: String { rawValue }
}

public enum TaskStatusChangeSource: String, CaseIterable, Codable, Identifiable {
    case manual
    case automatic

    public var id: String { rawValue }
}

public enum TaskWorkflowEventKind: String, CaseIterable, Codable, Identifiable {
    case statusChangedManually = "status_changed_manually"
    case statusChangedAutomatically = "status_changed_automatically"
    case planGenerated = "plan_generated"
    case planApproved = "plan_approved"
    case planRejected = "plan_rejected"
    case buildStarted = "build_started"
    case buildFinished = "build_finished"
    case buildFailed = "build_failed"
    case testsStarted = "tests_started"
    case testsFinished = "tests_finished"
    case testsFailed = "tests_failed"
    case visualQCStarted = "visual_qc_started"
    case visualQCFinished = "visual_qc_finished"
    case visualQCFailed = "visual_qc_failed"
    case diffReviewed = "diff_reviewed"
    case mergedClosed = "merged_closed"

    public var id: String { rawValue }

    public var displayName: String {
        rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

public struct TaskEvent: Identifiable, Equatable, Codable {
    public var id: String
    public var taskId: String
    public var kind: TaskWorkflowEventKind
    public var source: TaskStatusChangeSource
    public var message: String
    public var previousStatus: TaskStatus?
    public var newStatus: TaskStatus?
    public var runId: String?
    public var artifactId: String?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        taskId: String,
        kind: TaskWorkflowEventKind,
        source: TaskStatusChangeSource,
        message: String = "",
        previousStatus: TaskStatus? = nil,
        newStatus: TaskStatus? = nil,
        runId: String? = nil,
        artifactId: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.taskId = taskId
        self.kind = kind
        self.source = source
        self.message = message
        self.previousStatus = previousStatus
        self.newStatus = newStatus
        self.runId = runId
        self.artifactId = artifactId
        self.createdAt = createdAt
    }
}

public enum WorkflowCheckStatus: String, CaseIterable, Codable, Identifiable {
    case notConfigured = "not_configured"
    case notRun = "not_run"
    case running
    case passed
    case failed
    case cancelled
    case unknown

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .notConfigured: "Not Configured"
        case .notRun: "Not Run"
        case .running: "Running"
        case .passed: "Passed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        case .unknown: "Unknown"
        }
    }
}

public enum WorkflowRunKind: String, CaseIterable, Codable, Identifiable {
    case build
    case unitTests = "unit_tests"
    case integrationTests = "integration_tests"
    case e2eTests = "e2e_tests"
    case visualQC = "visual_qc"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .build: "Build"
        case .unitTests: "Unit Tests"
        case .integrationTests: "Integration Tests"
        case .e2eTests: "E2E Tests"
        case .visualQC: "Visual QC"
        }
    }

    public var isTestKind: Bool {
        switch self {
        case .unitTests, .integrationTests, .e2eTests:
            return true
        case .build, .visualQC:
            return false
        }
    }
}

public enum CodexExecutionMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case local
    case worktree
    case cloud
    case unknown

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .local: "Local"
        case .worktree: "Worktree"
        case .cloud: "Cloud"
        case .unknown: "Unknown"
        }
    }
}

public enum CodexSessionStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case unknown
    case active
    case paused
    case completed
    case failed

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .unknown: "Unknown"
        case .active: "Active"
        case .paused: "Paused"
        case .completed: "Completed"
        case .failed: "Failed"
        }
    }
}

public struct CodexProjectLink: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var projectId: String
    public var workspacePath: String
    public var preferredMode: CodexExecutionMode
    public var preferredModel: String?
    public var preferredReasoning: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        projectId: String,
        workspacePath: String,
        preferredMode: CodexExecutionMode = .unknown,
        preferredModel: String? = nil,
        preferredReasoning: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.workspacePath = workspacePath
        self.preferredMode = preferredMode
        self.preferredModel = preferredModel
        self.preferredReasoning = preferredReasoning
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct CodexSessionLink: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var projectId: String
    public var taskId: String?
    public var codexSessionId: String
    public var workspacePath: String
    public var mode: CodexExecutionMode
    public var branchName: String?
    public var worktreePath: String?
    public var status: CodexSessionStatus
    public var lastSeenAt: Date?
    public var lastSummary: String?
    public var transcriptPath: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        projectId: String,
        taskId: String? = nil,
        codexSessionId: String,
        workspacePath: String,
        mode: CodexExecutionMode = .unknown,
        branchName: String? = nil,
        worktreePath: String? = nil,
        status: CodexSessionStatus = .unknown,
        lastSeenAt: Date? = nil,
        lastSummary: String? = nil,
        transcriptPath: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.taskId = taskId
        self.codexSessionId = codexSessionId
        self.workspacePath = workspacePath
        self.mode = mode
        self.branchName = branchName
        self.worktreePath = worktreePath
        self.status = status
        self.lastSeenAt = lastSeenAt
        self.lastSummary = lastSummary
        self.transcriptPath = transcriptPath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ProjectCommandConfiguration: Equatable, Codable {
    public var build: String?
    public var unitTests: String?
    public var integrationTests: String?
    public var e2eTests: String?
    public var visualQC: String?

    public init(
        build: String? = nil,
        unitTests: String? = nil,
        integrationTests: String? = nil,
        e2eTests: String? = nil,
        visualQC: String? = nil
    ) {
        self.build = Self.normalized(build)
        self.unitTests = Self.normalized(unitTests)
        self.integrationTests = Self.normalized(integrationTests)
        self.e2eTests = Self.normalized(e2eTests)
        self.visualQC = Self.normalized(visualQC)
    }

    public static func fromLegacyTestCommands(_ commands: [String]) -> ProjectCommandConfiguration {
        ProjectCommandConfiguration(unitTests: commands.first)
    }

    public func command(for kind: WorkflowRunKind) -> String? {
        switch kind {
        case .build: build
        case .unitTests: unitTests
        case .integrationTests: integrationTests
        case .e2eTests: e2eTests
        case .visualQC: visualQC
        }
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct WorkflowCheckSummary: Identifiable, Equatable {
    public var id: WorkflowRunKind { kind }
    public var kind: WorkflowRunKind
    public var status: WorkflowCheckStatus
    public var run: RunRecord?
    public var command: String?
    public var artifact: Artifact?

    public init(
        kind: WorkflowRunKind,
        status: WorkflowCheckStatus,
        run: RunRecord? = nil,
        command: String? = nil,
        artifact: Artifact? = nil
    ) {
        self.kind = kind
        self.status = status
        self.run = run
        self.command = command
        self.artifact = artifact
    }
}

public enum TaskStatusTransition {
    public static func status(
        after event: TaskWorkflowEventKind,
        current: TaskStatus,
        testsPassed: Bool? = nil,
        diffExists: Bool = false
    ) -> TaskStatus? {
        switch event {
        case .planGenerated:
            return .planReview
        case .planApproved:
            return .approved
        case .planRejected:
            return .needsFixes
        case .buildStarted:
            return .building
        case .buildFailed:
            return .needsFixes
        case .buildFinished:
            return current == .building ? .approved : current
        case .testsStarted:
            return .testing
        case .testsFailed:
            return .needsFixes
        case .testsFinished:
            guard testsPassed == true else { return testsPassed == false ? .needsFixes : current }
            return diffExists ? .readyForReview : current
        case .diffReviewed:
            return .readyForReview
        case .mergedClosed:
            return .done
        case .visualQCFailed:
            return .needsFixes
        case .visualQCStarted, .visualQCFinished, .statusChangedManually, .statusChangedAutomatically:
            return nil
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
    case preflight = "preflight"
    case taskStateReview = "task_state_review"

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
    case cancelled

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
    public var commandConfiguration: ProjectCommandConfiguration
    public var testCommands: [String] {
        get {
            commandConfiguration.unitTests.map { [$0] } ?? []
        }
        set {
            commandConfiguration.unitTests = newValue.first
        }
    }
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
        commandConfiguration: ProjectCommandConfiguration? = nil,
        metadata: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.path = path
        self.defaultBranch = defaultBranch
        self.commandConfiguration = commandConfiguration ?? .fromLegacyTestCommands(testCommands)
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
        status: TaskStatus = .backlog,
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
    public var projectId: String
    public var taskId: String?
    public var runType: WorkflowRunKind?
    public var executor: String
    public var model: String?
    public var status: RunStatus
    public var command: String?
    public var exitCode: Int?
    public var promptPath: String?
    public var outputPath: String?
    public var summary: String
    public var startedAt: Date
    public var endedAt: Date?

    public var duration: TimeInterval? {
        endedAt.map { $0.timeIntervalSince(startedAt) }
    }

    public init(
        id: String = UUID().uuidString,
        projectId: String = "",
        taskId: String?,
        runType: WorkflowRunKind? = nil,
        executor: String,
        model: String? = nil,
        status: RunStatus,
        command: String? = nil,
        exitCode: Int? = nil,
        promptPath: String? = nil,
        outputPath: String? = nil,
        summary: String = "",
        startedAt: Date = Date(),
        endedAt: Date? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.taskId = taskId
        self.runType = runType
        self.executor = executor
        self.model = model
        self.status = status
        self.command = command
        self.exitCode = exitCode
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
