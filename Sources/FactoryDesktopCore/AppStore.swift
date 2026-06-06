import Combine
import Foundation

@MainActor
public final class AppStore: ObservableObject {
    @Published public private(set) var projects: [Project] = []
    @Published public private(set) var tasks: [FactoryTask] = []
    @Published public private(set) var runs: [RunRecord] = []
    @Published public private(set) var artifacts: [Artifact] = []
    @Published public var selectedProjectID: String?
    @Published public var selectedTaskID: String?
    @Published public var selectedModel: String = ModelPolicy.plannerDefault
    @Published public var gitSnapshot: GitSnapshot = GitSnapshot()
    @Published public var latestPreflightReport: PreflightReport?
    @Published public private(set) var buildInfo: BuildInfo
    @Published public var selectedRunOutput: String = ""
    @Published public var statusMessage: String = ""
    @Published public var errorMessage: String?
    @Published public var isWorking: Bool = false

    public let paths: FactoryPaths

    private var database: SQLiteDatabase?
    private var repository: FactoryRepository?
    private var commandRunner: CommandRunner
    private var gitService: GitService?
    private var ollamaClient: OllamaClient
    private var handoffService: HandoffService

    public var selectedProject: Project? {
        guard let selectedProjectID else { return projects.first }
        return projects.first { $0.id == selectedProjectID }
    }

    public var selectedTask: FactoryTask? {
        guard let selectedTaskID else {
            return selectedProject.map { project in
                tasks.first { $0.projectId == project.id }
            } ?? nil
        }
        return tasks.first { $0.id == selectedTaskID }
    }

    public var tasksForSelectedProject: [FactoryTask] {
        guard let project = selectedProject else { return [] }
        return tasks.filter { $0.projectId == project.id }
    }

    public var runsForSelectedTask: [RunRecord] {
        guard let task = selectedTask else { return [] }
        return runs.filter { $0.taskId == task.id }
    }

    public var latestPlanArtifact: Artifact? {
        latestArtifact(type: .plan)
    }

    public var latestPlanText: String {
        latestPlanArtifact.flatMap { try? String(contentsOfFile: $0.path, encoding: .utf8) } ?? ""
    }

    public var latestPlanReviewText: String {
        let review = latestArtifact(type: .codexPlanReview) ?? latestArtifact(type: .localPlanReview)
        return review.flatMap { try? String(contentsOfFile: $0.path, encoding: .utf8) } ?? ""
    }

    public init(paths: FactoryPaths = FactoryPaths()) {
        self.paths = paths
        self.buildInfo = BuildInfoService.current(launchTimestamp: Date())
        self.commandRunner = CommandRunner()
        self.ollamaClient = OllamaClient()
        self.handoffService = HandoffService(paths: paths)

        do {
            try paths.ensureBaseDirectories()
            let database = try SQLiteDatabase(url: paths.database)
            try MigrationRunner(database: database, paths: paths).migrate()
            self.database = database
            self.repository = FactoryRepository(database: database)
            self.gitService = GitService(commandRunner: commandRunner, paths: paths)
            try reload()
            statusMessage = "Ready. SQLite: \(paths.database.path)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func reload() throws {
        guard let repository else { return }
        projects = try repository.projects()
        tasks = try repository.tasks()
        if selectedProjectID == nil {
            selectedProjectID = projects.first?.id
        }
        if let selectedProjectID, selectedTaskID == nil {
            selectedTaskID = tasks.first { $0.projectId == selectedProjectID }?.id
        }
        try reloadRunsAndArtifacts()
    }

    public func reloadRunsAndArtifacts() throws {
        guard let repository else { return }
        if let selectedTask {
            runs = try repository.runs(taskId: selectedTask.id)
            artifacts = try repository.artifacts(taskId: selectedTask.id)
        } else {
            runs = []
            artifacts = []
        }
    }

    public func selectProject(_ projectID: String?) {
        selectedProjectID = projectID
        selectedTaskID = tasks.first { $0.projectId == projectID }?.id
        latestPreflightReport = nil
        Task { await refreshGitStatus() }
        do {
            try reloadRunsAndArtifacts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func selectTask(_ taskID: String?) {
        selectedTaskID = taskID
        selectedRunOutput = ""
        latestPreflightReport = nil
        Task { await refreshGitStatus() }
        do {
            try reloadRunsAndArtifacts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func registerProject(name: String, type: ProjectType, path: String, defaultBranch: String, testCommandsText: String) {
        perform {
            guard let repository = self.repository else { return }
            let url = URL(fileURLWithPath: path).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw FactoryError.invalidProjectPath(path)
            }

            let project = Project(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? url.lastPathComponent : name,
                type: type,
                path: url.path,
                defaultBranch: defaultBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "main" : defaultBranch,
                testCommands: Self.lines(from: testCommandsText),
                metadata: [:],
                updatedAt: Date()
            )
            try repository.upsert(project: project)
            try self.reload()
            self.selectedProjectID = self.projects.first { $0.path == url.path }?.id
            self.statusMessage = "Registered \(project.name)."
        }
    }

    public func registerSelfProject() {
        let root = SelfRepoLocator.sourceRoot
        registerProject(
            name: "factory-desktop",
            type: .codeRepo,
            path: root.path,
            defaultBranch: "main",
            testCommandsText: "swift test"
        )
    }

    public func createTask(title: String, type: TaskType, goal: String = "") {
        perform {
            guard let repository = self.repository, let project = self.selectedProject else {
                throw FactoryError.missingSelection
            }
            let task = FactoryTask(
                projectId: project.id,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled task" : title,
                type: type,
                status: .inbox,
                goal: goal
            )
            try repository.upsert(task: task)
            try self.reload()
            self.selectedProjectID = project.id
            self.selectedTaskID = task.id
            self.statusMessage = "Created task \(task.title)."
        }
    }

    public func saveTask(_ task: FactoryTask) {
        perform {
            guard let repository = self.repository else { return }
            var updated = task
            updated.updatedAt = Date()
            try repository.upsert(task: updated)
            try self.reload()
            self.selectedTaskID = updated.id
            self.statusMessage = "Saved task."
        }
    }

    public func deleteSelectedTask() {
        perform {
            guard let repository = self.repository, let task = self.selectedTask else {
                throw FactoryError.missingSelection
            }
            try repository.deleteTask(id: task.id)
            try self.reload()
            self.statusMessage = "Deleted task."
        }
    }

    public func refreshGitStatus() async {
        guard let project = selectedProject else { return }
        guard project.type == .codeRepo else {
            gitSnapshot = GitSnapshot(statusText: "Non-code project. Worktrees are skipped; use the artifact folder.", worktreePath: project.path)
            return
        }
        guard let gitService else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            gitSnapshot = try await gitService.snapshot(project: project, task: selectedTask)
            statusMessage = "Git status refreshed."
        } catch {
            gitSnapshot = GitSnapshot(statusText: error.localizedDescription, worktreePath: project.path)
            errorMessage = error.localizedDescription
        }
    }

    public func createWorktree(flavor: WorktreeFlavor) async {
        guard let project = selectedProject, var task = selectedTask, let repository, let gitService else {
            errorMessage = FactoryError.missingSelection.localizedDescription
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await gitService.createWorktree(project: project, task: task, flavor: flavor)
            switch flavor {
            case .local:
                task.localBranch = result.branch
                task.localWorktreePath = result.path
            case .codex:
                task.codexBranch = result.branch
                task.codexWorktreePath = result.path
            }
            task.updatedAt = Date()
            try repository.upsert(task: task)
            try reload()
            selectedTaskID = task.id
            statusMessage = "Created \(flavor.rawValue) worktree at \(result.path)."
            await refreshGitStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func runPreflightCheck() async {
        guard let project = selectedProject, let task = selectedTask, let repository, let gitService else {
            errorMessage = FactoryError.missingSelection.localizedDescription
            return
        }

        isWorking = true
        defer { isWorking = false }

        let projectTasks = tasks.filter { $0.projectId == project.id }
        let directory = paths.runDirectory(project: project, task: task)
        let url = directory.appendingPathComponent("preflight.md")

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let report = await gitService.preflightReport(project: project, tasks: projectTasks)
            try report.markdown.write(to: url, atomically: true, encoding: .utf8)
            try repository.insert(artifact: Artifact(
                taskId: task.id,
                type: .preflight,
                path: url.path,
                description: "Read-only preflight check"
            ))
            latestPreflightReport = report
            selectedRunOutput = report.markdown
            try reloadRunsAndArtifacts()
            statusMessage = "Wrote preflight check to \(url.path)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func planLocally() async {
        guard let project = selectedProject, var task = selectedTask, let repository else {
            errorMessage = FactoryError.missingSelection.localizedDescription
            return
        }
        isWorking = true
        defer { isWorking = false }

        let runID = UUID().uuidString
        let directory = paths.runDirectory(project: project, task: task)
        let promptURL = directory.appendingPathComponent("\(runID.shortID)-planner-prompt.md")
        let outputURL = directory.appendingPathComponent("\(runID.shortID)-planner-output.md")
        let planURL = directory.appendingPathComponent("plan.md")
        let prompt = plannerPrompt(project: project, task: task)
        var run = RunRecord(
            id: runID,
            taskId: task.id,
            executor: "local_ollama",
            model: selectedModel,
            status: .running,
            promptPath: promptURL.path,
            outputPath: outputURL.path,
            summary: "Planning with \(selectedModel)"
        )

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try prompt.write(to: promptURL, atomically: true, encoding: .utf8)
            task.status = .planning
            task.updatedAt = Date()
            try repository.upsert(task: task)
            try repository.upsert(run: run)
            try reload()
            selectedTaskID = task.id

            let output = try await ollamaClient.generate(
                model: selectedModel,
                prompt: prompt,
                contextTokens: ModelPolicy.effectiveContext(for: selectedModel)
            )
            try output.write(to: outputURL, atomically: true, encoding: .utf8)
            try output.write(to: planURL, atomically: true, encoding: .utf8)
            run.status = .succeeded
            run.summary = "Planner output saved."
            run.endedAt = Date()
            task.status = .planReady
            task.updatedAt = Date()
            try repository.upsert(run: run)
            try repository.upsert(task: task)
            try repository.insert(artifact: Artifact(
                taskId: task.id,
                runId: run.id,
                type: .plannerPrompt,
                path: promptURL.path,
                description: "Local planner prompt"
            ))
            try repository.insert(artifact: Artifact(
                taskId: task.id,
                runId: run.id,
                type: .plan,
                path: planURL.path,
                description: "Local planner output"
            ))
            try reload()
            selectedTaskID = task.id
            selectedRunOutput = output
            statusMessage = "Local plan completed."
        } catch {
            let output = "Planner failed: \(error.localizedDescription)"
            try? output.write(to: outputURL, atomically: true, encoding: .utf8)
            run.status = .failed
            run.summary = output
            run.endedAt = Date()
            try? repository.upsert(run: run)
            try? reload()
            selectedTaskID = task.id
            selectedRunOutput = output
            errorMessage = error.localizedDescription
        }
    }

    public func reviewPlanLocally() async {
        guard let repository, let project = selectedProject, var task = selectedTask else {
            errorMessage = FactoryError.missingSelection.localizedDescription
            return
        }
        isWorking = true
        defer { isWorking = false }

        let directory = paths.runDirectory(project: project, task: task)
        let plan = latestArtifact(type: .plan)
        let planText = plan.flatMap { try? String(contentsOfFile: $0.path, encoding: .utf8) } ?? "(No local plan artifact found.)"
        let url = directory.appendingPathComponent("local-plan-review.md")

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let prompt = planReviewPrompt(
                project: project,
                task: task,
                planPath: plan?.path ?? "missing",
                planText: planText,
                reviewer: "local reviewer"
            )
            let review = try await ollamaClient.generate(
                model: selectedModel,
                prompt: prompt,
                contextTokens: ModelPolicy.effectiveContext(for: selectedModel)
            )
            try review.write(to: url, atomically: true, encoding: .utf8)
            task.status = Self.status(for: Self.parsePlanReviewDecision(from: review))
            if task.status == .planApproved {
                try writeApprovedPlanSnapshot(project: project, task: task)
            }
            task.updatedAt = Date()
            try repository.upsert(task: task)
            try repository.insert(artifact: Artifact(
                taskId: task.id,
                type: .localPlanReview,
                path: url.path,
                description: "Local model plan review"
            ))
            try reload()
            selectedTaskID = task.id
            selectedRunOutput = review
            statusMessage = "Wrote local plan review to \(url.path)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func askCodexToReviewPlan() async {
        guard let repository, let project = selectedProject, var task = selectedTask else {
            errorMessage = FactoryError.missingSelection.localizedDescription
            return
        }

        let worktree = task.localWorktreePath ?? task.codexWorktreePath ?? project.path
        let runID = UUID().uuidString
        let directory = paths.runDirectory(project: project, task: task)
        let promptURL = directory.appendingPathComponent("codex-plan-review-prompt.md")
        let reviewURL = directory.appendingPathComponent("codex-plan-review.md")
        let logURL = directory.appendingPathComponent("\(runID.shortID)-codex-plan-review.log")
        let plan = latestArtifact(type: .plan)
        let planText = plan.flatMap { try? String(contentsOfFile: $0.path, encoding: .utf8) } ?? "(No local plan artifact found.)"
        let prompt = planReviewPrompt(
            project: project,
            task: task,
            planPath: plan?.path ?? "missing",
            planText: planText,
            reviewer: "Codex"
        )
        var run = RunRecord(
            id: runID,
            taskId: task.id,
            executor: "codex_exec",
            model: nil,
            status: .running,
            promptPath: promptURL.path,
            outputPath: logURL.path,
            summary: "Codex plan review running"
        )

        isWorking = true
        defer { isWorking = false }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try prompt.write(to: promptURL, atomically: true, encoding: .utf8)
            task.status = .planReview
            task.updatedAt = Date()
            try repository.upsert(task: task)
            try repository.upsert(run: run)
            try reload()
            selectedTaskID = task.id
            statusMessage = "Codex plan review running..."

            let result = try await commandRunner.run(CommandRequest(
                executable: "codex",
                arguments: ["exec", "-C", worktree, "-s", "read-only", "-o", reviewURL.path, "-"],
                standardInput: prompt
            ))
            try result.output.write(to: logURL, atomically: true, encoding: .utf8)
            let reviewText = (try? String(contentsOfFile: reviewURL.path, encoding: .utf8)) ?? result.output
            if !FileManager.default.fileExists(atPath: reviewURL.path) {
                try reviewText.write(to: reviewURL, atomically: true, encoding: .utf8)
            }

            run.status = result.succeeded ? .succeeded : .failed
            run.summary = result.succeeded ? "Codex plan review completed" : "Codex plan review failed"
            run.endedAt = Date()
            task.status = result.succeeded ? Self.status(for: Self.parsePlanReviewDecision(from: reviewText)) : .planReview
            if task.status == .planApproved {
                try writeApprovedPlanSnapshot(project: project, task: task)
            }
            task.updatedAt = Date()
            try repository.upsert(run: run)
            try repository.upsert(task: task)
            try repository.insert(artifact: Artifact(
                taskId: task.id,
                runId: run.id,
                type: .codexPlanReview,
                path: reviewURL.path,
                description: "Read-only Codex plan review"
            ))
            try repository.insert(artifact: Artifact(
                taskId: task.id,
                runId: run.id,
                type: .codexPlanReviewHandoff,
                path: promptURL.path,
                description: "Read-only Codex plan review prompt"
            ))
            try reload()
            selectedTaskID = task.id
            selectedRunOutput = reviewText
            statusMessage = result.succeeded ? "Codex plan review saved to \(reviewURL.path)." : "Codex plan review failed. See \(logURL.path)."
            if !result.succeeded {
                errorMessage = result.output
            }
        } catch {
            let output = error.localizedDescription
            try? output.write(to: logURL, atomically: true, encoding: .utf8)
            run.status = .failed
            run.summary = "Codex plan review failed"
            run.endedAt = Date()
            try? repository.upsert(run: run)
            try? reload()
            selectedTaskID = task.id
            selectedRunOutput = output
            errorMessage = error.localizedDescription
        }
    }

    public func approvePlan() {
        perform {
            guard let repository = self.repository, let project = self.selectedProject, var task = self.selectedTask else {
                throw FactoryError.missingSelection
            }
            let directory = self.paths.runDirectory(project: project, task: task)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let plan = self.latestArtifact(type: .plan)
            let planText = plan.flatMap { try? String(contentsOfFile: $0.path, encoding: .utf8) } ?? "(No local plan artifact found.)"
            let url = directory.appendingPathComponent("approved-plan.md")
            let markdown = """
            # Approved Plan: \(task.title)

            Approved at: \(DateCoding.string(from: Date()))
            Source plan: \(plan?.path ?? "missing")

            ## Acceptance Criteria
            \(task.acceptanceCriteria.isEmpty ? "- No explicit acceptance criteria." : task.acceptanceCriteria.map { "- \($0)" }.joined(separator: "\n"))

            ## Plan
            ```markdown
            \(planText)
            ```
            """
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            task.status = .planApproved
            task.updatedAt = Date()
            try repository.upsert(task: task)
            try repository.insert(artifact: Artifact(
                taskId: task.id,
                type: .approvedPlan,
                path: url.path,
                description: "Approved plan snapshot"
            ))
            try self.reload()
            self.selectedTaskID = task.id
            self.statusMessage = "Approved plan and wrote \(url.path)."
        }
    }

    public func buildLocallyPlaceholder() {
        perform {
            guard let repository = self.repository, let project = self.selectedProject, var task = self.selectedTask else {
                throw FactoryError.missingSelection
            }
            guard task.status == .planApproved else {
                throw FactoryError.commandFailed("Approve the plan before building locally.")
            }
            let directory = self.paths.runDirectory(project: project, task: task)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("implementation-log.md")
            let markdown = """
            # Implementation Log: \(task.title)

            Factory Desktop does not autonomously edit code yet.

            ## Manual Build Handoff
            - Worktree: \(task.localWorktreePath ?? task.codexWorktreePath ?? project.path)
            - Approved plan: \(self.latestArtifact(type: .approvedPlan)?.path ?? "missing")
            - Next step: make the implementation changes manually in the task worktree, then run tests and review the diff.
            """
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            task.status = .building
            task.updatedAt = Date()
            try repository.upsert(task: task)
            try repository.insert(artifact: Artifact(
                taskId: task.id,
                type: .implementationLog,
                path: url.path,
                description: "Manual implementation placeholder"
            ))
            try self.reload()
            self.selectedTaskID = task.id
            self.statusMessage = "Wrote implementation placeholder to \(url.path)."
        }
    }

    public func generateCodexHandoff() {
        perform {
            guard let repository = self.repository, let project = self.selectedProject, let task = self.selectedTask else {
                throw FactoryError.missingSelection
            }
            let url = try self.handoffService.codexHandoff(project: project, task: task, gitSnapshot: self.gitSnapshot)
            let artifact = Artifact(taskId: task.id, type: .implementationLog, path: url.path, description: "Codex implementation handoff")
            try repository.insert(artifact: artifact)
            try self.reloadRunsAndArtifacts()
            self.statusMessage = "Wrote Codex handoff to \(url.path)."
        }
    }

    public func sendToCodex() async {
        guard let status = selectedTask?.status, status == .planApproved || status == .escalationRecommended else {
            errorMessage = "Approve the plan or accept an escalation recommendation before sending to Codex Build."
            return
        }
        if selectedTask?.codexWorktreePath == nil {
            await createWorktree(flavor: .codex)
        }
        await refreshGitStatus()
        generateCodexHandoff()

        guard let path = selectedTask?.codexWorktreePath, let gitService else {
            errorMessage = "Create a Codex worktree first."
            return
        }
        do {
            _ = try await gitService.openTerminal(path: path)
            statusMessage = "Opened Terminal in Codex worktree. Run `codex` and use the generated handoff."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func openVSCodeForSelectedTask(preferCodex: Bool = false) async {
        guard let project = selectedProject, let gitService else { return }
        let path: String
        if project.type == .codeRepo {
            if preferCodex, let codex = selectedTask?.codexWorktreePath {
                path = codex
            } else if let local = selectedTask?.localWorktreePath {
                path = local
            } else if let codex = selectedTask?.codexWorktreePath {
                path = codex
            } else {
                errorMessage = "Create a task worktree before opening a code project."
                return
            }
        } else {
            path = paths.runDirectory(project: project, task: selectedTask ?? FactoryTask(projectId: project.id, title: "Project notes")).path
            try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        }

        do {
            _ = try await gitService.openVSCode(path: path)
            statusMessage = "Opened VS Code at \(path)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func runFirstTestCommand() async {
        guard let project = selectedProject, var task = selectedTask, let repository, let gitService else {
            errorMessage = FactoryError.missingSelection.localizedDescription
            return
        }
        guard let command = project.testCommands.first else {
            errorMessage = "No test command configured for \(project.name)."
            return
        }
        let worktreePath = task.localWorktreePath ?? task.codexWorktreePath
        guard let worktreePath else {
            errorMessage = "Create a task worktree before running tests."
            return
        }

        isWorking = true
        defer { isWorking = false }

        let runID = UUID().uuidString
        let directory = paths.runDirectory(project: project, task: task)
        let outputURL = directory.appendingPathComponent("\(runID.shortID)-test-output.txt")
        var run = RunRecord(
            id: runID,
            taskId: task.id,
            executor: "command",
            model: nil,
            status: .running,
            promptPath: nil,
            outputPath: outputURL.path,
            summary: command
        )

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            task.status = .testing
            task.updatedAt = Date()
            try repository.upsert(task: task)
            try repository.upsert(run: run)
            let result = try await gitService.runTestCommand(command, in: worktreePath)
            try result.output.write(to: outputURL, atomically: true, encoding: .utf8)
            run.status = .succeeded
            run.summary = "Passed: \(command)"
            run.endedAt = Date()
            task.status = .needsReview
            task.updatedAt = Date()
            try repository.upsert(run: run)
            try repository.upsert(task: task)
            try repository.insert(artifact: Artifact(
                taskId: task.id,
                runId: run.id,
                type: .testOutput,
                path: outputURL.path,
                description: "Test output: \(command)"
            ))
            try reload()
            selectedTaskID = task.id
            selectedRunOutput = result.output
            statusMessage = "Test command passed."
        } catch {
            let output = error.localizedDescription
            try? output.write(to: outputURL, atomically: true, encoding: .utf8)
            run.status = .failed
            run.summary = "Failed: \(command)"
            run.endedAt = Date()
            task.status = .blocked
            task.updatedAt = Date()
            try? repository.upsert(run: run)
            try? repository.upsert(task: task)
            try? repository.insert(artifact: Artifact(
                taskId: task.id,
                runId: run.id,
                type: .testOutput,
                path: outputURL.path,
                description: "Failed test output: \(command)"
            ))
            try? reload()
            selectedTaskID = task.id
            selectedRunOutput = output
            errorMessage = error.localizedDescription
        }
    }

    public func reviewDiffLocally() async {
        guard let project = selectedProject, var task = selectedTask, let repository, let gitService else {
            errorMessage = FactoryError.missingSelection.localizedDescription
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let snapshot = try await gitService.snapshot(project: project, task: task)
            guard !snapshot.changedFiles.isEmpty else {
                errorMessage = "No changed files detected to review."
                gitSnapshot = snapshot
                return
            }
            let diff = try await gitService.diff(in: snapshot.worktreePath)
            let directory = paths.runDirectory(project: project, task: task)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("local-diff-review.md")
            let markdown = """
            # Local Diff Review: \(task.title)

            ## Status
            - Worktree: \(snapshot.worktreePath)
            - Branch: \(snapshot.currentBranch ?? "unknown")
            - Changed file count: \(snapshot.changedFiles.count)

            ## Review Checklist
            - [ ] Diff matches the approved plan.
            - [ ] Acceptance criteria are covered.
            - [ ] Tests have been run or a test gap is documented.
            - [ ] No unrelated files are included.
            - [ ] Commit message can be written from the final review note.

            ## Changed Files
            \(snapshot.changedFiles.map { "- \($0)" }.joined(separator: "\n"))

            ## Diff Stat
            ```text
            \(snapshot.diffStat.isEmpty ? "(empty)" : snapshot.diffStat)
            ```

            ## Diff
            ```diff
            \(diff.output.isEmpty ? "(empty)" : diff.output)
            ```
            """
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            task.status = .readyToCommit
            task.updatedAt = Date()
            try repository.upsert(task: task)
            try repository.insert(artifact: Artifact(
                taskId: task.id,
                type: .localDiffReview,
                path: url.path,
                description: "Local diff review"
            ))
            gitSnapshot = snapshot
            try reload()
            selectedTaskID = task.id
            statusMessage = "Wrote local diff review to \(url.path)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func askCodexToReviewDiff() {
        perform {
            guard let repository = self.repository, let project = self.selectedProject, var task = self.selectedTask else {
                throw FactoryError.missingSelection
            }
            guard !self.gitSnapshot.changedFiles.isEmpty else {
                throw FactoryError.commandFailed("Refresh git status and ensure changed files exist before generating a diff review handoff.")
            }
            let url = try self.handoffService.codexDiffReviewHandoff(
                project: project,
                task: task,
                gitSnapshot: self.gitSnapshot,
                latestRun: self.runsForSelectedTask.first
            )
            task.status = .needsReview
            task.updatedAt = Date()
            try repository.upsert(task: task)
            try repository.insert(artifact: Artifact(
                taskId: task.id,
                type: .codexDiffReviewHandoff,
                path: url.path,
                description: "Read-only Codex diff review prompt"
            ))
            try self.reload()
            self.selectedTaskID = task.id
            self.statusMessage = "Wrote Codex diff review handoff to \(url.path)."
        }
    }

    public func generateReviewNote() {
        perform {
            guard let repository = self.repository, let project = self.selectedProject, var task = self.selectedTask else {
                throw FactoryError.missingSelection
            }
            let url = try self.handoffService.reviewNote(
                project: project,
                task: task,
                gitSnapshot: self.gitSnapshot,
                latestRun: self.runsForSelectedTask.first
            )
            task.status = .readyToCommit
            task.updatedAt = Date()
            try repository.upsert(task: task)
            let artifact = Artifact(taskId: task.id, type: .finalReview, path: url.path, description: "Final review note")
            try repository.insert(artifact: artifact)
            try self.reload()
            self.selectedTaskID = task.id
            self.statusMessage = "Wrote review note to \(url.path)."
        }
    }

    public func commitSelectedWorktree(message: String) async {
        guard let project = selectedProject, let task = selectedTask, let gitService else {
            errorMessage = FactoryError.missingSelection.localizedDescription
            return
        }
        guard let path = task.localWorktreePath ?? task.codexWorktreePath else {
            errorMessage = "Create a task worktree before committing."
            return
        }
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            errorMessage = "Enter a commit message first."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await gitService.commitAll(path: path, defaultBranch: project.defaultBranch, message: trimmedMessage)
            selectedRunOutput = result.output
            statusMessage = "Commit completed."
            await refreshGitStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func loadRunOutput(_ run: RunRecord) {
        guard let outputPath = run.outputPath else {
            selectedRunOutput = ""
            return
        }
        selectedRunOutput = (try? String(contentsOfFile: outputPath, encoding: .utf8)) ?? ""
    }

    public func openArtifact(_ artifact: Artifact) async {
        do {
            _ = try await commandRunner.run(CommandRequest(executable: "open", arguments: [artifact.path]))
            statusMessage = "Opened \(artifact.path)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func backupDatabaseNow() {
        perform {
            let timestamp = DateFormatter.backup.string(from: Date())
            let destination = self.paths.snapshots.appendingPathComponent("factory-manual-backup-\(timestamp).db")
            try FileManager.default.copyItem(at: self.paths.database, to: destination)
            self.statusMessage = "Backed up database to \(destination.path)."
        }
    }

    private func perform(_ body: () throws -> Void) {
        do {
            try body()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func latestArtifact(type: ArtifactType) -> Artifact? {
        artifacts.first { $0.type == type.rawValue }
    }

    public nonisolated static func parsePlanReviewDecision(from text: String) -> PlanReviewDecision {
        let normalized = text.lowercased()
        let firstLines = normalized
            .split(separator: "\n", maxSplits: 12, omittingEmptySubsequences: true)
            .prefix(12)
            .joined(separator: "\n")
        let decisionRegion = firstLines.isEmpty ? normalized : firstLines

        if decisionRegion.contains("escalate_to_codex_build") || decisionRegion.contains("escalate to codex build") {
            return .escalateToCodexBuild
        }
        if decisionRegion.contains("decision: approve") || decisionRegion.contains("recommendation: approve") {
            return .approve
        }
        if decisionRegion.contains("decision: revise") || decisionRegion.contains("recommendation: revise") {
            return .revise
        }
        if decisionRegion.contains("decision: reject") || decisionRegion.contains("recommendation: reject") || decisionRegion.contains("decision: block") {
            return .reject
        }
        return .unknown
    }

    private nonisolated static func status(for decision: PlanReviewDecision) -> TaskStatus {
        switch decision {
        case .approve:
            return .planApproved
        case .revise, .unknown:
            return .planReview
        case .reject:
            return .planRejected
        case .escalateToCodexBuild:
            return .escalationRecommended
        }
    }

    private func writeApprovedPlanSnapshot(project: Project, task: FactoryTask) throws {
        guard let repository else { throw FactoryError.missingSelection }
        let directory = paths.runDirectory(project: project, task: task)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let plan = latestArtifact(type: .plan)
        let planText = plan.flatMap { try? String(contentsOfFile: $0.path, encoding: .utf8) } ?? "(No local plan artifact found.)"
        let url = directory.appendingPathComponent("approved-plan.md")
        let markdown = approvedPlanMarkdown(task: task, planPath: plan?.path ?? "missing", planText: planText)
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        try repository.insert(artifact: Artifact(
            taskId: task.id,
            type: .approvedPlan,
            path: url.path,
            description: "Approved plan snapshot"
        ))
    }

    private func approvedPlanMarkdown(task: FactoryTask, planPath: String, planText: String) -> String {
        """
        # Approved Plan: \(task.title)

        Approved at: \(DateCoding.string(from: Date()))
        Source plan: \(planPath)

        ## Acceptance Criteria
        \(task.acceptanceCriteria.isEmpty ? "- No explicit acceptance criteria." : task.acceptanceCriteria.map { "- \($0)" }.joined(separator: "\n"))

        ## Plan
        ```markdown
        \(planText)
        ```
        """
    }

    private func planReviewPrompt(project: Project, task: FactoryTask, planPath: String, planText: String, reviewer: String) -> String {
        let acceptance = task.acceptanceCriteria.isEmpty
            ? "- Confirm the plan satisfies the task goal."
            : task.acceptanceCriteria.map { "- \($0)" }.joined(separator: "\n")
        let tests = project.testCommands.isEmpty
            ? "- No test commands configured."
            : project.testCommands.map { "- \($0)" }.joined(separator: "\n")

        return """
        You are Factory Desktop's \(reviewer). Review only. Do not edit files, run formatters, commit, merge, push, or change the worktree.

        Return a clear decision on the first non-empty line exactly as one of:
        Decision: approve
        Decision: revise
        Decision: reject
        Decision: escalate_to_codex_build

        Use approve only when the plan is ready for local execution. Use revise when the plan is close but needs edits. Use reject when it is materially wrong or unsafe. Use escalate_to_codex_build when the plan is sound but the implementation should be sent to Codex Build rather than built locally.

        Project:
        - Name: \(project.name)
        - Type: \(project.type.rawValue)
        - Source path: \(project.path)
        - Default branch: \(project.defaultBranch)
        - Test commands:
        \(tests)

        Task:
        - ID: \(task.id)
        - Title: \(task.title)
        - Status: \(task.status.rawValue)
        - Plan artifact: \(planPath)

        Goal:
        \(task.goal.isEmpty ? task.title : task.goal)

        Context:
        \(task.context.isEmpty ? "No extra context provided." : task.context)

        Acceptance criteria:
        \(acceptance)

        Plan under review:
        ```markdown
        \(planText)
        ```

        After the decision line, include:
        - Blocking issues, if any
        - Required revisions, if any
        - Acceptance coverage
        - Verification gaps
        - Residual risk
        """
    }

    private func plannerPrompt(project: Project, task: FactoryTask) -> String {
        let acceptance = task.acceptanceCriteria.isEmpty
            ? "- Define acceptance checks in your plan."
            : task.acceptanceCriteria.map { "- \($0)" }.joined(separator: "\n")
        let tests = project.testCommands.isEmpty
            ? "- No test commands configured."
            : project.testCommands.map { "- \($0)" }.joined(separator: "\n")
        let gitStatus = gitSnapshot.statusText.isEmpty ? "Not refreshed yet." : gitSnapshot.statusText

        return """
        You are Factory Desktop's local planning model.
        Generate a concise, implementation-ready plan. Do not edit files. Do not propose destructive commands.

        Model policy:
        - Use 64k context by default.
        - Do not use qwen3.5:9b above 128k.
        - Do not use granite4.1:3b above 64k.
        - Do not use 256k globally.

        Project:
        - Name: \(project.name)
        - Type: \(project.type.rawValue)
        - Path: \(project.path)
        - Default branch: \(project.defaultBranch)

        Task:
        - ID: \(task.id)
        - Title: \(task.title)
        - Type: \(task.type.rawValue)
        - Status: \(task.status.rawValue)
        - Priority: \(task.priority.rawValue)

        Goal:
        \(task.goal.isEmpty ? task.title : task.goal)

        Context:
        \(task.context.isEmpty ? "No extra context provided." : task.context)

        Acceptance criteria:
        \(acceptance)

        Test commands:
        \(tests)

        Current git status:
        ```text
        \(gitStatus)
        ```

        Output format:
        1. Understanding
        2. Proposed plan
        3. Files or artifacts likely involved
        4. Verification checklist
        5. Risks and questions
        """
    }

    private static func lines(from text: String) -> [String] {
        text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private extension DateFormatter {
    static let backup: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
