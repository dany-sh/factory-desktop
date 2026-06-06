import Combine
import Foundation

@MainActor
public final class AppStore: ObservableObject {
    @Published public private(set) var projects: [Project] = []
    @Published public private(set) var tasks: [FactoryTask] = []
    @Published public private(set) var runs: [RunRecord] = []
    @Published public private(set) var artifacts: [Artifact] = []
    @Published public private(set) var taskEvents: [TaskEvent] = []
    @Published public var selectedProjectID: String?
    @Published public var selectedTaskID: String?
    @Published public var selectedModel: String = ModelPolicy.plannerDefault
    @Published public var gitSnapshot: GitSnapshot = GitSnapshot()
    @Published public var latestPreflightReport: PreflightReport?
    @Published public private(set) var latestTaskStateReview: TaskStateReview?
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

    public var latestApprovedPlanArtifact: Artifact? {
        latestArtifact(type: .approvedPlan)
    }

    public var latestPlanText: String {
        latestPlanArtifact.flatMap { try? String(contentsOfFile: $0.path, encoding: .utf8) } ?? ""
    }

    public var latestApprovedPlanText: String {
        latestApprovedPlanArtifact.flatMap { try? String(contentsOfFile: $0.path, encoding: .utf8) } ?? ""
    }

    public var currentPlanText: String {
        latestApprovedPlanText.isEmpty ? latestPlanText : latestApprovedPlanText
    }

    public var currentPlanArtifact: Artifact? {
        latestApprovedPlanArtifact ?? latestPlanArtifact
    }

    public var latestPlanReviewText: String {
        let review = latestArtifact(type: .codexPlanReview) ?? latestArtifact(type: .localPlanReview)
        return review.flatMap { try? String(contentsOfFile: $0.path, encoding: .utf8) } ?? ""
    }

    public var latestTaskStateReviewArtifact: Artifact? {
        latestArtifact(type: .taskStateReview)
    }

    public var latestTaskStateReviewText: String {
        latestTaskStateReviewArtifact.flatMap { try? String(contentsOfFile: $0.path, encoding: .utf8) } ?? ""
    }

    public var latestTestOutputArtifact: Artifact? {
        latestArtifact(type: .testOutput)
    }

    public var latestTestOutputText: String {
        latestTestOutputArtifact.flatMap { try? String(contentsOfFile: $0.path, encoding: .utf8) } ?? ""
    }

    public var latestDiffReviewArtifact: Artifact? {
        latestArtifact(type: .finalReview) ?? latestArtifact(type: .localDiffReview)
    }

    public var latestDiffReviewText: String {
        latestDiffReviewArtifact.flatMap { try? String(contentsOfFile: $0.path, encoding: .utf8) } ?? ""
    }

    public var artifactDisplayGroups: ArtifactDisplayGroups {
        ArtifactGrouping.group(artifacts)
    }

    public var taskWorkflowHealth: TaskWorkflowHealth {
        TaskWorkflowHealthBuilder.build(
            task: selectedTask,
            review: latestTaskStateReview,
            artifacts: artifacts,
            gitSnapshot: gitSnapshot
        )
    }

    public var workflowCheckSummaries: [WorkflowCheckSummary] {
        WorkflowCheckSummariesBuilder.build(
            project: selectedProject,
            runs: runsForSelectedTask,
            artifacts: artifacts
        )
    }

    public var selectedTaskWorktreeDisplays: [TaskWorktreeDisplay] {
        selectedTask.map(TaskWorktreeDisplayMapper.displays(for:)) ?? []
    }

    public var canPlanSelectedTaskLocally: Bool {
        guard let project = selectedProject, let task = selectedTask else { return false }
        return project.type != .codeRepo || hasExistingTaskWorktree(task)
    }

    public var selectedTaskWorktreeWarning: String? {
        guard let project = selectedProject, let task = selectedTask else { return nil }
        guard project.type == .codeRepo, !hasExistingTaskWorktree(task) else { return nil }
        return "Create a task worktree before planning this code task."
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
            taskEvents = try repository.taskEvents(taskId: selectedTask.id)
        } else {
            runs = []
            artifacts = []
            taskEvents = []
        }
    }

    public func selectProject(_ projectID: String?) {
        selectedProjectID = projectID
        selectedTaskID = tasks.first { $0.projectId == projectID }?.id
        latestPreflightReport = nil
        latestTaskStateReview = nil
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
        latestTaskStateReview = nil
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
                status: .backlog,
                goal: goal
            )
            try repository.upsert(task: task)
            try repository.insert(taskEvent: TaskEvent(
                taskId: task.id,
                kind: .statusChangedManually,
                source: .manual,
                message: "Task created.",
                previousStatus: nil,
                newStatus: task.status
            ))
            try self.reload()
            self.selectedProjectID = project.id
            self.selectedTaskID = task.id
            self.statusMessage = "Created task \(task.title)."
        }
    }

    public func saveTask(_ task: FactoryTask) {
        perform {
            guard let repository = self.repository else { return }
            let previousStatus = self.tasks.first { $0.id == task.id }?.status
            var updated = task
            updated.updatedAt = Date()
            try repository.upsert(task: updated)
            if let previousStatus, previousStatus != updated.status {
                try repository.insert(taskEvent: TaskEvent(
                    taskId: updated.id,
                    kind: .statusChangedManually,
                    source: .manual,
                    message: "Manual status changed to \(updated.status.displayName).",
                    previousStatus: previousStatus,
                    newStatus: updated.status
                ))
            }
            try self.reload()
            self.selectedTaskID = updated.id
            self.statusMessage = "Saved task."
        }
    }

    public func updateSelectedTaskStatus(_ status: TaskStatus) {
        perform {
            guard let task = self.selectedTask else {
                throw FactoryError.missingSelection
            }
            try self.updateStatus(
                for: task,
                to: status,
                source: .manual,
                eventKind: .statusChangedManually,
                message: "Manual status changed to \(status.displayName)."
            )
            self.statusMessage = "Task status changed to \(status.displayName)."
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
            statusMessage = "Created \(flavor == .local ? "task" : "alternate") worktree at \(result.path)."
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
            var markdown = report.markdown
            if project.type == .codeRepo && !hasExistingTaskWorktree(task) {
                markdown += "\n## Selected Task Worktree\n\nNo task worktree exists for the selected coding task. Create a task worktree before planning or implementing this task.\n"
            }
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            try repository.insert(artifact: Artifact(
                taskId: task.id,
                type: .preflight,
                path: url.path,
                description: "Read-only preflight check"
            ))
            latestPreflightReport = report
            selectedRunOutput = markdown
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
        guard project.type != .codeRepo || hasExistingTaskWorktree(task) else {
            errorMessage = "Create a task worktree before planning this code task."
            statusMessage = "Create Task Worktree is the next safe action for this code task."
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
            try updateStatus(
                for: &task,
                to: .planning,
                source: .automatic,
                eventKind: .statusChangedAutomatically,
                runId: run.id,
                message: "Planning run started.",
                repository: repository
            )
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
            try repository.upsert(run: run)
            let plannerPromptArtifact = Artifact(
                taskId: task.id,
                runId: run.id,
                type: .plannerPrompt,
                path: promptURL.path,
                description: "Local planner prompt"
            )
            try repository.insert(artifact: plannerPromptArtifact)
            let planArtifact = Artifact(
                taskId: task.id,
                runId: run.id,
                type: .plan,
                path: planURL.path,
                description: "Local planner output"
            )
            try repository.insert(artifact: planArtifact)
            try applyWorkflowEvent(
                .planGenerated,
                to: &task,
                runId: run.id,
                artifactId: planArtifact.id,
                message: "Plan generated and ready for review."
            )
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
            let decision = Self.parsePlanReviewDecision(from: review)
            let nextStatus = Self.status(for: decision)
            try updateStatus(
                for: &task,
                to: nextStatus,
                source: .automatic,
                eventKind: decision == .approve ? .planApproved : .statusChangedAutomatically,
                message: "Local plan review decision: \(decision.rawValue).",
                repository: repository
            )
            if task.status == .approved {
                try writeApprovedPlanSnapshot(project: project, task: task)
            }
            let artifact = Artifact(
                taskId: task.id,
                type: .localPlanReview,
                path: url.path,
                description: "Local model plan review"
            )
            try repository.insert(artifact: artifact)
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
            try updateStatus(
                for: &task,
                to: .planReview,
                source: .automatic,
                eventKind: .statusChangedAutomatically,
                runId: run.id,
                message: "Codex plan review started.",
                repository: repository
            )
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
            let decision = Self.parsePlanReviewDecision(from: reviewText)
            let nextStatus = result.succeeded ? Self.status(for: decision) : .planReview
            try updateStatus(
                for: &task,
                to: nextStatus,
                source: .automatic,
                eventKind: decision == .approve ? .planApproved : .statusChangedAutomatically,
                runId: run.id,
                message: result.succeeded ? "Codex plan review decision: \(decision.rawValue)." : "Codex plan review failed.",
                repository: repository
            )
            if task.status == .approved {
                try writeApprovedPlanSnapshot(project: project, task: task)
            }
            try repository.upsert(run: run)
            let reviewArtifact = Artifact(
                taskId: task.id,
                runId: run.id,
                type: .codexPlanReview,
                path: reviewURL.path,
                description: "Read-only Codex plan review"
            )
            try repository.insert(artifact: reviewArtifact)
            let promptArtifact = Artifact(
                taskId: task.id,
                runId: run.id,
                type: .codexPlanReviewHandoff,
                path: promptURL.path,
                description: "Read-only Codex plan review prompt"
            )
            try repository.insert(artifact: promptArtifact)
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

    public func generateCodexPlanReviewHandoff() {
        perform {
            guard let repository = self.repository, let project = self.selectedProject, let task = self.selectedTask else {
                throw FactoryError.missingSelection
            }
            let url = try self.handoffService.codexPlanReviewHandoff(
                project: project,
                task: task,
                latestPlan: self.latestPlanArtifact
            )
            try repository.insert(artifact: Artifact(
                taskId: task.id,
                type: .codexPlanReviewHandoff,
                path: url.path,
                description: "Read-only Codex plan review handoff"
            ))
            try self.reloadRunsAndArtifacts()
            self.statusMessage = "Wrote Codex plan review handoff to \(url.path)."
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
            let artifact = Artifact(
                taskId: task.id,
                type: .approvedPlan,
                path: url.path,
                description: "Approved plan snapshot"
            )
            try repository.insert(artifact: artifact)
            try self.applyWorkflowEvent(
                .planApproved,
                to: &task,
                artifactId: artifact.id,
                message: "Plan approved manually."
            )
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
            guard task.status == .approved else {
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
            let artifact = Artifact(
                taskId: task.id,
                type: .implementationLog,
                path: url.path,
                description: "Manual implementation placeholder"
            )
            try repository.insert(artifact: artifact)
            try self.applyWorkflowEvent(
                .buildStarted,
                to: &task,
                artifactId: artifact.id,
                message: "Manual build handoff placeholder created."
            )
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
        guard let status = selectedTask?.status, status == .approved else {
            errorMessage = "Approve the plan or accept an escalation recommendation before sending to Codex Build."
            return
        }
        if selectedTask?.codexWorktreePath == nil {
            await createWorktree(flavor: .codex)
        }
        await refreshGitStatus()
        generateCodexHandoff()

        guard let path = selectedTask?.codexWorktreePath, let gitService else {
            errorMessage = "Create an alternate worktree first."
            return
        }
        do {
            _ = try await gitService.openTerminal(path: path)
            statusMessage = "Opened Terminal in the alternate worktree. Run `codex` and use the generated handoff."
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
            try applyWorkflowEvent(
                .testsStarted,
                to: &task,
                runId: run.id,
                message: "Test command started: \(command)."
            )
            try repository.upsert(run: run)
            let result = try await gitService.runTestCommand(command, in: worktreePath)
            try result.output.write(to: outputURL, atomically: true, encoding: .utf8)
            run.status = .succeeded
            run.summary = "Passed: \(command)"
            run.endedAt = Date()
            try repository.upsert(run: run)
            let artifact = Artifact(
                taskId: task.id,
                runId: run.id,
                type: .testOutput,
                path: outputURL.path,
                description: "Test output: \(command)"
            )
            try repository.insert(artifact: artifact)
            try applyWorkflowEvent(
                .testsFinished,
                to: &task,
                runId: run.id,
                artifactId: artifact.id,
                message: "Test command passed: \(command).",
                testsPassed: true,
                diffExists: !gitSnapshot.changedFiles.isEmpty
            )
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
            try? repository.upsert(run: run)
            let artifact = Artifact(
                taskId: task.id,
                runId: run.id,
                type: .testOutput,
                path: outputURL.path,
                description: "Failed test output: \(command)"
            )
            try? repository.insert(artifact: artifact)
            try? applyWorkflowEvent(
                .testsFailed,
                to: &task,
                runId: run.id,
                artifactId: artifact.id,
                message: "Test command failed: \(command).",
                testsPassed: false
            )
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
            let artifact = Artifact(
                taskId: task.id,
                type: .localDiffReview,
                path: url.path,
                description: "Local diff review"
            )
            try repository.insert(artifact: artifact)
            try applyWorkflowEvent(
                .diffReviewed,
                to: &task,
                artifactId: artifact.id,
                message: "Local diff review created."
            )
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
            let artifact = Artifact(
                taskId: task.id,
                type: .codexDiffReviewHandoff,
                path: url.path,
                description: "Read-only Codex diff review prompt"
            )
            try repository.insert(artifact: artifact)
            try self.applyWorkflowEvent(
                .statusChangedAutomatically,
                to: &task,
                artifactId: artifact.id,
                message: "Codex diff review handoff generated."
            )
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
            let artifact = Artifact(taskId: task.id, type: .finalReview, path: url.path, description: "Final review note")
            try repository.insert(artifact: artifact)
            try self.applyWorkflowEvent(
                .diffReviewed,
                to: &task,
                artifactId: artifact.id,
                message: "Final review note created."
            )
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

    public func reviewTaskState() async {
        guard let repository, let project = selectedProject, let task = selectedTask else {
            errorMessage = FactoryError.missingSelection.localizedDescription
            return
        }

        isWorking = true
        defer { isWorking = false }

        do {
            let artifactSummaries = taskStateArtifactSummaries()
            let taskWorktreeSummaries = await taskStateWorktreeSummaries(task: task)
            let canonicalSummary = await canonicalWorktreeSummary(project: project)
            let worktreeSummaries = ([canonicalSummary] + taskWorktreeSummaries).compactMap { $0 }
            let missingArtifacts = artifactSummaries
                .filter { !$0.exists }
                .map { "Missing artifact file for \($0.type.displayName): \($0.path)" }
            let missingWorktrees = taskWorktreeSummaries
                .filter { !$0.exists }
                .map { "Missing \($0.label.lowercased()) path: \($0.path)" }
            var warningIssues = missingArtifacts + missingWorktrees

            let hasPlan = artifactSummaries.contains { $0.type == .plan && $0.exists }
            let hasRawPlanReview = artifactSummaries.contains {
                ($0.type == .localPlanReview || $0.type == .codexPlanReview) && $0.exists
            }
            let hasApprovedPlan = artifactSummaries.contains { $0.type == .approvedPlan && $0.exists }
            let hasPlanReview = hasRawPlanReview || hasApprovedPlan
            let latestDecision = hasApprovedPlan ? nil : latestPlanReviewDecision(from: artifactSummaries)
            let hasPreflight = artifactSummaries.contains { $0.type == .preflight && $0.exists }
            let latestPreflight = latestExistingArtifact(type: .preflight)
            let latestTestOutput = latestExistingArtifact(type: .testOutput)
            let hasStalePreflight = preflightIsStale(preflight: latestPreflight, taskWorktrees: taskWorktreeSummaries, latestTestOutput: latestTestOutput)
            let canonicalDirty = canonicalSummary?.hasImplementationChanges == true
            let hasRiskyPreflight = canonicalDirty
            let hasImplementationChanges = taskWorktreeSummaries.contains { $0.exists && $0.hasImplementationChanges }
            let hasTestOutput = latestTestOutput != nil
            let hasPassingTestOutput = latestTestOutput.map { testOutputPassed($0) } ?? false
            let hasDiffReview = artifactSummaries.contains {
                ($0.type == .localDiffReview || $0.type == .finalReview) && $0.exists
            }
            let hasExistingWorktree = taskWorktreeSummaries.contains { $0.exists }
            let appearsMerged = task.status == .done || latestPreflightSuggestsArchive()
            if hasStalePreflight {
                warningIssues.append("Latest preflight is stale relative to newer implementation changes or test output.")
            }
            if hasPreflight, latestPreflightArtifactHasRisk(), !canonicalDirty {
                warningIssues.append("Preflight reports non-canonical or stale worktree risk; active task worktree changes are not blockers.")
            }
            let blockingIssues = hasRiskyPreflight
                ? ["Canonical repo has dirty or risky Git state."]
                : []

            let input = TaskStateRecommendationInput(
                taskType: task.type,
                status: task.status,
                hasExistingWorktree: hasExistingWorktree,
                hasPreflight: hasPreflight,
                hasRiskyPreflight: hasRiskyPreflight,
                hasStalePreflight: hasStalePreflight,
                hasPlan: hasPlan,
                hasPlanReview: hasPlanReview,
                latestPlanDecision: latestDecision,
                hasApprovedPlan: hasApprovedPlan,
                hasImplementationChanges: hasImplementationChanges,
                hasTestOutput: hasTestOutput,
                hasPassingTestOutput: hasPassingTestOutput,
                hasDiffReview: hasDiffReview,
                appearsMerged: appearsMerged
            )
            let recommendation = TaskStateRecommendationEvaluator.recommend(input)

            var review = TaskStateReview(
                projectId: project.id,
                taskId: task.id,
                status: task.status,
                summary: recommendation.1,
                latestArtifacts: artifactSummaries,
                worktreeSummaries: worktreeSummaries,
                latestPlanDecision: latestDecision,
                hasPlan: hasPlan,
                hasPlanReview: hasPlanReview,
                hasApprovedPlan: hasApprovedPlan,
                hasPreflight: hasPreflight,
                hasRiskyPreflight: hasRiskyPreflight,
                hasImplementationChanges: hasImplementationChanges,
                hasTestOutput: hasTestOutput,
                hasPassingTestOutput: hasPassingTestOutput,
                hasDiffReview: hasDiffReview,
                hasStalePreflight: hasStalePreflight,
                blockingIssues: blockingIssues,
                warningIssues: warningIssues,
                recommendedAction: recommendation.0
            )
            review.markdown = taskStateReviewMarkdown(project: project, task: task, review: review)

            let directory = paths.runDirectory(project: project, task: task)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("task-state-review.md")
            try review.markdown.write(to: url, atomically: true, encoding: .utf8)
            try repository.insert(artifact: Artifact(
                taskId: task.id,
                type: .taskStateReview,
                path: url.path,
                description: "Task state review and next-action recommendation"
            ))
            latestTaskStateReview = review
            selectedRunOutput = review.markdown
            try reloadRunsAndArtifacts()
            statusMessage = "Wrote task state review to \(url.path)."
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

    private func applyWorkflowEvent(
        _ eventKind: TaskWorkflowEventKind,
        to task: inout FactoryTask,
        runId: String? = nil,
        artifactId: String? = nil,
        message: String = "",
        testsPassed: Bool? = nil,
        diffExists: Bool? = nil
    ) throws {
        guard let repository else { throw FactoryError.missingSelection }
        let resolvedDiffExists = diffExists ?? !gitSnapshot.changedFiles.isEmpty
        let nextStatus = TaskStatusTransition.status(
            after: eventKind,
            current: task.status,
            testsPassed: testsPassed,
            diffExists: resolvedDiffExists
        )
        try updateStatus(
            for: &task,
            to: nextStatus,
            source: .automatic,
            eventKind: eventKind,
            runId: runId,
            artifactId: artifactId,
            message: message.isEmpty ? eventKind.displayName : message,
            repository: repository
        )
    }

    private func updateStatus(
        for task: FactoryTask,
        to status: TaskStatus,
        source: TaskStatusChangeSource,
        eventKind: TaskWorkflowEventKind,
        runId: String? = nil,
        artifactId: String? = nil,
        message: String
    ) throws {
        var updated = task
        try updateStatus(
            for: &updated,
            to: status,
            source: source,
            eventKind: eventKind,
            runId: runId,
            artifactId: artifactId,
            message: message,
            repository: repository
        )
        try reload()
        selectedTaskID = updated.id
    }

    private func updateStatus(
        for task: inout FactoryTask,
        to status: TaskStatus?,
        source: TaskStatusChangeSource,
        eventKind: TaskWorkflowEventKind,
        runId: String? = nil,
        artifactId: String? = nil,
        message: String,
        repository: FactoryRepository?
    ) throws {
        guard let repository else { throw FactoryError.missingSelection }
        let previousStatus = task.status
        if let status {
            task.status = status
        }
        task.updatedAt = Date()
        try repository.upsert(task: task)
        try repository.insert(taskEvent: TaskEvent(
            taskId: task.id,
            kind: eventKind,
            source: source,
            message: message,
            previousStatus: previousStatus,
            newStatus: status ?? task.status,
            runId: runId,
            artifactId: artifactId
        ))
    }

    private func latestArtifact(type: ArtifactType) -> Artifact? {
        artifacts.first { $0.type == type.rawValue }
    }

    private func latestExistingArtifact(type: ArtifactType) -> Artifact? {
        artifacts.first { $0.type == type.rawValue && FileManager.default.fileExists(atPath: $0.path) }
    }

    private func hasExistingTaskWorktree(_ task: FactoryTask) -> Bool {
        [task.localWorktreePath, task.codexWorktreePath]
            .compactMap { $0 }
            .contains { path in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
            }
    }

    private func taskStateArtifactSummaries() -> [TaskArtifactSummary] {
        let relevantTypes: [ArtifactType] = [
            .plan,
            .localPlanReview,
            .codexPlanReview,
            .approvedPlan,
            .preflight,
            .testOutput,
            .localDiffReview,
            .codexDiffReviewHandoff,
            .finalReview,
            .taskStateReview
        ]
        return relevantTypes.compactMap { type in
            let candidates = artifacts.filter { $0.type == type.rawValue }
            guard let artifact = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) ?? candidates.first else {
                return nil
            }
            let exists = FileManager.default.fileExists(atPath: artifact.path)
            let decision: PlanReviewDecision?
            if exists, type == .localPlanReview || type == .codexPlanReview {
                let text = (try? String(contentsOfFile: artifact.path, encoding: .utf8)) ?? ""
                decision = Self.parsePlanReviewDecision(from: text)
            } else {
                decision = nil
            }
            let summary = exists ? nil : "Missing artifact file."
            return TaskArtifactSummary(
                id: artifact.id,
                type: type,
                path: artifact.path,
                exists: exists,
                createdAt: artifact.createdAt,
                decision: decision,
                summary: summary
            )
        }
        .sorted { left, right in
            if left.exists != right.exists {
                return left.exists && !right.exists
            }
            return left.createdAt > right.createdAt
        }
    }

    private func taskStateWorktreeSummaries(task: FactoryTask) async -> [TaskWorktreeSummary] {
        var summaries: [TaskWorktreeSummary] = []
        for display in TaskWorktreeDisplayMapper.displays(for: task) {
            guard let path = display.path else { continue }
            if let gitService {
                summaries.append(await gitService.inspectWorktree(label: display.label, path: path))
            } else {
                summaries.append(TaskWorktreeSummary(label: display.label, path: path, exists: FileManager.default.fileExists(atPath: path)))
            }
        }
        return summaries
    }

    private func canonicalWorktreeSummary(project: Project) async -> TaskWorktreeSummary? {
        guard project.type == .codeRepo else { return nil }
        if let gitService {
            return await gitService.inspectWorktree(label: "Canonical repo", path: project.path)
        }
        return TaskWorktreeSummary(label: "Canonical repo", path: project.path, exists: FileManager.default.fileExists(atPath: project.path))
    }

    private func latestPlanReviewDecision(from summaries: [TaskArtifactSummary]) -> PlanReviewDecision? {
        summaries
            .filter { ($0.type == .localPlanReview || $0.type == .codexPlanReview) && $0.exists }
            .sorted { $0.createdAt > $1.createdAt }
            .first?
            .decision
    }

    private func latestPreflightArtifactHasRisk() -> Bool {
        guard let artifact = latestExistingArtifact(type: .preflight) else { return false }
        guard let text = try? String(contentsOfFile: artifact.path, encoding: .utf8) else { return false }
        let normalized = text.lowercased()
        let riskyPhrases = [
            "dirty worktree",
            "missing path",
            "uncommitted changes",
            "unexpected branch location",
            "unpushed default branch",
            "overall recommendation: inspect diff",
            "overall recommendation: commit",
            "overall recommendation: merge",
            "overall recommendation: push",
            "overall recommendation: fix missing path",
            "overall recommendation: investigate"
        ]
        return riskyPhrases.contains { normalized.contains($0) }
    }

    private func preflightIsStale(preflight: Artifact?, taskWorktrees: [TaskWorktreeSummary], latestTestOutput: Artifact?) -> Bool {
        guard let preflight else { return false }
        let newerTaskChange = taskWorktrees
            .compactMap(\.latestChangeAt)
            .contains { $0 > preflight.createdAt }
        let newerTestOutput = latestTestOutput.map { $0.createdAt > preflight.createdAt } ?? false
        return newerTaskChange || newerTestOutput
    }

    private func testOutputPassed(_ artifact: Artifact) -> Bool {
        let description = artifact.description.lowercased()
        if description.contains("failed") { return false }
        if description.contains("passed") || description.hasPrefix("test output") { return true }
        guard let text = try? String(contentsOfFile: artifact.path, encoding: .utf8).lowercased() else {
            return false
        }
        return !text.contains("failed") && !text.contains("error:")
    }

    private func latestPreflightSuggestsArchive() -> Bool {
        guard let artifact = latestExistingArtifact(type: .preflight) else { return false }
        guard let text = try? String(contentsOfFile: artifact.path, encoding: .utf8) else { return false }
        let normalized = text.lowercased()
        return normalized.contains("overall recommendation: archive") || normalized.contains("merged to default: yes")
    }

    private func taskStateReviewMarkdown(project: Project, task: FactoryTask, review: TaskStateReview) -> String {
        let blockingIssues = review.blockingIssues.isEmpty
            ? "- None."
            : review.blockingIssues.map { "- \($0)" }.joined(separator: "\n")
        let warningIssues = review.warningIssues.isEmpty
            ? "- None."
            : review.warningIssues.map { "- \($0)" }.joined(separator: "\n")
        let artifactRows = review.latestArtifacts.map { artifact in
            "| \(artifact.type.rawValue) | \(artifact.exists ? "yes" : "no") | \(DateCoding.string(from: artifact.createdAt)) | \(artifact.decision?.rawValue ?? "-") | \(Self.markdownTableCell(artifact.path)) |"
        }.joined(separator: "\n")
        let worktreeRows = review.worktreeSummaries.isEmpty
            ? "| none | no | - | - | - | 0 | 0 | 0 |"
            : review.worktreeSummaries.map { worktree in
                "| \(Self.markdownTableCell(worktree.label)) | \(worktree.exists ? "yes" : "no") | \(worktree.branch ?? "-") | \(worktree.headSHA ?? "-") | \(worktree.isClean.map { $0 ? "yes" : "no" } ?? "-") | \(worktree.stagedCount) | \(worktree.unstagedCount) | \(worktree.untrackedCount) |"
            }.joined(separator: "\n")

        let planReviewWarning = review.hasPlan && !review.hasPlanReview
            ? "\nPlan exists but has not been reviewed.\n"
            : ""

        return """
        # Task State Review: \(task.title)

        Generated at: \(DateCoding.string(from: review.createdAt))
        Project: \(project.name)
        Task: \(task.id)
        Status: \(task.status.rawValue)
        Recommended action: \(review.recommendedAction.displayName)

        ## Summary

        \(review.summary)
        \(planReviewWarning)
        - Latest review decision: \(review.hasApprovedPlan ? "superseded by approved_plan" : review.latestPlanDecision?.rawValue ?? "none")
        - Implementation changes exist: \(review.hasImplementationChanges ? "yes" : "no")
        - Tests were run: \(review.hasTestOutput ? "yes" : "no")
        - Tests passed: \(review.hasPassingTestOutput ? "yes" : "no")
        - Preflight stale: \(review.hasStalePreflight ? "yes" : "no")
        - Ready to commit or merge: \(review.recommendedAction == .commitAndMerge ? "yes" : "no")

        ## Blocking Issues

        \(blockingIssues)

        ## Warnings

        \(warningIssues)

        ## Latest Artifacts

        | Type | Exists | Created | Decision | Path |
        |---|---|---|---|---|
        \(artifactRows.isEmpty ? "| none | no | - | - | - |" : artifactRows)

        ## Worktrees

        | Label | Exists | Branch | SHA | Clean | Staged | Unstaged | Untracked |
        |---|---|---|---|---|---:|---:|---:|
        \(worktreeRows)

        ## Decision Basis

        \(review.summary)

        ## Next Action

        \(review.recommendedAction.displayName)
        """
    }

    private nonisolated static func markdownTableCell(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|")
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
            return .approved
        case .revise, .unknown:
            return .planReview
        case .reject:
            return .needsFixes
        case .escalateToCodexBuild:
            return .approved
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
