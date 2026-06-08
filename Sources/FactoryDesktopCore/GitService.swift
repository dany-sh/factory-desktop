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
        guard Self.pathIsExistingDirectory(worktreePath) else {
            throw FactoryError.missingWorktreePath(worktreePath)
        }
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

    public func lifecycleReport(
        project: Project,
        selectedTask: FactoryTask?,
        tasks: [FactoryTask],
        runs: [RunRecord],
        artifacts: [Artifact]
    ) async -> RepoHygieneReport {
        guard project.type == .codeRepo else {
            let environment = RunnerGitEnvironment()
            let gate = LifecyclePreflightGate(
                level: environment.hasGitOverrides ? .red : .green,
                checks: environment.hasGitOverrides
                    ? [LifecycleGateCheck(id: "runner-git-env", label: "Runner environment", level: .red, message: "Git runner environment overrides are set.")]
                    : [LifecycleGateCheck(id: "non-code", label: "Project", level: .green, message: "Non-code project; Git lifecycle scan is not required.")]
            )
            return RepoHygieneReport(
                projectId: project.id,
                projectName: project.name,
                canonicalRepoPath: project.path,
                currentBranch: nil,
                currentHEAD: nil,
                defaultBranch: project.defaultBranch,
                originDefaultBranch: nil,
                workingTreeClean: nil,
                defaultAheadOfOrigin: nil,
                defaultBehindOrigin: nil,
                localBranches: [],
                gitWorktrees: [],
                staleWorktreeMetadata: [],
                runnerEnvironment: environment,
                lifecycleItems: [],
                preflightGate: gate,
                artifactWasteItems: LifecycleClassifier.artifactWasteItems(project: project, tasks: tasks, runs: runs, artifacts: artifacts),
                hygieneEvents: ["Non-code project scan generated \(DateCoding.string(from: Date()))."]
            )
        }

        let directory = URL(fileURLWithPath: project.path)
        let environment = RunnerGitEnvironment()
        let canonicalPath = await gitValue(["rev-parse", "--show-toplevel"], in: directory) ?? project.path
        let currentBranch: String?
        if let branchFromCurrent = await gitValue(["branch", "--show-current"], in: directory) {
            currentBranch = branchFromCurrent
        } else {
            currentBranch = await gitValue(["rev-parse", "--abbrev-ref", "HEAD"], in: directory)
        }
        let currentHEAD = await gitValue(["rev-parse", "--short", "HEAD"], in: directory)
        let statusOutput = await gitOutput(["status", "--porcelain=v1", "--branch"], in: directory)
        let workingTreeClean = statusOutput.map { PreflightStatusSummary.parsePorcelainV1BranchStatus($0).isClean }
        let originDefaultBranch = await gitValue(["rev-parse", "--abbrev-ref", "origin/HEAD"], in: directory)

        var defaultAhead: Int?
        var defaultBehind: Int?
        if await gitValue(["rev-parse", "--verify", "origin/\(project.defaultBranch)"], in: directory) != nil,
           let countsOutput = await gitOutput(["rev-list", "--left-right", "--count", "\(project.defaultBranch)...origin/\(project.defaultBranch)"], in: directory),
           let counts = PreflightStatusSummary.parseAheadBehindCounts(countsOutput) {
            defaultAhead = counts.ahead
            defaultBehind = counts.behind
        }

        let prunableOutput = await gitOutput(["worktree", "prune", "--dry-run"], in: directory) ?? ""
        let prunablePaths = LifecycleParser.parsePrunableWorktreePaths(prunableOutput)
        let worktreeOutput = await gitOutput(["worktree", "list", "--porcelain"], in: directory) ?? ""
        var worktrees = LifecycleParser.parseWorktreePorcelain(worktreeOutput, prunablePaths: prunablePaths)
        for index in worktrees.indices {
            worktrees[index].isClean = await worktreeCleanState(path: worktrees[index].path)
        }

        let branchesOutput = await gitOutput(["branch", "--format=%(refname:short)|%(objectname:short)"], in: directory) ?? ""
        let mergedOutput = await gitOutput(["branch", "--merged", project.defaultBranch, "--no-color"], in: directory) ?? ""
        let mergedBranches = LifecycleParser.parseMergedBranches(mergedOutput)
        let checkedOutBranches = Set(worktrees.compactMap(\.branch))
        var branches: [GitBranchRecord] = []
        for var branch in LifecycleParser.parseBranchFormat(branchesOutput) {
            branch.isMergedToDefault = mergedBranches.contains(branch.name)
            branch.isBackupProtected = Self.isBackupProtectedBranch(branch.name)
            branch.isActiveFactoryBranch = Self.isActiveFactoryBranch(branch.name)

            if await gitValue(["rev-parse", "--verify", "origin/\(branch.name)"], in: directory) != nil,
               let countsOutput = await gitOutput(["rev-list", "--left-right", "--count", "\(branch.name)...origin/\(branch.name)"], in: directory),
               let counts = PreflightStatusSummary.parseAheadBehindCounts(countsOutput) {
                branch.aheadOfOrigin = counts.ahead
                branch.behindOrigin = counts.behind
            }

            if branch.name != project.defaultBranch {
                let cherryLog = await gitOutput(["log", "--left-right", "--cherry-pick", "--oneline", "\(project.defaultBranch)...\(branch.name)"], in: directory) ?? ""
                let diffStat = await gitOutput(["diff", "--stat", "\(project.defaultBranch)..\(branch.name)"], in: directory) ?? ""
                let defaultIsAncestor = await isAncestor(project.defaultBranch, of: branch.name, in: directory)
                switch MergeSafetyHelper.assess(cherryPickLog: cherryLog, diffStat: diffStat, defaultIsAncestorOfBranch: defaultIsAncestor) {
                case .duplicateEquivalent:
                    branch.isDuplicateEquivalent = true
                    branch.hasUniqueCommits = false
                    branch.fastForwardPossible = nil
                case .fastForwardPossible:
                    branch.isDuplicateEquivalent = false
                    branch.hasUniqueCommits = true
                    branch.fastForwardPossible = true
                case .manualReviewRequired:
                    branch.isDuplicateEquivalent = false
                    branch.hasUniqueCommits = true
                    branch.fastForwardPossible = false
                }
            }
            branches.append(branch)
        }

        let branchItems = branches.map {
            LifecycleClassifier.classifyBranch($0, defaultBranch: project.defaultBranch, checkedOutBranches: checkedOutBranches)
        }
        let worktreeItems = worktrees.map {
            LifecycleClassifier.classifyWorktree($0, defaultBranch: project.defaultBranch)
        }
        let storedTaskWorktreeItems = tasks.flatMap { task in
            TaskWorktreeDisplayMapper.displays(for: task).map { display in
                LifecycleClassifier.classifyStoredTaskWorktreeReference(task: task, display: display)
            }
        }
        let staleMetadataItems = prunablePaths.sorted().map { path in
            LifecycleItem(
                id: "metadata-\(path)",
                kind: .metadata,
                label: path,
                path: path,
                classification: .orphanedMetadata,
                state: .unknown,
                reason: "Git worktree prune dry-run reports stale metadata.",
                recommendation: .manualReviewRequired,
                allowedActions: [.refreshScan],
                blockedActions: [LifecycleBlockedAction(action: .pruneWorktreeMetadata, reason: "Prune is foundation-only until confirmation wiring is complete.")]
            )
        }

        let gate = LifecycleClassifier.gate(
            project: project,
            selectedTask: selectedTask,
            currentBranch: currentBranch,
            workingTreeClean: workingTreeClean,
            defaultAheadOfOrigin: defaultAhead,
            worktrees: worktrees,
            branches: branches,
            staleMetadata: Array(prunablePaths),
            runnerEnvironment: environment
        )

        var report = RepoHygieneReport(
            projectId: project.id,
            projectName: project.name,
            canonicalRepoPath: canonicalPath,
            currentBranch: currentBranch,
            currentHEAD: currentHEAD,
            defaultBranch: project.defaultBranch,
            originDefaultBranch: originDefaultBranch,
            workingTreeClean: workingTreeClean,
            defaultAheadOfOrigin: defaultAhead,
            defaultBehindOrigin: defaultBehind,
            localBranches: branches.sorted { $0.name < $1.name },
            gitWorktrees: worktrees.sorted { $0.path < $1.path },
            staleWorktreeMetadata: Array(prunablePaths).sorted(),
            runnerEnvironment: environment,
            lifecycleItems: (branchItems + worktreeItems + storedTaskWorktreeItems + staleMetadataItems).sorted { $0.label < $1.label },
            preflightGate: gate,
            artifactWasteItems: LifecycleClassifier.artifactWasteItems(project: project, tasks: tasks, runs: runs, artifacts: artifacts),
            hygieneEvents: []
        )
        report.hygieneEvents = LifecycleClassifier.hygieneEvents(from: report)
        return report
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
        guard Self.pathIsExistingDirectory(path) else {
            throw FactoryError.missingWorktreePath(path)
        }
        return try await commandRunner.run(
            CommandRequest(executable: "code", arguments: [path], workingDirectory: URL(fileURLWithPath: path))
        )
    }

    public func openTerminal(path: String) async throws -> CommandResult {
        guard Self.pathIsExistingDirectory(path) else {
            throw FactoryError.missingWorktreePath(path)
        }
        return try await commandRunner.run(
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
        guard Self.pathIsExistingDirectory(path) else {
            throw FactoryError.missingWorktreePath(path)
        }
        return try await commandRunner.run(
            CommandRequest(executable: "git", arguments: ["diff"], workingDirectory: URL(fileURLWithPath: path))
        )
    }

    public func lifecycleActionCommand(_ action: LifecycleSafeAction, project: Project, item: LifecycleItem?) -> CommandRequest? {
        let directory = URL(fileURLWithPath: project.path)
        switch action {
        case .refreshScan:
            return nil
        case .inspectDiff:
            if let branch = item?.branch, branch != project.defaultBranch {
                return CommandRequest(executable: "git", arguments: ["diff", "--stat", "\(project.defaultBranch)..\(branch)"], workingDirectory: directory)
            }
            if let path = item?.path {
                return CommandRequest(executable: "git", arguments: ["diff", "--stat"], workingDirectory: URL(fileURLWithPath: path))
            }
            return CommandRequest(executable: "git", arguments: ["diff", "--stat"], workingDirectory: directory)
        case .createWIPBackupCommit:
            guard let path = item?.path else { return nil }
            return CommandRequest(executable: "git", arguments: ["commit", "-m", "WIP backup before cleanup"], workingDirectory: URL(fileURLWithPath: path), manuallyApproved: true)
        case .fastForwardMergeToMain:
            guard let branch = item?.branch else { return nil }
            return CommandRequest(executable: "git", arguments: ["merge", "--ff-only", branch], workingDirectory: directory, manuallyApproved: true)
        case .pushMain:
            return CommandRequest(executable: "git", arguments: ["push", "origin", project.defaultBranch], workingDirectory: directory, manuallyApproved: true)
        case .deleteMergedBranch, .deleteDuplicateBranch:
            guard let branch = item?.branch else { return nil }
            return CommandRequest(executable: "git", arguments: ["branch", "-d", branch], workingDirectory: directory, manuallyApproved: true)
        case .removeCleanWorktree:
            guard let path = item?.path else { return nil }
            return CommandRequest(executable: "git", arguments: ["worktree", "remove", path], workingDirectory: directory, manuallyApproved: true)
        case .pruneWorktreeMetadata:
            return CommandRequest(executable: "git", arguments: ["worktree", "prune"], workingDirectory: directory, manuallyApproved: true)
        case .archiveOldArtifacts, .deleteOldArtifacts, .keepProtectBackupBranch:
            return nil
        }
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
        guard Self.pathIsExistingDirectory(path) else {
            throw FactoryError.missingWorktreePath(path)
        }
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

    private func gitOutput(_ arguments: [String], in directory: URL) async -> String? {
        do {
            let result = try await commandRunner.run(CommandRequest(executable: "git", arguments: arguments, workingDirectory: directory))
            return result.succeeded ? result.output : nil
        } catch {
            return nil
        }
    }

    private func gitValue(_ arguments: [String], in directory: URL) async -> String? {
        await gitOutput(arguments, in: directory).flatMap(normalized)
    }

    private func isAncestor(_ possibleAncestor: String, of revision: String, in directory: URL) async -> Bool? {
        do {
            let result = try await commandRunner.run(CommandRequest(
                executable: "git",
                arguments: ["merge-base", "--is-ancestor", possibleAncestor, revision],
                workingDirectory: directory
            ))
            return result.succeeded
        } catch {
            return nil
        }
    }

    private func worktreeCleanState(path: String) async -> Bool? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        guard let output = await gitOutput(["status", "--porcelain=v1", "--branch"], in: URL(fileURLWithPath: path)) else {
            return nil
        }
        return PreflightStatusSummary.parsePorcelainV1BranchStatus(output).isClean
    }

    private static func isBackupProtectedBranch(_ branch: String) -> Bool {
        let lowered = branch.lowercased()
        return lowered.contains("backup") ||
            lowered.contains("bak") ||
            lowered.contains("rescue") ||
            lowered.contains("snapshot") ||
            lowered.contains("archive")
    }

    private static func isActiveFactoryBranch(_ branch: String) -> Bool {
        branch.hasPrefix("factory/") ||
            branch.hasPrefix("codex/") ||
            branch.hasPrefix("local/")
    }

    public static func pathIsExistingDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
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
