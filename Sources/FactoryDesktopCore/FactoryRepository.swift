import Foundation

public final class FactoryRepository {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func projects() throws -> [Project] {
        let rows = try database.query(
            """
            SELECT id, name, type, path, default_branch, test_commands_json, command_config_json, metadata_json, created_at, updated_at
            FROM projects
            ORDER BY updated_at DESC, name ASC;
            """
        )
        return rows.map(project(from:))
    }

    public func upsert(project: Project) throws {
        try database.execute(
            """
            INSERT INTO projects (id, name, type, path, default_branch, test_commands_json, command_config_json, metadata_json, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(path) DO UPDATE SET
              name = excluded.name,
              type = excluded.type,
              default_branch = excluded.default_branch,
              test_commands_json = excluded.test_commands_json,
              command_config_json = excluded.command_config_json,
              metadata_json = excluded.metadata_json,
              updated_at = excluded.updated_at;
            """,
            binds: [
                .text(project.id),
                .text(project.name),
                .text(project.type.rawValue),
                .text(project.path),
                .text(project.defaultBranch),
                .text(JSONCoding.encodeArray(project.testCommands)),
                .text(JSONCoding.encode(project.commandConfiguration)),
                .text(JSONCoding.encodeDictionary(project.metadata)),
                .text(DateCoding.string(from: project.createdAt)),
                .text(DateCoding.string(from: project.updatedAt))
            ]
        )
    }

    public func deleteProject(id: String) throws {
        try database.execute("DELETE FROM projects WHERE id = ?;", binds: [.text(id)])
    }

    public func upsert(codexProjectLink link: CodexProjectLink) throws {
        try database.execute(
            """
            INSERT INTO codex_project_links (
              id, project_id, workspace_path, preferred_mode, preferred_model, preferred_reasoning, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(project_id) DO UPDATE SET
              workspace_path = excluded.workspace_path,
              preferred_mode = excluded.preferred_mode,
              preferred_model = excluded.preferred_model,
              preferred_reasoning = excluded.preferred_reasoning,
              updated_at = excluded.updated_at;
            """,
            binds: [
                .text(link.id),
                .text(link.projectId),
                .text(link.workspacePath),
                .text(link.preferredMode.rawValue),
                .text(link.preferredModel),
                .text(link.preferredReasoning),
                .text(DateCoding.string(from: link.createdAt)),
                .text(DateCoding.string(from: link.updatedAt))
            ]
        )
    }

    public func codexProjectLink(projectId: String) throws -> CodexProjectLink? {
        let rows = try database.query(
            """
            SELECT id, project_id, workspace_path, preferred_mode, preferred_model, preferred_reasoning, created_at, updated_at
            FROM codex_project_links
            WHERE project_id = ?
            LIMIT 1;
            """,
            binds: [.text(projectId)]
        )
        return rows.first.map(codexProjectLink(from:))
    }

    public func deleteCodexProjectLink(projectId: String) throws {
        try database.execute("DELETE FROM codex_project_links WHERE project_id = ?;", binds: [.text(projectId)])
    }

    public func runnerProjectLink(projectId: String) throws -> RunnerProjectLink? {
        try codexProjectLink(projectId: projectId)?.asRunnerProjectLink()
    }

    public func upsert(runnerProjectLink link: RunnerProjectLink) throws {
        guard link.provider == .codex else {
            throw FactoryError.commandFailed("Only the Codex runner adapter is implemented in v1.")
        }
        let codexLink = CodexProjectLink(
            id: link.id,
            projectId: link.projectId,
            workspacePath: link.workspacePath,
            preferredMode: link.preferredModelProfile?.location == .cloud ? .cloud : (link.workspacePath.contains("/.factory/worktrees/") ? .worktree : .local),
            preferredModel: link.preferredModelProfile?.modelName,
            preferredReasoning: link.preferredModelProfile?.reasoningEffort,
            createdAt: link.createdAt,
            updatedAt: link.updatedAt
        )
        try upsert(codexProjectLink: codexLink)
    }

    public func deleteRunnerProjectLink(projectId: String) throws {
        try deleteCodexProjectLink(projectId: projectId)
    }

    public func tasks(projectId: String? = nil) throws -> [FactoryTask] {
        let rows: [[String: String?]]
        if let projectId {
            rows = try database.query(
                """
                SELECT id, project_id, title, type, status, priority, kind, triage_status, readiness, priority_label,
                       effort, risk, source, category, scoping_notes, dependencies, non_goals, suggested_split,
                       recommended_next_action, parent_task_id, goal, context, acceptance_criteria_json,
                       local_branch, codex_branch, local_worktree_path, codex_worktree_path,
                       local_base_branch_commit, codex_base_branch_commit, created_at, updated_at
                FROM tasks
                WHERE project_id = ?
                ORDER BY updated_at DESC, created_at DESC;
                """,
                binds: [.text(projectId)]
            )
        } else {
            rows = try database.query(
                """
                SELECT id, project_id, title, type, status, priority, kind, triage_status, readiness, priority_label,
                       effort, risk, source, category, scoping_notes, dependencies, non_goals, suggested_split,
                       recommended_next_action, parent_task_id, goal, context, acceptance_criteria_json,
                       local_branch, codex_branch, local_worktree_path, codex_worktree_path,
                       local_base_branch_commit, codex_base_branch_commit, created_at, updated_at
                FROM tasks
                ORDER BY updated_at DESC, created_at DESC;
                """
            )
        }
        return rows.map(task(from:))
    }

    public func upsert(task: FactoryTask) throws {
        try database.execute(
            """
            INSERT INTO tasks (
              id, project_id, title, type, status, priority, kind, triage_status, readiness, priority_label,
              effort, risk, source, category, scoping_notes, dependencies, non_goals, suggested_split,
              recommended_next_action, parent_task_id, goal, context, acceptance_criteria_json,
              local_branch, codex_branch, local_worktree_path, codex_worktree_path,
              local_base_branch_commit, codex_base_branch_commit, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              project_id = excluded.project_id,
              title = excluded.title,
              type = excluded.type,
              status = excluded.status,
              priority = excluded.priority,
              kind = excluded.kind,
              triage_status = excluded.triage_status,
              readiness = excluded.readiness,
              priority_label = excluded.priority_label,
              effort = excluded.effort,
              risk = excluded.risk,
              source = excluded.source,
              category = excluded.category,
              scoping_notes = excluded.scoping_notes,
              dependencies = excluded.dependencies,
              non_goals = excluded.non_goals,
              suggested_split = excluded.suggested_split,
              recommended_next_action = excluded.recommended_next_action,
              parent_task_id = excluded.parent_task_id,
              goal = excluded.goal,
              context = excluded.context,
              acceptance_criteria_json = excluded.acceptance_criteria_json,
              local_branch = excluded.local_branch,
              codex_branch = excluded.codex_branch,
              local_worktree_path = excluded.local_worktree_path,
              codex_worktree_path = excluded.codex_worktree_path,
              local_base_branch_commit = excluded.local_base_branch_commit,
              codex_base_branch_commit = excluded.codex_base_branch_commit,
              updated_at = excluded.updated_at;
            """,
            binds: [
                .text(task.id),
                .text(task.projectId),
                .text(task.title),
                .text(task.type.rawValue),
                .text(task.status.rawValue),
                .text(task.priority.rawValue),
                .text(task.kind.rawValue),
                .text(task.triageStatus.rawValue),
                .text(task.readiness.rawValue),
                .text(task.priorityLabel.rawValue),
                .text(task.effort.rawValue),
                .text(task.risk.rawValue),
                .text(task.source),
                .text(task.category),
                .text(task.scopingNotes),
                .text(task.dependencies),
                .text(task.nonGoals),
                .text(task.suggestedSplit),
                .text(task.recommendedNextAction),
                .text(task.parentTaskId),
                .text(task.goal),
                .text(task.context),
                .text(JSONCoding.encodeArray(task.acceptanceCriteria)),
                .text(task.localBranch),
                .text(task.codexBranch),
                .text(task.localWorktreePath),
                .text(task.codexWorktreePath),
                .text(task.localBaseBranchCommit),
                .text(task.codexBaseBranchCommit),
                .text(DateCoding.string(from: task.createdAt)),
                .text(DateCoding.string(from: task.updatedAt))
            ]
        )
    }

    public func deleteTask(id: String) throws {
        try database.transaction {
            try database.execute(
                "UPDATE codex_session_links SET task_id = NULL, updated_at = ? WHERE task_id = ?;",
                binds: [.text(DateCoding.string(from: Date())), .text(id)]
            )
            try database.execute(
                "UPDATE backlog_ideas SET linked_task_id = NULL, updated_at = ? WHERE linked_task_id = ?;",
                binds: [.text(DateCoding.string(from: Date())), .text(id)]
            )
            try database.execute("UPDATE tasks SET parent_task_id = NULL WHERE parent_task_id = ?;", binds: [.text(id)])
            try database.execute("DELETE FROM task_events WHERE task_id = ?;", binds: [.text(id)])
            try database.execute("DELETE FROM artifacts WHERE task_id = ?;", binds: [.text(id)])
            try database.execute("DELETE FROM runs WHERE task_id = ?;", binds: [.text(id)])
            try database.execute("DELETE FROM tasks WHERE id = ?;", binds: [.text(id)])
        }
    }

    public func runnerWorkspaces(taskId: String) throws -> [RunnerWorkspace] {
        let rows = try database.query(
            """
            SELECT id, project_id, task_id, branch_name, worktree_path, base_commit, head_commit,
                   archived, cleaned, pinned, created_at, updated_at
            FROM runner_workspaces
            WHERE task_id = ?
            ORDER BY pinned DESC, archived ASC, updated_at DESC, created_at DESC;
            """,
            binds: [.text(taskId)]
        )
        return rows.map(runnerWorkspace(from:))
    }

    public func latestRunnerWorkspace(taskId: String) throws -> RunnerWorkspace? {
        try runnerWorkspaces(taskId: taskId).first
    }

    public func upsert(runnerWorkspace workspace: RunnerWorkspace) throws {
        try database.execute(
            """
            INSERT INTO runner_workspaces (
              id, project_id, task_id, branch_name, worktree_path, base_commit, head_commit,
              archived, cleaned, pinned, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              project_id = excluded.project_id,
              task_id = excluded.task_id,
              branch_name = excluded.branch_name,
              worktree_path = excluded.worktree_path,
              base_commit = excluded.base_commit,
              head_commit = excluded.head_commit,
              archived = excluded.archived,
              cleaned = excluded.cleaned,
              pinned = excluded.pinned,
              updated_at = excluded.updated_at;
            """,
            binds: [
                .text(workspace.id),
                .text(workspace.projectId),
                .text(workspace.taskId),
                .text(workspace.branchName),
                .text(workspace.worktreePath),
                .text(workspace.baseCommit),
                .text(workspace.headCommit),
                .int(workspace.archived ? 1 : 0),
                .int(workspace.cleaned ? 1 : 0),
                .int(workspace.pinned ? 1 : 0),
                .text(DateCoding.string(from: workspace.createdAt)),
                .text(DateCoding.string(from: workspace.updatedAt))
            ]
        )
    }

    public func runnerSessions(workspaceId: String) throws -> [RunnerSession] {
        let rows = try database.query(
            """
            SELECT id, workspace_id, provider, mode, model_profile_json, external_session_id, status,
                   transcript_path, active_turn_id, created_at, updated_at
            FROM runner_sessions
            WHERE workspace_id = ?
            ORDER BY updated_at DESC, created_at DESC;
            """,
            binds: [.text(workspaceId)]
        )
        return rows.map(runnerSession(from:))
    }

    public func runnerSessions(taskId: String) throws -> [RunnerSession] {
        let rows = try database.query(
            """
            SELECT s.id, s.workspace_id, s.provider, s.mode, s.model_profile_json, s.external_session_id, s.status,
                   s.transcript_path, s.active_turn_id, s.created_at, s.updated_at
            FROM runner_sessions s
            INNER JOIN runner_workspaces w ON w.id = s.workspace_id
            WHERE w.task_id = ?
            ORDER BY s.updated_at DESC, s.created_at DESC;
            """,
            binds: [.text(taskId)]
        )
        return rows.map(runnerSession(from:))
    }

    public func latestRunnerSession(taskId: String) throws -> RunnerSession? {
        try runnerSessions(taskId: taskId).first
    }

    public func upsert(runnerSession session: RunnerSession) throws {
        try database.execute(
            """
            INSERT INTO runner_sessions (
              id, workspace_id, provider, mode, model_profile_json, external_session_id, status,
              transcript_path, active_turn_id, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              workspace_id = excluded.workspace_id,
              provider = excluded.provider,
              mode = excluded.mode,
              model_profile_json = excluded.model_profile_json,
              external_session_id = excluded.external_session_id,
              status = excluded.status,
              transcript_path = excluded.transcript_path,
              active_turn_id = excluded.active_turn_id,
              updated_at = excluded.updated_at;
            """,
            binds: [
                .text(session.id),
                .text(session.workspaceId),
                .text(session.provider.rawValue),
                .text(session.mode.rawValue),
                .text(session.modelProfile.map(JSONCoding.encode)),
                .text(session.externalSessionId),
                .text(session.status.rawValue),
                .text(session.transcriptPath),
                .text(session.activeTurnId),
                .text(DateCoding.string(from: session.createdAt)),
                .text(DateCoding.string(from: session.updatedAt))
            ]
        )
    }

    public func upsert(runnerExecution execution: RunnerExecution) throws {
        try database.execute(
            """
            INSERT INTO runner_executions (
              id, session_id, run_reason, command, status, exit_code, log_path,
              before_repo_state, after_repo_state, started_at, ended_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              session_id = excluded.session_id,
              run_reason = excluded.run_reason,
              command = excluded.command,
              status = excluded.status,
              exit_code = excluded.exit_code,
              log_path = excluded.log_path,
              before_repo_state = excluded.before_repo_state,
              after_repo_state = excluded.after_repo_state,
              ended_at = excluded.ended_at;
            """,
            binds: [
                .text(execution.id),
                .text(execution.sessionId),
                .text(execution.runReason),
                .text(execution.command),
                .text(execution.status.rawValue),
                execution.exitCode.map(SQLiteValue.int) ?? .null,
                .text(execution.logPath),
                .text(execution.beforeRepoState),
                .text(execution.afterRepoState),
                .text(DateCoding.string(from: execution.startedAt)),
                .text(execution.endedAt.map(DateCoding.string(from:)))
            ]
        )
    }

    public func runnerExecutions(sessionId: String) throws -> [RunnerExecution] {
        let rows = try database.query(
            """
            SELECT id, session_id, run_reason, command, status, exit_code, log_path,
                   before_repo_state, after_repo_state, started_at, ended_at
            FROM runner_executions
            WHERE session_id = ?
            ORDER BY started_at DESC;
            """,
            binds: [.text(sessionId)]
        )
        return rows.map(runnerExecution(from:))
    }

    public func latestRunnerExecution(taskId: String) throws -> RunnerExecution? {
        let rows = try database.query(
            """
            SELECT e.id, e.session_id, e.run_reason, e.command, e.status, e.exit_code, e.log_path,
                   e.before_repo_state, e.after_repo_state, e.started_at, e.ended_at
            FROM runner_executions e
            INNER JOIN runner_sessions s ON s.id = e.session_id
            INNER JOIN runner_workspaces w ON w.id = s.workspace_id
            WHERE w.task_id = ?
            ORDER BY e.started_at DESC
            LIMIT 1;
            """,
            binds: [.text(taskId)]
        )
        return rows.first.map(runnerExecution(from:))
    }

    public func insert(agentTurn: AgentTurn) throws {
        try database.execute(
            """
            INSERT INTO agent_turns (id, session_id, role, content, created_at)
            VALUES (?, ?, ?, ?, ?);
            """,
            binds: [
                .text(agentTurn.id),
                .text(agentTurn.sessionId),
                .text(agentTurn.role),
                .text(agentTurn.content),
                .text(DateCoding.string(from: agentTurn.createdAt))
            ]
        )
    }

    public func upsert(workerReport report: WorkerReport) throws {
        try database.execute(
            """
            INSERT INTO worker_reports (
              id, session_id, execution_id, status, summary, files_changed_json, tests_run_json,
              risks_json, blockers_json, next_recommended_action, recommended_task_status, raw_text, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              status = excluded.status,
              summary = excluded.summary,
              files_changed_json = excluded.files_changed_json,
              tests_run_json = excluded.tests_run_json,
              risks_json = excluded.risks_json,
              blockers_json = excluded.blockers_json,
              next_recommended_action = excluded.next_recommended_action,
              recommended_task_status = excluded.recommended_task_status,
              raw_text = excluded.raw_text;
            """,
            binds: [
                .text(report.id),
                .text(report.sessionId),
                .text(report.executionId),
                .text(report.status.rawValue),
                .text(report.summary),
                .text(JSONCoding.encodeArray(report.filesChanged)),
                .text(JSONCoding.encodeArray(report.testsRun)),
                .text(JSONCoding.encodeArray(report.risks)),
                .text(JSONCoding.encodeArray(report.blockers)),
                .text(report.nextRecommendedAction),
                .text(report.recommendedTaskStatus?.rawValue),
                .text(report.rawText),
                .text(DateCoding.string(from: report.createdAt))
            ]
        )
    }

    public func workerReports(sessionId: String) throws -> [WorkerReport] {
        let rows = try database.query(
            """
            SELECT id, session_id, execution_id, status, summary, files_changed_json, tests_run_json,
                   risks_json, blockers_json, next_recommended_action, recommended_task_status, raw_text, created_at
            FROM worker_reports
            WHERE session_id = ?
            ORDER BY created_at DESC;
            """,
            binds: [.text(sessionId)]
        )
        return rows.map(workerReport(from:))
    }

    public func latestWorkerReport(taskId: String) throws -> WorkerReport? {
        let rows = try database.query(
            """
            SELECT r.id, r.session_id, r.execution_id, r.status, r.summary, r.files_changed_json, r.tests_run_json,
                   r.risks_json, r.blockers_json, r.next_recommended_action, r.recommended_task_status, r.raw_text, r.created_at
            FROM worker_reports r
            INNER JOIN runner_sessions s ON s.id = r.session_id
            INNER JOIN runner_workspaces w ON w.id = s.workspace_id
            WHERE w.task_id = ?
            ORDER BY r.created_at DESC
            LIMIT 1;
            """,
            binds: [.text(taskId)]
        )
        return rows.first.map(workerReport(from:))
    }

    public func upsert(taskProposal proposal: TaskProposal) throws {
        try database.execute(
            """
            INSERT INTO task_proposals (
              id, source_task_id, source_session_id, title, goal, context, acceptance_criteria_json,
              reason_discovered, suggested_priority, suggested_stage, source_files_json, status,
              created_task_id, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              title = excluded.title,
              goal = excluded.goal,
              context = excluded.context,
              acceptance_criteria_json = excluded.acceptance_criteria_json,
              reason_discovered = excluded.reason_discovered,
              suggested_priority = excluded.suggested_priority,
              suggested_stage = excluded.suggested_stage,
              source_files_json = excluded.source_files_json,
              status = excluded.status,
              created_task_id = excluded.created_task_id;
            """,
            binds: [
                .text(proposal.id),
                .text(proposal.sourceTaskId),
                .text(proposal.sourceSessionId),
                .text(proposal.title),
                .text(proposal.goal),
                .text(proposal.context),
                .text(JSONCoding.encodeArray(proposal.acceptanceCriteria)),
                .text(proposal.reasonDiscovered),
                .text(proposal.suggestedPriority.rawValue),
                .text(proposal.suggestedStage.rawValue),
                .text(JSONCoding.encodeArray(proposal.sourceFiles)),
                .text(proposal.status.rawValue),
                .text(proposal.createdTaskId),
                .text(DateCoding.string(from: proposal.createdAt))
            ]
        )
    }

    public func taskProposals(sourceTaskId: String, status: TaskProposalStatus? = nil) throws -> [TaskProposal] {
        let rows: [[String: String?]]
        if let status {
            rows = try database.query(
                """
                SELECT id, source_task_id, source_session_id, title, goal, context, acceptance_criteria_json,
                       reason_discovered, suggested_priority, suggested_stage, source_files_json, status,
                       created_task_id, created_at
                FROM task_proposals
                WHERE source_task_id = ? AND status = ?
                ORDER BY created_at DESC;
                """,
                binds: [.text(sourceTaskId), .text(status.rawValue)]
            )
        } else {
            rows = try database.query(
                """
                SELECT id, source_task_id, source_session_id, title, goal, context, acceptance_criteria_json,
                       reason_discovered, suggested_priority, suggested_stage, source_files_json, status,
                       created_task_id, created_at
                FROM task_proposals
                WHERE source_task_id = ?
                ORDER BY created_at DESC;
                """,
                binds: [.text(sourceTaskId)]
            )
        }
        return rows.map(taskProposal(from:))
    }

    @discardableResult
    public func acceptTaskProposal(id: String) throws -> FactoryTask {
        let proposal = try database.query(
            """
            SELECT id, source_task_id, source_session_id, title, goal, context, acceptance_criteria_json,
                   reason_discovered, suggested_priority, suggested_stage, source_files_json, status,
                   created_task_id, created_at
            FROM task_proposals
            WHERE id = ?
            LIMIT 1;
            """,
            binds: [.text(id)]
        ).first.map(taskProposal(from:))
        guard var proposal else {
            throw FactoryError.commandFailed("Task proposal not found.")
        }
        guard proposal.status == .proposed else {
            if let taskId = proposal.createdTaskId,
               let existing = try tasks().first(where: { $0.id == taskId }) {
                return existing
            }
            throw FactoryError.commandFailed("Task proposal is not proposed.")
        }
        let sourceTask = try tasks().first { $0.id == proposal.sourceTaskId }
        guard let sourceTask else {
            throw FactoryError.commandFailed("Source task not found.")
        }
        var task = FactoryTask(
            projectId: sourceTask.projectId,
            title: proposal.title,
            type: sourceTask.type,
            status: status(for: proposal.suggestedStage),
            priority: proposal.suggestedPriority.taskPriority,
            kind: .task,
            triageStatus: proposal.suggestedStage,
            readiness: proposal.suggestedStage == .ready ? .executable : .scoped,
            priorityLabel: proposal.suggestedPriority,
            source: "worker_proposal",
            category: sourceTask.category,
            parentTaskId: sourceTask.id,
            goal: proposal.goal,
            context: proposal.context,
            acceptanceCriteria: proposal.acceptanceCriteria
        )
        task.updatedAt = Date()
        try upsert(task: task)
        try insert(taskEvent: TaskEvent(
            taskId: task.id,
            kind: .statusChangedManually,
            source: .manual,
            message: "Created from worker proposal \(proposal.id).",
            previousStatus: nil,
            newStatus: task.status
        ))
        proposal.status = .accepted
        proposal.createdTaskId = task.id
        try upsert(taskProposal: proposal)
        return task
    }

    public func dismissTaskProposal(id: String) throws {
        var rows = try database.query(
            """
            SELECT id, source_task_id, source_session_id, title, goal, context, acceptance_criteria_json,
                   reason_discovered, suggested_priority, suggested_stage, source_files_json, status,
                   created_task_id, created_at
            FROM task_proposals
            WHERE id = ?
            LIMIT 1;
            """,
            binds: [.text(id)]
        )
        guard var proposal = rows.popLast().map(taskProposal(from:)) else { return }
        proposal.status = .dismissed
        try upsert(taskProposal: proposal)
    }

    public func insert(runnerNotification notification: RunnerNotification) throws {
        try database.execute(
            """
            INSERT INTO runner_notifications (
              id, task_id, session_id, execution_id, level, message, is_read, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """,
            binds: [
                .text(notification.id),
                .text(notification.taskId),
                .text(notification.sessionId),
                .text(notification.executionId),
                .text(notification.level.rawValue),
                .text(notification.message),
                .int(notification.isRead ? 1 : 0),
                .text(DateCoding.string(from: notification.createdAt))
            ]
        )
    }

    public func runnerNotifications(taskId: String, unreadOnly: Bool = false) throws -> [RunnerNotification] {
        let rows: [[String: String?]]
        if unreadOnly {
            rows = try database.query(
                """
                SELECT id, task_id, session_id, execution_id, level, message, is_read, created_at
                FROM runner_notifications
                WHERE task_id = ? AND is_read = 0
                ORDER BY created_at DESC;
                """,
                binds: [.text(taskId)]
            )
        } else {
            rows = try database.query(
                """
                SELECT id, task_id, session_id, execution_id, level, message, is_read, created_at
                FROM runner_notifications
                WHERE task_id = ?
                ORDER BY created_at DESC;
                """,
                binds: [.text(taskId)]
            )
        }
        return rows.map(runnerNotification(from:))
    }

    public func upsert(lifecycleSnapshot snapshot: LifecycleSnapshot) throws {
        try database.execute(
            """
            INSERT INTO lifecycle_snapshots (
              id, task_id, workspace_id, worktree_exists, branch_exists, dirty_state, main_moved,
              latest_execution_status, latest_report_status, unseen_notifications, proposed_tasks_count,
              recommended_action, evidence_json, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              worktree_exists = excluded.worktree_exists,
              branch_exists = excluded.branch_exists,
              dirty_state = excluded.dirty_state,
              main_moved = excluded.main_moved,
              latest_execution_status = excluded.latest_execution_status,
              latest_report_status = excluded.latest_report_status,
              unseen_notifications = excluded.unseen_notifications,
              proposed_tasks_count = excluded.proposed_tasks_count,
              recommended_action = excluded.recommended_action,
              evidence_json = excluded.evidence_json;
            """,
            binds: [
                .text(snapshot.id),
                .text(snapshot.taskId),
                .text(snapshot.workspaceId),
                .int(snapshot.worktreeExists ? 1 : 0),
                .int(snapshot.branchExists ? 1 : 0),
                .text(snapshot.dirtyState),
                .int(snapshot.mainMoved ? 1 : 0),
                .text(snapshot.latestExecutionStatus?.rawValue),
                .text(snapshot.latestReportStatus?.rawValue),
                .int(snapshot.unseenNotifications),
                .int(snapshot.proposedTasksCount),
                .text(snapshot.recommendedAction),
                .text(JSONCoding.encodeArray(snapshot.evidence)),
                .text(DateCoding.string(from: snapshot.createdAt))
            ]
        )
    }

    public func latestLifecycleSnapshot(taskId: String) throws -> LifecycleSnapshot? {
        let rows = try database.query(
            """
            SELECT id, task_id, workspace_id, worktree_exists, branch_exists, dirty_state, main_moved,
                   latest_execution_status, latest_report_status, unseen_notifications, proposed_tasks_count,
                   recommended_action, evidence_json, created_at
            FROM lifecycle_snapshots
            WHERE task_id = ?
            ORDER BY created_at DESC
            LIMIT 1;
            """,
            binds: [.text(taskId)]
        )
        return rows.first.map(lifecycleSnapshot(from:))
    }

    public func upsert(codexSessionLink link: CodexSessionLink) throws {
        try database.execute(
            """
            INSERT INTO codex_session_links (
              id, project_id, task_id, codex_session_id, workspace_path, mode, branch_name, worktree_path,
              status, last_seen_at, last_summary, transcript_path, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(codex_session_id) DO UPDATE SET
              project_id = excluded.project_id,
              task_id = excluded.task_id,
              workspace_path = excluded.workspace_path,
              mode = excluded.mode,
              branch_name = excluded.branch_name,
              worktree_path = excluded.worktree_path,
              status = excluded.status,
              last_seen_at = excluded.last_seen_at,
              last_summary = excluded.last_summary,
              transcript_path = excluded.transcript_path,
              updated_at = excluded.updated_at;
            """,
            binds: [
                .text(link.id),
                .text(link.projectId),
                .text(link.taskId),
                .text(link.codexSessionId),
                .text(link.workspacePath),
                .text(link.mode.rawValue),
                .text(link.branchName),
                .text(link.worktreePath),
                .text(link.status.rawValue),
                .text(link.lastSeenAt.map(DateCoding.string(from:))),
                .text(link.lastSummary),
                .text(link.transcriptPath),
                .text(DateCoding.string(from: link.createdAt)),
                .text(DateCoding.string(from: link.updatedAt))
            ]
        )
    }

    public func codexSessionLinks(projectId: String) throws -> [CodexSessionLink] {
        let rows = try database.query(
            """
            SELECT id, project_id, task_id, codex_session_id, workspace_path, mode, branch_name, worktree_path,
                   status, last_seen_at, last_summary, transcript_path, created_at, updated_at
            FROM codex_session_links
            WHERE project_id = ?
            ORDER BY updated_at DESC, created_at DESC;
            """,
            binds: [.text(projectId)]
        )
        return rows.map(codexSessionLink(from:))
    }

    public func codexSessionLinks(taskId: String) throws -> [CodexSessionLink] {
        let rows = try database.query(
            """
            SELECT id, project_id, task_id, codex_session_id, workspace_path, mode, branch_name, worktree_path,
                   status, last_seen_at, last_summary, transcript_path, created_at, updated_at
            FROM codex_session_links
            WHERE task_id = ?
            ORDER BY CASE status WHEN 'active' THEN 0 ELSE 1 END, updated_at DESC, created_at DESC;
            """,
            binds: [.text(taskId)]
        )
        return rows.map(codexSessionLink(from:))
    }

    public func latestCodexSessionLink(taskId: String) throws -> CodexSessionLink? {
        try codexSessionLinks(taskId: taskId).first
    }

    public func runnerSessionLinks(projectId: String) throws -> [RunnerSessionLink] {
        try codexSessionLinks(projectId: projectId).map { $0.asRunnerSessionLink() }
    }

    public func runnerSessionLinks(taskId: String) throws -> [RunnerSessionLink] {
        try codexSessionLinks(taskId: taskId).map { $0.asRunnerSessionLink() }
    }

    public func latestRunnerSessionLink(taskId: String) throws -> RunnerSessionLink? {
        try latestCodexSessionLink(taskId: taskId)?.asRunnerSessionLink()
    }

    public func upsert(runnerSessionLink link: RunnerSessionLink) throws {
        guard link.provider == .codex else {
            throw FactoryError.commandFailed("Only the Codex runner adapter is implemented in v1.")
        }
        let codexLink = CodexSessionLink(
            id: link.id,
            projectId: link.projectId,
            taskId: link.taskId,
            codexSessionId: link.sessionID,
            workspacePath: link.workspacePath,
            mode: link.workspacePath.contains("/.factory/worktrees/") ? .worktree : .local,
            branchName: link.branchName,
            worktreePath: link.worktreePath,
            status: CodexSessionStatus(rawValue: link.status.rawValue) ?? .unknown,
            lastSeenAt: link.lastSeenAt,
            lastSummary: link.lastSummary,
            transcriptPath: link.transcriptPath,
            createdAt: link.createdAt,
            updatedAt: link.updatedAt
        )
        try upsert(codexSessionLink: codexLink)
    }

    public func updateRunnerSessionLink(
        id: String,
        status: RunnerSessionStatus,
        lastSeenAt: Date?,
        lastSummary: String?,
        transcriptPath: String?
    ) throws {
        try updateCodexSessionLink(
            id: id,
            status: CodexSessionStatus(rawValue: status.rawValue) ?? .unknown,
            lastSeenAt: lastSeenAt,
            lastSummary: lastSummary,
            transcriptPath: transcriptPath
        )
    }

    public func detachRunnerSessionLinkFromTask(id: String) throws {
        try detachCodexSessionLinkFromTask(id: id)
    }

    public func updateCodexSessionLink(
        id: String,
        status: CodexSessionStatus,
        lastSeenAt: Date?,
        lastSummary: String?,
        transcriptPath: String?
    ) throws {
        try database.execute(
            """
            UPDATE codex_session_links
            SET status = ?,
                last_seen_at = ?,
                last_summary = ?,
                transcript_path = ?,
                updated_at = ?
            WHERE id = ?;
            """,
            binds: [
                .text(status.rawValue),
                .text(lastSeenAt.map(DateCoding.string(from:))),
                .text(lastSummary),
                .text(transcriptPath),
                .text(DateCoding.string(from: Date())),
                .text(id)
            ]
        )
    }

    public func detachCodexSessionLinkFromTask(id: String) throws {
        try database.execute(
            """
            UPDATE codex_session_links
            SET task_id = NULL,
                status = 'paused',
                updated_at = ?
            WHERE id = ?;
            """,
            binds: [.text(DateCoding.string(from: Date())), .text(id)]
        )
    }

    public func runs(taskId: String) throws -> [RunRecord] {
        let rows = try database.query(
            """
            SELECT id, project_id, task_id, run_type, executor, model, status, command, exit_code, prompt_path, output_path, summary, started_at, ended_at
            FROM runs
            WHERE task_id = ?
            ORDER BY started_at DESC;
            """,
            binds: [.text(taskId)]
        )
        return rows.map(run(from:))
    }

    public func runs(projectId: String) throws -> [RunRecord] {
        let rows = try database.query(
            """
            SELECT r.id, r.project_id, r.task_id, r.run_type, r.executor, r.model, r.status, r.command, r.exit_code, r.prompt_path, r.output_path, r.summary, r.started_at, r.ended_at
            FROM runs r
            LEFT JOIN tasks t ON r.task_id = t.id
            WHERE r.project_id = ? OR t.project_id = ?
            ORDER BY r.started_at DESC;
            """,
            binds: [.text(projectId), .text(projectId)]
        )
        return rows.map(run(from:))
    }

    public func upsert(run: RunRecord) throws {
        try database.execute(
            """
            INSERT INTO runs (id, project_id, task_id, run_type, executor, model, status, command, exit_code, prompt_path, output_path, summary, started_at, ended_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              project_id = excluded.project_id,
              task_id = excluded.task_id,
              run_type = excluded.run_type,
              executor = excluded.executor,
              model = excluded.model,
              status = excluded.status,
              command = excluded.command,
              exit_code = excluded.exit_code,
              prompt_path = excluded.prompt_path,
              output_path = excluded.output_path,
              summary = excluded.summary,
              started_at = excluded.started_at,
              ended_at = excluded.ended_at;
            """,
            binds: [
                .text(run.id),
                .text(run.projectId),
                .text(run.taskId),
                .text(run.runType?.rawValue),
                .text(run.executor),
                .text(run.model),
                .text(run.status.rawValue),
                .text(run.command),
                run.exitCode.map(SQLiteValue.int) ?? .null,
                .text(run.promptPath),
                .text(run.outputPath),
                .text(run.summary),
                .text(DateCoding.string(from: run.startedAt)),
                .text(run.endedAt.map(DateCoding.string(from:)))
            ]
        )
    }

    public func artifacts(taskId: String) throws -> [Artifact] {
        let rows = try database.query(
            """
            SELECT id, task_id, run_id, type, path, description, created_at
            FROM artifacts
            WHERE task_id = ?
            ORDER BY created_at DESC;
            """,
            binds: [.text(taskId)]
        )
        return rows.map(artifact(from:))
    }

    public func artifacts(projectId: String) throws -> [Artifact] {
        let rows = try database.query(
            """
            SELECT a.id, a.task_id, a.run_id, a.type, a.path, a.description, a.created_at
            FROM artifacts a
            INNER JOIN tasks t ON a.task_id = t.id
            WHERE t.project_id = ?
            ORDER BY a.created_at DESC;
            """,
            binds: [.text(projectId)]
        )
        return rows.map(artifact(from:))
    }

    public func taskEvents(taskId: String, limit: Int = 50) throws -> [TaskEvent] {
        let rows = try database.query(
            """
            SELECT id, task_id, kind, source, message, previous_status, new_status, run_id, artifact_id, created_at
            FROM task_events
            WHERE task_id = ?
            ORDER BY created_at DESC
            LIMIT ?;
            """,
            binds: [.text(taskId), .int(limit)]
        )
        return rows.map(taskEvent(from:))
    }

    public func insert(artifact: Artifact) throws {
        try database.execute(
            """
            INSERT INTO artifacts (id, task_id, run_id, type, path, description, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """,
            binds: [
                .text(artifact.id),
                .text(artifact.taskId),
                .text(artifact.runId),
                .text(artifact.type),
                .text(artifact.path),
                .text(artifact.description),
                .text(DateCoding.string(from: artifact.createdAt))
            ]
        )
    }

    public func insert(taskEvent: TaskEvent) throws {
        try database.execute(
            """
            INSERT INTO task_events (
              id, task_id, kind, source, message, previous_status, new_status, run_id, artifact_id, created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            binds: [
                .text(taskEvent.id),
                .text(taskEvent.taskId),
                .text(taskEvent.kind.rawValue),
                .text(taskEvent.source.rawValue),
                .text(taskEvent.message),
                .text(taskEvent.previousStatus?.rawValue),
                .text(taskEvent.newStatus?.rawValue),
                .text(taskEvent.runId),
                .text(taskEvent.artifactId),
                .text(DateCoding.string(from: taskEvent.createdAt))
            ]
        )
    }

    private func project(from row: [String: String?]) -> Project {
        let legacyCommands = JSONCoding.decodeArray(row.optional("test_commands_json"))
        let commandConfiguration = JSONCoding.decode(
            row.optional("command_config_json"),
            as: ProjectCommandConfiguration.self
        ) ?? .fromLegacyTestCommands(legacyCommands)
        return Project(
            id: row.required("id"),
            name: row.required("name"),
            type: ProjectType(rawValue: row.required("type")) ?? .generic,
            path: row.required("path"),
            defaultBranch: row.optional("default_branch") ?? "main",
            testCommands: legacyCommands,
            commandConfiguration: commandConfiguration,
            metadata: JSONCoding.decodeDictionary(row.optional("metadata_json")),
            createdAt: DateCoding.date(from: row.required("created_at")),
            updatedAt: DateCoding.date(from: row.required("updated_at"))
        )
    }

    private func codexProjectLink(from row: [String: String?]) -> CodexProjectLink {
        CodexProjectLink(
            id: row.required("id"),
            projectId: row.required("project_id"),
            workspacePath: row.required("workspace_path"),
            preferredMode: CodexExecutionMode(rawValue: row.optional("preferred_mode") ?? "") ?? .unknown,
            preferredModel: row.optional("preferred_model"),
            preferredReasoning: row.optional("preferred_reasoning"),
            createdAt: DateCoding.date(from: row.required("created_at")),
            updatedAt: DateCoding.date(from: row.required("updated_at"))
        )
    }

    private func task(from row: [String: String?]) -> FactoryTask {
        FactoryTask(
            id: row.required("id"),
            projectId: row.required("project_id"),
            title: row.required("title"),
            type: TaskType(rawValue: row.optional("type") ?? "") ?? .coding,
            status: TaskStatus.storedValue(row.optional("status")),
            priority: TaskPriority(rawValue: row.optional("priority") ?? "") ?? .normal,
            kind: FactoryTaskKind(rawValue: row.optional("kind") ?? "") ?? .task,
            triageStatus: FactoryTaskTriageStatus(rawValue: row.optional("triage_status") ?? ""),
            readiness: FactoryTaskReadiness(rawValue: row.optional("readiness") ?? "") ?? .scoped,
            priorityLabel: FactoryTaskPriorityLabel(rawValue: row.optional("priority_label") ?? ""),
            effort: FactoryTaskEffort(rawValue: row.optional("effort") ?? "") ?? .unknown,
            risk: FactoryTaskRisk(rawValue: row.optional("risk") ?? "") ?? .unknown,
            source: row.optional("source") ?? "",
            category: row.optional("category") ?? "",
            scopingNotes: row.optional("scoping_notes") ?? "",
            dependencies: row.optional("dependencies") ?? "",
            nonGoals: row.optional("non_goals") ?? "",
            suggestedSplit: row.optional("suggested_split") ?? "",
            recommendedNextAction: row.optional("recommended_next_action") ?? "",
            parentTaskId: row.optional("parent_task_id"),
            goal: row.optional("goal") ?? "",
            context: row.optional("context") ?? "",
            acceptanceCriteria: JSONCoding.decodeArray(row.optional("acceptance_criteria_json")),
            localBranch: row.optional("local_branch"),
            codexBranch: row.optional("codex_branch"),
            localWorktreePath: row.optional("local_worktree_path"),
            codexWorktreePath: row.optional("codex_worktree_path"),
            localBaseBranchCommit: row.optional("local_base_branch_commit"),
            codexBaseBranchCommit: row.optional("codex_base_branch_commit"),
            createdAt: DateCoding.date(from: row.required("created_at")),
            updatedAt: DateCoding.date(from: row.required("updated_at"))
        )
    }

    private func run(from row: [String: String?]) -> RunRecord {
        let endedAt = row.optional("ended_at").map(DateCoding.date(from:))
        return RunRecord(
            id: row.required("id"),
            projectId: row.optional("project_id") ?? "",
            taskId: row.optional("task_id"),
            runType: row.optional("run_type").flatMap(WorkflowRunKind.init(rawValue:)),
            executor: row.required("executor"),
            model: row.optional("model"),
            status: RunStatus(rawValue: row.optional("status") ?? "") ?? .failed,
            command: row.optional("command"),
            exitCode: row.optional("exit_code").flatMap(Int.init),
            promptPath: row.optional("prompt_path"),
            outputPath: row.optional("output_path"),
            summary: row.optional("summary") ?? "",
            startedAt: DateCoding.date(from: row.required("started_at")),
            endedAt: endedAt
        )
    }

    private func runnerWorkspace(from row: [String: String?]) -> RunnerWorkspace {
        RunnerWorkspace(
            id: row.required("id"),
            projectId: row.required("project_id"),
            taskId: row.required("task_id"),
            branchName: row.required("branch_name"),
            worktreePath: row.required("worktree_path"),
            baseCommit: row.optional("base_commit"),
            headCommit: row.optional("head_commit"),
            archived: row.bool("archived"),
            cleaned: row.bool("cleaned"),
            pinned: row.bool("pinned"),
            createdAt: DateCoding.date(from: row.required("created_at")),
            updatedAt: DateCoding.date(from: row.required("updated_at"))
        )
    }

    private func runnerSession(from row: [String: String?]) -> RunnerSession {
        RunnerSession(
            id: row.required("id"),
            workspaceId: row.required("workspace_id"),
            provider: RunnerProvider(rawValue: row.optional("provider") ?? "") ?? .unknown,
            mode: RunnerMode(rawValue: row.optional("mode") ?? "") ?? .coding,
            modelProfile: JSONCoding.decode(row.optional("model_profile_json"), as: ModelProfile.self),
            externalSessionId: row.optional("external_session_id"),
            status: RunnerSessionStatus(rawValue: row.optional("status") ?? "") ?? .unknown,
            transcriptPath: row.optional("transcript_path"),
            activeTurnId: row.optional("active_turn_id"),
            createdAt: DateCoding.date(from: row.required("created_at")),
            updatedAt: DateCoding.date(from: row.required("updated_at"))
        )
    }

    private func runnerExecution(from row: [String: String?]) -> RunnerExecution {
        RunnerExecution(
            id: row.required("id"),
            sessionId: row.required("session_id"),
            runReason: row.required("run_reason"),
            command: row.optional("command"),
            status: RunnerExecutionStatus(rawValue: row.optional("status") ?? "") ?? .failed,
            exitCode: row.optional("exit_code").flatMap(Int.init),
            logPath: row.optional("log_path"),
            beforeRepoState: row.optional("before_repo_state"),
            afterRepoState: row.optional("after_repo_state"),
            startedAt: DateCoding.date(from: row.required("started_at")),
            endedAt: row.optional("ended_at").map(DateCoding.date(from:))
        )
    }

    private func workerReport(from row: [String: String?]) -> WorkerReport {
        WorkerReport(
            id: row.required("id"),
            sessionId: row.required("session_id"),
            executionId: row.required("execution_id"),
            status: WorkerReportStatus(rawValue: row.optional("status") ?? "") ?? .failed,
            summary: row.optional("summary") ?? "",
            filesChanged: JSONCoding.decodeArray(row.optional("files_changed_json")),
            testsRun: JSONCoding.decodeArray(row.optional("tests_run_json")),
            risks: JSONCoding.decodeArray(row.optional("risks_json")),
            blockers: JSONCoding.decodeArray(row.optional("blockers_json")),
            nextRecommendedAction: row.optional("next_recommended_action") ?? "",
            recommendedTaskStatus: row.optional("recommended_task_status").map(TaskStatus.storedValue),
            rawText: row.optional("raw_text") ?? "",
            createdAt: DateCoding.date(from: row.required("created_at"))
        )
    }

    private func taskProposal(from row: [String: String?]) -> TaskProposal {
        TaskProposal(
            id: row.required("id"),
            sourceTaskId: row.required("source_task_id"),
            sourceSessionId: row.required("source_session_id"),
            title: row.required("title"),
            goal: row.optional("goal") ?? "",
            context: row.optional("context") ?? "",
            acceptanceCriteria: JSONCoding.decodeArray(row.optional("acceptance_criteria_json")),
            reasonDiscovered: row.optional("reason_discovered") ?? "",
            suggestedPriority: FactoryTaskPriorityLabel(rawValue: row.optional("suggested_priority") ?? "") ?? .normal,
            suggestedStage: FactoryTaskTriageStatus(rawValue: row.optional("suggested_stage") ?? "") ?? .backlog,
            sourceFiles: JSONCoding.decodeArray(row.optional("source_files_json")),
            status: TaskProposalStatus(rawValue: row.optional("status") ?? "") ?? .proposed,
            createdTaskId: row.optional("created_task_id"),
            createdAt: DateCoding.date(from: row.required("created_at"))
        )
    }

    private func runnerNotification(from row: [String: String?]) -> RunnerNotification {
        RunnerNotification(
            id: row.required("id"),
            taskId: row.required("task_id"),
            sessionId: row.optional("session_id"),
            executionId: row.optional("execution_id"),
            level: RunnerNotificationLevel(rawValue: row.optional("level") ?? "") ?? .info,
            message: row.required("message"),
            isRead: row.bool("is_read"),
            createdAt: DateCoding.date(from: row.required("created_at"))
        )
    }

    private func lifecycleSnapshot(from row: [String: String?]) -> LifecycleSnapshot {
        LifecycleSnapshot(
            id: row.required("id"),
            taskId: row.required("task_id"),
            workspaceId: row.optional("workspace_id"),
            worktreeExists: row.bool("worktree_exists"),
            branchExists: row.bool("branch_exists"),
            dirtyState: row.optional("dirty_state") ?? "unknown",
            mainMoved: row.bool("main_moved"),
            latestExecutionStatus: row.optional("latest_execution_status").flatMap(RunnerExecutionStatus.init(rawValue:)),
            latestReportStatus: row.optional("latest_report_status").flatMap(WorkerReportStatus.init(rawValue:)),
            unseenNotifications: row.optional("unseen_notifications").flatMap(Int.init) ?? 0,
            proposedTasksCount: row.optional("proposed_tasks_count").flatMap(Int.init) ?? 0,
            recommendedAction: row.optional("recommended_action") ?? "",
            evidence: JSONCoding.decodeArray(row.optional("evidence_json")),
            createdAt: DateCoding.date(from: row.required("created_at"))
        )
    }

    private func codexSessionLink(from row: [String: String?]) -> CodexSessionLink {
        CodexSessionLink(
            id: row.required("id"),
            projectId: row.required("project_id"),
            taskId: row.optional("task_id"),
            codexSessionId: row.required("codex_session_id"),
            workspacePath: row.required("workspace_path"),
            mode: CodexExecutionMode(rawValue: row.optional("mode") ?? "") ?? .unknown,
            branchName: row.optional("branch_name"),
            worktreePath: row.optional("worktree_path"),
            status: CodexSessionStatus(rawValue: row.optional("status") ?? "") ?? .unknown,
            lastSeenAt: row.optional("last_seen_at").map(DateCoding.date(from:)),
            lastSummary: row.optional("last_summary"),
            transcriptPath: row.optional("transcript_path"),
            createdAt: DateCoding.date(from: row.required("created_at")),
            updatedAt: DateCoding.date(from: row.required("updated_at"))
        )
    }

    private func artifact(from row: [String: String?]) -> Artifact {
        Artifact(
            id: row.required("id"),
            taskId: row.required("task_id"),
            runId: row.optional("run_id"),
            type: row.required("type"),
            path: row.required("path"),
            description: row.optional("description") ?? "",
            createdAt: DateCoding.date(from: row.required("created_at"))
        )
    }

    private func status(for stage: FactoryTaskTriageStatus) -> TaskStatus {
        switch stage {
        case .ready: .ready
        case .running: .building
        case .review: .readyForReview
        case .done: .readyForReview
        case .archived: .archived
        case .needsScoping, .inbox, .backlog: .backlog
        }
    }

    private func taskEvent(from row: [String: String?]) -> TaskEvent {
        TaskEvent(
            id: row.required("id"),
            taskId: row.required("task_id"),
            kind: TaskWorkflowEventKind(rawValue: row.required("kind")) ?? .statusChangedAutomatically,
            source: TaskStatusChangeSource(rawValue: row.optional("source") ?? "") ?? .automatic,
            message: row.optional("message") ?? "",
            previousStatus: row.optional("previous_status").map(TaskStatus.storedValue),
            newStatus: row.optional("new_status").map(TaskStatus.storedValue),
            runId: row.optional("run_id"),
            artifactId: row.optional("artifact_id"),
            createdAt: DateCoding.date(from: row.required("created_at"))
        )
    }
}

private extension Dictionary where Key == String, Value == String? {
    func optional(_ key: String) -> String? {
        guard let value = self[key] else { return nil }
        return value
    }

    func required(_ key: String) -> String {
        optional(key) ?? ""
    }

    func bool(_ key: String) -> Bool {
        (optional(key).flatMap(Int.init) ?? 0) != 0
    }
}
