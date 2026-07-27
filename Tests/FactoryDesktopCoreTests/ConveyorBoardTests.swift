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
        await store.refresh()
        store.selectFeature("F001")

        await store.setScope(.all)
        XCTAssertEqual(store.queue?.scope, .all)
        XCTAssertEqual(store.selectedFeatureID, "F001")

        await store.setMilestoneFilter("M1")
        XCTAssertNil(store.selectedFeatureID)
        let commands = await executor.recordedArguments()
        XCTAssertTrue(commands.contains(["queue", "--project", "interview-companion", "--scope", "all", "--milestone", "M1", "--json"]))
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

    init(failPrioritize: Bool = false) { self.failPrioritize = failPrioritize }

    func execute(arguments: [String]) async throws -> ConveyorCommandResult {
        self.arguments.append(arguments)
        if failPrioritize && arguments.first == "prioritize" {
            return ConveyorCommandResult(exitCode: 1, standardOutput: "", standardError: "exact controller failure")
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

private func fixtureFeature(id: String, column: ConveyorColumn) -> ConveyorFeature {
    try! JSONDecoder().decode(ConveyorFeature.self, from: Data("""
    {"feature_id":"\(id)","title":"Fixture \(id)","milestone":"M0","status":"proposed","description":"","specification_path":null,"kanban_column":"\(column.rawValue)","priority":"P2","queue_position":2,"dependencies":[],"dependencies_complete":true,"readiness":"not_ready","blocked_reason":null,"ready_transition_eligible":true,"ready_transition_reason":null,"active_milestone_member":true,"execution_eligible":false,"execution_ineligible_reason":"feature status is proposed; expected ready","execution_profile":{"profile":"bounded_precise","model":"gpt-5.6-terra","reasoning":"high","parent_sessions":1,"child_sessions":0},"execution_model":"gpt-5.6-terra","reasoning":"high","branch":null,"commit":null,"latest_terminal_result":null}
    """.utf8))
}

private func fixtureQueue(project: String, scope: String = "active", milestone: String? = nil) -> String {
    let featureID = milestone == "M1" ? "F002" : "F001"
    let featureMilestone = milestone ?? "M0"
    return """
    {"project_id":"\(project)","scope":"\(scope)","requested_milestone":\(milestone.map { "\"\($0)\"" } ?? "null"),"active_milestone":"M0","paused":false,"active_feature":null,"selected_feature":null,"next_ready_feature":null,"total_feature_count":2,"scoped_feature_count":1,"visible_nonterminal_count":1,"terminal_feature_count":1,"milestones":[{"milestone_id":"M0","title":"Current","total_count":1,"unfinished_count":1,"ready_count":0,"blocked_count":0,"completed_count":0,"active":true},{"milestone_id":"M1","title":"Future","total_count":1,"unfinished_count":0,"ready_count":0,"blocked_count":0,"completed_count":1,"active":false}],"features":[{"feature_id":"\(featureID)","title":"Build queue controls","milestone":"\(featureMilestone)","status":"proposed","description":"Controller backlog metadata","specification_path":"/tmp/F001.md","kanban_column":"Backlog","priority":"P2","queue_position":1,"dependencies":[],"dependencies_complete":true,"readiness":"not_ready","blocked_reason":null,"ready_transition_eligible":true,"ready_transition_reason":null,"active_milestone_member":\(featureMilestone == "M0"),"execution_eligible":false,"execution_ineligible_reason":"feature status is proposed; expected ready","execution_profile":{"profile":"bounded_precise","model":"gpt-5.6-terra","reasoning":"high","parent_sessions":1,"child_sessions":0},"execution_model":"gpt-5.6-terra","reasoning":"high","branch":null,"commit":null,"latest_terminal_result":null}]}
    """
}
