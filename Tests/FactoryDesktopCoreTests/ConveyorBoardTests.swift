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
            return ConveyorCommandResult(exitCode: 0, standardOutput: fixtureQueue(project: project), standardError: "")
        }
        return ConveyorCommandResult(exitCode: 0, standardOutput: """
        {"classification":"ok","feature_id":"F001","changed_paths":["docs/FEATURE_QUEUE.yaml"],"model_sessions_launched":0,"child_sessions_launched":0}
        """, standardError: "")
    }

    func recordedArguments() -> [[String]] { arguments }
}

private func fixtureFeature(id: String, column: ConveyorColumn) -> ConveyorFeature {
    try! JSONDecoder().decode(ConveyorFeature.self, from: Data("""
    {"feature_id":"\(id)","title":"Fixture \(id)","status":"proposed","description":"","specification_path":null,"kanban_column":"\(column.rawValue)","priority":"P2","queue_position":2,"dependencies":[],"dependencies_complete":true,"readiness":"not_ready","blocked_reason":null,"ready_transition_eligible":true,"ready_transition_reason":null,"execution_profile":{"profile":"bounded_precise","model":"gpt-5.6-terra","reasoning":"high","parent_sessions":1,"child_sessions":0},"execution_model":"gpt-5.6-terra","reasoning":"high","branch":null,"commit":null,"latest_terminal_result":null}
    """.utf8))
}

private func fixtureQueue(project: String) -> String {
    """
    {"project_id":"\(project)","active_milestone":"M1","paused":false,"active_feature":null,"selected_feature":null,"next_ready_feature":null,"features":[{"feature_id":"F001","title":"Build queue controls","status":"proposed","description":"Controller backlog metadata","specification_path":"/tmp/F001.md","kanban_column":"Backlog","priority":"P2","queue_position":1,"dependencies":[],"dependencies_complete":true,"readiness":"not_ready","blocked_reason":null,"ready_transition_eligible":true,"ready_transition_reason":null,"execution_profile":{"profile":"bounded_precise","model":"gpt-5.6-terra","reasoning":"high","parent_sessions":1,"child_sessions":0},"execution_model":"gpt-5.6-terra","reasoning":"high","branch":null,"commit":null,"latest_terminal_result":null}]}
    """
}
