import CryptoKit
import Foundation

public enum WorkerEventKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case message
    case reasoning
    case toolCall
    case toolResult
    case command
    case fileChange
    case check
    case approval
    case question
    case report
    case warning
    case rawLog
    case error

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .message: "Message"
        case .reasoning: "Reasoning"
        case .toolCall: "Tool Call"
        case .toolResult: "Tool Result"
        case .command: "Command"
        case .fileChange: "File Change"
        case .check: "Check"
        case .approval: "Approval"
        case .question: "Question"
        case .report: "Report"
        case .warning: "Warning"
        case .rawLog: "Raw Log"
        case .error: "Error"
        }
    }
}

public enum WorkerEventSource: String, CaseIterable, Codable, Identifiable, Sendable {
    case user
    case assistant
    case runner
    case tool
    case system
    case normalizer

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .user: "User"
        case .assistant: "Worker"
        case .runner: "Runner"
        case .tool: "Tool"
        case .system: "Factory"
        case .normalizer: "Normalizer"
        }
    }
}

public struct WorkerEvent: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var taskId: String
    public var sessionId: String?
    public var executionId: String?
    public var parentEventId: String?
    public var branchKey: String?
    public var kind: WorkerEventKind
    public var createdAt: Date
    public var source: WorkerEventSource
    public var payloadJSON: String
    public var rawArtifactId: String?
    public var rawLogReference: String?

    public init(
        id: String = UUID().uuidString,
        taskId: String,
        sessionId: String? = nil,
        executionId: String? = nil,
        parentEventId: String? = nil,
        branchKey: String? = nil,
        kind: WorkerEventKind,
        createdAt: Date = Date(),
        source: WorkerEventSource,
        payloadJSON: String = "{}",
        rawArtifactId: String? = nil,
        rawLogReference: String? = nil
    ) {
        self.id = id
        self.taskId = taskId
        self.sessionId = sessionId
        self.executionId = executionId
        self.parentEventId = parentEventId
        self.branchKey = branchKey
        self.kind = kind
        self.createdAt = createdAt
        self.source = source
        self.payloadJSON = payloadJSON
        self.rawArtifactId = rawArtifactId
        self.rawLogReference = rawLogReference
    }

    public var payload: WorkerEventPayload {
        JSONCoding.decode(payloadJSON, as: WorkerEventPayload.self) ?? WorkerEventPayload()
    }
}

public struct WorkerEventPayload: Equatable, Codable, Sendable {
    public var role: String?
    public var title: String?
    public var summary: String?
    public var body: String?
    public var status: String?
    public var command: String?
    public var cwd: String?
    public var exitCode: Int?
    public var outputTail: String?
    public var files: [String]
    public var diffStat: String?
    public var level: String?
    public var mentions: [WorkerComposerMention]

    public init(
        role: String? = nil,
        title: String? = nil,
        summary: String? = nil,
        body: String? = nil,
        status: String? = nil,
        command: String? = nil,
        cwd: String? = nil,
        exitCode: Int? = nil,
        outputTail: String? = nil,
        files: [String] = [],
        diffStat: String? = nil,
        level: String? = nil,
        mentions: [WorkerComposerMention] = []
    ) {
        self.role = role
        self.title = title
        self.summary = summary
        self.body = body
        self.status = status
        self.command = command
        self.cwd = cwd
        self.exitCode = exitCode
        self.outputTail = outputTail
        self.files = files
        self.diffStat = diffStat
        self.level = level
        self.mentions = mentions
    }

    public var json: String {
        JSONCoding.encode(self)
    }
}

public enum WorkerContextItemKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case task
    case selectedFile = "selected_file"
    case changedFile = "changed_file"
    case diff
    case check
    case log
    case artifact
    case reviewFeedback = "review_feedback"
    case repoRule = "repo_rule"
    case projectGuidance = "project_guidance"
    case previousSummary = "previous_summary"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .task: "Task"
        case .selectedFile: "Selected File"
        case .changedFile: "Changed File"
        case .diff: "Diff"
        case .check: "Check"
        case .log: "Log"
        case .artifact: "Artifact"
        case .reviewFeedback: "Review Feedback"
        case .repoRule: "Repo Rule"
        case .projectGuidance: "Project Guidance"
        case .previousSummary: "Previous Summary"
        }
    }
}

public struct WorkerContextItem: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var taskId: String
    public var sessionId: String?
    public var kind: WorkerContextItemKind
    public var title: String
    public var path: String?
    public var value: String
    public var contentHash: String
    public var tokenCount: Int
    public var included: Bool
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        taskId: String,
        sessionId: String? = nil,
        kind: WorkerContextItemKind,
        title: String,
        path: String? = nil,
        value: String,
        contentHash: String? = nil,
        tokenCount: Int? = nil,
        included: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.taskId = taskId
        self.sessionId = sessionId
        self.kind = kind
        self.title = title
        self.path = path
        self.value = value
        self.contentHash = contentHash ?? WorkerContentHash.sha256(value)
        self.tokenCount = tokenCount ?? WorkerTokenEstimator.estimate(value)
        self.included = included
        self.createdAt = createdAt
    }
}

public struct WorkerPromptSnapshot: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var taskId: String
    public var sessionId: String?
    public var executionId: String?
    public var selectedContextItemIds: [String]
    public var contextHashes: [String]
    public var tokenCount: Int
    public var budget: Int
    public var provider: RunnerProvider
    public var model: String?
    public var promptMetadataJSON: String
    public var promptText: String
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        taskId: String,
        sessionId: String? = nil,
        executionId: String? = nil,
        selectedContextItemIds: [String],
        contextHashes: [String],
        tokenCount: Int,
        budget: Int,
        provider: RunnerProvider,
        model: String? = nil,
        promptMetadataJSON: String = "{}",
        promptText: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.taskId = taskId
        self.sessionId = sessionId
        self.executionId = executionId
        self.selectedContextItemIds = selectedContextItemIds
        self.contextHashes = contextHashes
        self.tokenCount = tokenCount
        self.budget = budget
        self.provider = provider
        self.model = model
        self.promptMetadataJSON = promptMetadataJSON
        self.promptText = promptText
        self.createdAt = createdAt
    }
}

public enum WorkerEvidenceKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case report
    case decision
    case warning
    case approval
    case artifact
    case toolResult = "tool_result"
    case provenance

    public var id: String { rawValue }
}

public struct WorkerEvidence: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var taskId: String
    public var sessionId: String?
    public var executionId: String?
    public var kind: WorkerEvidenceKind
    public var title: String
    public var summary: String
    public var artifactId: String?
    public var path: String?
    public var eventId: String?
    public var payloadJSON: String
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        taskId: String,
        sessionId: String? = nil,
        executionId: String? = nil,
        kind: WorkerEvidenceKind,
        title: String,
        summary: String = "",
        artifactId: String? = nil,
        path: String? = nil,
        eventId: String? = nil,
        payloadJSON: String = "{}",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.taskId = taskId
        self.sessionId = sessionId
        self.executionId = executionId
        self.kind = kind
        self.title = title
        self.summary = summary
        self.artifactId = artifactId
        self.path = path
        self.eventId = eventId
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
    }
}

public enum WorkerComposerPhase: String, CaseIterable, Codable, Identifiable, Sendable {
    case idle
    case sending
    case running
    case queued
    case stopping
    case feedback
    case editing
    case approval
    case needsAnswer = "needs_answer"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .idle: "Idle"
        case .sending: "Sending"
        case .running: "Running"
        case .queued: "Queued"
        case .stopping: "Stopping"
        case .feedback: "Feedback"
        case .editing: "Editing"
        case .approval: "Approval"
        case .needsAnswer: "Needs Answer"
        }
    }
}

public struct WorkerComposerState: Equatable, Codable, Sendable {
    public var taskId: String?
    public var sessionId: String?
    public var phase: WorkerComposerPhase
    public var draft: String
    public var parsedMentions: [WorkerComposerMention]
    public var queuedCount: Int
    public var supportsSteering: Bool

    public init(
        taskId: String? = nil,
        sessionId: String? = nil,
        phase: WorkerComposerPhase = .idle,
        draft: String = "",
        parsedMentions: [WorkerComposerMention] = [],
        queuedCount: Int = 0,
        supportsSteering: Bool = false
    ) {
        self.taskId = taskId
        self.sessionId = sessionId
        self.phase = phase
        self.draft = draft
        self.parsedMentions = parsedMentions
        self.queuedCount = queuedCount
        self.supportsSteering = supportsSteering
    }
}

public enum WorkerComposerMentionKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case file
    case diff
    case artifact
    case run
    case command

    public var id: String { rawValue }
}

public struct WorkerComposerMention: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var kind: WorkerComposerMentionKind
    public var rawText: String
    public var value: String

    public init(id: String = UUID().uuidString, kind: WorkerComposerMentionKind, rawText: String, value: String) {
        self.id = id
        self.kind = kind
        self.rawText = rawText
        self.value = value
    }
}

public enum WorkerQueuedMessageStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case queued
    case sent
    case cancelled

    public var id: String { rawValue }
}

public struct WorkerMessageQueueItem: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var taskId: String
    public var sessionId: String?
    public var body: String
    public var mentions: [WorkerComposerMention]
    public var status: WorkerQueuedMessageStatus
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        taskId: String,
        sessionId: String? = nil,
        body: String,
        mentions: [WorkerComposerMention] = [],
        status: WorkerQueuedMessageStatus = .queued,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.taskId = taskId
        self.sessionId = sessionId
        self.body = body
        self.mentions = mentions
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum WorkerToolApprovalStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case pending
    case approved
    case denied
    case cancelled

    public var id: String { rawValue }
}

public struct WorkerToolApproval: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var taskId: String
    public var sessionId: String?
    public var executionId: String?
    public var eventId: String?
    public var title: String
    public var requestedAction: String
    public var status: WorkerToolApprovalStatus
    public var payloadJSON: String
    public var decidedAt: Date?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        taskId: String,
        sessionId: String? = nil,
        executionId: String? = nil,
        eventId: String? = nil,
        title: String,
        requestedAction: String,
        status: WorkerToolApprovalStatus = .pending,
        payloadJSON: String = "{}",
        decidedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.taskId = taskId
        self.sessionId = sessionId
        self.executionId = executionId
        self.eventId = eventId
        self.title = title
        self.requestedAction = requestedAction
        self.status = status
        self.payloadJSON = payloadJSON
        self.decidedAt = decidedAt
        self.createdAt = createdAt
    }
}

public enum WorkerComposerMentionParser {
    public static func parse(_ text: String) -> [WorkerComposerMention] {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .compactMap { token -> WorkerComposerMention? in
                let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:()[]{}"))
                guard !trimmed.isEmpty else { return nil }
                if trimmed.hasPrefix("@file") {
                    return WorkerComposerMention(kind: .file, rawText: trimmed, value: suffix(after: "@file", in: trimmed))
                }
                if trimmed.hasPrefix("@diff") {
                    return WorkerComposerMention(kind: .diff, rawText: trimmed, value: suffix(after: "@diff", in: trimmed))
                }
                if trimmed.hasPrefix("@artifact") {
                    return WorkerComposerMention(kind: .artifact, rawText: trimmed, value: suffix(after: "@artifact", in: trimmed))
                }
                if trimmed.hasPrefix("#run") {
                    return WorkerComposerMention(kind: .run, rawText: trimmed, value: suffix(after: "#run", in: trimmed))
                }
                if ["/review", "/status", "/compact"].contains(trimmed) {
                    return WorkerComposerMention(kind: .command, rawText: trimmed, value: String(trimmed.dropFirst()))
                }
                return nil
            }
    }

    private static func suffix(after prefix: String, in token: String) -> String {
        let raw = String(token.dropFirst(prefix.count))
        return raw.trimmingCharacters(in: CharacterSet(charactersIn: ":=/"))
    }
}

public struct WorkerTimeline: Equatable {
    public var items: [WorkerTimelineItem]
    public var hiddenRawLogCount: Int
    public var truncatedCount: Int

    public init(items: [WorkerTimelineItem], hiddenRawLogCount: Int, truncatedCount: Int) {
        self.items = items
        self.hiddenRawLogCount = hiddenRawLogCount
        self.truncatedCount = truncatedCount
    }
}

public struct WorkerTimelineItem: Identifiable, Equatable {
    public enum Kind: String, Equatable {
        case message
        case command
        case tool
        case fileChange
        case check
        case report
        case warning
        case approval
        case question
        case error
        case fallback
    }

    public var id: String
    public var kind: Kind
    public var title: String
    public var subtitle: String
    public var body: String
    public var status: String?
    public var systemImage: String
    public var createdAt: Date
    public var metadata: [WorkerTimelineMetadata]
    public var rawLogReference: String?
    public var rawEventIds: [String]

    public init(
        id: String,
        kind: Kind,
        title: String,
        subtitle: String = "",
        body: String = "",
        status: String? = nil,
        systemImage: String,
        createdAt: Date,
        metadata: [WorkerTimelineMetadata] = [],
        rawLogReference: String? = nil,
        rawEventIds: [String]
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.status = status
        self.systemImage = systemImage
        self.createdAt = createdAt
        self.metadata = metadata
        self.rawLogReference = rawLogReference
        self.rawEventIds = rawEventIds
    }
}

public struct WorkerTimelineMetadata: Identifiable, Equatable {
    public var id: String
    public var label: String
    public var value: String

    public init(id: String = UUID().uuidString, label: String, value: String) {
        self.id = id
        self.label = label
        self.value = value
    }
}

public enum WorkerTimelineBuilderV2 {
    public static func build(events: [WorkerEvent], maxItems: Int = 200) -> WorkerTimeline {
        let sorted = events.sorted { left, right in
            if left.createdAt != right.createdAt {
                return left.createdAt < right.createdAt
            }
            return left.id < right.id
        }
        let hiddenRawLogCount = sorted.filter { $0.kind == .rawLog }.count
        let visibleEvents = sorted.filter { $0.kind != .rawLog }
        let limitedEvents: [WorkerEvent]
        let truncatedCount: Int
        if visibleEvents.count > maxItems {
            truncatedCount = visibleEvents.count - maxItems
            limitedEvents = Array(visibleEvents.suffix(maxItems))
        } else {
            truncatedCount = 0
            limitedEvents = visibleEvents
        }

        var consumed = Set<String>()
        var items: [WorkerTimelineItem] = []
        for event in limitedEvents {
            guard !consumed.contains(event.id) else { continue }
            switch event.kind {
            case .toolCall:
                let result = matchingResult(for: event, in: limitedEvents)
                if let result {
                    consumed.insert(result.id)
                }
                items.append(toolItem(call: event, result: result))
            case .command:
                items.append(commandItem(event))
            case .message, .reasoning:
                items.append(messageItem(event))
            case .toolResult:
                items.append(toolResultItem(event))
            case .fileChange:
                items.append(fileChangeItem(event))
            case .check:
                items.append(checkItem(event))
            case .approval:
                items.append(genericItem(event, kind: .approval, image: "hand.raised", defaultTitle: "Approval"))
            case .question:
                items.append(genericItem(event, kind: .question, image: "questionmark.bubble", defaultTitle: "Question"))
            case .report:
                items.append(reportItem(event))
            case .warning:
                items.append(genericItem(event, kind: .warning, image: "exclamationmark.triangle", defaultTitle: "Warning"))
            case .error:
                items.append(genericItem(event, kind: .error, image: "xmark.octagon", defaultTitle: "Error"))
            case .rawLog:
                break
            }
            consumed.insert(event.id)
        }

        return WorkerTimeline(items: items, hiddenRawLogCount: hiddenRawLogCount, truncatedCount: truncatedCount)
    }

    private static func matchingResult(for event: WorkerEvent, in events: [WorkerEvent]) -> WorkerEvent? {
        events.first { candidate in
            candidate.kind == .toolResult &&
                (candidate.parentEventId == event.id ||
                    (candidate.executionId == event.executionId && candidate.createdAt >= event.createdAt))
        }
    }

    private static func messageItem(_ event: WorkerEvent) -> WorkerTimelineItem {
        let payload = event.payload
        let role = payload.role ?? event.source.displayName
        return WorkerTimelineItem(
            id: event.id,
            kind: .message,
            title: role,
            subtitle: payload.title ?? "",
            body: payload.body ?? payload.summary ?? "",
            status: payload.status,
            systemImage: event.source == .user ? "person.crop.circle" : "sparkles",
            createdAt: event.createdAt,
            metadata: mentionMetadata(payload.mentions),
            rawLogReference: event.rawLogReference,
            rawEventIds: [event.id]
        )
    }

    private static func commandItem(_ event: WorkerEvent) -> WorkerTimelineItem {
        let payload = event.payload
        var metadata: [WorkerTimelineMetadata] = []
        if let cwd = payload.cwd, !cwd.isEmpty {
            metadata.append(.init(label: "cwd", value: cwd))
        }
        if let exitCode = payload.exitCode {
            metadata.append(.init(label: "exit", value: "\(exitCode)"))
        }
        return WorkerTimelineItem(
            id: event.id,
            kind: .command,
            title: payload.title ?? "Command",
            subtitle: payload.command ?? "",
            body: payload.outputTail ?? payload.summary ?? "",
            status: payload.status,
            systemImage: "terminal",
            createdAt: event.createdAt,
            metadata: metadata,
            rawLogReference: event.rawLogReference,
            rawEventIds: [event.id]
        )
    }

    private static func toolItem(call: WorkerEvent, result: WorkerEvent?) -> WorkerTimelineItem {
        let callPayload = call.payload
        let resultPayload = result?.payload
        var metadata = mentionMetadata(callPayload.mentions)
        if let status = resultPayload?.status ?? callPayload.status {
            metadata.append(.init(label: "status", value: status))
        }
        return WorkerTimelineItem(
            id: call.id,
            kind: .tool,
            title: callPayload.title ?? "Tool Call",
            subtitle: callPayload.summary ?? "",
            body: resultPayload?.outputTail ?? resultPayload?.summary ?? callPayload.body ?? "",
            status: resultPayload?.status ?? callPayload.status,
            systemImage: "wrench.and.screwdriver",
            createdAt: call.createdAt,
            metadata: metadata,
            rawLogReference: result?.rawLogReference ?? call.rawLogReference,
            rawEventIds: [call.id] + (result.map { [$0.id] } ?? [])
        )
    }

    private static func toolResultItem(_ event: WorkerEvent) -> WorkerTimelineItem {
        genericItem(event, kind: .tool, image: "wrench.and.screwdriver", defaultTitle: "Tool Result")
    }

    private static func fileChangeItem(_ event: WorkerEvent) -> WorkerTimelineItem {
        let payload = event.payload
        var body = payload.summary ?? ""
        if !payload.files.isEmpty {
            body += body.isEmpty ? "" : "\n"
            body += payload.files.prefix(12).joined(separator: "\n")
        }
        if let diffStat = payload.diffStat, !diffStat.isEmpty {
            body += body.isEmpty ? "" : "\n\n"
            body += diffStat
        }
        return WorkerTimelineItem(
            id: event.id,
            kind: .fileChange,
            title: payload.title ?? "Changed Files",
            body: body,
            status: payload.status,
            systemImage: "doc.on.doc",
            createdAt: event.createdAt,
            metadata: [.init(label: "files", value: "\(payload.files.count)")],
            rawLogReference: event.rawLogReference,
            rawEventIds: [event.id]
        )
    }

    private static func checkItem(_ event: WorkerEvent) -> WorkerTimelineItem {
        genericItem(event, kind: .check, image: "checkmark.seal", defaultTitle: "Check")
    }

    private static func reportItem(_ event: WorkerEvent) -> WorkerTimelineItem {
        genericItem(event, kind: .report, image: "doc.text.magnifyingglass", defaultTitle: "Worker Report")
    }

    private static func genericItem(_ event: WorkerEvent, kind: WorkerTimelineItem.Kind, image: String, defaultTitle: String) -> WorkerTimelineItem {
        let payload = event.payload
        return WorkerTimelineItem(
            id: event.id,
            kind: kind,
            title: payload.title ?? defaultTitle,
            subtitle: payload.summary ?? "",
            body: payload.body ?? payload.outputTail ?? "",
            status: payload.status,
            systemImage: image,
            createdAt: event.createdAt,
            metadata: mentionMetadata(payload.mentions),
            rawLogReference: event.rawLogReference,
            rawEventIds: [event.id]
        )
    }

    private static func mentionMetadata(_ mentions: [WorkerComposerMention]) -> [WorkerTimelineMetadata] {
        guard !mentions.isEmpty else { return [] }
        return mentions.map { mention in
            WorkerTimelineMetadata(label: mention.kind.rawValue, value: mention.rawText)
        }
    }
}

public enum WorkerEventNormalizer {
    public static func normalizedEvents(detail: WorkerRunDetail, processStatus: WorkerProcessStatus = .unknown) -> [WorkerEvent] {
        var events: [WorkerEvent] = []
        let task = detail.task
        let branchKey = detail.workspace?.branchName ?? detail.workspace?.worktreePath
        let anchorDate = detail.execution?.startedAt ?? detail.session?.createdAt ?? task.updatedAt
        events.append(WorkerEvent(
            id: "normalized-task-\(task.id)",
            taskId: task.id,
            sessionId: detail.session?.id,
            executionId: detail.execution?.id,
            branchKey: branchKey,
            kind: .message,
            createdAt: anchorDate,
            source: .system,
            payloadJSON: WorkerEventPayload(
                role: "Factory",
                title: "Task Context",
                body: task.goal.isEmpty ? task.title : task.goal
            ).json
        ))

        for turn in detail.agentTurns.sorted(by: { $0.createdAt < $1.createdAt }) {
            let role = turn.role.lowercased()
            let visibleText: String
            if role == "assistant" {
                visibleText = WorkerConversationBuilder.visibleWorkerText(from: turn.content)
            } else {
                visibleText = trim(turn.content, maxCharacters: 2400)
            }
            guard !visibleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            events.append(WorkerEvent(
                id: "normalized-turn-\(turn.id)",
                taskId: task.id,
                sessionId: turn.sessionId,
                executionId: detail.execution?.id,
                branchKey: branchKey,
                kind: .message,
                createdAt: turn.createdAt,
                source: role == "assistant" ? .assistant : .user,
                payloadJSON: WorkerEventPayload(
                    role: role == "assistant" ? "Worker" : "User",
                    body: visibleText
                ).json,
                rawLogReference: detail.execution?.logPath ?? detail.session?.transcriptPath
            ))
        }

        if let execution = detail.execution {
            events.append(WorkerEvent(
                id: "normalized-command-\(execution.id)",
                taskId: task.id,
                sessionId: execution.sessionId,
                executionId: execution.id,
                branchKey: branchKey,
                kind: .command,
                createdAt: execution.startedAt,
                source: .runner,
                payloadJSON: WorkerEventPayload(
                    title: execution.runReason == "resume_ai_worker" ? "Worker resumed" : "Worker started",
                    summary: processStatus == .unknown ? "" : "Process: \(processStatus.displayName)",
                    status: execution.status.displayName,
                    command: execution.command,
                    cwd: detail.workspace?.worktreePath,
                    exitCode: execution.exitCode,
                    outputTail: outputTail(path: execution.logPath)
                ).json,
                rawLogReference: execution.logPath
            ))
        }

        if let report = detail.report {
            if !report.testsRun.isEmpty {
                events.append(WorkerEvent(
                    id: "normalized-checks-\(report.id)",
                    taskId: task.id,
                    sessionId: report.sessionId,
                    executionId: report.executionId,
                    branchKey: branchKey,
                    kind: .check,
                    createdAt: report.createdAt,
                    source: .runner,
                    payloadJSON: WorkerEventPayload(
                        title: "Checks",
                        summary: report.testsRun.count == 1 ? report.testsRun[0] : "\(report.testsRun.count) checks recorded",
                        body: report.testsRun.joined(separator: "\n"),
                        status: report.testsRun.contains(where: { $0.localizedCaseInsensitiveContains("fail") }) ? "Failed" : "Recorded"
                    ).json,
                    rawLogReference: detail.execution?.logPath
                ))
            }

            let changedFiles = (detail.diffSnapshot?.changedFiles.isEmpty == false) ? (detail.diffSnapshot?.changedFiles ?? []) : report.filesChanged
            if !changedFiles.isEmpty || !(detail.diffSnapshot?.diffStat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                events.append(WorkerEvent(
                    id: "normalized-file-change-\(report.id)",
                    taskId: task.id,
                    sessionId: report.sessionId,
                    executionId: report.executionId,
                    branchKey: branchKey,
                    kind: .fileChange,
                    createdAt: report.createdAt,
                    source: .runner,
                    payloadJSON: WorkerEventPayload(
                        title: "Changed Files",
                        summary: "\(changedFiles.count) changed file\(changedFiles.count == 1 ? "" : "s")",
                        files: changedFiles,
                        diffStat: detail.diffSnapshot?.diffStat
                    ).json,
                    rawLogReference: detail.execution?.logPath
                ))
            }

            events.append(WorkerEvent(
                id: "normalized-report-\(report.id)",
                taskId: task.id,
                sessionId: report.sessionId,
                executionId: report.executionId,
                branchKey: branchKey,
                kind: report.status == .failed ? .error : .report,
                createdAt: report.createdAt,
                source: .assistant,
                payloadJSON: WorkerEventPayload(
                    title: "Worker Report",
                    summary: report.nextRecommendedAction,
                    body: report.summary,
                    status: report.status.displayName
                ).json,
                rawLogReference: detail.execution?.logPath
            ))
        }

        for notification in detail.notifications {
            events.append(WorkerEvent(
                id: "normalized-warning-\(notification.id)",
                taskId: task.id,
                sessionId: notification.sessionId,
                executionId: notification.executionId,
                branchKey: branchKey,
                kind: notification.level == .error ? .error : .warning,
                createdAt: notification.createdAt,
                source: .system,
                payloadJSON: WorkerEventPayload(
                    title: notification.level.rawValue.capitalized,
                    body: notification.message,
                    level: notification.level.rawValue
                ).json
            ))
        }

        for event in detail.events {
            events.append(WorkerEvent(
                id: "normalized-task-event-\(event.id)",
                taskId: task.id,
                sessionId: detail.session?.id,
                executionId: detail.execution?.id,
                branchKey: branchKey,
                kind: .report,
                createdAt: event.createdAt,
                source: .system,
                payloadJSON: WorkerEventPayload(
                    title: event.kind.displayName,
                    body: event.message,
                    status: event.newStatus?.displayName
                ).json,
                rawArtifactId: event.artifactId
            ))
        }

        if let rawLog = detail.execution?.logPath ?? detail.session?.transcriptPath {
            events.append(WorkerEvent(
                id: "normalized-raw-log-\(detail.execution?.id ?? detail.session?.id ?? task.id)",
                taskId: task.id,
                sessionId: detail.session?.id,
                executionId: detail.execution?.id,
                branchKey: branchKey,
                kind: .rawLog,
                createdAt: detail.execution?.endedAt ?? detail.report?.createdAt ?? anchorDate,
                source: .runner,
                payloadJSON: WorkerEventPayload(title: "Raw Log", body: rawLog).json,
                rawLogReference: rawLog
            ))
        }

        return events
    }

    private static func outputTail(path: String?, maxLines: Int = 12) -> String? {
        guard let path,
              let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        return lines.suffix(maxLines).joined(separator: "\n")
    }

    private static func trim(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else { return text }
        let index = text.index(text.startIndex, offsetBy: maxCharacters)
        return String(text[..<index]).trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n[Trimmed. See context or raw logs for the full input.]"
    }
}

public struct WorkerContextPack: Equatable {
    public var items: [WorkerContextItem]
    public var tokenCount: Int
    public var budget: Int
    public var promptMetadataJSON: String

    public init(items: [WorkerContextItem], tokenCount: Int, budget: Int, promptMetadataJSON: String = "{}") {
        self.items = items
        self.tokenCount = tokenCount
        self.budget = budget
        self.promptMetadataJSON = promptMetadataJSON
    }
}

public enum ContextPackBuilder {
    public static func build(
        project: Project?,
        task: FactoryTask,
        diffSnapshot: GitSnapshot,
        artifacts: [Artifact],
        runs: [RunRecord],
        reviewFeedback: String,
        previousSummary: String,
        budget: Int = 16_000,
        fileManager: FileManager = .default
    ) -> WorkerContextPack {
        var items: [WorkerContextItem] = [
            WorkerContextItem(
                taskId: task.id,
                kind: .task,
                title: "Task Brief",
                value: taskBrief(task)
            )
        ]

        if !diffSnapshot.changedFiles.isEmpty {
            items.append(WorkerContextItem(
                taskId: task.id,
                kind: .changedFile,
                title: "Changed Files",
                value: diffSnapshot.changedFiles.joined(separator: "\n")
            ))
        }

        if !diffSnapshot.diffStat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(WorkerContextItem(
                taskId: task.id,
                kind: .diff,
                title: "Current Diff Stat",
                value: diffSnapshot.diffStat
            ))
        }

        for run in runs.prefix(6) {
            let label = run.runType?.displayName ?? run.command ?? run.executor
            let body = [
                "Status: \(run.status.rawValue.capitalized)",
                run.exitCode.map { "Exit: \($0)" },
                run.summary.isEmpty ? nil : "Summary: \(run.summary)"
            ].compactMap { $0 }.joined(separator: "\n")
            items.append(WorkerContextItem(
                taskId: task.id,
                kind: .check,
                title: label,
                path: run.outputPath,
                value: body
            ))
        }

        for artifact in artifacts.prefix(8) {
            items.append(WorkerContextItem(
                taskId: task.id,
                kind: .artifact,
                title: artifact.artifactType?.displayName ?? artifact.type,
                path: artifact.path,
                value: artifact.description.isEmpty ? artifact.path : artifact.description
            ))
        }

        if !reviewFeedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(WorkerContextItem(
                taskId: task.id,
                kind: .reviewFeedback,
                title: "Review Feedback",
                value: reviewFeedback
            ))
        }

        if !previousSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(WorkerContextItem(
                taskId: task.id,
                kind: .previousSummary,
                title: "Previous Summary",
                value: previousSummary
            ))
        }

        if let project {
            items.append(contentsOf: ruleItems(project: project, task: task, scopePaths: diffSnapshot.changedFiles, fileManager: fileManager))
        }

        var included: [WorkerContextItem] = []
        var usedTokens = 0
        for item in items {
            if usedTokens + item.tokenCount <= budget {
                included.append(item)
                usedTokens += item.tokenCount
            } else {
                var excluded = item
                excluded.included = false
                included.append(excluded)
            }
        }

        let metadata = [
            "item_count": "\(included.count)",
            "included_count": "\(included.filter(\.included).count)",
            "budget": "\(budget)"
        ]
        return WorkerContextPack(
            items: included,
            tokenCount: usedTokens,
            budget: budget,
            promptMetadataJSON: JSONCoding.encodeDictionary(metadata)
        )
    }

    private static func taskBrief(_ task: FactoryTask) -> String {
        var parts = ["Title: \(task.title)"]
        if !task.goal.isEmpty { parts.append("Goal: \(task.goal)") }
        if !task.context.isEmpty { parts.append("Context: \(task.context)") }
        if !task.acceptanceCriteria.isEmpty {
            parts.append("Acceptance Criteria:\n" + task.acceptanceCriteria.map { "- \($0)" }.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n")
    }

    private static func ruleItems(
        project: Project,
        task: FactoryTask,
        scopePaths: [String],
        fileManager: FileManager
    ) -> [WorkerContextItem] {
        var urls: [URL] = []
        let root = URL(fileURLWithPath: project.path, isDirectory: true)
        let agents = root.appendingPathComponent("AGENTS.md")
        if fileManager.fileExists(atPath: agents.path) {
            urls.append(agents)
        }
        let rulesDirectory = root.appendingPathComponent(".factory/rules", isDirectory: true)
        if let children = try? fileManager.contentsOfDirectory(at: rulesDirectory, includingPropertiesForKeys: [.isRegularFileKey]) {
            urls.append(contentsOf: children.filter { url in
                ((try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false) &&
                    ruleApplies(ruleURL: url, scopePaths: scopePaths, projectRoot: root)
            })
        }
        return urls.compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return WorkerContextItem(
                taskId: task.id,
                kind: url.lastPathComponent == "AGENTS.md" ? .projectGuidance : .repoRule,
                title: url.lastPathComponent,
                path: url.path,
                value: text
            )
        }
    }

    private static func ruleApplies(ruleURL: URL, scopePaths: [String], projectRoot: URL) -> Bool {
        guard !scopePaths.isEmpty else { return true }
        let ruleName = ruleURL.deletingPathExtension().lastPathComponent.lowercased()
        if ["global", "factory", "repo", "project"].contains(ruleName) {
            return true
        }
        return scopePaths.contains { path in
            let lower = path.lowercased()
            return lower.contains(ruleName) || ruleURL.path.lowercased().contains(URL(fileURLWithPath: path, relativeTo: projectRoot).deletingLastPathComponent().path.lowercased())
        }
    }
}

public enum WorkerContentHash {
    public static func sha256(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public enum WorkerTokenEstimator {
    public static func estimate(_ text: String) -> Int {
        max(1, Int(ceil(Double(text.count) / 4.0)))
    }
}
