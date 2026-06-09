import Foundation

public enum FactoryTaskKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case idea
    case bug
    case feature
    case task
    case chore
    case techDebt = "tech_debt"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .idea: "Idea"
        case .bug: "Bug"
        case .feature: "Feature"
        case .task: "Task"
        case .chore: "Chore"
        case .techDebt: "Tech Debt"
        }
    }
}

public enum FactoryTaskTriageStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case inbox
    case backlog
    case needsScoping = "needs_scoping"
    case ready
    case running
    case review
    case done
    case archived

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .inbox: "Inbox"
        case .backlog: "Backlog"
        case .needsScoping: "Needs Scoping"
        case .ready: "Ready"
        case .running: "Running"
        case .review: "Review"
        case .done: "Done"
        case .archived: "Archived"
        }
    }

    public var sortOrder: Int {
        switch self {
        case .inbox: 0
        case .backlog: 10
        case .needsScoping: 20
        case .ready: 30
        case .running: 40
        case .review: 50
        case .done: 60
        case .archived: 70
        }
    }

    public static var kanbanColumns: [FactoryTaskTriageStatus] {
        [.inbox, .backlog, .needsScoping, .ready, .running, .review, .done]
    }

    public static func fromLegacyStatus(_ status: TaskStatus) -> FactoryTaskTriageStatus {
        switch status {
        case .backlog: .backlog
        case .ready, .planning, .planReview, .approved: .ready
        case .building, .testing: .running
        case .needsFixes, .blocked: .needsScoping
        case .readyForReview: .review
        case .done: .done
        case .archived: .archived
        }
    }
}

public enum FactoryTaskReadiness: String, CaseIterable, Codable, Identifiable, Sendable {
    case raw
    case needsScoping = "needs_scoping"
    case scoped
    case executable

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .raw: "Raw"
        case .needsScoping: "Needs Scoping"
        case .scoped: "Scoped"
        case .executable: "Executable"
        }
    }

    public var sortOrder: Int {
        switch self {
        case .executable: 0
        case .scoped: 10
        case .needsScoping: 20
        case .raw: 30
        }
    }
}

public enum FactoryTaskPriorityLabel: String, CaseIterable, Codable, Identifiable, Sendable {
    case critical
    case high
    case normal
    case low
    case someday

    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }

    public var sortOrder: Int {
        switch self {
        case .critical: 0
        case .high: 10
        case .normal: 20
        case .low: 30
        case .someday: 40
        }
    }

    public var taskPriority: TaskPriority {
        switch self {
        case .critical: .urgent
        case .high: .high
        case .normal: .normal
        case .low, .someday: .low
        }
    }

    public static func fromLegacyPriority(_ priority: TaskPriority) -> FactoryTaskPriorityLabel {
        switch priority {
        case .urgent: .critical
        case .high: .high
        case .normal: .normal
        case .low: .low
        }
    }
}

public enum FactoryTaskEffort: String, CaseIterable, Codable, Identifiable, Sendable {
    case unknown
    case small
    case medium
    case large

    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }

    public var sortOrder: Int {
        switch self {
        case .small: 0
        case .medium: 10
        case .large: 20
        case .unknown: 99
        }
    }
}

public enum FactoryTaskRisk: String, CaseIterable, Codable, Identifiable, Sendable {
    case unknown
    case low
    case medium
    case high

    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }

    public var sortOrder: Int {
        switch self {
        case .low: 0
        case .medium: 10
        case .high: 20
        case .unknown: 99
        }
    }
}

public enum BacklogNextWorkKind: Equatable {
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
        tasks: [FactoryTask],
        runnerLinksByTaskID: [String: RunnerSessionLink],
        recommendationsByTaskID: [String: RunnerRecommendation]
    ) -> [BacklogNextWorkItem] {
        tasks
            .filter { $0.triageStatus != .done && $0.triageStatus != .archived }
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
                    if hasLinkedSession {
                        action = .continueRun
                        reason = "Continue the linked runner session."
                        readinessBucket = 1
                    } else if task.readiness == .executable {
                        action = .dispatch
                        reason = "Task is executable and ready for dispatch."
                        readinessBucket = 1
                    } else {
                        action = .scope
                        reason = task.recommendedNextAction.isEmpty ? "Task needs runner-assisted scoping." : task.recommendedNextAction
                        readinessBucket = task.readiness.sortOrder
                    }
                }

                return BacklogNextWorkItem(
                    id: "task-\(task.id)",
                    kind: .task(task),
                    title: task.title,
                    subtitle: "\(task.kind.displayName) · \(task.priorityLabel.displayName) · \(task.readiness.displayName)",
                    primaryAction: action,
                    reason: reason,
                    priorityOrder: task.priorityLabel.sortOrder,
                    readinessBucket: readinessBucket,
                    effortOrder: task.effort.sortOrder,
                    riskOrder: task.risk.sortOrder,
                    updatedAt: task.updatedAt
                )
            }
            .sorted { left, right in
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
