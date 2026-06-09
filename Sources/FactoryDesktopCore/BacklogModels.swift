import Foundation

public enum BacklogPriorityLevel: String, CaseIterable, Codable, Identifiable, Sendable {
    case p0
    case p1
    case p2
    case p3

    public var id: String { rawValue }

    public var displayName: String {
        rawValue.uppercased()
    }

    public var sortOrder: Int {
        switch self {
        case .p0: 0
        case .p1: 10
        case .p2: 20
        case .p3: 30
        }
    }

    public var taskPriority: TaskPriority {
        switch self {
        case .p0: .urgent
        case .p1: .high
        case .p2: .normal
        case .p3: .low
        }
    }
}

public enum BacklogEffort: String, CaseIterable, Codable, Identifiable, Sendable {
    case unknown
    case small
    case medium
    case large

    public var id: String { rawValue }

    public var displayName: String {
        rawValue.capitalized
    }

    public var sortOrder: Int {
        switch self {
        case .unknown: 99
        case .small: 0
        case .medium: 10
        case .large: 20
        }
    }
}

public enum BacklogRisk: String, CaseIterable, Codable, Identifiable, Sendable {
    case unknown
    case low
    case medium
    case high

    public var id: String { rawValue }

    public var displayName: String {
        rawValue.capitalized
    }

    public var sortOrder: Int {
        switch self {
        case .unknown: 99
        case .low: 0
        case .medium: 10
        case .high: 20
        }
    }
}

public enum BacklogIdeaStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case idea
    case scoping
    case readyToPromote = "ready_to_promote"
    case promoted
    case archived

    public var id: String { rawValue }

    public var displayName: String {
        rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

public struct BacklogIdea: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var projectId: String
    public var title: String
    public var priorityLevel: BacklogPriorityLevel
    public var category: String
    public var source: String
    public var goal: String
    public var context: String
    public var acceptanceCriteria: [String]
    public var effort: BacklogEffort
    public var risk: BacklogRisk
    public var dependencies: String
    public var nonGoals: String
    public var suggestedTaskSplit: String
    public var recommendedNextAction: String
    public var status: BacklogIdeaStatus
    public var linkedTaskId: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        projectId: String,
        title: String,
        priorityLevel: BacklogPriorityLevel = .p2,
        category: String = "",
        source: String = "",
        goal: String = "",
        context: String = "",
        acceptanceCriteria: [String] = [],
        effort: BacklogEffort = .unknown,
        risk: BacklogRisk = .unknown,
        dependencies: String = "",
        nonGoals: String = "",
        suggestedTaskSplit: String = "",
        recommendedNextAction: String = "",
        status: BacklogIdeaStatus = .idea,
        linkedTaskId: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.priorityLevel = priorityLevel
        self.category = category
        self.source = source
        self.goal = goal
        self.context = context
        self.acceptanceCriteria = acceptanceCriteria
        self.effort = effort
        self.risk = risk
        self.dependencies = dependencies
        self.nonGoals = nonGoals
        self.suggestedTaskSplit = suggestedTaskSplit
        self.recommendedNextAction = recommendedNextAction
        self.status = status
        self.linkedTaskId = linkedTaskId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isReadyToPromote: Bool {
        !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !acceptanceCriteria.isEmpty
    }
}

public enum BacklogNextWorkKind: Equatable {
    case idea(BacklogIdea)
    case task(FactoryTask)
}

public struct BacklogNextWorkItem: Identifiable, Equatable {
    public var id: String
    public var kind: BacklogNextWorkKind
    public var title: String
    public var subtitle: String
    public var primaryAction: RunnerRecommendedAction
    public var reason: String
    public var priorityOrder: Int
    public var readinessBucket: Int
    public var effortOrder: Int
    public var riskOrder: Int
    public var updatedAt: Date

    public init(
        id: String,
        kind: BacklogNextWorkKind,
        title: String,
        subtitle: String,
        primaryAction: RunnerRecommendedAction,
        reason: String,
        priorityOrder: Int,
        readinessBucket: Int,
        effortOrder: Int,
        riskOrder: Int,
        updatedAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.primaryAction = primaryAction
        self.reason = reason
        self.priorityOrder = priorityOrder
        self.readinessBucket = readinessBucket
        self.effortOrder = effortOrder
        self.riskOrder = riskOrder
        self.updatedAt = updatedAt
    }
}

public enum BacklogQueueRanking {
    public static func rank(
        ideas: [BacklogIdea],
        tasks: [FactoryTask],
        runnerLinksByTaskID: [String: RunnerSessionLink],
        recommendationsByTaskID: [String: RunnerRecommendation]
    ) -> [BacklogNextWorkItem] {
        let taskItems = tasks
            .filter { $0.status != .done && $0.status != .archived }
            .map { task -> BacklogNextWorkItem in
                let recommendation = recommendationsByTaskID[task.id]
                let hasLinkedSession = runnerLinksByTaskID[task.id] != nil
                let action: RunnerRecommendedAction
                let reason: String
                let readinessBucket: Int
                switch recommendation?.action {
                case .reviewDiff:
                    action = .reviewDiff
                    reason = recommendation?.reason ?? "Runner changes are ready for review."
                    readinessBucket = 0
                case .runTests:
                    action = .runTests
                    reason = recommendation?.reason ?? "Run tests before continuing."
                    readinessBucket = 0
                case .syncLifecycle:
                    action = .syncLifecycle
                    reason = recommendation?.reason ?? "Lifecycle sync has a safe status update."
                    readinessBucket = 0
                case .continueRun:
                    action = .continueRun
                    reason = recommendation?.reason ?? "Continue the existing runner session."
                    readinessBucket = 1
                case .needsManualReview:
                    action = .needsManualReview
                    reason = recommendation?.reason ?? "Review the latest runner output before continuing."
                    readinessBucket = 0
                default:
                    action = hasLinkedSession ? .continueRun : .dispatch
                    reason = hasLinkedSession ? "Continue the linked runner session." : "Scoped task is ready for dispatch."
                    readinessBucket = 1
                }
                return BacklogNextWorkItem(
                    id: "task-\(task.id)",
                    kind: .task(task),
                    title: task.title,
                    subtitle: "\(task.status.displayName) · \(task.priority.displayName)",
                    primaryAction: action,
                    reason: reason,
                    priorityOrder: task.priority.sortOrder,
                    readinessBucket: readinessBucket,
                    effortOrder: 99,
                    riskOrder: 99,
                    updatedAt: task.updatedAt
                )
            }

        let ideaItems = ideas
            .filter { $0.status != .archived && $0.status != .promoted }
            .map { idea -> BacklogNextWorkItem in
                let readinessBucket = idea.isReadyToPromote ? 2 : 3
                let action: RunnerRecommendedAction = idea.isReadyToPromote ? .promoteToTask : .scopeIdea
                let reason = idea.recommendedNextAction.isEmpty
                    ? (idea.isReadyToPromote ? "Idea is ready to promote into a task." : "Idea needs more scoping before it can become executable work.")
                    : idea.recommendedNextAction
                return BacklogNextWorkItem(
                    id: "idea-\(idea.id)",
                    kind: .idea(idea),
                    title: idea.title,
                    subtitle: "\(idea.priorityLevel.displayName) · \(idea.status.displayName)",
                    primaryAction: action,
                    reason: reason,
                    priorityOrder: idea.priorityLevel.sortOrder,
                    readinessBucket: readinessBucket,
                    effortOrder: idea.effort.sortOrder,
                    riskOrder: idea.risk.sortOrder,
                    updatedAt: idea.updatedAt
                )
            }

        return (taskItems + ideaItems).sorted { left, right in
            if left.readinessBucket != right.readinessBucket {
                return left.readinessBucket < right.readinessBucket
            }
            if left.priorityOrder != right.priorityOrder {
                return left.priorityOrder < right.priorityOrder
            }
            if left.effortOrder != right.effortOrder {
                return left.effortOrder < right.effortOrder
            }
            if left.riskOrder != right.riskOrder {
                return left.riskOrder < right.riskOrder
            }
            return left.updatedAt < right.updatedAt
        }
    }
}
