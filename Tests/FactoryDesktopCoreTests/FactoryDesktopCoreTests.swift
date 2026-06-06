import XCTest
@testable import FactoryDesktopCore

final class FactoryDesktopCoreTests: XCTestCase {
    func testSlugIsStableAndBranchSafe() {
        XCTAssertEqual(Slug.make("Improve source controls UI"), "improve-source-controls-ui")
        XCTAssertEqual(Slug.make("   ***   "), "task")
        XCTAssertLessThanOrEqual(Slug.make(String(repeating: "a", count: 80), maxLength: 36).count, 36)
    }

    func testModelPolicyCapsRiskyContexts() {
        XCTAssertEqual(ModelPolicy.effectiveContext(for: "qwen3.5:4b", requested: 256_000), 64_000)
        XCTAssertEqual(ModelPolicy.effectiveContext(for: "granite4.1:3b", requested: 128_000), 64_000)
        XCTAssertEqual(ModelPolicy.effectiveContext(for: "qwen3.5:9b", requested: 256_000), 128_000)
        XCTAssertEqual(ModelPolicy.effectiveContext(for: "qwen2.5-coder:7b", requested: 128_000), 128_000)
    }

    func testWorkflowStagesMatchStagedReviewVocabulary() {
        XCTAssertEqual(TaskStatus.allCases.map(\.rawValue), [
            "inbox",
            "planning",
            "plan_ready",
            "plan_review",
            "plan_approved",
            "plan_rejected",
            "escalation_recommended",
            "building",
            "built",
            "testing",
            "needs_review",
            "ready_to_commit",
            "done",
            "blocked"
        ])
        XCTAssertEqual(TaskStatus.storedValue("approved"), .planApproved)
        XCTAssertEqual(TaskStatus.storedValue("running"), .building)
    }

    func testArtifactTypesMatchStagedReviewVocabulary() {
        XCTAssertEqual(ArtifactType.allCases.map(\.rawValue), [
            "planner_prompt",
            "plan",
            "local_plan_review",
            "codex_plan_review_handoff",
            "codex_plan_review",
            "approved_plan",
            "implementation_log",
            "test_output",
            "local_diff_review",
            "codex_diff_review_handoff",
            "final_review"
        ])
    }

    func testRunDirectoryUsesFullTaskID() {
        let paths = FactoryPaths(root: URL(fileURLWithPath: "/tmp/factory-test-root"))
        let project = Project(id: "project-1", name: "Demo Project", type: .codeRepo, path: "/tmp/demo")
        let task = FactoryTask(id: "12345678-90AB-CDEF-1234-567890ABCDEF", projectId: project.id, title: "Task")

        XCTAssertEqual(
            paths.runDirectory(project: project, task: task).path,
            "/tmp/factory-test-root/runs/demo-project/12345678-90AB-CDEF-1234-567890ABCDEF"
        )
    }

    func testCommandRunnerBlocksDestructiveCommands() {
        let runner = CommandRunner()
        XCTAssertNoThrow(try runner.validate(CommandRequest(executable: "git", arguments: ["status", "--short"])))
        XCTAssertNoThrow(try runner.validate(CommandRequest(executable: "npm", arguments: ["run", "lint"])))
        XCTAssertNoThrow(try runner.validate(CommandRequest(executable: "codex", arguments: ["exec", "-C", "/tmp/repo", "-s", "read-only", "-o", "/tmp/review.md", "-"])))
        XCTAssertNoThrow(try runner.validate(CommandRequest(executable: "git", arguments: ["commit", "-m", "safe"], manuallyApproved: true)))
        XCTAssertThrowsError(try runner.validate(CommandRequest(executable: "sudo", arguments: ["true"])))
        XCTAssertThrowsError(try runner.validate(CommandRequest(executable: "git", arguments: ["reset", "--hard"])))
        XCTAssertThrowsError(try runner.validate(CommandRequest(executable: "git", arguments: ["commit", "-m", "needs approval"])))
        XCTAssertThrowsError(try runner.validate(CommandRequest(executable: "git", arguments: ["worktree", "remove", "/tmp/nope"])))
        XCTAssertThrowsError(try runner.validate(CommandRequest(executable: "git", arguments: ["checkout", "--", "."])))
        XCTAssertThrowsError(try runner.validate(CommandRequest(executable: "rm", arguments: ["-rf", "/tmp/nope"])))
        XCTAssertThrowsError(try runner.validate(CommandRequest(executable: "codex", arguments: ["exec", "-C", "/tmp/repo", "-s", "workspace-write", "-"])))
        XCTAssertThrowsError(try runner.validate(CommandRequest(executable: "codex", arguments: ["exec", "-C", "/tmp/repo", "-s", "read-only", "--add-dir", "/tmp/other", "-"])))
    }

    func testPlanReviewDecisionParserReadsDecisionLine() {
        XCTAssertEqual(AppStore.parsePlanReviewDecision(from: "Decision: approve\nNo issues."), .approve)
        XCTAssertEqual(AppStore.parsePlanReviewDecision(from: "Decision: revise\nMissing tests."), .revise)
        XCTAssertEqual(AppStore.parsePlanReviewDecision(from: "Decision: reject\nUnsafe."), .reject)
        XCTAssertEqual(AppStore.parsePlanReviewDecision(from: "Decision: escalate_to_codex_build\nUse Codex."), .escalateToCodexBuild)
        XCTAssertEqual(AppStore.parsePlanReviewDecision(from: "Looks fine but no machine-readable decision."), .unknown)
    }

    func testBuildInfoRepoStateParsing() {
        XCTAssertEqual(BuildInfoService.repoState(fromPorcelainOutput: ""), .clean)
        XCTAssertEqual(BuildInfoService.repoState(fromPorcelainOutput: "\n"), .clean)
        XCTAssertEqual(BuildInfoService.repoState(fromPorcelainOutput: " M Sources/App.swift\n"), .dirty)
        XCTAssertEqual(BuildInfoService.repoState(fromPorcelainOutput: "?? Sources/New.swift\n"), .dirty)
        XCTAssertEqual(BuildInfoService.repoState(fromPorcelainOutput: nil), .unknown)
    }

    func testBuildInfoNormalizesEmptyGitValuesToUnknown() {
        XCTAssertEqual(BuildInfoService.normalizedGitValue("main\n"), "main")
        XCTAssertEqual(BuildInfoService.normalizedGitValue("   \n"), "unknown")
        XCTAssertEqual(BuildInfoService.normalizedGitValue(nil), "unknown")
    }

    func testBuildInfoCompactsWorktreeBranchForSidebar() {
        XCTAssertEqual(BuildInfo.compactBranchName("main"), "main")
        XCTAssertEqual(BuildInfo.compactBranchName("codex/88CE8956-add-visible-build-and-run-identity"), "codex/88CE8956")
        XCTAssertEqual(BuildInfo.compactBranchName("local/ABC123-task-title"), "local/ABC123")
    }

    func testBuildInfoFallbackDoesNotDependOnRealGitRepo() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let missingRepo = FileManager.default.temporaryDirectory
            .appendingPathComponent("factory-desktop-missing-repo-\(UUID().uuidString)", isDirectory: true)
        let info = BuildInfoService.current(sourceRoot: missingRepo, launchTimestamp: timestamp)

        XCTAssertEqual(info.branch, "unknown")
        XCTAssertEqual(info.shortSHA, "unknown")
        XCTAssertEqual(info.repoState, .unknown)
        XCTAssertEqual(info.repoPath, missingRepo.path)
        XCTAssertEqual(info.launchTimestamp, timestamp)
        XCTAssertFalse(info.appVersion.isEmpty)
    }

    func testMigrationCreatesInitialTables() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("factory-desktop-tests-\(UUID().uuidString)", isDirectory: true)
        let paths = FactoryPaths(root: root)
        try paths.ensureBaseDirectories()
        let database = try SQLiteDatabase(url: paths.database)
        try MigrationRunner(database: database, paths: paths).migrate()

        let rows = try database.query(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('projects', 'tasks', 'runs', 'artifacts', 'schema_migrations');"
        )
        XCTAssertEqual(Set(rows.compactMap { $0["name"] ?? nil }), Set(["projects", "tasks", "runs", "artifacts", "schema_migrations"]))
    }
}
