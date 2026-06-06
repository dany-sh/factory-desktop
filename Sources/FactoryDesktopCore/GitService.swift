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

    public func preflightReport(project: Project, tasks: [FactoryTask]) async -> PreflightReport {
        let targets = discoverPreflightTargets(project: project, tasks: tasks)
        var reports: [PreflightTargetReport] = []
        for target in targets {
            reports.append(await inspectPreflightTarget(target, project: project))
        }
        return PreflightReport(
            projectName: project.name,
            projectPath: project.path,
            defaultBranch: project.defaultBranch,
            targets: reports
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

    public func diff(in path: String) async throws -> CommandResult {
        try await commandRunner.run(
            CommandRequest(executable: "git", arguments: ["diff"], workingDirectory: URL(fileURLWithPath: path))
        )
    }

    public func inspectWorktree(label: String, path: String) async -> TaskWorktreeSummary {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return TaskWorktreeSummary(label: label, path: path, exists: false)
        }

        let directory = URL(fileURLWithPath: path)
        do {
            let statusResult = try await commandRunner.run(CommandRequest(
                executable: "git",
                arguments: ["status", "--porcelain=v1", "--branch"],
                workingDirectory: directory
            ))
            guard statusResult.succeeded else {
                return TaskWorktreeSummary(label: label, path: path, exists: true, isClean: nil)
            }

            let summary = PreflightStatusSummary.parsePorcelainV1BranchStatus(statusResult.output)
            let headResult = try await commandRunner.run(CommandRequest(
                executable: "git",
                arguments: ["rev-parse", "--short", "HEAD"],
                workingDirectory: directory
            ))
            let headSHA = headResult.succeeded ? normalized(headResult.output) : nil
            let latestChangeAt = Self.latestChangeDate(fromStatusOutput: statusResult.output, in: directory)

            return TaskWorktreeSummary(
                label: label,
                path: path,
                exists: true,
                branch: summary.branch,
                headSHA: headSHA,
                isClean: summary.isClean,
                stagedCount: summary.stagedCount,
                unstagedCount: summary.unstagedCount,
                untrackedCount: summary.untrackedCount,
                hasImplementationChanges: !summary.isClean,
                latestChangeAt: latestChangeAt
            )
        } catch {
            return TaskWorktreeSummary(label: label, path: path, exists: true, isClean: nil)
        }
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

    private static func latestChangeDate(fromStatusOutput output: String, in directory: URL) -> Date? {
        changedPaths(fromStatusOutput: output)
            .compactMap { path in
                let url = directory.appendingPathComponent(path)
                return try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            }
            .max()
    }

    private static func changedPaths(fromStatusOutput output: String) -> [String] {
        output
            .split(separator: "\n")
            .compactMap { line -> String? in
                guard !line.hasPrefix("## ") else { return nil }
                guard line.count > 3 else { return nil }
                let value = String(line.dropFirst(3))
                if let arrowRange = value.range(of: " -> ") {
                    return String(value[arrowRange.upperBound...])
                }
                return value.isEmpty ? nil : value
            }
    }

    private func discoverPreflightTargets(project: Project, tasks: [FactoryTask]) -> [PreflightTarget] {
        var targets: [PreflightTarget] = []
        var seen: Set<String> = []

        func append(type: PreflightTargetType, path: String) {
            let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
            let key = url.path
            guard !seen.contains(key) else { return }
            seen.insert(key)
            targets.append(PreflightTarget(type: type, path: URL(fileURLWithPath: path).standardizedFileURL.path))
        }

        append(type: .canonicalRepo, path: project.path)

        for task in tasks.sorted(by: { $0.id < $1.id }) {
            if let localPath = task.localWorktreePath {
                append(type: .localWorktree, path: localPath)
            }
            if let codexPath = task.codexWorktreePath {
                append(type: .codexWorktree, path: codexPath)
            }
        }

        let factoryWorktreeRoot = paths.worktrees.appendingPathComponent(Slug.make(project.name), isDirectory: true)
        let children = (try? FileManager.default.contentsOfDirectory(
            at: factoryWorktreeRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for child in children.sorted(by: { $0.path < $1.path }) {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: child.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            append(type: .factoryWorktree, path: child.path)
        }

        return targets
    }

    private func inspectPreflightTarget(_ target: PreflightTarget, project: Project) async -> PreflightTargetReport {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            let risks: [PreflightRisk] = [.missingPath]
            return PreflightTargetReport(
                type: target.type,
                path: target.path,
                pathExists: false,
                risks: risks,
                recommendation: PreflightRecommendationMapper.recommendation(for: risks, targetType: target.type, isMerged: nil)
            )
        }

        let directory = URL(fileURLWithPath: target.path)
        do {
            let statusResult = try await commandRunner.run(CommandRequest(
                executable: "git",
                arguments: ["status", "--porcelain=v1", "--branch"],
                workingDirectory: directory
            ))
            guard statusResult.succeeded else {
                return unknownTarget(target, pathExists: true, output: statusResult.output)
            }

            let summary = PreflightStatusSummary.parsePorcelainV1BranchStatus(statusResult.output)
            let branchResult = try await commandRunner.run(CommandRequest(
                executable: "git",
                arguments: ["branch", "--show-current"],
                workingDirectory: directory
            ))
            let branch = normalized(branchResult.output) ?? summary.branch

            let headResult = try await commandRunner.run(CommandRequest(
                executable: "git",
                arguments: ["rev-parse", "--short", "HEAD"],
                workingDirectory: directory
            ))
            let headSHA = headResult.succeeded ? normalized(headResult.output) : nil
            let fullHeadResult = try await commandRunner.run(CommandRequest(
                executable: "git",
                arguments: ["rev-parse", "--verify", "HEAD"],
                workingDirectory: directory
            ))
            let fullHeadSHA = fullHeadResult.succeeded ? normalized(fullHeadResult.output) : headSHA

            var remoteTrackingExists = false
            var aheadOfRemote: Int?
            var behindRemote: Int?
            if target.type == .canonicalRepo {
                let remoteRef = "origin/\(project.defaultBranch)"
                let remoteResult = try await commandRunner.run(CommandRequest(
                    executable: "git",
                    arguments: ["rev-parse", "--verify", remoteRef],
                    workingDirectory: directory
                ))
                remoteTrackingExists = remoteResult.succeeded
                if remoteTrackingExists {
                    let countsResult = try await commandRunner.run(CommandRequest(
                        executable: "git",
                        arguments: ["rev-list", "--left-right", "--count", "\(project.defaultBranch)...\(remoteRef)"],
                        workingDirectory: directory
                    ))
                    if countsResult.succeeded, let counts = PreflightStatusSummary.parseAheadBehindCounts(countsResult.output) {
                        aheadOfRemote = counts.ahead
                        behindRemote = counts.behind
                    }
                }
            }

            let merged = await mergedToDefault(target: target, branch: branch, headSHA: fullHeadSHA, project: project, directory: directory)
            var risks = risksForTarget(
                target: target,
                project: project,
                branch: branch,
                summary: summary,
                remoteTrackingExists: remoteTrackingExists,
                aheadOfRemote: aheadOfRemote,
                merged: merged
            )
            if headSHA == nil || branch == nil {
                risks.append(.unknownGitState)
            }
            risks = Array(Set(risks)).sorted { $0.rawValue < $1.rawValue }
            let recommendation = PreflightRecommendationMapper.recommendation(for: risks, targetType: target.type, isMerged: merged)

            return PreflightTargetReport(
                type: target.type,
                path: target.path,
                pathExists: true,
                branch: branch,
                headSHA: headSHA,
                isClean: summary.isClean,
                stagedCount: summary.stagedCount,
                unstagedCount: summary.unstagedCount,
                untrackedCount: summary.untrackedCount,
                aheadOfRemote: aheadOfRemote ?? summary.ahead,
                behindRemote: behindRemote ?? summary.behind,
                remoteTrackingExists: remoteTrackingExists,
                isMergedToDefault: merged,
                risks: risks,
                recommendation: recommendation,
                statusOutput: statusResult.output
            )
        } catch {
            return unknownTarget(target, pathExists: true, output: error.localizedDescription)
        }
    }

    private func mergedToDefault(
        target: PreflightTarget,
        branch: String?,
        headSHA: String?,
        project: Project,
        directory: URL
    ) async -> Bool? {
        guard target.type != .canonicalRepo else { return nil }
        guard let branch, branch != project.defaultBranch, let headSHA else { return nil }
        do {
            let defaultResult = try await commandRunner.run(CommandRequest(
                executable: "git",
                arguments: ["rev-parse", "--verify", project.defaultBranch],
                workingDirectory: directory
            ))
            guard defaultResult.succeeded, let defaultSHA = normalized(defaultResult.output) else { return nil }
            let mergeBaseResult = try await commandRunner.run(CommandRequest(
                executable: "git",
                arguments: ["merge-base", "--is-ancestor", headSHA, defaultSHA],
                workingDirectory: directory
            ))
            return mergeBaseResult.succeeded
        } catch {
            return nil
        }
    }

    private func risksForTarget(
        target: PreflightTarget,
        project: Project,
        branch: String?,
        summary: PreflightStatusSummary,
        remoteTrackingExists: Bool,
        aheadOfRemote: Int?,
        merged: Bool?
    ) -> [PreflightRisk] {
        var risks: [PreflightRisk] = []
        if !summary.isClean {
            risks.append(.dirtyWorktree)
        }
        if summary.stagedCount > 0 || summary.unstagedCount > 0 || summary.untrackedCount > 0 {
            risks.append(.uncommittedChanges)
        }
        if target.type == .canonicalRepo {
            if branch != nil, branch != project.defaultBranch {
                risks.append(.unexpectedBranchLocation)
            }
            if remoteTrackingExists, (aheadOfRemote ?? 0) > 0 {
                risks.append(.unpushedDefaultBranchCommits)
            }
        } else {
            if branch == project.defaultBranch {
                risks.append(.unexpectedBranchLocation)
            }
            if merged == false {
                risks.append(.branchNotMerged)
            }
        }
        return risks
    }

    private func unknownTarget(_ target: PreflightTarget, pathExists: Bool, output: String) -> PreflightTargetReport {
        let risks: [PreflightRisk] = [.unknownGitState]
        return PreflightTargetReport(
            type: target.type,
            path: target.path,
            pathExists: pathExists,
            risks: risks,
            recommendation: PreflightRecommendationMapper.recommendation(for: risks, targetType: target.type, isMerged: nil),
            statusOutput: output,
            error: output
        )
    }

    private func normalized(_ output: String) -> String? {
        let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

public struct WorktreeResult: Equatable {
    public let branch: String
    public let path: String
}

private struct PreflightTarget: Equatable {
    var type: PreflightTargetType
    var path: String
}
