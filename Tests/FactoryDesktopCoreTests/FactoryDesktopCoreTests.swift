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
            "backlog",
            "ready",
            "planning",
            "plan_review",
            "approved",
            "building",
            "testing",
            "needs_fixes",
            "ready_for_review",
            "done",
            "blocked",
            "archived"
        ])
        XCTAssertEqual(TaskStatus.storedValue("inbox"), .backlog)
        XCTAssertEqual(TaskStatus.storedValue("approved"), .approved)
        XCTAssertEqual(TaskStatus.storedValue("plan_approved"), .approved)
        XCTAssertEqual(TaskStatus.storedValue("ready_to_commit"), .readyForReview)
        XCTAssertEqual(TaskStatus.storedValue("running"), .building)
    }

    func testTaskStatusIsKanbanReady() {
        XCTAssertEqual(TaskStatus.backlog.sortOrder, 0)
        XCTAssertLessThan(TaskStatus.ready.sortOrder, TaskStatus.testing.sortOrder)
        XCTAssertEqual(TaskStatus.needsFixes.category, .attention)
        XCTAssertEqual(TaskStatus.readyForReview.category, .review)
        XCTAssertEqual(TaskStatus.archived.category, .archive)
    }

    func testAutomaticStatusTransitionHelper() {
        XCTAssertEqual(TaskStatusTransition.status(after: .planGenerated, current: .ready), .planReview)
        XCTAssertEqual(TaskStatusTransition.status(after: .planApproved, current: .planReview), .approved)
        XCTAssertEqual(TaskStatusTransition.status(after: .buildFailed, current: .building), .needsFixes)
        XCTAssertEqual(TaskStatusTransition.status(after: .testsStarted, current: .approved), .testing)
        XCTAssertEqual(TaskStatusTransition.status(after: .testsFailed, current: .testing), .needsFixes)
        XCTAssertEqual(TaskStatusTransition.status(after: .testsFinished, current: .testing, testsPassed: true, diffExists: true), .readyForReview)
        XCTAssertNil(TaskStatusTransition.status(after: .visualQCFinished, current: .readyForReview))
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
            "final_review",
            "preflight",
            "task_state_review"
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
        XCTAssertNoThrow(try runner.validate(CommandRequest(executable: "git", arguments: ["rev-parse", "--short", "HEAD"])))
        XCTAssertNoThrow(try runner.validate(CommandRequest(executable: "git", arguments: ["rev-parse", "--verify", "origin/trunk"])))
        XCTAssertNoThrow(try runner.validate(CommandRequest(executable: "git", arguments: ["rev-list", "--left-right", "--count", "trunk...origin/trunk"])))
        XCTAssertNoThrow(try runner.validate(CommandRequest(executable: "git", arguments: ["merge-base", "--is-ancestor", "abc123", "def456"])))
        XCTAssertNoThrow(try runner.validate(CommandRequest(executable: "npm", arguments: ["run", "lint"])))
        XCTAssertNoThrow(try runner.validate(CommandRequest(executable: "codex", arguments: ["exec", "-C", "/tmp/repo", "-s", "read-only", "-o", "/tmp/review.md", "-"])))
        XCTAssertNoThrow(try runner.validate(CommandRequest(executable: "git", arguments: ["commit", "-m", "safe"], manuallyApproved: true)))
        XCTAssertThrowsError(try runner.validate(CommandRequest(executable: "sudo", arguments: ["true"])))
        XCTAssertThrowsError(try runner.validate(CommandRequest(executable: "git", arguments: ["reset", "--hard"])))
        XCTAssertThrowsError(try runner.validate(CommandRequest(executable: "git", arguments: ["commit", "-m", "needs approval"])))
        XCTAssertThrowsError(try runner.validate(CommandRequest(executable: "git", arguments: ["worktree", "remove", "/tmp/nope"])))
        XCTAssertThrowsError(try runner.validate(CommandRequest(executable: "git", arguments: ["merge-base", "abc123", "def456"])))
        XCTAssertThrowsError(try runner.validate(CommandRequest(executable: "git", arguments: ["checkout", "--", "."])))
        XCTAssertThrowsError(try runner.validate(CommandRequest(executable: "rm", arguments: ["-rf", "/tmp/nope"])))
        XCTAssertThrowsError(try runner.validate(CommandRequest(executable: "codex", arguments: ["exec", "-C", "/tmp/repo", "-s", "workspace-write", "-"])))
        XCTAssertThrowsError(try runner.validate(CommandRequest(executable: "codex", arguments: ["exec", "-C", "/tmp/repo", "-s", "read-only", "--add-dir", "/tmp/other", "-"])))
    }

    func testPreflightPorcelainParserReadsCleanBranch() {
        let summary = PreflightStatusSummary.parsePorcelainV1BranchStatus("## trunk...origin/trunk\n")

        XCTAssertEqual(summary.branch, "trunk")
        XCTAssertEqual(summary.stagedCount, 0)
        XCTAssertEqual(summary.unstagedCount, 0)
        XCTAssertEqual(summary.untrackedCount, 0)
        XCTAssertTrue(summary.isClean)
    }

    func testPreflightPorcelainParserCountsMixedStates() {
        let output = """
        ## feature/demo...origin/feature/demo [ahead 2, behind 1]
        M  staged.swift
         M unstaged.swift
        AM mixed.swift
        ?? new.swift
        """

        let summary = PreflightStatusSummary.parsePorcelainV1BranchStatus(output)

        XCTAssertEqual(summary.branch, "feature/demo")
        XCTAssertEqual(summary.ahead, 2)
        XCTAssertEqual(summary.behind, 1)
        XCTAssertEqual(summary.stagedCount, 2)
        XCTAssertEqual(summary.unstagedCount, 2)
        XCTAssertEqual(summary.untrackedCount, 1)
        XCTAssertFalse(summary.isClean)
    }

    func testPreflightAheadBehindParserReadsRevListCounts() {
        let counts = PreflightStatusSummary.parseAheadBehindCounts("3\t7\n")

        XCTAssertEqual(counts?.ahead, 3)
        XCTAssertEqual(counts?.behind, 7)
        XCTAssertNil(PreflightStatusSummary.parseAheadBehindCounts("not counts"))
    }

    func testPreflightMissingPathReportRecommendsFixMissingPath() {
        let risks: [PreflightRisk] = [.missingPath]
        let report = PreflightTargetReport(
            type: .localWorktree,
            path: "/tmp/missing",
            pathExists: false,
            risks: risks,
            recommendation: PreflightRecommendationMapper.recommendation(for: risks, targetType: .localWorktree, isMerged: nil)
        )

        XCTAssertFalse(report.pathExists)
        XCTAssertEqual(report.risks, [.missingPath])
        XCTAssertEqual(report.recommendation, .fixMissingPath)
    }

    func testPreflightMergedBranchRecommendsArchiveWhenClean() {
        let recommendation = PreflightRecommendationMapper.recommendation(
            for: [],
            targetType: .factoryWorktree,
            isMerged: true
        )

        XCTAssertEqual(recommendation, .archive)
    }

    func testPreflightBranchNotMergedRecommendsMerge() {
        let recommendation = PreflightRecommendationMapper.recommendation(
            for: [.branchNotMerged],
            targetType: .codexWorktree,
            isMerged: false
        )

        XCTAssertEqual(recommendation, .merge)
    }

    func testPlanReviewDecisionParserReadsDecisionLine() {
        XCTAssertEqual(AppStore.parsePlanReviewDecision(from: "Decision: approve\nNo issues."), .approve)
        XCTAssertEqual(AppStore.parsePlanReviewDecision(from: "Decision: revise\nMissing tests."), .revise)
        XCTAssertEqual(AppStore.parsePlanReviewDecision(from: "Decision: reject\nUnsafe."), .reject)
        XCTAssertEqual(AppStore.parsePlanReviewDecision(from: "Decision: escalate_to_codex_build\nUse Codex."), .escalateToCodexBuild)
        XCTAssertEqual(AppStore.parsePlanReviewDecision(from: "Looks fine but no machine-readable decision."), .unknown)
    }

    func testTaskStateRecommendsCreateWorktreeWhenCodingTaskHasNoWorktree() {
        XCTAssertTaskStateRecommendation(.createWorktree, for: TaskStateRecommendationInput(taskType: .coding))
    }

    func testTaskStateRiskyPreflightOverridesPlanning() {
        XCTAssertTaskStateRecommendation(.inspectPreflightFixGitState, for: TaskStateRecommendationInput(
            hasExistingWorktree: true,
            hasPreflight: true,
            hasRiskyPreflight: true,
            hasPlan: true,
            hasPlanReview: true,
            hasApprovedPlan: true,
            hasImplementationChanges: true
        ))
    }

    func testTaskStateRecommendsPreflightWhenWorktreeExistsWithoutPreflight() {
        XCTAssertTaskStateRecommendation(.runPreflight, for: TaskStateRecommendationInput(hasExistingWorktree: true))
    }

    func testTaskStateRecommendsLocalPlanningWhenNoPlanExistsAfterPreflight() {
        XCTAssertTaskStateRecommendation(.planLocally, for: TaskStateRecommendationInput(
            hasExistingWorktree: true,
            hasPreflight: true
        ))
    }

    func testTaskStatePlanExistsWithoutReviewUsesRequiredMessage() {
        let result = TaskStateRecommendationEvaluator.recommend(TaskStateRecommendationInput(
            hasExistingWorktree: true,
            hasPreflight: true,
            hasPlan: true
        ))

        XCTAssertEqual(result.0, .reviewPlanLocally)
        XCTAssertEqual(result.1, "Plan exists but has not been reviewed.")
    }

    func testTaskStateReviewReviseRecommendsRevisePlan() {
        XCTAssertTaskStateRecommendation(.revisePlan, for: TaskStateRecommendationInput(
            hasExistingWorktree: true,
            hasPreflight: true,
            hasPlan: true,
            hasPlanReview: true,
            latestPlanDecision: .revise
        ))
    }

    func testTaskStateReviewRejectRecommendsInvestigate() {
        XCTAssertTaskStateRecommendation(.investigate, for: TaskStateRecommendationInput(
            hasExistingWorktree: true,
            hasPreflight: true,
            hasPlan: true,
            hasPlanReview: true,
            latestPlanDecision: .reject
        ))
    }

    func testTaskStateApprovedReviewWithoutApprovedPlanRecommendsApprovePlan() {
        XCTAssertTaskStateRecommendation(.approvePlan, for: TaskStateRecommendationInput(
            hasExistingWorktree: true,
            hasPreflight: true,
            hasPlan: true,
            hasPlanReview: true,
            latestPlanDecision: .approve
        ))
    }

    func testTaskStateApprovedPlanWithoutChangesRecommendsBuildLocally() {
        XCTAssertTaskStateRecommendation(.buildLocally, for: TaskStateRecommendationInput(
            hasExistingWorktree: true,
            hasPreflight: true,
            hasPlan: true,
            hasPlanReview: true,
            latestPlanDecision: .approve,
            hasApprovedPlan: true
        ))
    }

    func testTaskStateChangesWithoutTestsRecommendsRunTests() {
        XCTAssertTaskStateRecommendation(.runTests, for: TaskStateRecommendationInput(
            hasExistingWorktree: true,
            hasPreflight: true,
            hasPlan: true,
            hasPlanReview: true,
            latestPlanDecision: .approve,
            hasApprovedPlan: true,
            hasImplementationChanges: true
        ))
    }

    func testTaskStateDirtyActiveWorktreeWithoutTestsRecommendsRunTests() {
        XCTAssertTaskStateRecommendation(.runTests, for: TaskStateRecommendationInput(
            hasExistingWorktree: true,
            hasPreflight: true,
            hasPlan: true,
            hasPlanReview: true,
            latestPlanDecision: .revise,
            hasApprovedPlan: true,
            hasImplementationChanges: true
        ))
    }

    func testTaskStateTestsWithoutDiffReviewRecommendsReviewDiff() {
        XCTAssertTaskStateRecommendation(.reviewDiff, for: TaskStateRecommendationInput(
            hasExistingWorktree: true,
            hasPreflight: true,
            hasPlan: true,
            hasPlanReview: true,
            latestPlanDecision: .approve,
            hasApprovedPlan: true,
            hasImplementationChanges: true,
            hasTestOutput: true
        ))
    }

    func testTaskStateDirtyActiveWorktreeWithTestsRecommendsReviewDiff() {
        XCTAssertTaskStateRecommendation(.reviewDiff, for: TaskStateRecommendationInput(
            hasExistingWorktree: true,
            hasPreflight: true,
            hasPlan: true,
            hasPlanReview: true,
            latestPlanDecision: .revise,
            hasApprovedPlan: true,
            hasImplementationChanges: true,
            hasTestOutput: true
        ))
    }

    func testTaskStateDirtyCanonicalRepoRecommendsInspectPreflightFixGitState() {
        XCTAssertTaskStateRecommendation(.inspectPreflightFixGitState, for: TaskStateRecommendationInput(
            hasExistingWorktree: true,
            hasRiskyPreflight: true,
            hasPlan: true,
            hasPlanReview: true,
            hasApprovedPlan: true,
            hasImplementationChanges: true,
            hasTestOutput: true
        ))
    }

    func testTaskStateApprovedPlanSupersedesOlderReviseReview() {
        XCTAssertTaskStateRecommendation(.buildLocally, for: TaskStateRecommendationInput(
            hasExistingWorktree: true,
            hasPreflight: true,
            hasPlan: true,
            hasPlanReview: true,
            latestPlanDecision: .revise,
            hasApprovedPlan: true
        ))
    }

    func testTaskStateStalePreflightDoesNotOverrideNewerImplementationAndTests() {
        XCTAssertTaskStateRecommendation(.reviewDiff, for: TaskStateRecommendationInput(
            hasExistingWorktree: true,
            hasPreflight: true,
            hasStalePreflight: true,
            hasPlan: true,
            hasPlanReview: true,
            hasApprovedPlan: true,
            hasImplementationChanges: true,
            hasTestOutput: true
        ))
    }

    func testTaskStateStalePreflightWithoutNewerWorkRecommendsRunPreflight() {
        XCTAssertTaskStateRecommendation(.runPreflight, for: TaskStateRecommendationInput(
            hasExistingWorktree: true,
            hasPreflight: true,
            hasStalePreflight: true,
            hasPlan: true,
            hasPlanReview: true,
            hasApprovedPlan: true
        ))
    }

    func testTaskStateCodexDiffReviewHandoffDoesNotCountAsDiffReview() {
        XCTAssertTaskStateRecommendation(.reviewDiff, for: TaskStateRecommendationInput(
            hasExistingWorktree: true,
            hasPreflight: true,
            hasPlan: true,
            hasPlanReview: true,
            latestPlanDecision: .approve,
            hasApprovedPlan: true,
            hasImplementationChanges: true,
            hasTestOutput: true,
            hasDiffReview: false
        ))
    }

    func testTaskStateDiffReviewWithChangesRecommendsCommitAndMerge() {
        XCTAssertTaskStateRecommendation(.commitAndMerge, for: TaskStateRecommendationInput(
            hasExistingWorktree: true,
            hasPreflight: true,
            hasPlan: true,
            hasPlanReview: true,
            latestPlanDecision: .approve,
            hasApprovedPlan: true,
            hasImplementationChanges: true,
            hasTestOutput: true,
            hasPassingTestOutput: true,
            hasDiffReview: true
        ))
    }

    func testTaskStatePrimaryActionDisplayUsesTaskWorktreeLanguage() {
        XCTAssertEqual(TaskStateRecommendedAction.createWorktree.displayName, "Create Task Worktree")
        XCTAssertEqual(TaskStateRecommendedAction.commitAndMerge.displayName, "Ready to Commit")
    }

    func testArtifactGroupingPromotesApprovedPlanAndCurrentArtifacts() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let artifacts = [
            Artifact(id: "plan", taskId: "task", type: .plan, path: "/tmp/plan.md", createdAt: base),
            Artifact(id: "approved", taskId: "task", type: .approvedPlan, path: "/tmp/approved-plan.md", createdAt: base.addingTimeInterval(10)),
            Artifact(id: "review", taskId: "task", type: .localPlanReview, path: "/tmp/local-plan-review.md", createdAt: base.addingTimeInterval(20)),
            Artifact(id: "preflight", taskId: "task", type: .preflight, path: "/tmp/preflight.md", createdAt: base.addingTimeInterval(30)),
            Artifact(id: "prompt", taskId: "task", type: .plannerPrompt, path: "/tmp/planner-prompt.md", createdAt: base.addingTimeInterval(40))
        ]

        let groups = ArtifactGrouping.group(artifacts)

        XCTAssertTrue(groups.current.contains { $0.id == "approved" })
        XCTAssertTrue(groups.current.contains { $0.id == "preflight" })
        XCTAssertFalse(groups.current.contains { $0.id == "plan" })
        XCTAssertTrue(groups.history.contains { $0.id == "plan" })
        XCTAssertTrue(groups.history.contains { $0.id == "review" })
        XCTAssertTrue(groups.rawLogs.contains { $0.id == "prompt" })
    }

    func testArtifactGroupingKeepsCodexDiffHandoffWithRawPrompts() {
        let handoff = Artifact(id: "handoff", taskId: "task", type: .codexDiffReviewHandoff, path: "/tmp/codex-diff-review-handoff.md")

        let groups = ArtifactGrouping.group([handoff])

        XCTAssertTrue(groups.rawLogs.contains { $0.id == "handoff" })
        XCTAssertFalse(groups.current.contains { $0.id == "handoff" })
    }

    func testTaskWorktreeDisplayMapsSingleWorktreeToTaskWorktree() {
        let task = FactoryTask(
            projectId: "project",
            title: "Task",
            localBranch: "local/task",
            localWorktreePath: "/tmp/task"
        )

        let displays = TaskWorktreeDisplayMapper.displays(for: task)

        XCTAssertEqual(displays.count, 1)
        XCTAssertEqual(displays.first?.label, "Task Worktree")
        XCTAssertEqual(displays.first?.executionMode, "Local")
    }

    func testTaskWorktreeDisplayMapsSecondWorktreeToAlternateWorktree() {
        let task = FactoryTask(
            projectId: "project",
            title: "Task",
            localBranch: "local/task",
            codexBranch: "codex/task",
            localWorktreePath: "/tmp/task",
            codexWorktreePath: "/tmp/task-alt"
        )

        let displays = TaskWorktreeDisplayMapper.displays(for: task)

        XCTAssertEqual(displays.map(\.label), ["Primary Task Worktree", "Alternate Worktree"])
    }

    func testWorkflowHealthSummarizesTaskStateReview() {
        let review = TaskStateReview(
            projectId: "project",
            taskId: "task",
            status: .readyForReview,
            summary: "Tests were run; diff review is still needed.",
            latestArtifacts: [],
            worktreeSummaries: [],
            latestPlanDecision: nil,
            hasPlan: true,
            hasPlanReview: true,
            hasApprovedPlan: true,
            hasPreflight: true,
            hasRiskyPreflight: false,
            hasImplementationChanges: true,
            hasTestOutput: true,
            hasPassingTestOutput: true,
            hasDiffReview: false,
            blockingIssues: [],
            recommendedAction: .reviewDiff
        )
        let task = FactoryTask(projectId: "project", title: "Task", localWorktreePath: "/tmp/task")

        let health = TaskWorkflowHealthBuilder.build(task: task, review: review, artifacts: [], gitSnapshot: GitSnapshot())

        XCTAssertEqual(health.worktree, "dirty")
        XCTAssertEqual(health.plan, "approved")
        XCTAssertEqual(health.tests, "passed")
        XCTAssertEqual(health.diffReview, "missing")
        XCTAssertEqual(health.nextAction, "Review Diff")
    }

    func testWorkflowCheckSummariesExposeHonestFoundationStates() {
        let project = Project(id: "project", name: "Demo", type: .codeRepo, path: "/tmp/demo", testCommands: ["swift test"])
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let run = RunRecord(
            id: "run-1",
            taskId: "task",
            executor: "command",
            status: .failed,
            outputPath: "/tmp/test-output.txt",
            summary: "Failed: swift test",
            startedAt: started,
            endedAt: started.addingTimeInterval(12)
        )
        let artifact = Artifact(id: "test-artifact", taskId: "task", runId: "run-1", type: .testOutput, path: "/tmp/test-output.txt")

        let summaries = WorkflowCheckSummariesBuilder.build(project: project, runs: [run], artifacts: [artifact])

        XCTAssertEqual(summaries.first { $0.kind == .unitTests }?.status, .failed)
        XCTAssertEqual(summaries.first { $0.kind == .e2eTests }?.status, .notConfigured)
        XCTAssertEqual(summaries.first { $0.kind == .visualQC }?.status, .notConfigured)
    }

    func testTaskStateMissingWorktreeSummaryDoesNotCrash() {
        let summary = TaskWorktreeSummary(label: "Local worktree", path: "/tmp/missing", exists: false)

        XCTAssertFalse(summary.exists)
        XCTAssertFalse(summary.hasImplementationChanges)
    }

    func testTaskStateMissingArtifactSummaryDoesNotCrash() {
        let summary = TaskArtifactSummary(type: .plan, path: "/tmp/missing-plan.md", exists: false, createdAt: Date())

        XCTAssertFalse(summary.exists)
        XCTAssertEqual(summary.type, .plan)
    }

    func testTaskStateReviewUsesTaskStatus() {
        let review = TaskStateReview(
            projectId: "project",
            taskId: "task",
            status: .planReview,
            summary: "summary",
            latestArtifacts: [],
            worktreeSummaries: [],
            latestPlanDecision: nil,
            hasPlan: false,
            hasPlanReview: false,
            hasApprovedPlan: false,
            hasPreflight: false,
            hasRiskyPreflight: false,
            hasImplementationChanges: false,
            hasTestOutput: false,
            hasDiffReview: false,
            blockingIssues: [],
            recommendedAction: .planLocally
        )

        XCTAssertEqual(review.status, .planReview)
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
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('projects', 'tasks', 'runs', 'artifacts', 'task_events', 'schema_migrations');"
        )
        XCTAssertEqual(Set(rows.compactMap { $0["name"] ?? nil }), Set(["projects", "tasks", "runs", "artifacts", "task_events", "schema_migrations"]))
    }

    func testRepositoryPersistsManualStatusChangeEvent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("factory-desktop-tests-\(UUID().uuidString)", isDirectory: true)
        let paths = FactoryPaths(root: root)
        try paths.ensureBaseDirectories()
        let database = try SQLiteDatabase(url: paths.database)
        try MigrationRunner(database: database, paths: paths).migrate()
        let repository = FactoryRepository(database: database)
        let project = Project(id: "project", name: "Demo", type: .codeRepo, path: "/tmp/demo")
        var task = FactoryTask(id: "task", projectId: project.id, title: "Manual status")

        try repository.upsert(project: project)
        try repository.upsert(task: task)
        let previousStatus = task.status
        task.status = .readyForReview
        try repository.upsert(task: task)
        try repository.insert(taskEvent: TaskEvent(
            taskId: task.id,
            kind: .statusChangedManually,
            source: .manual,
            message: "Manual status changed to Ready for Review.",
            previousStatus: previousStatus,
            newStatus: task.status
        ))

        XCTAssertEqual(try repository.tasks(projectId: project.id).first?.status, .readyForReview)
        let events = try repository.taskEvents(taskId: task.id)
        XCTAssertEqual(events.first?.kind, .statusChangedManually)
        XCTAssertEqual(events.first?.previousStatus, .backlog)
        XCTAssertEqual(events.first?.newStatus, .readyForReview)
    }

    private func XCTAssertTaskStateRecommendation(
        _ expected: TaskStateRecommendedAction,
        for input: TaskStateRecommendationInput,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(TaskStateRecommendationEvaluator.recommend(input).0, expected, file: file, line: line)
    }
}
