import Foundation

public struct LocalCommandRunResult: Equatable {
    public var status: WorkflowCheckStatus
    public var run: RunRecord?
    public var output: String
    public var logPath: String?

    public init(status: WorkflowCheckStatus, run: RunRecord?, output: String = "", logPath: String? = nil) {
        self.status = status
        self.run = run
        self.output = output
        self.logPath = logPath
    }
}

public final class LocalRunnerService {
    private let commandRunner: CommandRunner
    private let paths: FactoryPaths
    private let repository: FactoryRepository

    public init(commandRunner: CommandRunner, paths: FactoryPaths, repository: FactoryRepository) {
        self.commandRunner = commandRunner
        self.paths = paths
        self.repository = repository
    }

    public func runConfiguredCommand(
        project: Project,
        task: FactoryTask?,
        kind: WorkflowRunKind,
        runID: String = UUID().uuidString,
        onRunStarted: ((RunRecord) throws -> Void)? = nil
    ) async throws -> LocalCommandRunResult {
        guard let command = project.commandConfiguration.command(for: kind) else {
            return LocalCommandRunResult(status: .notConfigured, run: nil)
        }

        let startedAt = Date()
        let directory = runDirectory(project: project, task: task)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let logURL = directory.appendingPathComponent("\(runID.shortID)-\(kind.rawValue)-output.txt")
        let workingDirectory = URL(fileURLWithPath: task?.localWorktreePath ?? task?.codexWorktreePath ?? project.path)
        guard GitService.pathIsExistingDirectory(workingDirectory.path) else {
            throw FactoryError.missingWorktreePath(workingDirectory.path)
        }
        var run = RunRecord(
            id: runID,
            projectId: project.id,
            taskId: task?.id,
            runType: kind,
            executor: "local_runner",
            model: nil,
            status: .running,
            command: command,
            outputPath: logURL.path,
            summary: "\(kind.displayName): \(command)",
            startedAt: startedAt
        )

        try repository.upsert(run: run)
        try onRunStarted?(run)

        let request = try commandRequest(from: command, workingDirectory: workingDirectory)
        do {
            let result = try await commandRunner.run(request)
            let output = logText(
                command: result.command,
                workingDirectory: workingDirectory.path,
                startedAt: startedAt,
                endedAt: Date(),
                exitCode: Int(result.exitCode),
                output: result.output
            )
            try output.write(to: logURL, atomically: true, encoding: .utf8)
            run.status = result.succeeded ? .succeeded : .failed
            run.exitCode = Int(result.exitCode)
            run.summary = result.succeeded ? "Passed: \(kind.displayName)" : "Failed: \(kind.displayName)"
            run.endedAt = Date()
            try repository.upsert(run: run)
            return LocalCommandRunResult(
                status: result.succeeded ? .passed : .failed,
                run: run,
                output: output,
                logPath: logURL.path
            )
        } catch {
            let endedAt = Date()
            let output = logText(
                command: command,
                workingDirectory: workingDirectory.path,
                startedAt: startedAt,
                endedAt: endedAt,
                exitCode: nil,
                output: error.localizedDescription
            )
            try output.write(to: logURL, atomically: true, encoding: .utf8)
            run.status = .failed
            run.summary = "Failed: \(kind.displayName)"
            run.endedAt = endedAt
            try repository.upsert(run: run)
            return LocalCommandRunResult(status: .failed, run: run, output: output, logPath: logURL.path)
        }
    }

    private func runDirectory(project: Project, task: FactoryTask?) -> URL {
        if let task {
            return paths.runDirectory(project: project, task: task)
        }
        return paths.runs
            .appendingPathComponent(Slug.make(project.name), isDirectory: true)
            .appendingPathComponent("project", isDirectory: true)
    }

    private func commandRequest(from command: String, workingDirectory: URL) throws -> CommandRequest {
        let parts = GitService.splitShellLike(command)
        guard let executable = parts.first else {
            throw FactoryError.commandRequiresApproval(command)
        }
        return CommandRequest(
            executable: executable,
            arguments: Array(parts.dropFirst()),
            workingDirectory: workingDirectory
        )
    }

    private func logText(
        command: String,
        workingDirectory: String,
        startedAt: Date,
        endedAt: Date,
        exitCode: Int?,
        output: String
    ) -> String {
        """
        Command: \(command)
        Working directory: \(workingDirectory)
        Started: \(DateCoding.string(from: startedAt))
        Ended: \(DateCoding.string(from: endedAt))
        Exit code: \(exitCode.map(String.init) ?? "unavailable")

        \(output)
        """
    }
}
