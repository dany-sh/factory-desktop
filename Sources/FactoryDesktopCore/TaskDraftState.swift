import Foundation

public struct TaskEditorSelectionState: Equatable {
    public var selectedText = ""
    public var isFocused = false
    public var activeSection: EditorAssistSection?
    public var cursorAtInsertionPoint = false
    public var changeToken = 0

    public init(
        selectedText: String = "",
        isFocused: Bool = false,
        activeSection: EditorAssistSection? = nil,
        cursorAtInsertionPoint: Bool = false,
        changeToken: Int = 0
    ) {
        self.selectedText = selectedText
        self.isFocused = isFocused
        self.activeSection = activeSection
        self.cursorAtInsertionPoint = cursorAtInsertionPoint
        self.changeToken = changeToken
    }

    public var hasSelection: Bool {
        !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct TaskDraft: Equatable {
    public var title = ""
    public var type: TaskType = .planning
    public var kind: FactoryTaskKind = .task
    public var readiness: FactoryTaskReadiness = .needsScoping
    public var priorityLabel: FactoryTaskPriorityLabel = .normal
    public var category = ""
    public var source = ""
    public var effort: FactoryTaskEffort = .unknown
    public var risk: FactoryTaskRisk = .unknown
    public var brief = ""
    public var dependencies = ""
    public var nonGoals = ""
    public var suggestedSplit = ""
    public var recommendedNextAction = ""

    public init() {}

    public init(task: FactoryTask) {
        title = task.title
        type = task.type
        kind = task.kind
        readiness = task.readiness
        priorityLabel = task.priorityLabel
        category = task.category
        source = task.source
        effort = task.effort
        risk = task.risk
        brief = Self.briefText(goal: task.goal, context: task.context, scopingNotes: task.scopingNotes)
        dependencies = task.dependencies
        nonGoals = task.nonGoals
        suggestedSplit = task.suggestedSplit
        recommendedNextAction = task.recommendedNextAction
    }

    public func task(updating task: FactoryTask, acceptanceText: String) -> FactoryTask {
        var updated = task
        let sections = Self.parseBrief(brief)
        updated.title = title
        updated.type = type
        updated.kind = kind
        updated.readiness = readiness
        updated.priorityLabel = priorityLabel
        updated.priority = priorityLabel.taskPriority
        updated.triageStatus = FactoryTaskTriageStatus.fromLegacyStatus(updated.status)
        updated.category = category
        updated.source = source
        updated.effort = effort
        updated.risk = risk
        updated.goal = sections.goal
        updated.context = sections.context
        updated.scopingNotes = sections.scopingNotes
        updated.dependencies = dependencies
        updated.nonGoals = nonGoals
        updated.suggestedSplit = suggestedSplit
        updated.recommendedNextAction = recommendedNextAction
        updated.acceptanceCriteria = Self.acceptanceCriteria(from: acceptanceText)
        return updated
    }

    public func hasChanges(comparedTo task: FactoryTask, acceptanceText: String) -> Bool {
        title != task.title ||
            type != task.type ||
            kind != task.kind ||
            readiness != task.readiness ||
            priorityLabel != task.priorityLabel ||
            category != task.category ||
            source != task.source ||
            effort != task.effort ||
            risk != task.risk ||
            brief != Self.briefText(goal: task.goal, context: task.context, scopingNotes: task.scopingNotes) ||
            dependencies != task.dependencies ||
            nonGoals != task.nonGoals ||
            suggestedSplit != task.suggestedSplit ||
            recommendedNextAction != task.recommendedNextAction ||
            Self.acceptanceCriteria(from: acceptanceText) != task.acceptanceCriteria
    }

    static func acceptanceCriteria(from acceptanceText: String) -> [String] {
        acceptanceText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func briefText(goal: String, context: String, scopingNotes: String) -> String {
        [
            briefSection(title: "Goal", body: goal),
            briefSection(title: "Context", body: context),
            briefSection(title: "Scoping", body: scopingNotes)
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    private static func briefSection(title: String, body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return "## \(title)\n\(trimmed)"
    }

    private static func parseBrief(_ brief: String) -> (goal: String, context: String, scopingNotes: String) {
        var parsed = ParsedBrief()
        var currentHeading: String?
        var currentBody: [String] = []

        func flush() {
            guard let currentHeading else { return }
            let body = currentBody
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            switch currentHeading {
            case "Goal":
                parsed.goal = body
            case "Context":
                parsed.context = body
            case "Scoping":
                parsed.scopingNotes = body
            default:
                break
            }
            currentBody = []
        }

        for rawLine in brief.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("## ") {
                flush()
                currentHeading = String(trimmed.dropFirst(3))
            } else {
                if currentHeading == nil {
                    currentHeading = "Goal"
                }
                currentBody.append(rawLine)
            }
        }

        flush()
        return (parsed.goal, parsed.context, parsed.scopingNotes)
    }
}

public struct TaskDraftState: Equatable {
    public var taskID: String
    public var draft: TaskDraft
    public var acceptanceText: String
    public var lastPersistedChecksum: String
    public var isDirty: Bool
    public var lastEditedAt: Date?
    public var hasExternalPersistedChange: Bool

    private var lastPersistedSnapshot: TaskDraftSnapshot
    private var lastPersistedUpdatedAt: Date

    public init(task: FactoryTask) {
        let snapshot = TaskDraftSnapshot(task: task)
        taskID = task.id
        draft = snapshot.draft
        acceptanceText = snapshot.acceptanceText
        lastPersistedChecksum = snapshot.checksum
        isDirty = false
        lastEditedAt = nil
        hasExternalPersistedChange = false
        lastPersistedSnapshot = snapshot
        lastPersistedUpdatedAt = task.updatedAt
    }

    public mutating func syncPersistedTask(_ task: FactoryTask) {
        guard task.id == taskID else {
            self = TaskDraftState(task: task)
            return
        }

        let incoming = TaskDraftSnapshot(task: task)
        if shouldPreserveExistingPersistedContent(incoming, updatedAt: task.updatedAt) {
            return
        }

        if isDirty {
            if incoming.checksum != lastPersistedChecksum {
                hasExternalPersistedChange = true
            }
            return
        }

        draft = incoming.draft
        acceptanceText = incoming.acceptanceText
        lastPersistedSnapshot = incoming
        lastPersistedChecksum = incoming.checksum
        lastPersistedUpdatedAt = task.updatedAt
        hasExternalPersistedChange = false
        recomputeDirtyState()
    }

    public mutating func updateDraft(_ draft: TaskDraft, editedAt: Date = Date()) {
        guard self.draft != draft else { return }
        self.draft = draft
        lastEditedAt = editedAt
        recomputeDirtyState()
    }

    public mutating func updateAcceptanceText(_ acceptanceText: String, editedAt: Date = Date()) {
        guard self.acceptanceText != acceptanceText else { return }
        self.acceptanceText = acceptanceText
        lastEditedAt = editedAt
        recomputeDirtyState()
    }

    public mutating func updateDocumentMarkdown(_ markdown: String, editedAt: Date = Date()) {
        let document = TaskEditorDocument.parse(markdown)
        let nextDraft = draftWithUpdatedBrief(document.brief)
        let draftChanged = nextDraft != draft
        let acceptanceChanged = document.acceptanceText != acceptanceText
        guard draftChanged || acceptanceChanged else { return }
        draft = nextDraft
        acceptanceText = document.acceptanceText
        lastEditedAt = editedAt
        recomputeDirtyState()
    }

    public mutating func markPersisted(_ task: FactoryTask) {
        guard task.id == taskID else {
            self = TaskDraftState(task: task)
            return
        }

        let snapshot = TaskDraftSnapshot(task: task)
        draft = snapshot.draft
        acceptanceText = snapshot.acceptanceText
        lastPersistedSnapshot = snapshot
        lastPersistedChecksum = snapshot.checksum
        lastPersistedUpdatedAt = task.updatedAt
        hasExternalPersistedChange = false
        lastEditedAt = nil
        recomputeDirtyState()
    }

    private func shouldPreserveExistingPersistedContent(_ incoming: TaskDraftSnapshot, updatedAt: Date) -> Bool {
        guard updatedAt <= lastPersistedUpdatedAt else { return false }
        return incoming.appearsPartiallyHydrated(comparedTo: lastPersistedSnapshot)
    }

    private func draftWithUpdatedBrief(_ brief: String) -> TaskDraft {
        var updated = draft
        updated.brief = brief
        return updated
    }

    private mutating func recomputeDirtyState() {
        isDirty = TaskDraftSnapshot(draft: draft, acceptanceText: acceptanceText).checksum != lastPersistedChecksum
    }
}

public final class TaskDraftStore {
    private var statesByTaskID: [String: TaskDraftState] = [:]

    public init() {}

    public func state(for taskID: String) -> TaskDraftState? {
        statesByTaskID[taskID]
    }

    @discardableResult
    public func activate(task: FactoryTask) -> TaskDraftState {
        var state = statesByTaskID[task.id] ?? TaskDraftState(task: task)
        state.syncPersistedTask(task)
        statesByTaskID[task.id] = state
        return state
    }

    @discardableResult
    public func update(taskID: String, mutate: (inout TaskDraftState) -> Void) -> TaskDraftState? {
        guard var state = statesByTaskID[taskID] else { return nil }
        mutate(&state)
        statesByTaskID[taskID] = state
        return state
    }

    @discardableResult
    public func markPersisted(task: FactoryTask) -> TaskDraftState {
        var state = statesByTaskID[task.id] ?? TaskDraftState(task: task)
        state.markPersisted(task)
        statesByTaskID[task.id] = state
        return state
    }

    public func remove(taskID: String) {
        statesByTaskID.removeValue(forKey: taskID)
    }

    public func reset() {
        statesByTaskID.removeAll()
    }
}

private struct TaskDraftSnapshot: Equatable {
    var draft: TaskDraft
    var acceptanceText: String

    init(task: FactoryTask) {
        draft = TaskDraft(task: task)
        acceptanceText = task.acceptanceCriteria.joined(separator: "\n")
    }

    init(draft: TaskDraft, acceptanceText: String) {
        self.draft = draft
        self.acceptanceText = acceptanceText
    }

    var checksum: String {
        [
            draft.title,
            draft.type.rawValue,
            draft.kind.rawValue,
            draft.readiness.rawValue,
            draft.priorityLabel.rawValue,
            draft.category,
            draft.source,
            draft.effort.rawValue,
            draft.risk.rawValue,
            draft.brief,
            draft.dependencies,
            draft.nonGoals,
            draft.suggestedSplit,
            draft.recommendedNextAction,
            acceptanceText
        ]
        .joined(separator: "\u{1F}")
    }

    func appearsPartiallyHydrated(comparedTo reference: TaskDraftSnapshot) -> Bool {
        let incomingBrief = draft.brief.trimmingCharacters(in: .whitespacesAndNewlines)
        let referenceBrief = reference.draft.brief.trimmingCharacters(in: .whitespacesAndNewlines)
        let incomingAcceptance = acceptanceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let referenceAcceptance = reference.acceptanceText.trimmingCharacters(in: .whitespacesAndNewlines)

        let lostBrief = incomingBrief.isEmpty && !referenceBrief.isEmpty
        let lostAcceptance = incomingAcceptance.isEmpty && !referenceAcceptance.isEmpty
        return lostBrief || lostAcceptance
    }
}

private struct ParsedBrief {
    var goal = ""
    var context = ""
    var scopingNotes = ""
}
