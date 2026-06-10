import Foundation

public enum RunnerWorkspaceStatusFlag: String, Codable, Sendable {
    case active
    case archived
    case cleaned
    case pinned
}

public struct RunnerWorkspace: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var projectId: String
    public var taskId: String
    public var branchName: String
    public var worktreePath: String
    public var baseCommit: String?
    public var headCommit: String?
    public var archived: Bool
    public var cleaned: Bool
    public var pinned: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        projectId: String,
        taskId: String,
        branchName: String,
        worktreePath: String,
        baseCommit: String? = nil,
        headCommit: String? = nil,
        archived: Bool = false,
        cleaned: Bool = false,
        pinned: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.taskId = taskId
        self.branchName = branchName
        self.worktreePath = worktreePath
        self.baseCommit = baseCommit
        self.headCommit = headCommit
        self.archived = archived
        self.cleaned = cleaned
        self.pinned = pinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct RunnerSession: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var workspaceId: String
    public var provider: RunnerProvider
    public var mode: RunnerMode
    public var modelProfile: ModelProfile?
    public var externalSessionId: String?
    public var status: RunnerSessionStatus
    public var transcriptPath: String?
    public var activeTurnId: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        workspaceId: String,
        provider: RunnerProvider,
        mode: RunnerMode,
        modelProfile: ModelProfile? = nil,
        externalSessionId: String? = nil,
        status: RunnerSessionStatus = .active,
        transcriptPath: String? = nil,
        activeTurnId: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.provider = provider
        self.mode = mode
        self.modelProfile = modelProfile
        self.externalSessionId = externalSessionId
        self.status = status
        self.transcriptPath = transcriptPath
        self.activeTurnId = activeTurnId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum RunnerExecutionStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case queued
    case running
    case completed
    case failed
    case cancelled

    public var id: String { rawValue }

    public var displayName: String {
        rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

public struct RunnerExecution: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var sessionId: String
    public var runReason: String
    public var command: String?
    public var status: RunnerExecutionStatus
    public var exitCode: Int?
    public var logPath: String?
    public var beforeRepoState: String?
    public var afterRepoState: String?
    public var startedAt: Date
    public var endedAt: Date?

    public init(
        id: String = UUID().uuidString,
        sessionId: String,
        runReason: String,
        command: String? = nil,
        status: RunnerExecutionStatus = .queued,
        exitCode: Int? = nil,
        logPath: String? = nil,
        beforeRepoState: String? = nil,
        afterRepoState: String? = nil,
        startedAt: Date = Date(),
        endedAt: Date? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.runReason = runReason
        self.command = command
        self.status = status
        self.exitCode = exitCode
        self.logPath = logPath
        self.beforeRepoState = beforeRepoState
        self.afterRepoState = afterRepoState
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

public struct AgentTurn: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var sessionId: String
    public var role: String
    public var content: String
    public var createdAt: Date

    public init(id: String = UUID().uuidString, sessionId: String, role: String, content: String, createdAt: Date = Date()) {
        self.id = id
        self.sessionId = sessionId
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

public enum WorkerReportStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case completed
    case needsReview = "needs_review"
    case blocked
    case failed

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .completed: "Completed"
        case .needsReview: "Needs Review"
        case .blocked: "Blocked"
        case .failed: "Failed"
        }
    }
}

public struct WorkerReport: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var sessionId: String
    public var executionId: String
    public var status: WorkerReportStatus
    public var parseStatus: WorkerReportParseStatus
    public var parseError: String?
    public var summary: String
    public var filesChanged: [String]
    public var testsRun: [String]
    public var risks: [String]
    public var blockers: [String]
    public var nextRecommendedAction: String
    public var recommendedTaskStatus: TaskStatus?
    public var rawText: String
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        sessionId: String,
        executionId: String,
        status: WorkerReportStatus,
        parseStatus: WorkerReportParseStatus = .parsed,
        parseError: String? = nil,
        summary: String,
        filesChanged: [String] = [],
        testsRun: [String] = [],
        risks: [String] = [],
        blockers: [String] = [],
        nextRecommendedAction: String = "",
        recommendedTaskStatus: TaskStatus? = nil,
        rawText: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.executionId = executionId
        self.status = status
        self.parseStatus = parseStatus
        self.parseError = parseError
        self.summary = summary
        self.filesChanged = filesChanged
        self.testsRun = testsRun
        self.risks = risks
        self.blockers = blockers
        self.nextRecommendedAction = nextRecommendedAction
        self.recommendedTaskStatus = recommendedTaskStatus
        self.rawText = rawText
        self.createdAt = createdAt
    }
}

public enum WorkerReportParseStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case parsed
    case partiallyParsed = "partially_parsed"
    case missing
    case invalid

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .parsed: "Parsed"
        case .partiallyParsed: "Partially Parsed"
        case .missing: "Missing"
        case .invalid: "Invalid"
        }
    }
}

public enum TaskProposalStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case proposed
    case accepted
    case dismissed

    public var id: String { rawValue }
}

public struct TaskProposal: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var sourceTaskId: String
    public var sourceSessionId: String
    public var title: String
    public var goal: String
    public var context: String
    public var acceptanceCriteria: [String]
    public var reasonDiscovered: String
    public var suggestedPriority: FactoryTaskPriorityLabel
    public var suggestedStage: FactoryTaskTriageStatus
    public var sourceFiles: [String]
    public var status: TaskProposalStatus
    public var createdTaskId: String?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        sourceTaskId: String,
        sourceSessionId: String,
        title: String,
        goal: String,
        context: String = "",
        acceptanceCriteria: [String] = [],
        reasonDiscovered: String,
        suggestedPriority: FactoryTaskPriorityLabel = .normal,
        suggestedStage: FactoryTaskTriageStatus = .backlog,
        sourceFiles: [String] = [],
        status: TaskProposalStatus = .proposed,
        createdTaskId: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sourceTaskId = sourceTaskId
        self.sourceSessionId = sourceSessionId
        self.title = title
        self.goal = goal
        self.context = context
        self.acceptanceCriteria = acceptanceCriteria
        self.reasonDiscovered = reasonDiscovered
        self.suggestedPriority = suggestedPriority
        self.suggestedStage = suggestedStage
        self.sourceFiles = sourceFiles
        self.status = status
        self.createdTaskId = createdTaskId
        self.createdAt = createdAt
    }
}

public enum RunnerNotificationLevel: String, CaseIterable, Codable, Identifiable, Sendable {
    case info
    case warning
    case error

    public var id: String { rawValue }
}

public struct RunnerNotification: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var taskId: String
    public var sessionId: String?
    public var executionId: String?
    public var level: RunnerNotificationLevel
    public var message: String
    public var isRead: Bool
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        taskId: String,
        sessionId: String? = nil,
        executionId: String? = nil,
        level: RunnerNotificationLevel,
        message: String,
        isRead: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.taskId = taskId
        self.sessionId = sessionId
        self.executionId = executionId
        self.level = level
        self.message = message
        self.isRead = isRead
        self.createdAt = createdAt
    }
}

public struct LifecycleSnapshot: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var taskId: String
    public var workspaceId: String?
    public var worktreeExists: Bool
    public var branchExists: Bool
    public var dirtyState: String
    public var mainMoved: Bool
    public var latestExecutionStatus: RunnerExecutionStatus?
    public var latestReportStatus: WorkerReportStatus?
    public var unseenNotifications: Int
    public var proposedTasksCount: Int
    public var recommendedAction: String
    public var evidence: [String]
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        taskId: String,
        workspaceId: String? = nil,
        worktreeExists: Bool,
        branchExists: Bool,
        dirtyState: String,
        mainMoved: Bool,
        latestExecutionStatus: RunnerExecutionStatus? = nil,
        latestReportStatus: WorkerReportStatus? = nil,
        unseenNotifications: Int = 0,
        proposedTasksCount: Int = 0,
        recommendedAction: String,
        evidence: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.taskId = taskId
        self.workspaceId = workspaceId
        self.worktreeExists = worktreeExists
        self.branchExists = branchExists
        self.dirtyState = dirtyState
        self.mainMoved = mainMoved
        self.latestExecutionStatus = latestExecutionStatus
        self.latestReportStatus = latestReportStatus
        self.unseenNotifications = unseenNotifications
        self.proposedTasksCount = proposedTasksCount
        self.recommendedAction = recommendedAction
        self.evidence = evidence
        self.createdAt = createdAt
    }
}

public struct WorkerRunDetail: Equatable {
    public var task: FactoryTask
    public var workspace: RunnerWorkspace?
    public var session: RunnerSession?
    public var execution: RunnerExecution?
    public var prompt: String
    public var report: WorkerReport?
    public var proposals: [TaskProposal]
    public var lifecycleSnapshots: [LifecycleSnapshot]
    public var notifications: [RunnerNotification]
    public var events: [TaskEvent]

    public init(
        task: FactoryTask,
        workspace: RunnerWorkspace?,
        session: RunnerSession?,
        execution: RunnerExecution?,
        prompt: String,
        report: WorkerReport?,
        proposals: [TaskProposal],
        lifecycleSnapshots: [LifecycleSnapshot],
        notifications: [RunnerNotification],
        events: [TaskEvent]
    ) {
        self.task = task
        self.workspace = workspace
        self.session = session
        self.execution = execution
        self.prompt = prompt
        self.report = report
        self.proposals = proposals
        self.lifecycleSnapshots = lifecycleSnapshots
        self.notifications = notifications
        self.events = events
    }
}

public struct WorkerReportParseResult: Equatable, Sendable {
    public var report: WorkerReport?
    public var proposals: [TaskProposal]
    public var rawReportText: String
    public var status: WorkerReportParseStatus
    public var error: String?

    public var isValid: Bool { report != nil && status == .parsed && error == nil }
}

public enum WorkerReportParser {
    public static func parse(
        output: String,
        sessionId: String,
        executionId: String,
        sourceTaskId: String
    ) -> WorkerReportParseResult {
        guard let reportStart = output.range(of: "WORKER REPORT", options: [.caseInsensitive]) else {
            return WorkerReportParseResult(
                report: nil,
                proposals: [],
                rawReportText: output,
                status: .missing,
                error: "Worker output did not contain a WORKER REPORT block."
            )
        }

        let rawReport = String(output[reportStart.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let sections = sections(from: rawReport)
        guard let statusText = sections["status"]?.first?.nonEmptyTrimmed,
              let status = WorkerReportStatus(workerText: statusText) else {
            return WorkerReportParseResult(
                report: nil,
                proposals: [],
                rawReportText: rawReport,
                status: .invalid,
                error: "Worker report did not include a valid Status."
            )
        }

        let filesChanged = list(in: sections["files changed"])
        let testsRun = list(in: sections["tests run"])
        let risks = list(in: sections["risks"])
        let blockers = list(in: sections["blockers"])
        let summary = text(in: sections["summary"])
        let nextAction = text(in: sections["next recommended action"])
        let recommendedStatus = text(in: sections["recommended task status"]).nonEmptyTrimmed.flatMap(TaskStatus.workerText)
        let requiredSections = ["summary", "files changed", "tests run", "risks", "blockers"]
        let missingSections = requiredSections.filter { sections[$0] == nil }
        let parseStatus: WorkerReportParseStatus = missingSections.isEmpty ? .parsed : .partiallyParsed
        let parseError = missingSections.isEmpty ? nil : "Worker report is missing section(s): \(missingSections.joined(separator: ", "))."
        let report = WorkerReport(
            sessionId: sessionId,
            executionId: executionId,
            status: status,
            parseStatus: parseStatus,
            parseError: parseError,
            summary: summary,
            filesChanged: filesChanged,
            testsRun: testsRun,
            risks: risks,
            blockers: blockers,
            nextRecommendedAction: nextAction,
            recommendedTaskStatus: recommendedStatus,
            rawText: rawReport
        )

        let proposals = taskProposals(
            from: sections["follow-up tasks proposed"],
            sourceTaskId: sourceTaskId,
            sourceSessionId: sessionId,
            sourceFiles: filesChanged
        )
        return WorkerReportParseResult(report: report, proposals: proposals, rawReportText: rawReport, status: parseStatus, error: parseError)
    }

    private static func sections(from text: String) -> [String: [String]] {
        let labels = Set([
            "status",
            "summary",
            "files changed",
            "tests run",
            "risks",
            "blockers",
            "follow-up tasks proposed",
            "next recommended action",
            "recommended task status"
        ])
        var current: String?
        var result: [String: [String]] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.caseInsensitiveCompare("WORKER REPORT") != .orderedSame else { continue }
            if let colon = line.firstIndex(of: ":") {
                let label = String(line[..<colon]).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if labels.contains(label) {
                    current = label
                    let rest = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !rest.isEmpty {
                        result[label, default: []].append(rest)
                    } else {
                        result[label, default: []] = result[label, default: []]
                    }
                    continue
                }
            }
            if let current {
                result[current, default: []].append(rawLine)
            }
        }
        return result
    }

    private static func text(in lines: [String]?) -> String {
        (lines ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func list(in lines: [String]?) -> [String] {
        (lines ?? [])
            .flatMap { line -> [String] in
                line.components(separatedBy: "\n")
            }
            .map { line in
                line.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingLeadingListMarker()
            }
            .filter { !$0.isEmpty && !Self.isNone($0) }
    }

    private static func taskProposals(
        from lines: [String]?,
        sourceTaskId: String,
        sourceSessionId: String,
        sourceFiles: [String]
    ) -> [TaskProposal] {
        list(in: lines)
            .filter { !isNone($0) }
            .map { item in
                let title = title(fromProposalLine: item)
                return TaskProposal(
                    sourceTaskId: sourceTaskId,
                    sourceSessionId: sourceSessionId,
                    title: title,
                    goal: item,
                    context: "Proposed by worker report for source task \(sourceTaskId).",
                    acceptanceCriteria: [],
                    reasonDiscovered: item,
                    suggestedPriority: .normal,
                    suggestedStage: .backlog,
                    sourceFiles: sourceFiles
                )
            }
    }

    private static func title(fromProposalLine line: String) -> String {
        let cleaned = line.replacingOccurrences(of: "Title:", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let separator = cleaned.range(of: " - ") ?? cleaned.range(of: " | ") {
            return String(cleaned[..<separator.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned
    }

    private static func isNone(_ value: String) -> Bool {
        let normalized = value.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        return normalized == "none" || normalized == "n/a" || normalized == "no follow-up tasks"
    }
}

public final class LifecycleMonitorService {
    private let commandRunner: CommandRunner

    public init(commandRunner: CommandRunner = CommandRunner()) {
        self.commandRunner = commandRunner
    }

    public func snapshot(
        project: Project,
        task: FactoryTask,
        workspace: RunnerWorkspace?,
        latestExecution: RunnerExecution?,
        latestReport: WorkerReport?,
        unseenNotifications: Int,
        proposedTasksCount: Int
    ) async -> LifecycleSnapshot {
        let worktreePath = workspace?.worktreePath ?? task.localWorktreePath ?? task.codexWorktreePath
        let worktreeExists = worktreePath.map(Self.existingDirectory) ?? false
        let branchName = workspace?.branchName ?? task.localBranch ?? task.codexBranch
        let branchExists = await branchExists(branchName, project: project)
        let dirtyState = await dirtyState(path: worktreePath, exists: worktreeExists)
        let defaultHead = await gitValue(["rev-parse", "--short", project.defaultBranch], in: project.path)
        let mainMoved = {
            guard let base = workspace?.baseCommit, let defaultHead else { return false }
            return !base.isEmpty && !defaultHead.isEmpty && !defaultHead.hasPrefix(base) && !base.hasPrefix(defaultHead)
        }()
        let recommendation = Self.recommendation(
            worktreeExists: worktreeExists,
            branchExists: branchExists,
            dirtyState: dirtyState,
            reportStatus: latestReport?.status,
            proposedTasksCount: proposedTasksCount,
            notifications: unseenNotifications
        )
        var evidence: [String] = []
        evidence.append(worktreeExists ? "worktree exists" : "worktree missing")
        evidence.append(branchExists ? "branch exists" : "branch missing")
        evidence.append("dirty state: \(dirtyState)")
        if mainMoved { evidence.append("default branch moved since workspace base") }
        if let latestExecution { evidence.append("latest execution: \(latestExecution.status.rawValue)") }
        if let latestReport { evidence.append("latest report: \(latestReport.status.rawValue)") }

        return LifecycleSnapshot(
            taskId: task.id,
            workspaceId: workspace?.id,
            worktreeExists: worktreeExists,
            branchExists: branchExists,
            dirtyState: dirtyState,
            mainMoved: mainMoved,
            latestExecutionStatus: latestExecution?.status,
            latestReportStatus: latestReport?.status,
            unseenNotifications: unseenNotifications,
            proposedTasksCount: proposedTasksCount,
            recommendedAction: recommendation,
            evidence: evidence
        )
    }

    private func branchExists(_ branchName: String?, project: Project) async -> Bool {
        guard project.type == .codeRepo, let branchName, !branchName.isEmpty else { return branchName != nil }
        guard Self.existingDirectory(project.path) else { return false }
        let result = try? await commandRunner.run(CommandRequest(
            executable: "git",
            arguments: ["rev-parse", "--verify", branchName],
            workingDirectory: URL(fileURLWithPath: project.path)
        ))
        return result?.succeeded == true
    }

    private func dirtyState(path: String?, exists: Bool) async -> String {
        guard exists, let path else { return "missing" }
        let result = try? await commandRunner.run(CommandRequest(
            executable: "git",
            arguments: ["status", "--porcelain=v1"],
            workingDirectory: URL(fileURLWithPath: path)
        ))
        guard let result, result.succeeded else { return "unknown" }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "clean" : "dirty"
    }

    private func gitValue(_ arguments: [String], in path: String) async -> String? {
        guard Self.existingDirectory(path) else { return nil }
        let result = try? await commandRunner.run(CommandRequest(
            executable: "git",
            arguments: arguments,
            workingDirectory: URL(fileURLWithPath: path)
        ))
        guard result?.succeeded == true else { return nil }
        return result?.output.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyTrimmed
    }

    private static func existingDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func recommendation(
        worktreeExists: Bool,
        branchExists: Bool,
        dirtyState: String,
        reportStatus: WorkerReportStatus?,
        proposedTasksCount: Int,
        notifications: Int
    ) -> String {
        if notifications > 0 { return "Review runner notifications." }
        if !worktreeExists { return "Recreate or relink the runner workspace." }
        if !branchExists { return "Inspect missing runner branch." }
        if reportStatus == .blocked { return "Review blocker and decide next action." }
        if reportStatus == .needsReview || reportStatus == .completed {
            return proposedTasksCount > 0 ? "Review worker report and proposed tasks." : "Review worker report."
        }
        if dirtyState == "dirty" { return "Review diff and run tests." }
        return "No worker action required."
    }
}

private extension WorkerReportStatus {
    init?(workerText: String) {
        let normalized = workerText
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
        switch normalized {
        case "completed", "complete", "success", "succeeded":
            self = .completed
        case "needs_review", "review":
            self = .needsReview
        case "blocked":
            self = .blocked
        case "failed", "failure":
            self = .failed
        default:
            return nil
        }
    }
}

private extension TaskStatus {
    static func workerText(_ value: String) -> TaskStatus? {
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
        switch normalized {
        case "in_progress", "running":
            return .building
        case "needs_review":
            return .readyForReview
        default:
            return TaskStatus.storedValue(normalized)
        }
    }
}

private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func trimmingLeadingListMarker() -> String {
        var value = trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasPrefix("-") || value.hasPrefix("*") {
            value.removeFirst()
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let dot = value.firstIndex(of: ".") {
            let prefix = value[..<dot]
            if !prefix.isEmpty, prefix.allSatisfy(\.isNumber) {
                value = String(value[value.index(after: dot)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return value
    }
}
