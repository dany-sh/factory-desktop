import Foundation

public struct FactoryPaths: Equatable {
    public let root: URL
    public let database: URL
    public let snapshots: URL
    public let runs: URL
    public let worktrees: URL
    public let prompts: URL

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".factory")) {
        self.root = root
        self.database = root.appendingPathComponent("factory.db")
        self.snapshots = root.appendingPathComponent("snapshots")
        self.runs = root.appendingPathComponent("runs")
        self.worktrees = root.appendingPathComponent("worktrees")
        self.prompts = root.appendingPathComponent("prompts")
    }

    public func ensureBaseDirectories() throws {
        let manager = FileManager.default
        for directory in [root, snapshots, runs, worktrees, prompts] {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    public func runDirectory(project: Project, task: FactoryTask) -> URL {
        runs
            .appendingPathComponent(Slug.make(project.name), isDirectory: true)
            .appendingPathComponent(task.id.shortID, isDirectory: true)
    }

    public func artifactDirectory(project: Project, task: FactoryTask) -> URL {
        runDirectory(project: project, task: task)
            .appendingPathComponent("artifacts", isDirectory: true)
    }

    public func worktreeDirectory(project: Project, task: FactoryTask, flavor: WorktreeFlavor) -> URL {
        worktrees
            .appendingPathComponent(Slug.make(project.name), isDirectory: true)
            .appendingPathComponent("\(task.id.shortID)-\(flavor.directorySuffix)", isDirectory: true)
    }
}

public enum WorktreeFlavor: String, CaseIterable, Identifiable {
    case local
    case codex

    public var id: String { rawValue }

    public var branchPrefix: String {
        switch self {
        case .local: "factory"
        case .codex: "codex"
        }
    }

    public var directorySuffix: String {
        switch self {
        case .local: "local"
        case .codex: "codex"
        }
    }
}

public enum Slug {
    public static func make(_ value: String, maxLength: Int = 48) -> String {
        let lowered = value.lowercased()
        let scalars = lowered.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        var collapsed = String(scalars)
        while collapsed.contains("--") {
            collapsed = collapsed.replacingOccurrences(of: "--", with: "-")
        }
        collapsed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if collapsed.isEmpty {
            collapsed = "task"
        }
        if collapsed.count > maxLength {
            collapsed = String(collapsed.prefix(maxLength)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }
        return collapsed
    }
}

public extension String {
    var shortID: String {
        String(prefix(8))
    }
}

public enum DateCoding {
    public static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    public static func date(from string: String) -> Date {
        formatter.date(from: string) ?? Date()
    }
}
