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
        )
    ]
}
