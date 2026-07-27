import Combine
import Foundation

@MainActor
public final class ConveyorBoardStore: ObservableObject {
    @Published public private(set) var queues: [String: ConveyorQueue] = [:]
    @Published public var selectedProjectID: String = ConveyorProject.registered[0].id
    @Published public var selectedFeatureID: String?
    @Published public var scope: ConveyorScope = .active
    @Published public var milestoneFilter: String?
    @Published public var searchText = ""
    @Published public var priorityFilter: ConveyorPriority?
    @Published public var statusFilter: ConveyorColumn?
    @Published public var isSidebarVisible = true
    @Published public var isInspectorVisible = true
    @Published public var isLoading = false
    @Published public var mutationInFlight = false
    @Published public var errorMessage: String?
    @Published public var statusMessage = ""

    private let client: ConveyorProcessClient

    public init(client: ConveyorProcessClient = ConveyorProcessClient()) {
        self.client = client
    }

    public var projects: [ConveyorProject] { ConveyorProject.registered }

    public var selectedProject: ConveyorProject {
        projects.first(where: { $0.id == selectedProjectID }) ?? projects[0]
    }

    public var queue: ConveyorQueue? { queues[selectedProjectID] }

    public var selectedFeature: ConveyorFeature? {
        queue?.features.first(where: { $0.id == selectedFeatureID })
    }

    public func features(in column: ConveyorColumn) -> [ConveyorFeature] {
        guard let queue else { return [] }
        return queue.features
            .filter { $0.kanbanColumn == column }
            .filter { feature in
                (priorityFilter == nil || feature.priority == priorityFilter)
                    && (statusFilter == nil || feature.kanbanColumn == statusFilter)
                    && (searchText.isEmpty || feature.featureID.localizedCaseInsensitiveContains(searchText)
                        || feature.title.localizedCaseInsensitiveContains(searchText))
            }
            .sorted { left, right in
                if left.priority != right.priority { return left.priority.rawValue < right.priority.rawValue }
                if left.queuePosition != right.queuePosition { return left.queuePosition < right.queuePosition }
                return left.featureID < right.featureID
            }
    }

    public var visibleFeatures: [ConveyorFeature] {
        ConveyorColumn.allCases.flatMap { features(in: $0) }
    }

    public var hasActiveFilters: Bool {
        !searchText.isEmpty || priorityFilter != nil || statusFilter != nil || milestoneFilter != nil
    }

    public func resetFilters() {
        searchText = ""
        priorityFilter = nil
        statusFilter = nil
        milestoneFilter = nil
        Task { await refresh() }
    }

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let updated = try await client.queue(
                projectID: selectedProjectID,
                scope: scope,
                milestone: milestoneFilter
            )
            queues[selectedProjectID] = updated
            if let selectedFeatureID, !updated.features.contains(where: { $0.id == selectedFeatureID }) {
                self.selectedFeatureID = nil
            }
            errorMessage = nil
            statusMessage = "Refreshed \(selectedProject.name)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func selectProject(_ projectID: String) async {
        selectedProjectID = projectID
        selectedFeatureID = nil
        await refresh()
    }

    public func setScope(_ newScope: ConveyorScope) async {
        guard scope != newScope else { return }
        scope = newScope
        if newScope == .active { milestoneFilter = nil }
        await refresh()
    }

    public func setMilestoneFilter(_ milestone: String?) async {
        guard milestoneFilter != milestone else { return }
        milestoneFilter = milestone
        await refresh()
    }

    public func selectFeature(_ featureID: String) {
        selectedFeatureID = featureID
    }

    public func inspect(_ featureID: String) {
        selectedFeatureID = featureID
        isInspectorVisible = true
    }

    public func actionReason(_ action: ConveyorBoardAction, for feature: ConveyorFeature?) -> String? {
        guard let queue else { return "Refresh the project first." }
        guard let feature else { return "Select a feature first." }
        guard feature.activeMilestoneMember else {
            return feature.executionIneligibleReason ?? "Execution is restricted to the active milestone."
        }
        switch action {
        case .markReady:
            if queue.activeFeature != nil { return "A Conveyor transaction is active." }
            return feature.readyTransitionEligible ? nil : (feature.readyTransitionReason ?? "Feature is not eligible to become Ready.")
        case .moveToBacklog:
            if queue.activeFeature != nil { return "A Conveyor transaction is active." }
            return feature.status == "ready" ? nil : "Only Ready features can return to Backlog."
        case .runThis:
            return feature.executionEligible ? nil : (feature.executionIneligibleReason ?? "Only an eligible Ready feature can be run.")
        case .setPriority, .reorder:
            if queue.activeFeature != nil { return "A Conveyor transaction is active." }
            return feature.kanbanColumn == .backlog || feature.kanbanColumn == .ready
                ? nil : "Only Backlog and Ready features can be reordered."
        }
    }

    public func markReady(_ feature: ConveyorFeature) async {
        await mutate("Marked \(feature.featureID) Ready.") {
            try await self.client.markReady(projectID: self.selectedProjectID, featureID: feature.featureID)
        }
    }

    public func moveToBacklog(_ feature: ConveyorFeature) async {
        await mutate("Moved \(feature.featureID) to Backlog.") {
            try await self.client.moveToBacklog(projectID: self.selectedProjectID, featureID: feature.featureID)
        }
    }

    public func setPriority(_ feature: ConveyorFeature, priority: ConveyorPriority) async {
        guard feature.priority != priority else { return }
        await mutate("Set \(feature.featureID) to \(priority.rawValue).") {
            try await self.client.prioritize(projectID: self.selectedProjectID, featureID: feature.featureID, priority: priority)
        }
    }

    /// Dragging changes queue metadata only. It never invokes a run command.
    public func drop(_ feature: ConveyorFeature, onto target: ConveyorFeature?, column: ConveyorColumn) async {
        guard actionReason(.reorder, for: feature) == nil else { return }
        guard column == .backlog || column == .ready else {
            errorMessage = "Running, Blocked, and Done do not accept drops."
            return
        }
        guard let target, target.id != feature.id else { return }
        guard target.kanbanColumn == column, target.milestone == feature.milestone else { return }
        await mutate("Reordered \(feature.featureID).") {
            try await self.client.reorder(projectID: self.selectedProjectID, featureID: feature.featureID, beforeFeatureID: target.featureID)
        }
    }

    public func setPaused(_ paused: Bool) async {
        await mutate(paused ? "Pause requested after the current transaction." : "Project unpaused; no work started.") {
            if paused {
                return try await self.client.pause(projectID: self.selectedProjectID)
            }
            return try await self.client.unpause(projectID: self.selectedProjectID)
        }
    }

    public func runThis(_ feature: ConveyorFeature) async {
        await mutate("Run requested for \(feature.featureID).") {
            try await self.client.runThisFeature(projectID: self.selectedProjectID, featureID: feature.featureID)
        }
    }

    public func runNext() async {
        await mutate("Requested one deterministic next feature cycle.") {
            try await self.client.runNext(projectID: self.selectedProjectID)
        }
    }

    private func mutate(_ success: String, operation: @escaping () async throws -> ConveyorMutationResult) async {
        guard !mutationInFlight else { return }
        mutationInFlight = true
        defer { mutationInFlight = false }
        do {
            _ = try await operation()
            statusMessage = success
            errorMessage = nil
            await refresh()
        } catch {
            // The UI is projection-based; keeping the prior queue until refresh succeeds restores a failed drag.
            errorMessage = error.localizedDescription
        }
    }
}

public enum ConveyorBoardAction: Sendable {
    case markReady
    case moveToBacklog
    case runThis
    case setPriority
    case reorder
}
