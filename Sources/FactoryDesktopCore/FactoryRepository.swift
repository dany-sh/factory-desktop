import Foundation

public final class FactoryRepository {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func projects() throws -> [Project] {
        let rows = try database.query(
            """
            SELECT id, name, type, path, default_branch, test_commands_json, metadata_json, created_at, updated_at
            FROM projects
            ORDER BY updated_at DESC, name ASC;
            """
        )
        return rows.map(project(from:))
    }

    public func upsert(project: Project) throws {
        try database.execute(
            """
            INSERT INTO projects (id, name, type, path, default_branch, test_commands_json, metadata_json, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(path) DO UPDATE SET
              name = excluded.name,
              type = excluded.type,
              default_branch = excluded.default_branch,
              test_commands_json = excluded.test_commands_json,
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
                .text(JSONCoding.encodeDictionary(project.metadata)),
                .text(DateCoding.string(from: project.createdAt)),
                .text(DateCoding.string(from: project.updatedAt))
            ]
        )
    }

    public func deleteProject(id: String) throws {
        try database.execute("DELETE FROM projects WHERE id = ?;", binds: [.text(id)])
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

    public func runs(taskId: String) throws -> [RunRecord] {
        let rows = try database.query(
            """
            SELECT id, task_id, executor, model, status, prompt_path, output_path, summary, started_at, ended_at
            FROM runs
            WHERE task_id = ?
            ORDER BY started_at DESC;
            """,
            binds: [.text(taskId)]
        )
        return rows.map(run(from:))
    }

    public func upsert(run: RunRecord) throws {
        try database.execute(
            """
            INSERT INTO runs (id, task_id, executor, model, status, prompt_path, output_path, summary, started_at, ended_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              executor = excluded.executor,
              model = excluded.model,
              status = excluded.status,
              prompt_path = excluded.prompt_path,
              output_path = excluded.output_path,
              summary = excluded.summary,
              ended_at = excluded.ended_at;
            """,
            binds: [
                .text(run.id),
                .text(run.taskId),
                .text(run.executor),
                .text(run.model),
                .text(run.status.rawValue),
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
        Project(
            id: row.required("id"),
            name: row.required("name"),
            type: ProjectType(rawValue: row.required("type")) ?? .generic,
            path: row.required("path"),
            defaultBranch: row.optional("default_branch") ?? "main",
            testCommands: JSONCoding.decodeArray(row.optional("test_commands_json")),
            metadata: JSONCoding.decodeDictionary(row.optional("metadata_json")),
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
            taskId: row.required("task_id"),
            executor: row.required("executor"),
            model: row.optional("model"),
            status: RunStatus(rawValue: row.optional("status") ?? "") ?? .failed,
            promptPath: row.optional("prompt_path"),
            outputPath: row.optional("output_path"),
            summary: row.optional("summary") ?? "",
            startedAt: DateCoding.date(from: row.required("started_at")),
            endedAt: endedAt
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
