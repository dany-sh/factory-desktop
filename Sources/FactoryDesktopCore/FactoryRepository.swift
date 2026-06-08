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

    public func tasks(projectId: String? = nil) throws -> [FactoryTask] {
        let rows: [[String: String?]]
        if let projectId {
            rows = try database.query(
                """
                SELECT id, project_id, title, type, status, priority, goal, context, acceptance_criteria_json,
                       local_branch, codex_branch, local_worktree_path, codex_worktree_path, created_at, updated_at
                FROM tasks
                WHERE project_id = ?
                ORDER BY updated_at DESC, created_at DESC;
                """,
                binds: [.text(projectId)]
            )
        } else {
            rows = try database.query(
                """
                SELECT id, project_id, title, type, status, priority, goal, context, acceptance_criteria_json,
                       local_branch, codex_branch, local_worktree_path, codex_worktree_path, created_at, updated_at
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
              id, project_id, title, type, status, priority, goal, context, acceptance_criteria_json,
              local_branch, codex_branch, local_worktree_path, codex_worktree_path, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              project_id = excluded.project_id,
              title = excluded.title,
              type = excluded.type,
              status = excluded.status,
              priority = excluded.priority,
              goal = excluded.goal,
              context = excluded.context,
              acceptance_criteria_json = excluded.acceptance_criteria_json,
              local_branch = excluded.local_branch,
              codex_branch = excluded.codex_branch,
              local_worktree_path = excluded.local_worktree_path,
              codex_worktree_path = excluded.codex_worktree_path,
              updated_at = excluded.updated_at;
            """,
            binds: [
                .text(task.id),
                .text(task.projectId),
                .text(task.title),
                .text(task.type.rawValue),
                .text(task.status.rawValue),
                .text(task.priority.rawValue),
                .text(task.goal),
                .text(task.context),
                .text(JSONCoding.encodeArray(task.acceptanceCriteria)),
                .text(task.localBranch),
                .text(task.codexBranch),
                .text(task.localWorktreePath),
                .text(task.codexWorktreePath),
                .text(DateCoding.string(from: task.createdAt)),
                .text(DateCoding.string(from: task.updatedAt))
            ]
        )
    }

    public func deleteTask(id: String) throws {
        try database.execute("DELETE FROM tasks WHERE id = ?;", binds: [.text(id)])
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
            goal: row.optional("goal") ?? "",
            context: row.optional("context") ?? "",
            acceptanceCriteria: JSONCoding.decodeArray(row.optional("acceptance_criteria_json")),
            localBranch: row.optional("local_branch"),
            codexBranch: row.optional("codex_branch"),
            localWorktreePath: row.optional("local_worktree_path"),
            codexWorktreePath: row.optional("codex_worktree_path"),
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
}
