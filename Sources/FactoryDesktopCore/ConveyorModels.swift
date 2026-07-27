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
    public let activeMilestone: String
    public let paused: Bool
    public let activeFeature: String?
    public let selectedFeature: String?
    public let nextReadyFeature: String?
    public let features: [ConveyorFeature]

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case activeMilestone = "active_milestone"
        case paused, features
        case activeFeature = "active_feature"
        case selectedFeature = "selected_feature"
        case nextReadyFeature = "next_ready_feature"
    }
}

public struct ConveyorFeature: Codable, Identifiable, Equatable, Sendable {
    public let featureID: String
    public let title: String
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

    public var id: String { featureID }

    enum CodingKeys: String, CodingKey {
        case featureID = "feature_id"
        case title, status, description, priority, dependencies, readiness, branch, commit
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
