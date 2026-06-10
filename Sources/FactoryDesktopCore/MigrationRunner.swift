import CryptoKit
import Foundation

public struct Migration {
    public let version: Int
    public let name: String
    public let sql: String

    public var checksum: String {
        let digest = SHA256.hash(data: Data(sql.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public final class MigrationRunner {
    public let database: SQLiteDatabase
    public let paths: FactoryPaths

    public init(database: SQLiteDatabase, paths: FactoryPaths) {
        self.database = database
        self.paths = paths
    }

    public func migrate() throws {
        let applied = try appliedVersions()
        let pending = Self.migrations.filter { !applied.contains($0.version) }
        guard !pending.isEmpty else { return }

        try backupDatabaseIfNeeded()

        try database.transaction {
            for migration in pending {
                try database.executeScript(migration.sql)
                try database.execute(
                    """
                    INSERT INTO schema_migrations (version, name, checksum, applied_at)
                    VALUES (?, ?, ?, ?);
                    """,
                    binds: [
                        .int(migration.version),
                        .text(migration.name),
                        .text(migration.checksum),
                        .text(DateCoding.string(from: Date()))
                    ]
                )
            }
        }
    }

    private func appliedVersions() throws -> Set<Int> {
        let tables = try database.query(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'schema_migrations';"
        )
        guard !tables.isEmpty else { return [] }
        let rows = try database.query("SELECT version FROM schema_migrations;")
        return Set(rows.compactMap { row -> Int? in
            guard let value = row["version"] ?? nil else { return nil }
            return Int(value)
        })
    }

    private func backupDatabaseIfNeeded() throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: paths.database.path) else { return }
        let attributes = try manager.attributesOfItem(atPath: paths.database.path)
        let fileSize = attributes[.size] as? NSNumber
        guard (fileSize?.intValue ?? 0) > 0 else { return }

        try manager.createDirectory(at: paths.snapshots, withIntermediateDirectories: true)
        let timestamp = Self.backupFormatter.string(from: Date())
        let destination = paths.snapshots.appendingPathComponent("factory-before-migration-\(timestamp).db")
        if !manager.fileExists(atPath: destination.path) {
            try manager.copyItem(at: paths.database, to: destination)
        }
    }

    private static let backupFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    public static let migrations: [Migration] = [
        Migration(
            version: 1,
            name: "initial_schema",
            sql: """
            CREATE TABLE IF NOT EXISTS projects (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              type TEXT NOT NULL,
              path TEXT NOT NULL UNIQUE,
              default_branch TEXT DEFAULT 'main',
              test_commands_json TEXT DEFAULT '[]',
              metadata_json TEXT DEFAULT '{}',
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS tasks (
              id TEXT PRIMARY KEY,
              project_id TEXT NOT NULL,
              title TEXT NOT NULL,
              type TEXT NOT NULL DEFAULT 'coding',
              status TEXT NOT NULL DEFAULT 'inbox',
              priority TEXT NOT NULL DEFAULT 'normal',
              goal TEXT DEFAULT '',
              context TEXT DEFAULT '',
              acceptance_criteria_json TEXT DEFAULT '[]',
              local_branch TEXT,
              codex_branch TEXT,
              local_worktree_path TEXT,
              codex_worktree_path TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS runs (
              id TEXT PRIMARY KEY,
              task_id TEXT NOT NULL,
              executor TEXT NOT NULL,
              model TEXT,
              status TEXT NOT NULL,
              prompt_path TEXT,
              output_path TEXT,
              summary TEXT DEFAULT '',
              started_at TEXT NOT NULL,
              ended_at TEXT,
              FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS artifacts (
              id TEXT PRIMARY KEY,
              task_id TEXT NOT NULL,
              run_id TEXT,
              type TEXT NOT NULL,
              path TEXT NOT NULL,
              description TEXT DEFAULT '',
              created_at TEXT NOT NULL,
              FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE,
              FOREIGN KEY(run_id) REFERENCES runs(id) ON DELETE SET NULL
            );

            CREATE TABLE IF NOT EXISTS schema_migrations (
              version INTEGER PRIMARY KEY,
              name TEXT NOT NULL,
              checksum TEXT NOT NULL,
              applied_at TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_tasks_project_id ON tasks(project_id);
            CREATE INDEX IF NOT EXISTS idx_runs_task_id ON runs(task_id);
            CREATE INDEX IF NOT EXISTS idx_artifacts_task_id ON artifacts(task_id);
            """
        ),
        Migration(
            version: 2,
            name: "task_events",
            sql: """
            CREATE TABLE IF NOT EXISTS task_events (
              id TEXT PRIMARY KEY,
              task_id TEXT NOT NULL,
              kind TEXT NOT NULL,
              source TEXT NOT NULL,
              message TEXT DEFAULT '',
              previous_status TEXT,
              new_status TEXT,
              run_id TEXT,
              artifact_id TEXT,
              created_at TEXT NOT NULL,
              FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE,
              FOREIGN KEY(run_id) REFERENCES runs(id) ON DELETE SET NULL,
              FOREIGN KEY(artifact_id) REFERENCES artifacts(id) ON DELETE SET NULL
            );

            CREATE INDEX IF NOT EXISTS idx_task_events_task_id_created_at ON task_events(task_id, created_at DESC);
            """
        ),
        Migration(
            version: 3,
            name: "local_runner_foundation",
            sql: """
            ALTER TABLE projects ADD COLUMN command_config_json TEXT DEFAULT '{}';
            ALTER TABLE runs ADD COLUMN project_id TEXT DEFAULT '';
            ALTER TABLE runs ADD COLUMN run_type TEXT;
            ALTER TABLE runs ADD COLUMN command TEXT;
            ALTER TABLE runs ADD COLUMN exit_code INTEGER;

            UPDATE runs
            SET project_id = COALESCE((
              SELECT project_id FROM tasks WHERE tasks.id = runs.task_id
            ), '')
            WHERE project_id IS NULL OR project_id = '';
            """
        ),
        Migration(
            version: 4,
            name: "codex_project_session_links",
            sql: """
            CREATE TABLE IF NOT EXISTS codex_project_links (
              id TEXT PRIMARY KEY,
              project_id TEXT NOT NULL UNIQUE,
              workspace_path TEXT NOT NULL,
              preferred_mode TEXT NOT NULL DEFAULT 'unknown',
              preferred_model TEXT,
              preferred_reasoning TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS codex_session_links (
              id TEXT PRIMARY KEY,
              project_id TEXT NOT NULL,
              task_id TEXT,
              codex_session_id TEXT NOT NULL UNIQUE,
              workspace_path TEXT NOT NULL,
              mode TEXT NOT NULL DEFAULT 'unknown',
              branch_name TEXT,
              worktree_path TEXT,
              status TEXT NOT NULL DEFAULT 'unknown',
              last_seen_at TEXT,
              last_summary TEXT,
              transcript_path TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE,
              FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE SET NULL
            );

            CREATE INDEX IF NOT EXISTS idx_codex_session_links_project_id ON codex_session_links(project_id, updated_at DESC);
            CREATE INDEX IF NOT EXISTS idx_codex_session_links_task_id ON codex_session_links(task_id, updated_at DESC);
            """
        ),
        Migration(
            version: 5,
            name: "task_base_branch_commits",
            sql: """
            ALTER TABLE tasks ADD COLUMN local_base_branch_commit TEXT;
            ALTER TABLE tasks ADD COLUMN codex_base_branch_commit TEXT;
            """
        ),
        Migration(
            version: 6,
            name: "backlog_ideas",
            sql: """
            CREATE TABLE IF NOT EXISTS backlog_ideas (
              id TEXT PRIMARY KEY,
              project_id TEXT NOT NULL,
              title TEXT NOT NULL,
              priority_level TEXT NOT NULL DEFAULT 'p2',
              category TEXT DEFAULT '',
              source TEXT DEFAULT '',
              goal TEXT DEFAULT '',
              context TEXT DEFAULT '',
              acceptance_criteria_json TEXT DEFAULT '[]',
              effort TEXT NOT NULL DEFAULT 'unknown',
              risk TEXT NOT NULL DEFAULT 'unknown',
              dependencies TEXT DEFAULT '',
              non_goals TEXT DEFAULT '',
              suggested_task_split TEXT DEFAULT '',
              recommended_next_action TEXT DEFAULT '',
              status TEXT NOT NULL DEFAULT 'idea',
              linked_task_id TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE,
              FOREIGN KEY(linked_task_id) REFERENCES tasks(id) ON DELETE SET NULL
            );

            CREATE INDEX IF NOT EXISTS idx_backlog_ideas_project_id ON backlog_ideas(project_id, updated_at DESC);
            CREATE INDEX IF NOT EXISTS idx_backlog_ideas_linked_task_id ON backlog_ideas(linked_task_id);
            """
        ),
        Migration(
            version: 7,
            name: "runs_allow_null_task_id",
            sql: """
            PRAGMA foreign_keys = OFF;

            ALTER TABLE artifacts RENAME TO artifacts_legacy;
            ALTER TABLE task_events RENAME TO task_events_legacy;
            ALTER TABLE runs RENAME TO runs_legacy;

            CREATE TABLE runs (
              id TEXT PRIMARY KEY,
              task_id TEXT,
              executor TEXT NOT NULL,
              model TEXT,
              status TEXT NOT NULL,
              prompt_path TEXT,
              output_path TEXT,
              summary TEXT DEFAULT '',
              started_at TEXT NOT NULL,
              ended_at TEXT,
              project_id TEXT DEFAULT '',
              run_type TEXT,
              command TEXT,
              exit_code INTEGER,
              FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE
            );

            CREATE TABLE artifacts (
              id TEXT PRIMARY KEY,
              task_id TEXT NOT NULL,
              run_id TEXT,
              type TEXT NOT NULL,
              path TEXT NOT NULL,
              description TEXT DEFAULT '',
              created_at TEXT NOT NULL,
              FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE,
              FOREIGN KEY(run_id) REFERENCES runs(id) ON DELETE SET NULL
            );

            CREATE TABLE task_events (
              id TEXT PRIMARY KEY,
              task_id TEXT NOT NULL,
              kind TEXT NOT NULL,
              source TEXT NOT NULL,
              message TEXT DEFAULT '',
              previous_status TEXT,
              new_status TEXT,
              run_id TEXT,
              artifact_id TEXT,
              created_at TEXT NOT NULL,
              FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE,
              FOREIGN KEY(run_id) REFERENCES runs(id) ON DELETE SET NULL,
              FOREIGN KEY(artifact_id) REFERENCES artifacts(id) ON DELETE SET NULL
            );

            INSERT INTO runs (
              id, task_id, executor, model, status, prompt_path, output_path, summary, started_at, ended_at, project_id, run_type, command, exit_code
            )
            SELECT
              id, task_id, executor, model, status, prompt_path, output_path, summary, started_at, ended_at, project_id, run_type, command, exit_code
            FROM runs_legacy;

            INSERT INTO artifacts (id, task_id, run_id, type, path, description, created_at)
            SELECT id, task_id, run_id, type, path, description, created_at
            FROM artifacts_legacy;

            INSERT INTO task_events (id, task_id, kind, source, message, previous_status, new_status, run_id, artifact_id, created_at)
            SELECT id, task_id, kind, source, message, previous_status, new_status, run_id, artifact_id, created_at
            FROM task_events_legacy;

            DROP TABLE task_events_legacy;
            DROP TABLE artifacts_legacy;
            DROP TABLE runs_legacy;

            CREATE INDEX IF NOT EXISTS idx_runs_task_id ON runs(task_id);
            CREATE INDEX IF NOT EXISTS idx_artifacts_task_id ON artifacts(task_id);
            CREATE INDEX IF NOT EXISTS idx_task_events_task_id_created_at ON task_events(task_id, created_at DESC);

            PRAGMA foreign_keys = ON;
            """
        ),
        Migration(
            version: 8,
            name: "factory_task_work_item_metadata",
            sql: """
            ALTER TABLE tasks ADD COLUMN kind TEXT NOT NULL DEFAULT 'task';
            ALTER TABLE tasks ADD COLUMN triage_status TEXT NOT NULL DEFAULT 'backlog';
            ALTER TABLE tasks ADD COLUMN readiness TEXT NOT NULL DEFAULT 'scoped';
            ALTER TABLE tasks ADD COLUMN priority_label TEXT NOT NULL DEFAULT 'normal';
            ALTER TABLE tasks ADD COLUMN effort TEXT NOT NULL DEFAULT 'unknown';
            ALTER TABLE tasks ADD COLUMN risk TEXT NOT NULL DEFAULT 'unknown';
            ALTER TABLE tasks ADD COLUMN source TEXT DEFAULT '';
            ALTER TABLE tasks ADD COLUMN category TEXT DEFAULT '';
            ALTER TABLE tasks ADD COLUMN scoping_notes TEXT DEFAULT '';
            ALTER TABLE tasks ADD COLUMN dependencies TEXT DEFAULT '';
            ALTER TABLE tasks ADD COLUMN non_goals TEXT DEFAULT '';
            ALTER TABLE tasks ADD COLUMN suggested_split TEXT DEFAULT '';
            ALTER TABLE tasks ADD COLUMN recommended_next_action TEXT DEFAULT '';
            ALTER TABLE tasks ADD COLUMN parent_task_id TEXT;

            UPDATE tasks
            SET
              triage_status = CASE
                WHEN status = 'ready' OR status = 'planning' OR status = 'plan_review' OR status = 'approved' THEN 'ready'
                WHEN status = 'building' OR status = 'testing' THEN 'running'
                WHEN status = 'needs_fixes' OR status = 'blocked' THEN 'needs_scoping'
                WHEN status = 'ready_for_review' THEN 'review'
                WHEN status = 'done' THEN 'done'
                WHEN status = 'archived' THEN 'archived'
                ELSE 'backlog'
              END,
              priority_label = CASE
                WHEN priority = 'urgent' THEN 'critical'
                WHEN priority = 'high' THEN 'high'
                WHEN priority = 'low' THEN 'low'
                ELSE 'normal'
              END;

            INSERT OR IGNORE INTO tasks (
              id, project_id, title, type, status, priority, kind, triage_status, readiness, priority_label,
              effort, risk, source, category, scoping_notes, dependencies, non_goals, suggested_split,
              recommended_next_action, goal, context, acceptance_criteria_json, created_at, updated_at
            )
            SELECT
              COALESCE(linked_task_id, id),
              project_id,
              title,
              'planning',
              CASE
                WHEN status = 'archived' THEN 'archived'
                WHEN status = 'ready_to_promote' OR status = 'promoted' THEN 'ready'
                ELSE 'backlog'
              END,
              CASE
                WHEN priority_level = 'p0' THEN 'urgent'
                WHEN priority_level = 'p1' THEN 'high'
                WHEN priority_level = 'p3' THEN 'low'
                ELSE 'normal'
              END,
              'idea',
              CASE
                WHEN status = 'archived' THEN 'archived'
                WHEN status = 'scoping' THEN 'needs_scoping'
                WHEN status = 'ready_to_promote' OR status = 'promoted' THEN 'ready'
                ELSE 'backlog'
              END,
              CASE
                WHEN status = 'ready_to_promote' OR status = 'promoted' THEN 'executable'
                WHEN status = 'scoping' THEN 'needs_scoping'
                ELSE 'raw'
              END,
              CASE
                WHEN priority_level = 'p0' THEN 'critical'
                WHEN priority_level = 'p1' THEN 'high'
                WHEN priority_level = 'p3' THEN 'low'
                ELSE 'normal'
              END,
              effort,
              risk,
              source,
              category,
              '',
              dependencies,
              non_goals,
              suggested_task_split,
              recommended_next_action,
              goal,
              context,
              acceptance_criteria_json,
              created_at,
              updated_at
            FROM backlog_ideas;

            UPDATE tasks
            SET
              kind = 'idea',
              source = COALESCE((SELECT source FROM backlog_ideas WHERE linked_task_id = tasks.id LIMIT 1), source),
              category = COALESCE((SELECT category FROM backlog_ideas WHERE linked_task_id = tasks.id LIMIT 1), category),
              effort = COALESCE((SELECT effort FROM backlog_ideas WHERE linked_task_id = tasks.id LIMIT 1), effort),
              risk = COALESCE((SELECT risk FROM backlog_ideas WHERE linked_task_id = tasks.id LIMIT 1), risk),
              dependencies = COALESCE((SELECT dependencies FROM backlog_ideas WHERE linked_task_id = tasks.id LIMIT 1), dependencies),
              non_goals = COALESCE((SELECT non_goals FROM backlog_ideas WHERE linked_task_id = tasks.id LIMIT 1), non_goals),
              suggested_split = COALESCE((SELECT suggested_task_split FROM backlog_ideas WHERE linked_task_id = tasks.id LIMIT 1), suggested_split),
              recommended_next_action = COALESCE((SELECT recommended_next_action FROM backlog_ideas WHERE linked_task_id = tasks.id LIMIT 1), recommended_next_action)
            WHERE id IN (SELECT linked_task_id FROM backlog_ideas WHERE linked_task_id IS NOT NULL);

            CREATE INDEX IF NOT EXISTS idx_tasks_project_triage ON tasks(project_id, triage_status, updated_at DESC);
            CREATE INDEX IF NOT EXISTS idx_tasks_parent_task_id ON tasks(parent_task_id);
            """
        ),
        Migration(
            version: 9,
            name: "ai_worker_orchestration",
            sql: """
            CREATE TABLE IF NOT EXISTS runner_workspaces (
              id TEXT PRIMARY KEY,
              project_id TEXT NOT NULL,
              task_id TEXT NOT NULL,
              branch_name TEXT NOT NULL,
              worktree_path TEXT NOT NULL,
              base_commit TEXT,
              head_commit TEXT,
              archived INTEGER NOT NULL DEFAULT 0,
              cleaned INTEGER NOT NULL DEFAULT 0,
              pinned INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE,
              FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS runner_sessions (
              id TEXT PRIMARY KEY,
              workspace_id TEXT NOT NULL,
              provider TEXT NOT NULL,
              mode TEXT NOT NULL,
              model_profile_json TEXT,
              external_session_id TEXT,
              status TEXT NOT NULL,
              transcript_path TEXT,
              active_turn_id TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              FOREIGN KEY(workspace_id) REFERENCES runner_workspaces(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS runner_executions (
              id TEXT PRIMARY KEY,
              session_id TEXT NOT NULL,
              run_reason TEXT NOT NULL,
              command TEXT,
              status TEXT NOT NULL,
              exit_code INTEGER,
              log_path TEXT,
              before_repo_state TEXT,
              after_repo_state TEXT,
              started_at TEXT NOT NULL,
              ended_at TEXT,
              FOREIGN KEY(session_id) REFERENCES runner_sessions(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS agent_turns (
              id TEXT PRIMARY KEY,
              session_id TEXT NOT NULL,
              role TEXT NOT NULL,
              content TEXT NOT NULL,
              created_at TEXT NOT NULL,
              FOREIGN KEY(session_id) REFERENCES runner_sessions(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS worker_reports (
              id TEXT PRIMARY KEY,
              session_id TEXT NOT NULL,
              execution_id TEXT NOT NULL,
              status TEXT NOT NULL,
              summary TEXT DEFAULT '',
              files_changed_json TEXT DEFAULT '[]',
              tests_run_json TEXT DEFAULT '[]',
              risks_json TEXT DEFAULT '[]',
              blockers_json TEXT DEFAULT '[]',
              next_recommended_action TEXT DEFAULT '',
              recommended_task_status TEXT,
              raw_text TEXT DEFAULT '',
              created_at TEXT NOT NULL,
              FOREIGN KEY(session_id) REFERENCES runner_sessions(id) ON DELETE CASCADE,
              FOREIGN KEY(execution_id) REFERENCES runner_executions(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS task_proposals (
              id TEXT PRIMARY KEY,
              source_task_id TEXT NOT NULL,
              source_session_id TEXT NOT NULL,
              title TEXT NOT NULL,
              goal TEXT DEFAULT '',
              context TEXT DEFAULT '',
              acceptance_criteria_json TEXT DEFAULT '[]',
              reason_discovered TEXT DEFAULT '',
              suggested_priority TEXT NOT NULL DEFAULT 'normal',
              suggested_stage TEXT NOT NULL DEFAULT 'backlog',
              source_files_json TEXT DEFAULT '[]',
              status TEXT NOT NULL DEFAULT 'proposed',
              created_task_id TEXT,
              created_at TEXT NOT NULL,
              FOREIGN KEY(source_task_id) REFERENCES tasks(id) ON DELETE CASCADE,
              FOREIGN KEY(source_session_id) REFERENCES runner_sessions(id) ON DELETE CASCADE,
              FOREIGN KEY(created_task_id) REFERENCES tasks(id) ON DELETE SET NULL
            );

            CREATE TABLE IF NOT EXISTS runner_notifications (
              id TEXT PRIMARY KEY,
              task_id TEXT NOT NULL,
              session_id TEXT,
              execution_id TEXT,
              level TEXT NOT NULL,
              message TEXT NOT NULL,
              is_read INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL,
              FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE,
              FOREIGN KEY(session_id) REFERENCES runner_sessions(id) ON DELETE CASCADE,
              FOREIGN KEY(execution_id) REFERENCES runner_executions(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS lifecycle_snapshots (
              id TEXT PRIMARY KEY,
              task_id TEXT NOT NULL,
              workspace_id TEXT,
              worktree_exists INTEGER NOT NULL,
              branch_exists INTEGER NOT NULL,
              dirty_state TEXT NOT NULL,
              main_moved INTEGER NOT NULL,
              latest_execution_status TEXT,
              latest_report_status TEXT,
              unseen_notifications INTEGER NOT NULL DEFAULT 0,
              proposed_tasks_count INTEGER NOT NULL DEFAULT 0,
              recommended_action TEXT NOT NULL,
              evidence_json TEXT DEFAULT '[]',
              created_at TEXT NOT NULL,
              FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE,
              FOREIGN KEY(workspace_id) REFERENCES runner_workspaces(id) ON DELETE SET NULL
            );

            CREATE INDEX IF NOT EXISTS idx_runner_workspaces_task ON runner_workspaces(task_id, updated_at DESC);
            CREATE INDEX IF NOT EXISTS idx_runner_sessions_workspace ON runner_sessions(workspace_id, updated_at DESC);
            CREATE INDEX IF NOT EXISTS idx_runner_executions_session ON runner_executions(session_id, started_at DESC);
            CREATE INDEX IF NOT EXISTS idx_worker_reports_session ON worker_reports(session_id, created_at DESC);
            CREATE INDEX IF NOT EXISTS idx_task_proposals_source_task ON task_proposals(source_task_id, status, created_at DESC);
            CREATE INDEX IF NOT EXISTS idx_runner_notifications_task ON runner_notifications(task_id, is_read, created_at DESC);
            CREATE INDEX IF NOT EXISTS idx_lifecycle_snapshots_task ON lifecycle_snapshots(task_id, created_at DESC);
            """
        ),
        Migration(
            version: 10,
            name: "worker_run_detail_reliability",
            sql: """
            ALTER TABLE worker_reports ADD COLUMN parse_status TEXT NOT NULL DEFAULT 'parsed';
            ALTER TABLE worker_reports ADD COLUMN parse_error TEXT;
            """
        ),
        Migration(
            version: 11,
            name: "worker_chat_workspace_v2",
            sql: """
            CREATE TABLE IF NOT EXISTS worker_events (
              id TEXT PRIMARY KEY,
              task_id TEXT NOT NULL,
              session_id TEXT,
              execution_id TEXT,
              parent_event_id TEXT,
              branch_key TEXT,
              kind TEXT NOT NULL,
              created_at TEXT NOT NULL,
              source TEXT NOT NULL,
              payload_json TEXT NOT NULL DEFAULT '{}',
              raw_artifact_id TEXT,
              raw_log_reference TEXT,
              FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE,
              FOREIGN KEY(session_id) REFERENCES runner_sessions(id) ON DELETE SET NULL,
              FOREIGN KEY(execution_id) REFERENCES runner_executions(id) ON DELETE SET NULL,
              FOREIGN KEY(parent_event_id) REFERENCES worker_events(id) ON DELETE SET NULL,
              FOREIGN KEY(raw_artifact_id) REFERENCES artifacts(id) ON DELETE SET NULL
            );

            CREATE TABLE IF NOT EXISTS worker_context_items (
              id TEXT PRIMARY KEY,
              task_id TEXT NOT NULL,
              session_id TEXT,
              kind TEXT NOT NULL,
              title TEXT NOT NULL,
              path TEXT,
              value TEXT NOT NULL DEFAULT '',
              content_hash TEXT NOT NULL,
              token_count INTEGER NOT NULL DEFAULT 0,
              included INTEGER NOT NULL DEFAULT 1,
              created_at TEXT NOT NULL,
              FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE,
              FOREIGN KEY(session_id) REFERENCES runner_sessions(id) ON DELETE SET NULL
            );

            CREATE TABLE IF NOT EXISTS worker_prompt_snapshots (
              id TEXT PRIMARY KEY,
              task_id TEXT NOT NULL,
              session_id TEXT,
              execution_id TEXT,
              selected_context_items_json TEXT NOT NULL DEFAULT '[]',
              context_hashes_json TEXT NOT NULL DEFAULT '[]',
              token_count INTEGER NOT NULL DEFAULT 0,
              budget INTEGER NOT NULL DEFAULT 0,
              provider TEXT NOT NULL,
              model TEXT,
              prompt_metadata_json TEXT NOT NULL DEFAULT '{}',
              prompt_text TEXT NOT NULL DEFAULT '',
              created_at TEXT NOT NULL,
              FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE,
              FOREIGN KEY(session_id) REFERENCES runner_sessions(id) ON DELETE SET NULL,
              FOREIGN KEY(execution_id) REFERENCES runner_executions(id) ON DELETE SET NULL
            );

            CREATE TABLE IF NOT EXISTS worker_evidence (
              id TEXT PRIMARY KEY,
              task_id TEXT NOT NULL,
              session_id TEXT,
              execution_id TEXT,
              kind TEXT NOT NULL,
              title TEXT NOT NULL,
              summary TEXT NOT NULL DEFAULT '',
              artifact_id TEXT,
              path TEXT,
              event_id TEXT,
              payload_json TEXT NOT NULL DEFAULT '{}',
              created_at TEXT NOT NULL,
              FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE,
              FOREIGN KEY(session_id) REFERENCES runner_sessions(id) ON DELETE SET NULL,
              FOREIGN KEY(execution_id) REFERENCES runner_executions(id) ON DELETE SET NULL,
              FOREIGN KEY(artifact_id) REFERENCES artifacts(id) ON DELETE SET NULL,
              FOREIGN KEY(event_id) REFERENCES worker_events(id) ON DELETE SET NULL
            );

            CREATE TABLE IF NOT EXISTS worker_composer_drafts (
              id TEXT PRIMARY KEY,
              task_id TEXT NOT NULL,
              session_id TEXT,
              draft_text TEXT NOT NULL DEFAULT '',
              updated_at TEXT NOT NULL,
              FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE,
              FOREIGN KEY(session_id) REFERENCES runner_sessions(id) ON DELETE SET NULL
            );

            CREATE TABLE IF NOT EXISTS worker_message_queue (
              id TEXT PRIMARY KEY,
              task_id TEXT NOT NULL,
              session_id TEXT,
              body TEXT NOT NULL,
              mentions_json TEXT NOT NULL DEFAULT '[]',
              status TEXT NOT NULL DEFAULT 'queued',
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE,
              FOREIGN KEY(session_id) REFERENCES runner_sessions(id) ON DELETE SET NULL
            );

            CREATE TABLE IF NOT EXISTS worker_tool_approvals (
              id TEXT PRIMARY KEY,
              task_id TEXT NOT NULL,
              session_id TEXT,
              execution_id TEXT,
              event_id TEXT,
              title TEXT NOT NULL,
              requested_action TEXT NOT NULL,
              status TEXT NOT NULL DEFAULT 'pending',
              payload_json TEXT NOT NULL DEFAULT '{}',
              decided_at TEXT,
              created_at TEXT NOT NULL,
              FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE,
              FOREIGN KEY(session_id) REFERENCES runner_sessions(id) ON DELETE SET NULL,
              FOREIGN KEY(execution_id) REFERENCES runner_executions(id) ON DELETE SET NULL,
              FOREIGN KEY(event_id) REFERENCES worker_events(id) ON DELETE SET NULL
            );

            CREATE INDEX IF NOT EXISTS idx_worker_events_task_created ON worker_events(task_id, created_at ASC);
            CREATE INDEX IF NOT EXISTS idx_worker_events_session_created ON worker_events(session_id, created_at ASC);
            CREATE INDEX IF NOT EXISTS idx_worker_context_items_task_created ON worker_context_items(task_id, created_at DESC);
            CREATE INDEX IF NOT EXISTS idx_worker_prompt_snapshots_task_created ON worker_prompt_snapshots(task_id, created_at DESC);
            CREATE INDEX IF NOT EXISTS idx_worker_evidence_task_created ON worker_evidence(task_id, created_at DESC);
            CREATE UNIQUE INDEX IF NOT EXISTS idx_worker_composer_drafts_task_session ON worker_composer_drafts(id);
            CREATE INDEX IF NOT EXISTS idx_worker_message_queue_task_status ON worker_message_queue(task_id, status, created_at ASC);
            CREATE INDEX IF NOT EXISTS idx_worker_tool_approvals_task_status ON worker_tool_approvals(task_id, status, created_at DESC);
            """
        )
    ]
}
