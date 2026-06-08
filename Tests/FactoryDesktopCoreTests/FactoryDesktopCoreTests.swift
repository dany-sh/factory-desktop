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
        XCTAssertNoThrow(try runner.validate(CommandRequest(executable: "git", arguments: ["branch", "--format=%(refname:short)|%(objectname:short)"])))
        XCTAssertNoThrow(try runner.validate(CommandRequest(executable: "git", arguments: ["branch", "--merged", "main", "--no-color"])))
        XCTAssertNoThrow(try runner.validate(CommandRequest(executable: "git", arguments: ["worktree", "list", "--porcelain"])))
        XCTAssertNoThrow(try runner.validate(CommandRequest(executable: "git", arguments: ["worktree", "prune", "--dry-run"])))
        XCTAssertNoThrow(try runner.validate(CommandRequest(executable: "npm", arguments: ["run", "lint"])))
        XCTAssertNoThrow(try runner.validate(CommandRequest(executable: "codex", arguments: ["exec", "-C", "/tmp/repo", "-s", "read-only", "-o", "/tmp/review.md", "-"])))
        XCTAssertNoThrow(try runner.validate(CommandRequest(executable: "git", arguments: ["commit", "-m", "safe"], manuallyApproved: true)))
        XCTAssertThrowsError(try runner.validate(CommandRequest(executable: "sudo", arguments: ["true"])))
        XCTAssertThrowsError(try runner.validate(CommandRequest(executable: "git", arguments: ["reset", "--hard"])))
        XCTAssertThrowsError(try runner.validate(CommandRequest(executable: "git", arguments: ["commit", "-m", "needs approval"])))
        XCTAssertThrowsError(try runner.validate(CommandRequest(executable: "git", arguments: ["worktree", "remove", "/tmp/nope"])))
        XCTAssertThrowsError(try runner.validate(CommandRequest(executable: "git", arguments: ["worktree", "prune"])))
        XCTAssertThrowsError(try runner.validate(CommandRequest(executable: "git", arguments: ["merge-base", "abc123", "def456"])))
        XCTAssertThrowsError(try runner.validate(CommandRequest(executable: "git", arguments: ["checkout", "--", "."])))
        XCTAssertThrowsError(try runner.validate(CommandRequest(executable: "rm", arguments: ["-rf", "/tmp/nope"])))
        XCTAssertThrowsError(try runner.validate(CommandRequest(executable: "codex", arguments: ["exec", "-C", "/tmp/repo", "-s", "workspace-write", "-"])))
        XCTAssertThrowsError(try runner.validate(CommandRequest(executable: "codex", arguments: ["exec", "-C", "/tmp/repo", "-s", "read-only", "--add-dir", "/tmp/other", "-"])))
    }

    func testLifecycleParsersReadBranchesAndWorktrees() {
        let worktrees = LifecycleParser.parseWorktreePorcelain(
            """
            worktree /repo
            HEAD abc123
            branch refs/heads/main

            worktree /repo/.factory/worktrees/task
            HEAD def456
            branch refs/heads/codex/task
            """,
            prunablePaths: ["/repo/.factory/worktrees/task"]
        )
        let branches = LifecycleParser.parseBranchFormat("main|abc123\ncodex/task|def456\n")
        let merged = LifecycleParser.parseMergedBranches("* main\n  codex/task\n")

        XCTAssertEqual(worktrees.count, 2)
        XCTAssertEqual(worktrees.last?.branch, "codex/task")
        XCTAssertTrue(worktrees.last?.isPrunable == true)
        XCTAssertEqual(branches.map(\.name), ["main", "codex/task"])
        XCTAssertEqual(merged, Set(["main", "codex/task"]))
    }

    func testMergeSafetyHelperMarksDuplicateEquivalentBeforeMerge() {
        XCTAssertEqual(MergeSafetyHelper.assess(cherryPickLog: "", diffStat: "", defaultIsAncestorOfBranch: true), .duplicateEquivalent)
        XCTAssertEqual(MergeSafetyHelper.assess(cherryPickLog: "> abc work", diffStat: "Sources/App.swift | 2 +", defaultIsAncestorOfBranch: true), .fastForwardPossible)
        XCTAssertEqual(MergeSafetyHelper.assess(cherryPickLog: "> abc work", diffStat: "Sources/App.swift | 2 +", defaultIsAncestorOfBranch: false), .manualReviewRequired)
    }

    func testLifecycleGateBlocksDirtyCanonicalRepoAndGitEnvironmentOverrides() {
        let project = Project(id: "project", name: "Demo", type: .codeRepo, path: "/tmp/demo", defaultBranch: "main")
        let gate = LifecycleClassifier.gate(
            project: project,
            selectedTask: nil,
            currentBranch: "feature",
            workingTreeClean: false,
            defaultAheadOfOrigin: 1,
            worktrees: [GitWorktreeRecord(path: "/tmp/other", branch: "main", isClean: true)],
            branches: [],
            staleMetadata: ["/tmp/stale"],
            runnerEnvironment: RunnerGitEnvironment(environment: ["GIT_DIR": "/tmp/git-dir"])
        )

        XCTAssertEqual(gate.level, .red)
        XCTAssertTrue(gate.checks.contains { $0.id == "canonical-dirty" })
        XCTAssertTrue(gate.checks.contains { $0.id == "runner-git-env" })
        XCTAssertTrue(gate.checks.contains { $0.id == "stale-metadata" })
    }

    func testLifecycleClassifierProtectsBackupAndDuplicateBranches() {
        let backup = GitBranchRecord(name: "backup/main-before-cleanup", isBackupProtected: true)
        let duplicate = GitBranchRecord(name: "codex/demo", isDuplicateEquivalent: true, isActiveFactoryBranch: true)

        let backupItem = LifecycleClassifier.classifyBranch(backup, defaultBranch: "main", checkedOutBranches: [])
        let duplicateItem = LifecycleClassifier.classifyBranch(duplicate, defaultBranch: "main", checkedOutBranches: [])

        XCTAssertEqual(backupItem.classification, .backupProtected)
        XCTAssertTrue(backupItem.blockedActions.contains { $0.action == .deleteMergedBranch })
        XCTAssertEqual(duplicateItem.classification, .duplicateEquivalent)
        XCTAssertEqual(duplicateItem.recommendation, .deleteDuplicateBranch)
    }

    func testLifecycleClassifierMarksStoredMissingWorktreeReference() {
        let task = FactoryTask(id: "task", projectId: "project", title: "Task", localBranch: "factory/task", localWorktreePath: "/tmp/missing")
        let display = TaskWorktreeDisplay(
            id: "local",
            label: "Task Worktree",
            branch: "factory/task",
            path: "/tmp/missing",
            executionMode: "Local",
            state: .missingPath
        )

        let item = LifecycleClassifier.classifyStoredTaskWorktreeReference(task: task, display: display)

        XCTAssertEqual(item.classification, .missingPath)
        XCTAssertEqual(item.state, .blocked)
        XCTAssertTrue(item.blockedActions.contains { $0.action == .inspectDiff })
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
        XCTAssertEqual(TaskStateRecommendedAction.noActionRequired.displayName, "No Action Required")
    }

    func testArchivedTaskHasNoActiveNextAction() {
        let archived = TaskStateRecommendationEvaluator.recommend(TaskStateRecommendationInput(
            status: .archived,
            hasRiskyPreflight: true,
            hasImplementationChanges: true
        ))
        let done = TaskStateRecommendationEvaluator.recommend(TaskStateRecommendationInput(
            status: .done,
            hasImplementationChanges: true,
            hasTestOutput: true
        ))

        XCTAssertEqual(archived.0, .noActionRequired)
        XCTAssertEqual(archived.1, "Task is archived.")
        XCTAssertEqual(done.0, .noActionRequired)
    }

    func testWorkflowHealthUsesPassiveNextActionForArchivedTaskWithoutReview() {
        let task = FactoryTask(projectId: "project", title: "Archived", status: .archived)

        let health = TaskWorkflowHealthBuilder.build(task: task, review: nil, artifacts: [], gitSnapshot: GitSnapshot())

        XCTAssertEqual(health.nextAction, "Archived")
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

    func testArtifactWasteFoundationClassifiesTrackedOldAndActiveArtifacts() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("factory-artifact-waste-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let oldURL = root.appendingPathComponent("old.log")
        try "old".write(to: oldURL, atomically: true, encoding: .utf8)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let project = Project(id: "project", name: "Demo", type: .codeRepo, path: root.path)
        let activeTask = FactoryTask(id: "active-task", projectId: project.id, title: "Active")
        let oldArtifact = Artifact(id: "old", taskId: "done-task", type: .implementationLog, path: oldURL.path, createdAt: now.addingTimeInterval(-40 * 24 * 60 * 60))
        let activeArtifact = Artifact(id: "active", taskId: activeTask.id, type: .plan, path: oldURL.path, createdAt: now)

        let waste = LifecycleClassifier.artifactWasteItems(
            project: project,
            tasks: [activeTask],
            runs: [],
            artifacts: [oldArtifact, activeArtifact],
            now: now
        )

        XCTAssertEqual(waste.first { $0.id == "old" }?.classification, .safeToArchive)
        XCTAssertEqual(waste.first { $0.id == "active" }?.classification, .active)
        XCTAssertEqual(waste.first { $0.id == "old" }?.sizeBytes, 3)
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

    func testTaskWorktreeDisplayClassifiesExistingPathAsHealthy() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("factory-existing-worktree-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let task = FactoryTask(projectId: "project", title: "Task", localBranch: "factory/task", localWorktreePath: root.path)

        let display = try XCTUnwrap(TaskWorktreeDisplayMapper.displays(for: task).first)

        XCTAssertEqual(display.state, .healthy)
        XCTAssertTrue(display.canOpen)
        XCTAssertEqual(display.recommendedAction, "Continue work")
    }

    func testTaskWorktreeDisplayClassifiesMissingPathAsMissingPathAndDisablesOpen() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("factory-missing-worktree-\(UUID().uuidString)", isDirectory: true)
        let task = FactoryTask(projectId: "project", title: "Task", localBranch: "factory/task", localWorktreePath: missing.path)

        let display = try XCTUnwrap(TaskWorktreeDisplayMapper.displays(for: task).first)

        XCTAssertEqual(display.state, .missingPath)
        XCTAssertFalse(display.canOpen)
        XCTAssertEqual(display.recommendedAction, "Remove stale reference or relink/recreate the worktree")
    }

    func testClearedWorktreeReferenceIsMarkedRemovedCleaned() throws {
        let fixture = try makeRepositoryFixture()
        let project = Project(id: "project", name: "Demo", type: .codeRepo, path: fixture.root.path)
        var task = FactoryTask(
            id: "task",
            projectId: "project",
            title: "Task",
            localBranch: "factory/task",
            localWorktreePath: "/tmp/deleted-worktree"
        )
        try fixture.repository.upsert(project: project)
        try fixture.repository.upsert(task: task)
        task.localWorktreePath = nil
        try fixture.repository.upsert(task: task)

        let stored = try XCTUnwrap(fixture.repository.tasks().first { $0.id == "task" })
        let display = try XCTUnwrap(TaskWorktreeDisplayMapper.displays(for: stored).first)

        XCTAssertEqual(display.state, .removedCleaned)
        XCTAssertFalse(display.canOpen)
        XCTAssertEqual(display.recommendedAction, "No action required after cleanup")
    }

    func testCleanupHelperMarksLinkedTaskWorktreeReferenceCleaned() {
        var task = FactoryTask(
            projectId: "project",
            title: "Task",
            localBranch: "factory/task",
            codexBranch: "codex/task",
            localWorktreePath: "/tmp/local-worktree",
            codexWorktreePath: "/tmp/codex-worktree"
        )

        XCTAssertTrue(task.markWorktreeReferenceCleaned(path: "/tmp/local-worktree"))

        XCTAssertNil(task.localWorktreePath)
        XCTAssertEqual(task.localBranch, "factory/task")
        XCTAssertEqual(task.codexWorktreePath, "/tmp/codex-worktree")
    }

    func testRepairActionMetadataExistsForMissingWorktrees() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("factory-missing-worktree-\(UUID().uuidString)", isDirectory: true)
        let task = FactoryTask(projectId: "project", title: "Task", localBranch: "factory/task", localWorktreePath: missing.path)

        let display = try XCTUnwrap(TaskWorktreeDisplayMapper.displays(for: task).first)

        XCTAssertEqual(display.repairActions, WorktreeRepairAction.p0Actions)
        XCTAssertTrue(display.repairActions.contains(.refreshLifecycleScan))
        XCTAssertTrue(display.repairActions.contains(.removeStaleWorktreeReference))
        XCTAssertTrue(display.repairActions.contains(.markWorktreeCleaned))
        XCTAssertTrue(display.repairActions.contains(.recreateWorktreeFromBranch))
        XCTAssertTrue(display.repairActions.contains(.relinkExistingWorktree))
        XCTAssertTrue(display.repairActions.contains(.archiveTask))
    }

    func testArchiveActionHiddenForArchivedTaskRecoveryActions() {
        let actions = WorktreeRepairAction.visibleActions(for: .removedCleaned, taskStatus: .archived)

        XCTAssertFalse(actions.contains(.archiveTask))
        XCTAssertTrue(actions.contains(.refreshLifecycleScan))
    }

    func testRemovedCleanedWorktreeRecoveryActionsArePassiveByDefault() {
        let actions = WorktreeRepairAction.visibleActions(for: .removedCleaned, taskStatus: .approved)

        XCTAssertFalse(actions.contains(.removeStaleWorktreeReference))
        XCTAssertFalse(actions.contains(.markWorktreeCleaned))
        XCTAssertTrue(actions.contains(.refreshLifecycleScan))
        XCTAssertTrue(actions.contains(.archiveTask))
    }

    func testMissingPathStillBlocksUnsafeOpenAction() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("factory-missing-blocks-\(UUID().uuidString)", isDirectory: true)
        let task = FactoryTask(projectId: "project", title: "Task", localBranch: "factory/task", localWorktreePath: missing.path)

        let display = try XCTUnwrap(TaskWorktreeDisplayMapper.displays(for: task).first)

        XCTAssertEqual(display.state, .missingPath)
        XCTAssertFalse(display.canOpen)
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

    func testWorkflowHealthSummarizesTaskStateReview() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("factory-health-worktree-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
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
        let task = FactoryTask(projectId: "project", title: "Task", localWorktreePath: root.path)

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

    func testProjectCommandConfigurationDefaults() {
        let empty = ProjectCommandConfiguration()
        XCTAssertNil(empty.command(for: .build))
        XCTAssertNil(empty.command(for: .unitTests))
        XCTAssertNil(empty.command(for: .integrationTests))
        XCTAssertNil(empty.command(for: .e2eTests))
        XCTAssertNil(empty.command(for: .visualQC))

        let legacy = Project(name: "Demo", type: .codeRepo, path: "/tmp/demo", testCommands: ["swift test"])
        XCTAssertEqual(legacy.commandConfiguration.command(for: .unitTests), "swift test")
        XCTAssertEqual(legacy.testCommands, ["swift test"])
    }

    func testRepositoryPersistsProjectCommandConfiguration() throws {
        let fixture = try makeRepositoryFixture()
        let project = Project(
            id: "project",
            name: "Demo",
            type: .codeRepo,
            path: fixture.root.path,
            commandConfiguration: ProjectCommandConfiguration(
                build: "swift build",
                unitTests: "swift test",
                integrationTests: "npm run integration",
                e2eTests: "npm run e2e",
                visualQC: "npm run visual-qc"
            )
        )

        try fixture.repository.upsert(project: project)
        let stored = try XCTUnwrap(fixture.repository.projects().first)

        XCTAssertEqual(stored.commandConfiguration.command(for: .build), "swift build")
        XCTAssertEqual(stored.commandConfiguration.command(for: .unitTests), "swift test")
        XCTAssertEqual(stored.commandConfiguration.command(for: .integrationTests), "npm run integration")
        XCTAssertEqual(stored.commandConfiguration.command(for: .e2eTests), "npm run e2e")
        XCTAssertEqual(stored.commandConfiguration.command(for: .visualQC), "npm run visual-qc")
    }

    func testLocalRunnerMissingCommandDoesNotCreateFakeRun() async throws {
        let fixture = try makeRepositoryFixture()
        let project = Project(id: "project", name: "Demo", type: .codeRepo, path: fixture.root.path)
        let task = FactoryTask(id: "task", projectId: project.id, title: "Run missing", localWorktreePath: fixture.root.path)
        try fixture.repository.upsert(project: project)
        try fixture.repository.upsert(task: task)

        let runner = LocalRunnerService(commandRunner: CommandRunner(), paths: fixture.paths, repository: fixture.repository)
        let result = try await runner.runConfiguredCommand(project: project, task: task, kind: .unitTests)

        XCTAssertEqual(result.status, .notConfigured)
        XCTAssertNil(result.run)
        XCTAssertEqual(try fixture.repository.runs(taskId: task.id), [])
    }

    func testLocalRunnerRunLifecycleAndSuccessfulExitCode() async throws {
        let fixture = try makeRepositoryFixture()
        let project = Project(
            id: "project",
            name: "Demo",
            type: .codeRepo,
            path: fixture.root.path,
            commandConfiguration: ProjectCommandConfiguration(unitTests: "printf local-runner-ok")
        )
        let task = FactoryTask(id: "task", projectId: project.id, title: "Run success", localWorktreePath: fixture.root.path)
        try fixture.repository.upsert(project: project)
        try fixture.repository.upsert(task: task)

        let runner = LocalRunnerService(commandRunner: CommandRunner(), paths: fixture.paths, repository: fixture.repository)
        var sawRunningRecord = false
        let result = try await runner.runConfiguredCommand(project: project, task: task, kind: .unitTests) { startedRun in
            let stored = try XCTUnwrap(fixture.repository.runs(taskId: task.id).first { $0.id == startedRun.id })
            sawRunningRecord = stored.status == .running
        }

        XCTAssertTrue(sawRunningRecord)
        XCTAssertEqual(result.status, .passed)
        XCTAssertEqual(result.run?.status, .succeeded)
        XCTAssertEqual(result.run?.exitCode, 0)
        XCTAssertTrue(result.output.contains("local-runner-ok"))
    }

    func testLocalRunnerFailingCommandExitCode() async throws {
        let fixture = try makeRepositoryFixture()
        let project = Project(
            id: "project",
            name: "Demo",
            type: .codeRepo,
            path: fixture.root.path,
            commandConfiguration: ProjectCommandConfiguration(unitTests: "false")
        )
        let task = FactoryTask(id: "task", projectId: project.id, title: "Run failure", localWorktreePath: fixture.root.path)
        try fixture.repository.upsert(project: project)
        try fixture.repository.upsert(task: task)

        let runner = LocalRunnerService(commandRunner: CommandRunner(), paths: fixture.paths, repository: fixture.repository)
        let result = try await runner.runConfiguredCommand(project: project, task: task, kind: .unitTests)

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.run?.status, .failed)
        XCTAssertEqual(result.run?.exitCode, 1)
    }

    func testRepositoryPersistsLocalRunnerRunRecords() async throws {
        let fixture = try makeRepositoryFixture()
        let project = Project(
            id: "project",
            name: "Demo",
            type: .codeRepo,
            path: fixture.root.path,
            commandConfiguration: ProjectCommandConfiguration(build: "printf build-ok")
        )
        let task = FactoryTask(id: "task", projectId: project.id, title: "Persist run", localWorktreePath: fixture.root.path)
        try fixture.repository.upsert(project: project)
        try fixture.repository.upsert(task: task)

        let runner = LocalRunnerService(commandRunner: CommandRunner(), paths: fixture.paths, repository: fixture.repository)
        _ = try await runner.runConfiguredCommand(project: project, task: task, kind: .build, runID: "run-1")
        let stored = try XCTUnwrap(fixture.repository.runs(taskId: task.id).first)

        XCTAssertEqual(stored.id, "run-1")
        XCTAssertEqual(stored.projectId, project.id)
        XCTAssertEqual(stored.taskId, task.id)
        XCTAssertEqual(stored.runType, .build)
        XCTAssertEqual(stored.command, "printf build-ok")
        XCTAssertEqual(stored.exitCode, 0)
        XCTAssertNotNil(stored.outputPath)
        XCTAssertNotNil(stored.endedAt)
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

    private func makeRepositoryFixture() throws -> (root: URL, paths: FactoryPaths, repository: FactoryRepository) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("factory-desktop-tests-\(UUID().uuidString)", isDirectory: true)
        let paths = FactoryPaths(root: root)
        try paths.ensureBaseDirectories()
        let database = try SQLiteDatabase(url: paths.database)
        try MigrationRunner(database: database, paths: paths).migrate()
        return (root, paths, FactoryRepository(database: database))
    }
}
