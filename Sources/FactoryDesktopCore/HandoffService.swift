import Foundation

public final class HandoffService {
    private let paths: FactoryPaths

    public init(paths: FactoryPaths) {
        self.paths = paths
    }

    public func codexPlanReviewHandoff(project: Project, task: FactoryTask, latestPlan: Artifact?) throws -> URL {
        let runDirectory = paths.runDirectory(project: project, task: task)
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)

        let targetPath = runDirectory.appendingPathComponent("codex-plan-review-handoff.md")
        let planPath = latestPlan?.path ?? "(no saved plan artifact found)"
        let acceptance = task.acceptanceCriteria.isEmpty
            ? "- Confirm the plan satisfies the task goal."
            : task.acceptanceCriteria.map { "- \($0)" }.joined(separator: "\n")

        let markdown = """
        # Codex Plan Review Handoff: \(task.title)

        You are reviewing only. Do not edit files, run formatters, commit, merge, push, or change the worktree.

        ## Project
        - Name: \(project.name)
        - Type: \(project.type.rawValue)
        - Source path: \(project.path)
        - Default branch: \(project.defaultBranch)

        ## Task
        - ID: \(task.id)
        - Status: \(task.status.rawValue)
        - Plan artifact: \(planPath)

        ## Goal
        \(task.goal.isEmpty ? task.title : task.goal)

        ## Context
        \(task.context.isEmpty ? "No extra context provided." : task.context)

        ## Acceptance Criteria
        \(acceptance)

        ## Review Request
        Critique the plan for correctness, missing steps, risk, test coverage, sequencing, and unnecessary scope. Return findings first, then a concise recommendation: approve, revise, or block.
        """

        try markdown.write(to: targetPath, atomically: true, encoding: .utf8)
        return targetPath
    }

    public func codexHandoff(project: Project, task: FactoryTask, gitSnapshot: GitSnapshot?) throws -> URL {
        let runDirectory = paths.runDirectory(project: project, task: task)
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)

        let targetPath = runDirectory.appendingPathComponent("codex-handoff.md")
        let worktree = task.codexWorktreePath ?? task.localWorktreePath ?? project.path
        let branch = task.codexBranch ?? task.localBranch ?? "(create a task worktree first)"
        let acceptance = task.acceptanceCriteria.isEmpty
            ? "- Confirm the implementation satisfies the task goal."
            : task.acceptanceCriteria.map { "- \($0)" }.joined(separator: "\n")
        let changedFiles = (gitSnapshot?.changedFiles ?? []).isEmpty
            ? "- No changed files detected yet."
            : (gitSnapshot?.changedFiles ?? []).map { "- \($0)" }.joined(separator: "\n")

        let markdown = """
        # Codex Handoff: \(task.title)

        ## Project
        - Name: \(project.name)
        - Type: \(project.type.rawValue)
        - Source path: \(project.path)
        - Worktree path: \(worktree)
        - Branch: \(branch)
        - Default branch: \(project.defaultBranch)

        ## Goal
        \(task.goal.isEmpty ? task.title : task.goal)

        ## Context
        \(task.context.isEmpty ? "No extra context provided." : task.context)

        ## Acceptance Criteria
        \(acceptance)

        ## Current Changed Files
        \(changedFiles)

        ## Safety Rules
        - Work only inside the task worktree above.
        - Do not edit the default branch directly.
        - Do not run destructive commands.
        - Do not commit, merge, or push unless the human explicitly approves.
        - Keep a concise run note of what changed and what remains.

        ## Suggested Codex Start
        ```bash
        cd "\(worktree)"
        codex
        ```
        """

        try markdown.write(to: targetPath, atomically: true, encoding: .utf8)

        let startNote = runDirectory.appendingPathComponent("START_CODEX.md")
        try """
        Open Terminal in:
        \(worktree)

        Then run:
        codex

        Use this handoff:
        \(targetPath.path)
        """.write(to: startNote, atomically: true, encoding: .utf8)

        return targetPath
    }

    public func codexDiffReviewHandoff(project: Project, task: FactoryTask, gitSnapshot: GitSnapshot, latestRun: RunRecord?) throws -> URL {
        let runDirectory = paths.runDirectory(project: project, task: task)
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)

        let targetPath = runDirectory.appendingPathComponent("codex-diff-review-handoff.md")
        let latestRunText: String
        if let latestRun {
            latestRunText = "- Last run: \(latestRun.executor) \(latestRun.model ?? "") \(latestRun.status.rawValue)"
        } else {
            latestRunText = "- Last run: none"
        }

        let markdown = """
        # Codex Diff Review Handoff: \(task.title)

        You are reviewing only. Do not edit files, run formatters, commit, merge, push, or change the worktree.

        ## Project
        - Name: \(project.name)
        - Source path: \(project.path)
        - Worktree path: \(gitSnapshot.worktreePath)
        - Branch: \(gitSnapshot.currentBranch ?? "unknown")
        - Default branch: \(project.defaultBranch)

        ## Task
        - ID: \(task.id)
        - Status: \(task.status.rawValue)
        \(latestRunText)

        ## Goal
        \(task.goal.isEmpty ? task.title : task.goal)

        ## Acceptance Criteria
        \(task.acceptanceCriteria.isEmpty ? "- No explicit acceptance criteria." : task.acceptanceCriteria.map { "- \($0)" }.joined(separator: "\n"))

        ## Changed Files
        \(gitSnapshot.changedFiles.isEmpty ? "- No changed files detected." : gitSnapshot.changedFiles.map { "- \($0)" }.joined(separator: "\n"))

        ## Diff Stat
        ```text
        \(gitSnapshot.diffStat.isEmpty ? "(empty)" : gitSnapshot.diffStat)
        ```

        ## Review Request
        Critique the diff for bugs, regressions, missing tests, unsafe assumptions, and acceptance gaps. Return findings first, ordered by severity, then residual risk and a concise ready/not-ready recommendation.
        """

        try markdown.write(to: targetPath, atomically: true, encoding: .utf8)
        return targetPath
    }

    public func reviewNote(project: Project, task: FactoryTask, gitSnapshot: GitSnapshot, latestRun: RunRecord?) throws -> URL {
        let runDirectory = paths.runDirectory(project: project, task: task)
        try FileManager.default.createDirectory(at: runDirectory, withIntermediateDirectories: true)
        let targetPath = runDirectory.appendingPathComponent("review.md")
        let latestRunText: String
        if let latestRun {
            latestRunText = "- Last run: \(latestRun.executor) \(latestRun.model ?? "") \(latestRun.status.rawValue)"
        } else {
            latestRunText = "- Last run: none"
        }

        let markdown = """
        # Review Note: \(task.title)

        ## Status
        - Task status: \(task.status.rawValue)
        \(latestRunText)
        - Worktree: \(gitSnapshot.worktreePath)
        - Branch: \(gitSnapshot.currentBranch ?? "unknown")

        ## Changed Files
        \(gitSnapshot.changedFiles.isEmpty ? "- No changed files detected." : gitSnapshot.changedFiles.map { "- \($0)" }.joined(separator: "\n"))

        ## Diff Stat
        ```text
        \(gitSnapshot.diffStat.isEmpty ? "(empty)" : gitSnapshot.diffStat)
        ```

        ## Acceptance Criteria
        \(task.acceptanceCriteria.isEmpty ? "- No explicit acceptance criteria." : task.acceptanceCriteria.map { "- [ ] \($0)" }.joined(separator: "\n"))
        """

        try markdown.write(to: targetPath, atomically: true, encoding: .utf8)
        return targetPath
    }
}
