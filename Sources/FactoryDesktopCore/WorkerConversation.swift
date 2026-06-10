import Foundation

public struct WorkerConversation: Equatable {
    public var events: [WorkerConversationEvent]
    public var preview: WorkerConversationPreview

    public init(events: [WorkerConversationEvent], preview: WorkerConversationPreview) {
        self.events = events
        self.preview = preview
    }
}

public struct WorkerConversationPreview: Equatable {
    public var statusLine: String
    public var latestMeaningfulMessage: String
    public var verificationDigest: String
    public var changedFilesSummary: String
    public var nextRecommendedAction: String
    public var hasRawLogs: Bool

    public init(
        statusLine: String,
        latestMeaningfulMessage: String,
        verificationDigest: String,
        changedFilesSummary: String,
        nextRecommendedAction: String,
        hasRawLogs: Bool
    ) {
        self.statusLine = statusLine
        self.latestMeaningfulMessage = latestMeaningfulMessage
        self.verificationDigest = verificationDigest
        self.changedFilesSummary = changedFilesSummary
        self.nextRecommendedAction = nextRecommendedAction
        self.hasRawLogs = hasRawLogs
    }
}

public struct WorkerConversationEvent: Identifiable, Equatable {
    public enum Kind: Equatable {
        case assignment(Assignment)
        case workerMessage(WorkerMessage)
        case toolSummary(ToolSummary)
        case checkResult(CheckResult)
        case changedFiles(ChangedFiles)
        case report(Report)
        case proposedTask(ProposedTask)
        case automationEvent(AutomationEvent)
        case warning(Warning)
        case rawLogReference(RawLogReference)
    }

    public var id: String
    public var createdAt: Date
    public var kind: Kind

    public init(id: String, createdAt: Date, kind: Kind) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
    }
}

public extension WorkerConversationEvent {
    struct Assignment: Equatable {
        public var title: String
        public var taskIdentifier: String
        public var summary: String

        public init(title: String, taskIdentifier: String, summary: String) {
            self.title = title
            self.taskIdentifier = taskIdentifier
            self.summary = summary
        }
    }

    struct WorkerMessage: Equatable {
        public var text: String
        public var isFinal: Bool

        public init(text: String, isFinal: Bool) {
            self.text = text
            self.isFinal = isFinal
        }
    }

    struct ToolSummary: Equatable {
        public var title: String
        public var status: String
        public var detail: String

        public init(title: String, status: String, detail: String) {
            self.title = title
            self.status = status
            self.detail = detail
        }
    }

    struct CheckResult: Equatable {
        public struct Row: Equatable {
            public var label: String
            public var status: String

            public init(label: String, status: String) {
                self.label = label
                self.status = status
            }
        }

        public var summary: String
        public var rows: [Row]

        public init(summary: String, rows: [Row]) {
            self.summary = summary
            self.rows = rows
        }
    }

    struct ChangedFiles: Equatable {
        public var files: [String]
        public var diffStat: String
        public var summary: String

        public init(files: [String], diffStat: String, summary: String) {
            self.files = files
            self.diffStat = diffStat
            self.summary = summary
        }
    }

    struct Report: Equatable {
        public var status: WorkerReportStatus
        public var parseStatus: WorkerReportParseStatus
        public var parseError: String?
        public var summary: String
        public var risks: [String]
        public var blockers: [String]
        public var nextRecommendedAction: String

        public init(
            status: WorkerReportStatus,
            parseStatus: WorkerReportParseStatus,
            parseError: String?,
            summary: String,
            risks: [String],
            blockers: [String],
            nextRecommendedAction: String
        ) {
            self.status = status
            self.parseStatus = parseStatus
            self.parseError = parseError
            self.summary = summary
            self.risks = risks
            self.blockers = blockers
            self.nextRecommendedAction = nextRecommendedAction
        }
    }

    struct ProposedTask: Equatable {
        public var proposal: TaskProposal

        public init(proposal: TaskProposal) {
            self.proposal = proposal
        }
    }

    struct AutomationEvent: Equatable {
        public var title: String
        public var message: String
        public var previousStatus: TaskStatus?
        public var newStatus: TaskStatus?

        public init(title: String, message: String, previousStatus: TaskStatus?, newStatus: TaskStatus?) {
            self.title = title
            self.message = message
            self.previousStatus = previousStatus
            self.newStatus = newStatus
        }
    }

    struct Warning: Equatable {
        public var level: RunnerNotificationLevel
        public var message: String
        public var isRead: Bool

        public init(level: RunnerNotificationLevel, message: String, isRead: Bool) {
            self.level = level
            self.message = message
            self.isRead = isRead
        }
    }

    struct RawLogReference: Equatable {
        public var logPath: String?
        public var prompt: String
        public var rawReport: String

        public init(logPath: String?, prompt: String, rawReport: String) {
            self.logPath = logPath
            self.prompt = prompt
            self.rawReport = rawReport
        }
    }
}

public enum WorkerConversationBuilder {
    public static func build(
        detail: WorkerRunDetail,
        processStatus: WorkerProcessStatus = .unknown
    ) -> WorkerConversation {
        var events: [WorkerConversationEvent] = []
        let anchorDate = detail.execution?.startedAt ?? detail.session?.createdAt ?? detail.task.updatedAt
        events.append(.init(
            id: "assignment-\(detail.task.id)",
            createdAt: anchorDate,
            kind: .assignment(.init(
                title: detail.task.title,
                taskIdentifier: "TASK-\(detail.task.id.shortID.uppercased())",
                summary: assignmentSummary(for: detail.task)
            ))
        ))

        if let execution = detail.execution {
            events.append(.init(
                id: "tool-\(execution.id)",
                createdAt: execution.startedAt,
                kind: .toolSummary(.init(
                    title: execution.runReason == "resume_ai_worker" ? "Worker resumed" : "Worker started",
                    status: execution.status.displayName,
                    detail: toolDetail(execution: execution, processStatus: processStatus)
                ))
            ))
        }

        for turn in detail.agentTurns.sorted(by: { $0.createdAt < $1.createdAt }) where turn.role.lowercased() == "assistant" {
            let text = visibleWorkerText(from: turn.content)
            guard !text.isEmpty else { continue }
            events.append(.init(
                id: "worker-message-\(turn.id)",
                createdAt: turn.createdAt,
                kind: .workerMessage(.init(text: text, isFinal: detail.report != nil))
            ))
        }

        if let report = detail.report {
            if !report.testsRun.isEmpty {
                events.append(.init(
                    id: "checks-\(report.id)",
                    createdAt: report.createdAt,
                    kind: .checkResult(checkResult(from: report))
                ))
            }

            let changedFiles = changedFiles(from: detail)
            if !changedFiles.files.isEmpty || !changedFiles.diffStat.isEmpty {
                events.append(.init(
                    id: "changed-files-\(report.id)",
                    createdAt: report.createdAt,
                    kind: .changedFiles(changedFiles)
                ))
            }

            events.append(.init(
                id: "report-\(report.id)",
                createdAt: report.createdAt,
                kind: .report(.init(
                    status: report.status,
                    parseStatus: report.parseStatus,
                    parseError: report.parseError,
                    summary: report.summary,
                    risks: report.risks,
                    blockers: report.blockers,
                    nextRecommendedAction: report.nextRecommendedAction
                ))
            ))
        } else {
            let changedFiles = changedFiles(from: detail)
            if !changedFiles.files.isEmpty || !changedFiles.diffStat.isEmpty {
                events.append(.init(
                    id: "changed-files-\(detail.task.id)",
                    createdAt: detail.execution?.endedAt ?? anchorDate,
                    kind: .changedFiles(changedFiles)
                ))
            }
        }

        for proposal in detail.proposals.sorted(by: { $0.createdAt < $1.createdAt }) {
            events.append(.init(
                id: "proposal-\(proposal.id)",
                createdAt: proposal.createdAt,
                kind: .proposedTask(.init(proposal: proposal))
            ))
        }

        for notification in detail.notifications.sorted(by: { $0.createdAt < $1.createdAt }) {
            events.append(.init(
                id: "warning-\(notification.id)",
                createdAt: notification.createdAt,
                kind: .warning(.init(level: notification.level, message: notification.message, isRead: notification.isRead))
            ))
        }

        for event in detail.events.sorted(by: { $0.createdAt < $1.createdAt }) {
            events.append(.init(
                id: "automation-\(event.id)",
                createdAt: event.createdAt,
                kind: .automationEvent(.init(
                    title: event.kind.displayName,
                    message: event.message,
                    previousStatus: event.previousStatus,
                    newStatus: event.newStatus
                ))
            ))
        }

        if hasRawReference(detail) {
            events.append(.init(
                id: "raw-reference-\(detail.execution?.id ?? detail.task.id)",
                createdAt: detail.execution?.endedAt ?? detail.report?.createdAt ?? anchorDate,
                kind: .rawLogReference(.init(
                    logPath: detail.execution?.logPath ?? detail.session?.transcriptPath,
                    prompt: detail.prompt,
                    rawReport: detail.report?.rawText ?? ""
                ))
            ))
        }

        let sortedEvents = events.sorted { left, right in
            if left.createdAt != right.createdAt {
                return left.createdAt < right.createdAt
            }
            return eventSortRank(left.kind) < eventSortRank(right.kind)
        }
        return WorkerConversation(events: sortedEvents, preview: preview(from: detail, processStatus: processStatus))
    }

    public static func preview(
        task: FactoryTask?,
        execution: RunnerExecution?,
        processStatus: WorkerProcessStatus,
        report: WorkerReport?,
        proposals: [TaskProposal],
        notifications: [RunnerNotification],
        lifecycleSnapshot: LifecycleSnapshot?,
        diffSnapshot: GitSnapshot
    ) -> WorkerConversationPreview {
        let status = statusLine(execution: execution, processStatus: processStatus, report: report)
        let latestMessage = report?.summary.nonEmptyTrimmed
            ?? notifications.first(where: { !$0.isRead })?.message.nonEmptyTrimmed
            ?? lifecycleSnapshot?.recommendedAction.nonEmptyTrimmed
            ?? task.map { assignmentSummary(for: $0) }
            ?? "No AI Worker activity yet."
        let verification = verificationDigest(report: report)
        let changedSummary = changedFilesSummary(
            fileCount: diffSnapshot.changedFiles.isEmpty ? (report?.filesChanged.count ?? 0) : diffSnapshot.changedFiles.count,
            diffStat: diffSnapshot.diffStat
        )
        let nextAction = report?.nextRecommendedAction.nonEmptyTrimmed
            ?? lifecycleSnapshot?.recommendedAction.nonEmptyTrimmed
            ?? (proposals.contains { $0.status == .proposed } ? "Review proposed follow-up tasks." : nil)
            ?? "Assign or resume the worker when ready."
        return WorkerConversationPreview(
            statusLine: status,
            latestMeaningfulMessage: scrubPreview(latestMessage),
            verificationDigest: verification,
            changedFilesSummary: changedSummary,
            nextRecommendedAction: scrubPreview(nextAction),
            hasRawLogs: execution?.logPath != nil
        )
    }

    public static func visibleWorkerText(from output: String) -> String {
        let visible: String
        if let reportStart = output.range(of: "WORKER REPORT", options: [.caseInsensitive]) {
            visible = String(output[..<reportStart.lowerBound])
        } else {
            visible = output
        }
        return trimForConversation(visible.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func preview(from detail: WorkerRunDetail, processStatus: WorkerProcessStatus) -> WorkerConversationPreview {
        let latestAssistant = detail.agentTurns
            .filter { $0.role.lowercased() == "assistant" }
            .sorted { $0.createdAt > $1.createdAt }
            .compactMap { visibleWorkerText(from: $0.content).nonEmptyTrimmed }
            .first
        return preview(
            task: detail.task,
            execution: detail.execution,
            processStatus: processStatus,
            report: detail.report,
            proposals: detail.proposals,
            notifications: detail.notifications,
            lifecycleSnapshot: detail.lifecycleSnapshots.sorted(by: { $0.createdAt > $1.createdAt }).first,
            diffSnapshot: detail.diffSnapshot ?? GitSnapshot()
        ).withLatestMessage(latestAssistant)
    }

    private static func assignmentSummary(for task: FactoryTask) -> String {
        let goal = task.goal.nonEmptyTrimmed ?? task.title
        return "Factory assigned this task to the AI Worker: \(goal)"
    }

    private static func toolDetail(execution: RunnerExecution, processStatus: WorkerProcessStatus) -> String {
        let processText = processStatus == .unknown ? "" : " Process: \(processStatus.displayName)."
        let exitText = execution.exitCode.map { " Exit code: \($0)." } ?? ""
        return "Execution \(execution.id.shortID) is \(execution.status.displayName.lowercased()).\(processText)\(exitText)"
    }

    private static func checkResult(from report: WorkerReport) -> WorkerConversationEvent.CheckResult {
        let rows = report.testsRun.map { test -> WorkerConversationEvent.CheckResult.Row in
            let lowered = test.lowercased()
            let status: String
            if lowered.contains("not run") || lowered.contains("did not run") {
                status = "Not Run"
            } else if lowered.contains("fail") {
                status = "Failed"
            } else {
                status = "Recorded"
            }
            return .init(label: test, status: status)
        }
        return .init(summary: verificationDigest(report: report), rows: rows)
    }

    private static func changedFiles(from detail: WorkerRunDetail) -> WorkerConversationEvent.ChangedFiles {
        let snapshot = detail.diffSnapshot ?? GitSnapshot()
        let files = snapshot.changedFiles.isEmpty ? (detail.report?.filesChanged ?? []) : snapshot.changedFiles
        let summary = changedFilesSummary(fileCount: files.count, diffStat: snapshot.diffStat)
        return .init(files: files, diffStat: snapshot.diffStat, summary: summary)
    }

    private static func statusLine(
        execution: RunnerExecution?,
        processStatus: WorkerProcessStatus,
        report: WorkerReport?
    ) -> String {
        if processStatus == .running || processStatus == .cancelling {
            return processStatus.displayName
        }
        if let report {
            return "Report: \(report.status.displayName)"
        }
        if let execution {
            return "Execution: \(execution.status.displayName)"
        }
        return "No worker run"
    }

    private static func verificationDigest(report: WorkerReport?) -> String {
        guard let report else { return "No verification recorded" }
        if report.testsRun.isEmpty { return "No checks recorded" }
        if report.testsRun.count == 1 { return report.testsRun[0] }
        return "\(report.testsRun.count) checks recorded"
    }

    private static func changedFilesSummary(fileCount: Int, diffStat: String) -> String {
        let stat = compactDiffStat(diffStat)
        if fileCount == 0 {
            return stat.isEmpty ? "No changed files" : stat
        }
        let fileText = "\(fileCount) changed file\(fileCount == 1 ? "" : "s")"
        return stat.isEmpty ? fileText : "\(fileText) · \(stat)"
    }

    private static func compactDiffStat(_ diffStat: String) -> String {
        diffStat
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .last ?? ""
    }

    fileprivate static func scrubPreview(_ text: String) -> String {
        let lowercased = text.lowercased()
        if lowercased.contains("```") ||
            lowercased.contains("$ ") ||
            lowercased.contains("`git ") ||
            lowercased.contains("`swift ") ||
            lowercased.contains("`rg ") ||
            lowercased.contains("`grep ") ||
            lowercased.contains("`sed ") ||
            lowercased.contains("`codex ") ||
            ["git ", "swift ", "rg ", "grep ", "sed ", "codex "].contains(where: { lowercased.hasPrefix($0) || lowercased.contains("\n\($0)") }) {
            return "Worker update available. Open Conversation for details."
        }
        let noPaths = text
            .components(separatedBy: .whitespacesAndNewlines)
            .map { token in
                token.hasPrefix("/") ? URL(fileURLWithPath: token).lastPathComponent : token
            }
            .joined(separator: " ")
        return trimForConversation(noPaths, maxCharacters: 220)
    }

    private static func trimForConversation(_ text: String, maxCharacters: Int = 2400) -> String {
        guard text.count > maxCharacters else { return text }
        let index = text.index(text.startIndex, offsetBy: maxCharacters)
        return String(text[..<index]).trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n[Output trimmed. View raw logs for the full text.]"
    }

    private static func hasRawReference(_ detail: WorkerRunDetail) -> Bool {
        detail.execution?.logPath != nil ||
            detail.session?.transcriptPath != nil ||
            !detail.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !(detail.report?.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private static func eventSortRank(_ kind: WorkerConversationEvent.Kind) -> Int {
        switch kind {
        case .assignment: 0
        case .toolSummary: 1
        case .workerMessage: 2
        case .checkResult: 3
        case .changedFiles: 4
        case .report: 5
        case .proposedTask: 6
        case .warning: 7
        case .automationEvent: 8
        case .rawLogReference: 9
        }
    }
}

private extension WorkerConversationPreview {
    func withLatestMessage(_ message: String?) -> WorkerConversationPreview {
        guard let message, !message.isEmpty else { return self }
        var copy = self
        copy.latestMeaningfulMessage = WorkerConversationBuilder.scrubPreview(WorkerConversationBuilder.visibleWorkerText(from: message))
        return copy
    }
}

private extension Optional where Wrapped == String {
    var nonEmptyTrimmed: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
