import Foundation

public enum ConveyorColumn: String, CaseIterable, Codable, Identifiable, Sendable {
    case backlog = "Backlog"
    case ready = "Ready"
    case running = "Running"
    case blocked = "Blocked"
    case done = "Done"

    public var id: String { rawValue }
}

public enum ConveyorPriority: String, CaseIterable, Codable, Identifiable, Sendable {
    case p1 = "P1"
    case p2 = "P2"
    case p3 = "P3"

    public var id: String { rawValue }
}

public enum ConveyorScope: String, CaseIterable, Codable, Identifiable, Sendable {
    case active
    case unfinished
    case all

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .active: "Current Milestone"
        case .unfinished: "All Unfinished"
        case .all: "All Features"
        }
    }
}

public struct ConveyorMilestone: Codable, Equatable, Identifiable, Sendable {
    public let milestoneID: String
    public let title: String?
    public let totalCount: Int
    public let unfinishedCount: Int
    public let readyCount: Int
    public let blockedCount: Int
    public let completedCount: Int
    public let active: Bool

    public var id: String { milestoneID }

    enum CodingKeys: String, CodingKey {
        case milestoneID = "milestone_id"
        case title
        case totalCount = "total_count"
        case unfinishedCount = "unfinished_count"
        case readyCount = "ready_count"
        case blockedCount = "blocked_count"
        case completedCount = "completed_count"
        case active
    }
}

public struct ConveyorProject: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    public static let registered: [ConveyorProject] = [
        ConveyorProject(id: "interview-companion", name: "Interview Companion"),
        ConveyorProject(id: "case-manager", name: "Case Manager")
    ]
}

public struct ConveyorQueue: Codable, Equatable, Sendable {
    public let projectID: String
    public let scope: ConveyorScope
    public let requestedMilestone: String?
    public let activeMilestone: String
    public let paused: Bool
    public let activeFeature: String?
    public let selectedFeature: String?
    public let nextReadyFeature: String?
    public let features: [ConveyorFeature]
    public let totalFeatureCount: Int
    public let scopedFeatureCount: Int
    public let visibleNonterminalCount: Int
    public let terminalFeatureCount: Int
    public let milestones: [ConveyorMilestone]

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case scope
        case requestedMilestone = "requested_milestone"
        case activeMilestone = "active_milestone"
        case paused, features
        case activeFeature = "active_feature"
        case selectedFeature = "selected_feature"
        case nextReadyFeature = "next_ready_feature"
        case totalFeatureCount = "total_feature_count"
        case scopedFeatureCount = "scoped_feature_count"
        case visibleNonterminalCount = "visible_nonterminal_count"
        case terminalFeatureCount = "terminal_feature_count"
        case milestones
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectID = try container.decode(String.self, forKey: .projectID)
        scope = try container.decodeIfPresent(ConveyorScope.self, forKey: .scope) ?? .active
        requestedMilestone = try container.decodeIfPresent(String.self, forKey: .requestedMilestone)
        activeMilestone = try container.decode(String.self, forKey: .activeMilestone)
        paused = try container.decode(Bool.self, forKey: .paused)
        activeFeature = try container.decodeIfPresent(String.self, forKey: .activeFeature)
        selectedFeature = try container.decodeIfPresent(String.self, forKey: .selectedFeature)
        nextReadyFeature = try container.decodeIfPresent(String.self, forKey: .nextReadyFeature)
        features = try container.decode([ConveyorFeature].self, forKey: .features)
        totalFeatureCount = try container.decodeIfPresent(Int.self, forKey: .totalFeatureCount) ?? features.count
        scopedFeatureCount = try container.decodeIfPresent(Int.self, forKey: .scopedFeatureCount) ?? features.count
        visibleNonterminalCount = try container.decodeIfPresent(Int.self, forKey: .visibleNonterminalCount)
            ?? features.filter { $0.kanbanColumn != .done }.count
        terminalFeatureCount = try container.decodeIfPresent(Int.self, forKey: .terminalFeatureCount)
            ?? features.filter { $0.kanbanColumn == .done }.count
        milestones = try container.decodeIfPresent([ConveyorMilestone].self, forKey: .milestones) ?? []
    }
}

public struct ConveyorFeature: Codable, Identifiable, Equatable, Sendable {
    public let featureID: String
    public let title: String
    public let milestone: String
    public let status: String
    public let description: String
    public let specificationPath: String?
    public let kanbanColumn: ConveyorColumn
    public let priority: ConveyorPriority
    public let queuePosition: Int
    public let dependencies: [String]
    public let dependenciesComplete: Bool
    public let readiness: String
    public let blockedReason: String?
    public let readyTransitionEligible: Bool
    public let readyTransitionReason: String?
    public let executionProfile: ConveyorExecutionProfile
    public let executionModel: String?
    public let reasoning: String?
    public let branch: String?
    public let commit: String?
    public let latestTerminalResult: JSONValue?
    public let activeMilestoneMember: Bool
    public let executionEligible: Bool
    public let executionIneligibleReason: String?

    public var id: String { featureID }

    enum CodingKeys: String, CodingKey {
        case featureID = "feature_id"
        case title, milestone, status, description, priority, dependencies, readiness, branch, commit
        case specificationPath = "specification_path"
        case kanbanColumn = "kanban_column"
        case queuePosition = "queue_position"
        case dependenciesComplete = "dependencies_complete"
        case blockedReason = "blocked_reason"
        case readyTransitionEligible = "ready_transition_eligible"
        case readyTransitionReason = "ready_transition_reason"
        case executionProfile = "execution_profile"
        case executionModel = "execution_model"
        case reasoning = "reasoning"
        case latestTerminalResult = "latest_terminal_result"
        case activeMilestoneMember = "active_milestone_member"
        case executionEligible = "execution_eligible"
        case executionIneligibleReason = "execution_ineligible_reason"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        featureID = try container.decode(String.self, forKey: .featureID)
        title = try container.decode(String.self, forKey: .title)
        milestone = try container.decodeIfPresent(String.self, forKey: .milestone) ?? ""
        status = try container.decode(String.self, forKey: .status)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        specificationPath = try container.decodeIfPresent(String.self, forKey: .specificationPath)
        kanbanColumn = try container.decode(ConveyorColumn.self, forKey: .kanbanColumn)
        priority = try container.decode(ConveyorPriority.self, forKey: .priority)
        queuePosition = try container.decode(Int.self, forKey: .queuePosition)
        dependencies = try container.decodeIfPresent([String].self, forKey: .dependencies) ?? []
        dependenciesComplete = try container.decodeIfPresent(Bool.self, forKey: .dependenciesComplete) ?? false
        readiness = try container.decodeIfPresent(String.self, forKey: .readiness) ?? "not_ready"
        blockedReason = try container.decodeIfPresent(String.self, forKey: .blockedReason)
        readyTransitionEligible = try container.decodeIfPresent(Bool.self, forKey: .readyTransitionEligible) ?? false
        readyTransitionReason = try container.decodeIfPresent(String.self, forKey: .readyTransitionReason)
        executionProfile = try container.decode(ConveyorExecutionProfile.self, forKey: .executionProfile)
        executionModel = try container.decodeIfPresent(String.self, forKey: .executionModel)
        reasoning = try container.decodeIfPresent(String.self, forKey: .reasoning)
        branch = try container.decodeIfPresent(String.self, forKey: .branch)
        commit = try container.decodeIfPresent(String.self, forKey: .commit)
        latestTerminalResult = try container.decodeIfPresent(JSONValue.self, forKey: .latestTerminalResult)
        activeMilestoneMember = try container.decodeIfPresent(Bool.self, forKey: .activeMilestoneMember) ?? true
        executionEligible = (try container.decodeIfPresent(Bool.self, forKey: .executionEligible)) ?? (kanbanColumn == .ready)
        executionIneligibleReason = try container.decodeIfPresent(String.self, forKey: .executionIneligibleReason)
    }
}

public struct ConveyorExecutionProfile: Codable, Equatable, Sendable {
    public let profile: String?
    public let model: String?
    public let reasoning: String?
    public let parentSessions: Int
    public let childSessions: Int

    enum CodingKeys: String, CodingKey {
        case profile, model, reasoning
        case parentSessions = "parent_sessions"
        case childSessions = "child_sessions"
    }
}

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var summary: String {
        switch self {
        case let .string(value): return value
        case let .number(value): return String(value)
        case let .bool(value): return value ? "true" : "false"
        case .null: return "No terminal result"
        case .array: return "Terminal result available"
        case let .object(value):
            if case let .string(result)? = value["result"] { return result }
            if case let .string(outcome)? = value["outcome"] { return outcome }
            return "Terminal result available"
        }
    }
}

public struct ConveyorMutationResult: Codable, Equatable, Sendable {
    public let classification: String
    public let featureID: String?
    public let changedPaths: [String]
    public let modelSessionsLaunched: Int
    public let childSessionsLaunched: Int

    enum CodingKeys: String, CodingKey {
        case classification
        case featureID = "feature_id"
        case changedPaths = "changed_paths"
        case modelSessionsLaunched = "model_sessions_launched"
        case childSessionsLaunched = "child_sessions_launched"
    }
}
