import Foundation

public enum RunnerProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case codex
    case localOllama = "local_ollama"
    case openAI = "openai"
    case manual
    case unknown

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .codex: "Codex"
        case .localOllama: "Local Ollama"
        case .openAI: "OpenAI"
        case .manual: "Manual"
        case .unknown: "Unknown"
        }
    }
}

public enum RunnerMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case scoping
    case planning
    case coding
    case review
    case testDebug = "test_debug"
    case summary
    case editorAssist = "editor_assist"

    public var id: String { rawValue }

    public var displayName: String {
        rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

public enum RunnerLocation: String, CaseIterable, Codable, Identifiable, Sendable {
    case local
    case cloud
    case unknown

    public var id: String { rawValue }
}

public enum RunnerSessionStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case unknown
    case active
    case paused
    case completed
    case failed

    public var id: String { rawValue }

    public var displayName: String {
        rawValue.capitalized
    }
}

public struct ModelProfile: Equatable, Codable, Sendable {
    public var provider: RunnerProvider
    public var modelName: String
    public var reasoningEffort: String?
    public var contextLimit: Int?
    public var location: RunnerLocation

    public init(
        provider: RunnerProvider,
        modelName: String,
        reasoningEffort: String? = nil,
        contextLimit: Int? = nil,
        location: RunnerLocation = .unknown
    ) {
        self.provider = provider
        self.modelName = modelName
        self.reasoningEffort = reasoningEffort
        self.contextLimit = contextLimit
        self.location = location
    }
}

public enum RunnerSandboxMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case readOnly = "read_only"
    case workspaceWrite = "workspace_write"
    case unrestricted

    public var id: String { rawValue }
}

public struct RunnerSessionMetadata: Equatable, Codable, Sendable {
    public var sessionID: String?
    public var providerMetadata: [String: String]

    public init(sessionID: String? = nil, providerMetadata: [String: String] = [:]) {
        self.sessionID = sessionID
        self.providerMetadata = providerMetadata
    }
}

public struct RunnerCommand: Equatable, Codable, Sendable {
    public var executable: String
    public var arguments: [String]
    public var workingDirectory: String?

    public init(executable: String, arguments: [String], workingDirectory: String? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
    }

    public var displayString: String {
        ([executable] + arguments).joined(separator: " ")
    }
}

public struct RunnerRequest: Equatable, Codable, Sendable {
    public var provider: RunnerProvider
    public var mode: RunnerMode
    public var workspacePath: String
    public var taskID: String?
    public var instruction: String
    public var modelProfile: ModelProfile?
    public var linkedSessionID: String?
    public var sandboxMode: RunnerSandboxMode?

    public init(
        provider: RunnerProvider,
        mode: RunnerMode,
        workspacePath: String,
        taskID: String? = nil,
        instruction: String,
        modelProfile: ModelProfile? = nil,
        linkedSessionID: String? = nil,
        sandboxMode: RunnerSandboxMode? = .readOnly
    ) {
        self.provider = provider
        self.mode = mode
        self.workspacePath = workspacePath
        self.taskID = taskID
        self.instruction = instruction
        self.modelProfile = modelProfile
        self.linkedSessionID = linkedSessionID
        self.sandboxMode = sandboxMode
    }
}

public struct RunnerResult: Equatable, Codable, Sendable {
    public var provider: RunnerProvider
    public var mode: RunnerMode
    public var command: RunnerCommand
    public var standardOutput: String
    public var standardError: String
    public var exitCode: Int32
    public var startedAt: Date
    public var endedAt: Date
    public var summary: String
    public var sessionMetadata: RunnerSessionMetadata?

    public init(
        provider: RunnerProvider,
        mode: RunnerMode,
        command: RunnerCommand,
        standardOutput: String,
        standardError: String,
        exitCode: Int32,
        startedAt: Date,
        endedAt: Date,
        summary: String,
        sessionMetadata: RunnerSessionMetadata? = nil
    ) {
        self.provider = provider
        self.mode = mode
        self.command = command
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.exitCode = exitCode
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.summary = summary
        self.sessionMetadata = sessionMetadata
    }

    public var output: String {
        [standardOutput, standardError]
            .filter { !$0.isEmpty }
            .joined(separator: standardOutput.isEmpty || standardError.isEmpty ? "" : "\n")
    }

    public var succeeded: Bool {
        exitCode == 0
    }
}

public struct RunnerAvailability: Equatable, Sendable {
    public var isAvailable: Bool
    public var message: String

    public init(isAvailable: Bool, message: String) {
        self.isAvailable = isAvailable
        self.message = message
    }
}

public enum RunnerRecommendedAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case scope = "scope"
    case dispatch = "dispatch"
    case continueRun = "continue_run"
    case reviewDiff = "review_diff"
    case runTests = "run_tests"
    case syncLifecycle = "sync_lifecycle"
    case needsManualReview = "needs_manual_review"
    case noAction = "no_action"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .scope: "Scope"
        case .dispatch: "Dispatch"
        case .continueRun: "Continue Run"
        case .reviewDiff: "Review Diff"
        case .runTests: "Run Tests"
        case .syncLifecycle: "Sync Lifecycle"
        case .needsManualReview: "Manual Review"
        case .noAction: "No Action"
        }
    }
}

public struct RunnerRecommendation: Equatable, Sendable {
    public var action: RunnerRecommendedAction
    public var reason: String
    public var createdAt: Date

    public init(action: RunnerRecommendedAction, reason: String, createdAt: Date = Date()) {
        self.action = action
        self.reason = reason
        self.createdAt = createdAt
    }
}

public struct RunnerProjectLink: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var projectId: String
    public var provider: RunnerProvider
    public var workspacePath: String
    public var preferredMode: RunnerMode?
    public var preferredModelProfile: ModelProfile?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        projectId: String,
        provider: RunnerProvider,
        workspacePath: String,
        preferredMode: RunnerMode? = nil,
        preferredModelProfile: ModelProfile? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.provider = provider
        self.workspacePath = workspacePath
        self.preferredMode = preferredMode
        self.preferredModelProfile = preferredModelProfile
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct RunnerSessionLink: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var projectId: String
    public var taskId: String?
    public var provider: RunnerProvider
    public var sessionID: String
    public var workspacePath: String
    public var lastMode: RunnerMode?
    public var branchName: String?
    public var worktreePath: String?
    public var status: RunnerSessionStatus
    public var lastSeenAt: Date?
    public var lastSummary: String?
    public var transcriptPath: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        projectId: String,
        taskId: String? = nil,
        provider: RunnerProvider,
        sessionID: String,
        workspacePath: String,
        lastMode: RunnerMode? = nil,
        branchName: String? = nil,
        worktreePath: String? = nil,
        status: RunnerSessionStatus = .unknown,
        lastSeenAt: Date? = nil,
        lastSummary: String? = nil,
        transcriptPath: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.taskId = taskId
        self.provider = provider
        self.sessionID = sessionID
        self.workspacePath = workspacePath
        self.lastMode = lastMode
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

public protocol RunnerProviderAdapter {
    var provider: RunnerProvider { get }
    var supportedModes: Set<RunnerMode> { get }

    func availability() async -> RunnerAvailability
    func execute(_ request: RunnerRequest) async throws -> RunnerResult
}

public extension CodexProjectLink {
    func asRunnerProjectLink() -> RunnerProjectLink {
        let modelProfile = preferredModel.map {
            ModelProfile(
                provider: .codex,
                modelName: $0,
                reasoningEffort: preferredReasoning,
                location: preferredMode == .cloud ? .cloud : .local
            )
        }
        return RunnerProjectLink(
            id: id,
            projectId: projectId,
            provider: .codex,
            workspacePath: workspacePath,
            preferredMode: nil,
            preferredModelProfile: modelProfile,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

public extension CodexSessionLink {
    func asRunnerSessionLink() -> RunnerSessionLink {
        RunnerSessionLink(
            id: id,
            projectId: projectId,
            taskId: taskId,
            provider: .codex,
            sessionID: codexSessionId,
            workspacePath: workspacePath,
            lastMode: nil,
            branchName: branchName,
            worktreePath: worktreePath,
            status: RunnerSessionStatus(rawValue: status.rawValue) ?? .unknown,
            lastSeenAt: lastSeenAt,
            lastSummary: lastSummary,
            transcriptPath: transcriptPath,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
