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

public struct ConveyorStatusProjection: Decodable, Equatable, Sendable {
    public let projectID: String
    public let operatorPaused: Bool
    public let nextAction: String?
    public let unpausedProposedNextAction: String?
    public let currentState: String?
    public let derivedState: String?
    public let cyclePhase: String?
    public let cycleStopReason: String?
    public let humanResolutionRequired: Bool
    public let humanGate: JSONValue?
    public let queueStatus: ConveyorStatusQueue
    public let currentRepositoryState: ConveyorRepositoryStatus?
    public let lockStatus: ConveyorLockStatus?
    public let selectedFeature: String?

    public init(
        projectID: String,
        operatorPaused: Bool = false,
        nextAction: String? = nil,
        unpausedProposedNextAction: String? = nil,
        currentState: String? = nil,
        derivedState: String? = nil,
        cyclePhase: String? = nil,
        cycleStopReason: String? = nil,
        humanResolutionRequired: Bool = false,
        humanGate: JSONValue? = nil,
        queueStatus: ConveyorStatusQueue = ConveyorStatusQueue(),
        currentRepositoryState: ConveyorRepositoryStatus? = nil,
        lockStatus: ConveyorLockStatus? = nil,
        selectedFeature: String? = nil
    ) {
        self.projectID = projectID
        self.operatorPaused = operatorPaused
        self.nextAction = nextAction
        self.unpausedProposedNextAction = unpausedProposedNextAction
        self.currentState = currentState
        self.derivedState = derivedState
        self.cyclePhase = cyclePhase
        self.cycleStopReason = cycleStopReason
        self.humanResolutionRequired = humanResolutionRequired
        self.humanGate = humanGate
        self.queueStatus = queueStatus
        self.currentRepositoryState = currentRepositoryState
        self.lockStatus = lockStatus
        self.selectedFeature = selectedFeature
    }

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case operatorPaused = "operator_paused"
        case nextAction = "next_action"
        case unpausedProposedNextAction = "unpaused_proposed_next_action"
        case currentState = "current_state"
        case derivedState = "derived_state"
        case cyclePhase = "cycle_phase"
        case cycleStopReason = "cycle_stop_reason"
        case humanResolutionRequired = "human_resolution_required"
        case humanGate = "human_gate"
        case queueStatus = "queue_status"
        case currentRepositoryState = "current_repository_state"
        case repositoryState = "repository_state"
        case lockStatus = "lock_status"
        case selectedFeature = "selected_feature"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectID = try container.decode(String.self, forKey: .projectID)
        operatorPaused = try container.decodeIfPresent(Bool.self, forKey: .operatorPaused) ?? false
        nextAction = try container.decodeIfPresent(String.self, forKey: .nextAction)
        unpausedProposedNextAction = try container.decodeIfPresent(String.self, forKey: .unpausedProposedNextAction)
        currentState = try container.decodeIfPresent(String.self, forKey: .currentState)
        derivedState = try container.decodeIfPresent(String.self, forKey: .derivedState)
        cyclePhase = try container.decodeIfPresent(String.self, forKey: .cyclePhase)
        cycleStopReason = try container.decodeIfPresent(String.self, forKey: .cycleStopReason)
        humanResolutionRequired = try container.decodeIfPresent(Bool.self, forKey: .humanResolutionRequired) ?? false
        humanGate = try container.decodeIfPresent(JSONValue.self, forKey: .humanGate)
        queueStatus = try container.decodeIfPresent(ConveyorStatusQueue.self, forKey: .queueStatus) ?? ConveyorStatusQueue()
        currentRepositoryState = try container.decodeIfPresent(ConveyorRepositoryStatus.self, forKey: .currentRepositoryState)
            ?? container.decodeIfPresent(ConveyorRepositoryStatus.self, forKey: .repositoryState)
        lockStatus = try container.decodeIfPresent(ConveyorLockStatus.self, forKey: .lockStatus)
        selectedFeature = try container.decodeIfPresent(String.self, forKey: .selectedFeature)
    }
}

public struct ConveyorStatusQueue: Decodable, Equatable, Sendable {
    public let configuredMilestone: String?
    public let readyFeatures: [String]
    public let reconciliationClassification: String?
    public let selectedFeature: String?

    public init(
        configuredMilestone: String? = nil,
        readyFeatures: [String] = [],
        reconciliationClassification: String? = nil,
        selectedFeature: String? = nil
    ) {
        self.configuredMilestone = configuredMilestone
        self.readyFeatures = readyFeatures
        self.reconciliationClassification = reconciliationClassification
        self.selectedFeature = selectedFeature
    }

    enum CodingKeys: String, CodingKey {
        case configuredMilestone = "configured_milestone"
        case readyFeatures = "ready_features"
        case reconciliationClassification = "reconciliation_classification"
        case selectedFeature = "selected_feature"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        configuredMilestone = try container.decodeIfPresent(String.self, forKey: .configuredMilestone)
        readyFeatures = try container.decodeIfPresent([String].self, forKey: .readyFeatures) ?? []
        reconciliationClassification = try container.decodeIfPresent(String.self, forKey: .reconciliationClassification)
        selectedFeature = try container.decodeIfPresent(String.self, forKey: .selectedFeature)
    }
}

public struct ConveyorRepositoryStatus: Decodable, Equatable, Sendable {
    public let clean: Bool?
    public let writerLease: ConveyorLockObservation?

    public init(clean: Bool? = nil, writerLease: ConveyorLockObservation? = nil) {
        self.clean = clean
        self.writerLease = writerLease
    }

    enum CodingKeys: String, CodingKey {
        case clean
        case writerLease = "writer_lease"
    }
}

public struct ConveyorLockStatus: Decodable, Equatable, Sendable {
    public let controllerLaunch: ConveyorLockObservation?
    public let repositoryWriter: ConveyorLockObservation?

    public init(
        controllerLaunch: ConveyorLockObservation? = nil,
        repositoryWriter: ConveyorLockObservation? = nil
    ) {
        self.controllerLaunch = controllerLaunch
        self.repositoryWriter = repositoryWriter
    }

    enum CodingKeys: String, CodingKey {
        case controllerLaunch = "controller_launch"
        case repositoryWriter = "repository_writer"
    }
}

public struct ConveyorLockObservation: Decodable, Equatable, Sendable {
    public let ambiguous: Bool
    public let exists: Bool
    public let ownedByActiveCycle: Bool

    public init(ambiguous: Bool = false, exists: Bool = false, ownedByActiveCycle: Bool = false) {
        self.ambiguous = ambiguous
        self.exists = exists
        self.ownedByActiveCycle = ownedByActiveCycle
    }

    enum CodingKeys: String, CodingKey {
        case ambiguous, exists
        case ownedByActiveCycle = "owned_by_active_cycle"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ambiguous = try container.decodeIfPresent(Bool.self, forKey: .ambiguous) ?? false
        exists = try container.decodeIfPresent(Bool.self, forKey: .exists) ?? false
        ownedByActiveCycle = try container.decodeIfPresent(Bool.self, forKey: .ownedByActiveCycle) ?? false
    }
}

public struct ConveyorStatusPresentation: Equatable, Sendable {
    public let label: String
    public let supportingText: String
    public let systemImage: String
    public let attention: String?
    public let accessibilityHelp: String?
    public let unavailable: Bool

    public init(
        label: String,
        supportingText: String,
        systemImage: String,
        attention: String? = nil,
        accessibilityHelp: String? = nil,
        unavailable: Bool = false
    ) {
        self.label = label
        self.supportingText = supportingText
        self.systemImage = systemImage
        self.attention = attention
        self.accessibilityHelp = accessibilityHelp
        self.unavailable = unavailable
    }

    public var accessibilityLabel: String {
        [label, supportingText, attention].compactMap { $0 }.joined(separator: ". ")
    }

    public static func unavailable(_ reason: String) -> ConveyorStatusPresentation {
        ConveyorStatusPresentation(
            label: "Unavailable",
            supportingText: reason,
            systemImage: "exclamationmark.circle",
            unavailable: true
        )
    }
}

public enum ConveyorStatusPresenter {
    public static func presentation(for status: ConveyorStatusProjection) -> ConveyorStatusPresentation {
        let isRunning = status.cyclePhase != nil || lockObservations(status).contains(where: \.ownedByActiveCycle)
        let milestone = status.queueStatus.configuredMilestone ?? "current milestone"
        let ready = status.queueStatus.readyFeatures
        let feature = status.selectedFeature ?? status.queueStatus.selectedFeature ?? ready.first

        let execution: (String, String, String)
        if isRunning {
            let support: String
            if status.operatorPaused {
                support = "Pausing after current"
            } else if let feature, let phase = status.cyclePhase {
                support = "\(feature) · \(humanized(phase))"
            } else if let phase = status.cyclePhase {
                support = humanized(phase)
            } else if let feature {
                support = "Active feature \(feature)"
            } else {
                support = "Active Conveyor transaction"
            }
            execution = ("Running", support, "play.circle.fill")
        } else if status.operatorPaused {
            let support: String
            if ready.isEmpty {
                support = "No Ready work in \(milestone)"
            } else if let feature {
                support = "Next eligible: \(feature)"
            } else {
                support = "Work will remain stopped until unpaused"
            }
            execution = ("Paused", support, "pause.circle.fill")
        } else if let feature, !ready.isEmpty {
            execution = ("Ready", "Next eligible: \(feature)", "checkmark.circle.fill")
        } else {
            execution = ("Idle", "No Ready work in \(milestone)", "circle")
        }

        let attentionItems = attentions(for: status)
        return ConveyorStatusPresentation(
            label: execution.0,
            supportingText: execution.1,
            systemImage: execution.2,
            attention: attentionItems.first,
            accessibilityHelp: attentionItems.dropFirst().isEmpty
                ? nil
                : attentionItems.dropFirst().joined(separator: ". ")
        )
    }

    private static func attentions(for status: ConveyorStatusProjection) -> [String] {
        var items: [String] = []
        if status.humanResolutionRequired || status.humanGate != nil {
            items.append("Human decision required")
        }
        if status.currentState == "queue_reconciliation"
            || status.derivedState == "queue_reconciliation"
            || status.nextAction == "queue_reconciliation"
            || status.unpausedProposedNextAction == "queue_reconciliation" {
            items.append("Queue reconciliation required")
        }
        let locks = lockObservations(status)
        if locks.contains(where: \.ambiguous)
            || locks.filter(\.exists).count > 1
            || locks.contains(where: { $0.exists && !$0.ownedByActiveCycle }) {
            items.append("Lock state requires attention")
        }
        if status.currentRepositoryState?.clean == false {
            items.append("Repository has local changes")
        }
        return items
    }

    private static func lockObservations(_ status: ConveyorStatusProjection) -> [ConveyorLockObservation] {
        [
            status.currentRepositoryState?.writerLease,
            status.lockStatus?.controllerLaunch,
            status.lockStatus?.repositoryWriter
        ].compactMap { $0 }
    }

    private static func humanized(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
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
