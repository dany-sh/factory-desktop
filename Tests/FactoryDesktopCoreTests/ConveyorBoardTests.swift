import XCTest
@testable import FactoryDesktopCore

@MainActor
final class ConveyorBoardTests: XCTestCase {
    func testQueueJSONDecodesNativeBoardFields() async throws {
        let executor = FixtureConveyorExecutor()
        let client = ConveyorProcessClient(executor: executor)
        let queue = try await client.queue(projectID: "interview-companion")

        XCTAssertEqual(queue.projectID, "interview-companion")
        XCTAssertEqual(queue.features.first?.kanbanColumn, .backlog)
        XCTAssertEqual(queue.features.first?.priority, .p2)
        XCTAssertEqual(queue.features.first?.executionModel, "gpt-5.6-terra")
    }

    func testProcessClientBuildsOnlyValidatedConveyorCommands() async throws {
        let executor = FixtureConveyorExecutor()
        let client = ConveyorProcessClient(executor: executor)

        _ = try await client.markReady(projectID: "case-manager", featureID: "F001")
        _ = try await client.prioritize(projectID: "case-manager", featureID: "F001", priority: .p1, beforeFeatureID: "F002")
        _ = try await client.reorder(projectID: "case-manager", featureID: "F001", beforeFeatureID: "F002")
        _ = try await client.pause(projectID: "case-manager")
        _ = try await client.unpause(projectID: "case-manager")
        _ = try await client.runThisFeature(projectID: "case-manager", featureID: "F001")
        _ = try await client.runNext(projectID: "case-manager")

        let commands = await executor.recordedArguments()
        XCTAssertEqual(commands, [
            ["ready", "--project", "case-manager", "--feature", "F001"],
            ["prioritize", "--project", "case-manager", "--feature", "F001", "--priority", "P1", "--before", "F002"],
            ["prioritize", "--project", "case-manager", "--feature", "F001", "--before", "F002"],
            ["pause", "--project", "case-manager"],
            ["unpause", "--project", "case-manager"],
            ["run", "--project", "case-manager", "--feature", "F001"],
            ["resume", "--project", "case-manager"]
        ])
    }

    func testProcessClientIncludesReadOnlyScopeAndMilestone() async throws {
        let executor = FixtureConveyorExecutor()
        let client = ConveyorProcessClient(executor: executor)

        _ = try await client.queue(projectID: "interview-companion", scope: .all, milestone: "M1")

        let commands = await executor.recordedArguments()
        XCTAssertEqual(commands, [["queue", "--project", "interview-companion", "--scope", "all", "--milestone", "M1", "--json"]])
    }

    func testProcessClientUsesOnlyReadOnlyStatusArguments() async throws {
        let executor = FixtureConveyorExecutor()
        let client = ConveyorProcessClient(executor: executor)

        _ = try await client.status(projectID: "interview-companion")

        let commands = await executor.recordedArguments()
        XCTAssertEqual(commands, [["status", "--project", "interview-companion"]])
    }

    func testStatusPresentationMapsCurrentPausedReconciliationFixture() throws {
        let status = try decodeStatus("""
        {
          "project_id":"interview-companion",
          "operator_paused":true,
          "next_action":"project_paused",
          "current_state":"queue_reconciliation",
          "unpaused_proposed_next_action":"queue_reconciliation",
          "queue_status":{"ready_features":[],"configured_milestone":"M0","reconciliation_classification":"reconciled_no_ready_work"},
          "current_repository_state":{"clean":false,"writer_lease":{"ambiguous":false,"exists":false,"owned_by_active_cycle":false}},
          "future_controller_field":{"unknown":true}
        }
        """)

        let presentation = ConveyorStatusPresenter.presentation(for: status)
        XCTAssertEqual(presentation.label, "Paused")
        XCTAssertEqual(presentation.supportingText, "No Ready work in M0")
        XCTAssertEqual(presentation.attention, "Queue reconciliation required")
        XCTAssertEqual(presentation.accessibilityHelp, "Repository has local changes")
    }

    func testRunningTakesPrecedenceOverPauseRequest() throws {
        let status = try decodeStatus("""
        {
          "project_id":"case-manager",
          "operator_paused":true,
          "cycle_phase":"feature_execution",
          "selected_feature":"P0-003",
          "queue_status":{"ready_features":["P0-003"],"configured_milestone":"P0"}
        }
        """)

        let presentation = ConveyorStatusPresenter.presentation(for: status)
        XCTAssertEqual(presentation.label, "Running")
        XCTAssertEqual(presentation.supportingText, "Pausing after current")
    }

    func testStatusPresentationCoversReadyIdleHumanGateLockAndUnknownValues() throws {
        let ready = ConveyorStatusPresenter.presentation(for: try decodeStatus("""
        {"project_id":"case-manager","operator_paused":false,"current_state":"future_ready_state","queue_status":{"ready_features":["P0-003"],"configured_milestone":"P0"}}
        """))
        XCTAssertEqual(ready.label, "Ready")
        XCTAssertEqual(ready.supportingText, "Next eligible: P0-003")

        let idle = ConveyorStatusPresenter.presentation(for: try decodeStatus("""
        {"project_id":"case-manager","operator_paused":false,"derived_state":"future_idle_state","queue_status":{"ready_features":[],"configured_milestone":"P0"}}
        """))
        XCTAssertEqual(idle.label, "Idle")
        XCTAssertEqual(idle.supportingText, "No Ready work in P0")

        let attention = ConveyorStatusPresenter.presentation(for: try decodeStatus("""
        {
          "project_id":"case-manager",
          "human_resolution_required":true,
          "human_gate":{"kind":"future_gate"},
          "queue_status":{},
          "current_repository_state":{"clean":false},
          "lock_status":{"repository_writer":{"ambiguous":true,"exists":true,"owned_by_active_cycle":false}}
        }
        """))
        XCTAssertEqual(attention.attention, "Human decision required")
        XCTAssertEqual(attention.accessibilityHelp, "Lock state requires attention. Repository has local changes")
    }

    func testStatusFailureKeepsQueueAndOffersUnavailablePresentationWithoutMutation() async {
        let executor = FixtureConveyorExecutor(failStatus: true)
        let store = ConveyorBoardStore(client: ConveyorProcessClient(executor: executor))

        await store.refresh()

        XCTAssertNotNil(store.queue)
        XCTAssertEqual(store.conveyorStatusPresentation.label, "Unavailable")
        let commands = await executor.recordedArguments()
        XCTAssertEqual(commands.map(\.first), ["queue", "status"])
        XCTAssertFalse(commands.contains {
            ["pause", "unpause", "ready", "backlog", "prioritize", "run", "resume", "reconcile"].contains($0.first)
        })
    }

    func testReadinessPriorityAndDisabledReasonsMapToControllerActions() async {
        let executor = FixtureConveyorExecutor()
        let store = ConveyorBoardStore(client: ConveyorProcessClient(executor: executor))
        await store.refresh()
        let feature = try! XCTUnwrap(store.queue?.features.first)

        XCTAssertNil(store.actionReason(.markReady, for: feature))
        XCTAssertNil(store.actionReason(.setPriority, for: feature))
        await store.markReady(feature)
        await store.setPriority(feature, priority: .p1)
        let commands = await executor.recordedArguments()
        XCTAssertTrue(commands.contains(["ready", "--project", "interview-companion", "--feature", "F001"]))
        XCTAssertTrue(commands.contains(["prioritize", "--project", "interview-companion", "--feature", "F001", "--priority", "P1"]))
    }

    func testFailedDragKeepsPriorProjectionAndNeverRunsFeature() async {
        let executor = FixtureConveyorExecutor(failPrioritize: true)
        let store = ConveyorBoardStore(client: ConveyorProcessClient(executor: executor))
        await store.refresh()
        let original = store.queue
        let feature = try! XCTUnwrap(original?.features.first)
        await store.drop(feature, onto: fixtureFeature(id: "F002", column: .backlog), column: .backlog)

        XCTAssertEqual(store.queue, original)
        XCTAssertTrue(store.errorMessage?.contains("exact controller failure") == true)
        let commands = await executor.recordedArguments()
        XCTAssertEqual(commands.last?.first, "prioritize")
        XCTAssertFalse(commands.contains { $0.first == "run" || $0.first == "resume" })
    }

    func testCardDragTransitionsUseControllerReadyAndBacklogActionsWithoutRunning() async {
        let executor = FixtureConveyorExecutor()
        let store = ConveyorBoardStore(client: ConveyorProcessClient(executor: executor))
        await store.refresh()
        let backlogFeature = try! XCTUnwrap(store.queue?.features.first)

        await store.drop(backlogFeature, onto: nil, column: .ready)
        await store.drop(fixtureFeature(id: "F010", column: .ready), onto: nil, column: .backlog)

        let commands = await executor.recordedArguments()
        XCTAssertTrue(commands.contains(["ready", "--project", "interview-companion", "--feature", "F001"]))
        XCTAssertTrue(commands.contains(["backlog", "--project", "interview-companion", "--feature", "F010"]))
        XCTAssertFalse(commands.contains { $0.first == "run" || $0.first == "resume" })
    }

    func testProjectSwitchAndPauseStateRefresh() async {
        let executor = FixtureConveyorExecutor()
        let store = ConveyorBoardStore(client: ConveyorProcessClient(executor: executor))
        await store.selectProject("case-manager")
        XCTAssertEqual(store.queue?.projectID, "case-manager")
        await store.setPaused(true)
        await store.setPaused(false)
        let commands = await executor.recordedArguments()
        XCTAssertTrue(commands.contains(["pause", "--project", "case-manager"]))
        XCTAssertTrue(commands.contains(["unpause", "--project", "case-manager"]))
    }

    func testScopeAndMilestoneChangesRefreshAndClearAFilteredSelection() async {
        let executor = FixtureConveyorExecutor()
        let store = ConveyorBoardStore(client: ConveyorProcessClient(executor: executor))
        XCTAssertFalse(store.isInspectorVisible)
        await store.refresh()
        store.selectFeature("F001")

        await store.setScope(.all)
        XCTAssertEqual(store.queue?.scope, .all)
        XCTAssertEqual(store.selectedFeatureID, "F001")

        store.isInspectorVisible = true
        await store.setMilestoneFilter("M1")
        XCTAssertNil(store.selectedFeatureID)
        XCTAssertFalse(store.isInspectorVisible)
        let commands = await executor.recordedArguments()
        XCTAssertTrue(commands.contains(["queue", "--project", "interview-companion", "--scope", "all", "--milestone", "M1", "--json"]))
    }

    func testInspectorToggleRequiresSelectionAndRestoresTheSelectedFeatureInspector() async {
        let store = ConveyorBoardStore(client: ConveyorProcessClient(executor: FixtureConveyorExecutor()))
        await store.refresh()

        store.toggleInspector()
        XCTAssertFalse(store.isInspectorVisible)

        store.inspect("F001")
        XCTAssertEqual(store.selectedFeatureID, "F001")
        XCTAssertTrue(store.isInspectorVisible)
        store.toggleInspector()
        XCTAssertFalse(store.isInspectorVisible)
    }

    func testLocalFiltersAndFutureMilestoneActionsDoNotMutate() async throws {
        let executor = FixtureConveyorExecutor()
        let store = ConveyorBoardStore(client: ConveyorProcessClient(executor: executor))
        await store.refresh()
        store.searchText = "does-not-match"
        XCTAssertTrue(store.visibleFeatures.isEmpty)
        XCTAssertTrue(store.hasActiveFilters)

        let future = try JSONDecoder().decode(ConveyorFeature.self, from: Data("""
        {"feature_id":"F200","title":"Future","milestone":"M1","status":"ready","description":"","specification_path":null,"kanban_column":"Ready","priority":"P1","queue_position":2,"dependencies":[],"dependencies_complete":true,"readiness":"ready","blocked_reason":null,"ready_transition_eligible":false,"ready_transition_reason":"Feature is in milestone M1; execution is restricted to active milestone M0.","active_milestone_member":false,"execution_eligible":false,"execution_ineligible_reason":"Feature is in milestone M1; execution is restricted to active milestone M0.","execution_profile":{"profile":"bounded_precise","model":"gpt-5.6-terra","reasoning":"high","parent_sessions":1,"child_sessions":0},"execution_model":"gpt-5.6-terra","reasoning":"high","branch":null,"commit":null,"latest_terminal_result":null}
        """.utf8))
        XCTAssertEqual(store.actionReason(.runThis, for: future), "Feature is in milestone M1; execution is restricted to active milestone M0.")
        let commands = await executor.recordedArguments()
        XCTAssertTrue(commands.filter { $0.first == "run" || $0.first == "resume" }.isEmpty)
    }
}

private actor FixtureConveyorExecutor: ConveyorCommandExecuting {
    private(set) var arguments: [[String]] = []
    private let failPrioritize: Bool
    private let failStatus: Bool

    init(failPrioritize: Bool = false, failStatus: Bool = false) {
        self.failPrioritize = failPrioritize
        self.failStatus = failStatus
    }

    func execute(arguments: [String]) async throws -> ConveyorCommandResult {
        self.arguments.append(arguments)
        if failPrioritize && arguments.first == "prioritize" {
            return ConveyorCommandResult(exitCode: 1, standardOutput: "", standardError: "exact controller failure")
        }
        if arguments.first == "status" {
            if failStatus {
                return ConveyorCommandResult(exitCode: 1, standardOutput: "", standardError: "status unavailable")
            }
            return ConveyorCommandResult(exitCode: 0, standardOutput: fixtureStatus(project: arguments[2]), standardError: "")
        }
        if arguments.first == "queue" {
            let project = arguments[2]
            let scope = arguments[4]
            let milestone = arguments.lastIndex(of: "--milestone").map { arguments[$0 + 1] }
            return ConveyorCommandResult(exitCode: 0, standardOutput: fixtureQueue(project: project, scope: scope, milestone: milestone), standardError: "")
        }
        return ConveyorCommandResult(exitCode: 0, standardOutput: """
        {"classification":"ok","feature_id":"F001","changed_paths":["docs/FEATURE_QUEUE.yaml"],"model_sessions_launched":0,"child_sessions_launched":0}
        """, standardError: "")
    }

    func recordedArguments() -> [[String]] { arguments }
}

private func decodeStatus(_ source: String) throws -> ConveyorStatusProjection {
    try JSONDecoder().decode(ConveyorStatusProjection.self, from: Data(source.utf8))
}

private func fixtureFeature(id: String, column: ConveyorColumn) -> ConveyorFeature {
    let isReady = column == .ready
    return try! JSONDecoder().decode(ConveyorFeature.self, from: Data("""
    {"feature_id":"\(id)","title":"Fixture \(id)","milestone":"M0","status":"\(isReady ? "ready" : "proposed")","description":"","specification_path":null,"kanban_column":"\(column.rawValue)","priority":"P2","queue_position":2,"dependencies":[],"dependencies_complete":true,"readiness":"\(isReady ? "ready" : "not_ready")","blocked_reason":null,"ready_transition_eligible":\(!isReady),"ready_transition_reason":null,"active_milestone_member":true,"execution_eligible":false,"execution_ineligible_reason":"feature status is \(isReady ? "ready; expected execution eligibility" : "proposed; expected ready")","execution_profile":{"profile":"bounded_precise","model":"gpt-5.6-terra","reasoning":"high","parent_sessions":1,"child_sessions":0},"execution_model":"gpt-5.6-terra","reasoning":"high","branch":null,"commit":null,"latest_terminal_result":null}
    """.utf8))
}

private func fixtureQueue(project: String, scope: String = "active", milestone: String? = nil) -> String {
    let featureID = milestone == "M1" ? "F002" : "F001"
    let featureMilestone = milestone ?? "M0"
    return """
    {"project_id":"\(project)","scope":"\(scope)","requested_milestone":\(milestone.map { "\"\($0)\"" } ?? "null"),"active_milestone":"M0","paused":false,"active_feature":null,"selected_feature":null,"next_ready_feature":null,"total_feature_count":2,"scoped_feature_count":1,"visible_nonterminal_count":1,"terminal_feature_count":1,"milestones":[{"milestone_id":"M0","title":"Current","total_count":1,"unfinished_count":1,"ready_count":0,"blocked_count":0,"completed_count":0,"active":true},{"milestone_id":"M1","title":"Future","total_count":1,"unfinished_count":0,"ready_count":0,"blocked_count":0,"completed_count":1,"active":false}],"features":[{"feature_id":"\(featureID)","title":"Build queue controls","milestone":"\(featureMilestone)","status":"proposed","description":"Controller backlog metadata","specification_path":"/tmp/F001.md","kanban_column":"Backlog","priority":"P2","queue_position":1,"dependencies":[],"dependencies_complete":true,"readiness":"not_ready","blocked_reason":null,"ready_transition_eligible":true,"ready_transition_reason":null,"active_milestone_member":\(featureMilestone == "M0"),"execution_eligible":false,"execution_ineligible_reason":"feature status is proposed; expected ready","execution_profile":{"profile":"bounded_precise","model":"gpt-5.6-terra","reasoning":"high","parent_sessions":1,"child_sessions":0},"execution_model":"gpt-5.6-terra","reasoning":"high","branch":null,"commit":null,"latest_terminal_result":null}]}
    """
}

private func fixtureStatus(project: String) -> String {
    """
    {"project_id":"\(project)","operator_paused":false,"next_action":"feature_cycle","current_state":"feature_ready","derived_state":"feature_ready","cycle_phase":null,"cycle_stop_reason":null,"human_resolution_required":false,"human_gate":null,"queue_status":{"configured_milestone":"M0","ready_features":["F001"],"reconciliation_classification":"reconciled_ready_work","selected_feature":"F001"},"current_repository_state":{"clean":true,"writer_lease":{"ambiguous":false,"exists":false,"owned_by_active_cycle":false}},"lock_status":{"controller_launch":{"ambiguous":false,"exists":false,"owned_by_active_cycle":false},"repository_writer":{"ambiguous":false,"exists":false,"owned_by_active_cycle":false}},"selected_feature":"F001"}
    """
}
