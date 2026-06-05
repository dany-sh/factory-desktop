import Foundation

public final class GitService {
    private let commandRunner: CommandRunner
    private let paths: FactoryPaths

    public init(commandRunner: CommandRunner, paths: FactoryPaths) {
        self.commandRunner = commandRunner
        self.paths = paths
    }

    public func snapshot(project: Project, task: FactoryTask?) async throws -> GitSnapshot {
        let worktreePath = preferredWorktreePath(project: project, task: task)
        let directory = URL(fileURLWithPath: worktreePath)

        let status = try await commandRunner.run(
            CommandRequest(executable: "git", arguments: ["status", "--short", "--branch"], workingDirectory: directory)
        )
        let diffStat = try await commandRunner.run(
            CommandRequest(executable: "git", arguments: ["diff", "--stat"], workingDirectory: directory)
        )

        let files = status.output
            .split(separator: "\n")
            .drop { $0.hasPrefix("##") }
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        return GitSnapshot(
            statusText: status.output,
            diffStat: diffStat.output,
            changedFiles: files,
            currentBranch: Self.branchName(fromStatusOutput: status.output),
            worktreePath: worktreePath
        )
    }

    public func createWorktree(project: Project, task: FactoryTask, flavor: WorktreeFlavor) async throws -> WorktreeResult {
        guard project.type == .codeRepo else {
            try createArtifactFolders(project: project, task: task)
            throw FactoryError.notCodeProject
        }

        let branch = branchName(for: task, flavor: flavor)
        let worktreeURL = paths.worktreeDirectory(project: project, task: task, flavor: flavor)
        try FileManager.default.createDirectory(at: worktreeURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        if !FileManager.default.fileExists(atPath: worktreeURL.path) {
            let result = try await commandRunner.run(
                CommandRequest(
                    executable: "git",
                    arguments: ["worktree", "add", "-b", branch, worktreeURL.path, project.defaultBranch],
                    workingDirectory: URL(fileURLWithPath: project.path)
                )
            )
            guard result.succeeded else {
                throw FactoryError.commandFailed(result.output)
            }
        }

        return WorktreeResult(branch: branch, path: worktreeURL.path)
    }

    public func openVSCode(path: String) async throws -> CommandResult {
        try await commandRunner.run(
            CommandRequest(executable: "code", arguments: [path], workingDirectory: URL(fileURLWithPath: path))
        )
    }

    public func openTerminal(path: String) async throws -> CommandResult {
        try await commandRunner.run(
            CommandRequest(executable: "open", arguments: ["-a", "Terminal", path], workingDirectory: URL(fileURLWithPath: path))
        )
    }

    public func runTestCommand(_ command: String, in path: String) async throws -> CommandResult {
        let parts = Self.splitShellLike(command)
        guard let executable = parts.first else {
            throw FactoryError.commandRequiresApproval(command)
        }
        let request = CommandRequest(
            executable: executable,
            arguments: Array(parts.dropFirst()),
            workingDirectory: URL(fileURLWithPath: path)
        )
        let result = try await commandRunner.run(request)
        if !result.succeeded {
            throw FactoryError.commandFailed(result.output)
        }
        return result
    }

    public func commitAll(path: String, defaultBranch: String, message: String) async throws -> CommandResult {
        let directory = URL(fileURLWithPath: path)
        let status = try await commandRunner.run(
            CommandRequest(executable: "git", arguments: ["status", "--short", "--branch"], workingDirectory: directory)
        )
        let branch = Self.branchName(fromStatusOutput: status.output) ?? ""
        let protectedBranches = Set([defaultBranch, "main", "master"].filter { !$0.isEmpty })
        if protectedBranches.contains(branch) {
            throw FactoryError.unsafeMainBranch(branch)
        }

        let add = try await commandRunner.run(
            CommandRequest(executable: "git", arguments: ["add", "-A"], workingDirectory: directory, manuallyApproved: true)
        )
        guard add.succeeded else {
            throw FactoryError.commandFailed(add.output)
        }

        let commit = try await commandRunner.run(
            CommandRequest(executable: "git", arguments: ["commit", "-m", message], workingDirectory: directory, manuallyApproved: true)
        )
        if !commit.succeeded {
            throw FactoryError.commandFailed(commit.output)
        }
        return commit
    }

    public func branchName(for task: FactoryTask, flavor: WorktreeFlavor) -> String {
        "\(flavor.branchPrefix)/\(task.id.shortID)-\(Slug.make(task.title, maxLength: 36))"
    }

    private func preferredWorktreePath(project: Project, task: FactoryTask?) -> String {
        if let task {
            if let localPath = task.localWorktreePath {
                return localPath
            }
            if let codexPath = task.codexWorktreePath {
                return codexPath
            }
        }
        return project.path
    }

    private func createArtifactFolders(project: Project, task: FactoryTask) throws {
        try FileManager.default.createDirectory(
            at: paths.artifactDirectory(project: project, task: task),
            withIntermediateDirectories: true
        )
    }

    public static func branchName(fromStatusOutput output: String) -> String? {
        guard let firstLine = output.split(separator: "\n").first else { return nil }
        guard firstLine.hasPrefix("## ") else { return nil }
        let branchPart = firstLine.dropFirst(3)
        return branchPart.split(separator: ".").first.map(String.init)
    }

    public static func splitShellLike(_ command: String) -> [String] {
        command
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}

public struct WorktreeResult: Equatable {
    public let branch: String
    public let path: String
}
