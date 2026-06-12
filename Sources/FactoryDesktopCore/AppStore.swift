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
    @Published public var latestLifecycleReport: RepoHygieneReport?
    @Published public private(set) var latestTaskStateReview: TaskStateReview?
    @Published public private(set) var latestLifecycleSyncResult: TaskLifecycleSyncResult?
    @Published public private(set) var selectedRunnerProjectLink: RunnerProjectLink?
    @Published public private(set) var selectedTaskRunnerSessionLink: RunnerSessionLink?
    @Published public private(set) var runnerSessionLinks: [RunnerSessionLink] = []
    @Published public private(set) var latestRunnerRecommendation: RunnerRecommendation?
    @Published public private(set) var runnerWorkspaces: [RunnerWorkspace] = []
    @Published public private(set) var selectedRunnerWorkspace: RunnerWorkspace?
    @Published public private(set) var selectedRunnerSession: RunnerSession?
    @Published public private(set) var latestRunnerExecution: RunnerExecution?
    @Published public private(set) var latestWorkerReport: WorkerReport?
    @Published public private(set) var workerEvents: [WorkerEvent] = []
    @Published public private(set) var workerContextItems: [WorkerContextItem] = []
    @Published public private(set) var workerPromptSnapshots: [WorkerPromptSnapshot] = []
    @Published public private(set) var workerEvidence: [WorkerEvidence] = []
    @Published public private(set) var workerMessageQueue: [WorkerMessageQueueItem] = []
    @Published public private(set) var workerToolApprovals: [WorkerToolApproval] = []
    @Published public private(set) var workerComposerState = WorkerComposerState()
    @Published public private(set) var taskProposals: [TaskProposal] = []
    @Published public private(set) var runnerNotifications: [RunnerNotification] = []
    @Published public private(set) var latestLifecycleSnapshot: LifecycleSnapshot?
    @Published public private(set) var workerRunDetail: WorkerRunDetail?
    @Published public var isWorkerRunDetailPresented = false
    @Published public private(set) var workerRawLogsInitiallyExpanded = false
    @Published public private(set) var activeWorkerProcesses: [WorkerProcessSnapshot] = []
    @Published public private(set) var selectedCodexProjectLink: CodexProjectLink?
    @Published public private(set) var selectedTaskCodexSessionLink: CodexSessionLink?
    @Published public private(set) var codexSessionLinks: [CodexSessionLink] = []
    @Published public private(set) var latestCodexSessionRecommendation: CodexSessionResultRecommendation?
    @Published public private(set) var buildInfo: BuildInfo
    @Published public private(set) var appUpdateStatus: AppUpdateStatus = AppUpdateStatus()
    @Published public var selectedRunOutput: String = ""
    @Published public var selectedWorkspaceScope: WorkspaceSelectionScope = .project
    @Published public var statusMessage: String = ""
    @Published public var errorMessage: String?
    @Published public var isWorking: Bool = false
    @Published public var selectedEditorAssistProvider: RunnerProvider = .codex
    @Published public private(set) var isEditorAssistRunning: Bool = false
    @Published public private(set) var latestEditorAssistSuggestion: EditorAssistSuggestion?
    @Published public private(set) var latestAIAssistProposal: AIAssistProposal?

    public let paths: FactoryPaths

    private var database: SQLiteDatabase?
    private var repository: FactoryRepository?
    private var commandRunner: CommandRunner
    private var codexCLIService: CodexCLIService
    public let workerProcessRegistry: WorkerProcessRegistry
    private var workerCommandExecutor: WorkerCommandExecuting
    private var runnerAdapters: [RunnerProvider: RunnerProviderAdapter]
    private var lifecycleMonitorService: LifecycleMonitorService
    private var gitService: GitService?
    private var ollamaClient: OllamaClient
    private var handoffService: HandoffService
    private let currentBuildInfoProvider: () -> BuildInfo
    private let appRelauncher: () throws -> Void
    private let appTerminator: () -> Void
    private var appUpdateMonitorTask: Task<Void, Never>?
    private var isAppUpdateMonitoring = false
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

    public var backlogTasksForSelectedProject: [FactoryTask] {
        tasksForSelectedProject
            .filter { $0.status != .done && $0.status != .archived }
            .sorted { left, right in
                if left.status.sortOrder != right.status.sortOrder {
                    return left.status.sortOrder < right.status.sortOrder
                }
                if left.priorityLabel.sortOrder != right.priorityLabel.sortOrder {
                    return left.priorityLabel.sortOrder < right.priorityLabel.sortOrder
                }
                return left.updatedAt > right.updatedAt
            }
    }

    public var nextWorkItems: [BacklogNextWorkItem] {
        let runnerLinksByTaskID = Dictionary(uniqueKeysWithValues: runnerSessionLinks.compactMap { link in
            link.taskId.map { ($0, link) }
        })
        let recommendationsByTaskID: [String: RunnerRecommendation]
        if let selectedTask {
            recommendationsByTaskID = latestRunnerRecommendation.map { [selectedTask.id: $0] } ?? [:]
        } else {
            recommendationsByTaskID = [:]
        }
        return BacklogQueueRanking.rank(
            tasks: tasksForSelectedProject,
            runnerLinksByTaskID: runnerLinksByTaskID,
            recommendationsByTaskID: recommendationsByTaskID
        )
    }

    public var runsForSelectedTask: [RunRecord] {
        guard let task = selectedTask else { return [] }
        return runs.filter { $0.taskId == task.id }
    }

    public var workerConversationPreview: WorkerConversationPreview {
        WorkerConversationBuilder.preview(
            task: selectedTask,
            execution: latestRunnerExecution,
            processStatus: workerProcessStatus(for: latestRunnerExecution),
            report: latestWorkerReport,
            proposals: taskProposals,
            notifications: runnerNotifications,
            lifecycleSnapshot: latestLifecycleSnapshot,
            diffSnapshot: gitSnapshot
        )
    }

    public var workerTimelineEventsV2: [WorkerEvent] {
        var merged: [WorkerEvent] = workerEvents
        if let detail = workerRunDetail, selectedTask?.id == detail.task.id {
            merged.append(contentsOf: WorkerEventNormalizer.normalizedEvents(
                detail: detail,
                processStatus: workerProcessStatus(for: detail.execution)
            ))
        }

        var seen = Set<String>()
        return merged
            .sorted { left, right in
                if left.createdAt != right.createdAt {
                    return left.createdAt < right.createdAt
                }
                return left.id < right.id
            }
            .filter { event in
                guard !seen.contains(event.id) else { return false }
                seen.insert(event.id)
                return true
            }
    }

    public var workerTimelineV2: WorkerTimeline {
        WorkerTimelineBuilderV2.build(events: workerTimelineEventsV2)
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

    public var latestPlanReviewArtifact: Artifact? {
        latestArtifact(type: .codexPlanReview) ?? latestArtifact(type: .localPlanReview)
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

    public var projectHygieneSummary: ProjectHygieneSummary {
        ProjectHygienePresentation.summarize(
            report: latestLifecycleReport,
            selectedTask: selectedTask,
            tasks: tasksForSelectedProject
        )
    }

    public var projectStatusSummary: ProjectStatusSummary {
        ProjectWorkspacePresentation.projectStatusSummary(
            project: selectedProject,
            tasks: tasksForSelectedProject,
            hygiene: projectHygieneSummary,
            report: latestLifecycleReport
        )
    }

    public var taskProjectStatusSummary: TaskProjectStatusSummary {
        ProjectWorkspacePresentation.taskProjectStatusSummary(hygiene: projectHygieneSummary)
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

    public var selectedTaskHasMissingWorktreeReference: Bool {
        selectedTaskWorktreeDisplays.contains { $0.state == .missingPath }
    }

    public var selectedTaskCanUseWorktree: Bool {
        selectedTaskWorktreeDisplays.contains { $0.canOpen } && !selectedTaskHasMissingWorktreeReference
    }

    public var canPlanSelectedTaskLocally: Bool {
        selectedProject != nil && selectedTask != nil
    }

    public var selectedTaskWorktreeWarning: String? {
        guard let project = selectedProject, let task = selectedTask else { return nil }
        if task.status == .archived || task.status == .done {
            return nil
        }
        if let missing = TaskWorktreeDisplayMapper.displays(for: task).first(where: { $0.state == .missingPath }) {
            return "Missing Worktree: This task references a worktree path that no longer exists. \(missing.path ?? "")"
        }
        guard project.type == .codeRepo else { return nil }
        return nil
    }

    public var editorAssistProviderOptions: [EditorAssistProviderOption] {
        var providers: [RunnerProvider] = [.localOllama]

        for provider in runnerAdapters.keys.sorted(by: { $0.displayName < $1.displayName }) {
            guard provider != .manual, provider != .unknown else { continue }
            guard runnerAdapters[provider]?.supportedModes.contains(.editorAssist) == true else { continue }
            if !providers.contains(provider) {
                providers.append(provider)
            }
        }

        if let configuredProvider = selectedRunnerProjectLink?.preferredModelProfile?.provider,
           configuredProvider != .manual,
           configuredProvider != .unknown,
           !providers.contains(configuredProvider) {
            providers.append(configuredProvider)
        }

        return providers.map { provider in
            switch provider {
            case .localOllama:
                return EditorAssistProviderOption(
                    provider: provider,
                    isAvailable: true,
                    detail: selectedModel.isEmpty ? "Uses local model settings" : selectedModel
                )
            default:
                let isAvailable = runnerAdapters[provider]?.supportedModes.contains(.editorAssist) == true
                return EditorAssistProviderOption(
                    provider: provider,
                    isAvailable: isAvailable,
                    detail: isAvailable ? "Available" : "Not configured"
                )
            }
        }
    }

    public init(
        paths: FactoryPaths = FactoryPaths(),
        codexCLIService: CodexCLIService? = nil,
        workerCommandExecutor: WorkerCommandExecuting? = nil,
        workerProcessRegistry: WorkerProcessRegistry = WorkerProcessRegistry(),
        currentBuildInfoProvider: @escaping () -> BuildInfo = { BuildInfoService.current(launchTimestamp: Date()) },
        appRelauncher: @escaping () throws -> Void = { try AppUpdateService.relaunchCurrentApplication() },
        appTerminator: @escaping () -> Void = {}
    ) {
        self.paths = paths
        self.currentBuildInfoProvider = currentBuildInfoProvider
        self.appRelauncher = appRelauncher
        self.appTerminator = appTerminator
        self.buildInfo = currentBuildInfoProvider()
        self.commandRunner = CommandRunner()
        self.workerProcessRegistry = workerProcessRegistry
        self.codexCLIService = codexCLIService ?? CodexCLIService(commandRunner: commandRunner)
        self.workerCommandExecutor = workerCommandExecutor
            ?? (codexCLIService == nil
                ? CancellableWorkerCommandExecutor(commandRunner: commandRunner, registry: workerProcessRegistry)
                : CodexServiceWorkerCommandExecutor(service: self.codexCLIService))
        self.runnerAdapters = [:]
        self.lifecycleMonitorService = LifecycleMonitorService(commandRunner: commandRunner)
        self.ollamaClient = OllamaClient()
        self.handoffService = HandoffService(paths: paths)
        self.runnerAdapters[.codex] = CodexRunnerAdapter(service: self.codexCLIService)

        do {
            try paths.ensureBaseDirectories()
            let database = try SQLiteDatabase(url: paths.database)
            try MigrationRunner(database: database, paths: paths).migrate()
            self.database = database
            self.repository = FactoryRepository(database: database)
            self.gitService = GitService(commandRunner: commandRunner, paths: paths)
            try repository?.markRunningRunnerExecutionsDetached()
            try reload()
            statusMessage = "Ready. SQLite: \(paths.database.path)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    deinit {
        appUpdateMonitorTask?.cancel()
    }

    public func reload() throws {
        guard let repository else { return }
        projects = try repository.projects()
        tasks = try repository.tasks()
        if selectedProjectID == nil {
            selectedProjectID = projects.first?.id
        }
        if let selectedProjectID, selectedTaskID != nil, selectedTask == nil {
            selectedTaskID = tasks.first { $0.projectId == selectedProjectID }?.id
        }
        if let selectedProjectID, selectedTaskID == nil {
            selectedTaskID = tasks.first { $0.projectId == selectedProjectID }?.id
        }
        try reloadCodexLinks()
        try reloadRunsAndArtifacts()
        try reloadWorkerState()
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
        try reloadCodexLinks()
        try reloadWorkerState()
    }

    public func startAppUpdateMonitoring() {
        guard !isAppUpdateMonitoring else { return }
        isAppUpdateMonitoring = true
        appUpdateMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAppUpdateStatus()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    public func refreshAppUpdateStatus() async {
        guard appUpdateStatus.isApplying == false else { return }
        let checkedAt = Date()
        let launchedBuildInfo = buildInfo
        let currentBuildInfo = await Task.detached(priority: .utility) { [currentBuildInfoProvider] in
            currentBuildInfoProvider()
        }.value
        appUpdateStatus = AppUpdateService.evaluate(
            launched: launchedBuildInfo,
            current: currentBuildInfo,
            checkedAt: checkedAt
        )
    }

    public func applyAppUpdate() async {
        guard !appUpdateStatus.isApplying else { return }

        isWorking = true
        errorMessage = nil
        appUpdateStatus = AppUpdateStatus(
            availability: .applying,
            message: "Building Factory Desktop...",
            detectedBuildInfo: appUpdateStatus.detectedBuildInfo,
            lastCheckedAt: Date()
        )
        statusMessage = "Factory Desktop update running..."

        do {
            let sourceRoot = SelfRepoLocator.sourceRoot
            let buildResult = try await commandRunner.run(CommandRequest(
                executable: "swift",
                arguments: ["build"],
                workingDirectory: sourceRoot
            ))
            guard buildResult.succeeded else {
                throw FactoryError.commandFailed(buildResult.output)
            }

            appUpdateStatus = AppUpdateStatus(
                availability: .applying,
                message: "Running Factory Desktop tests...",
                detectedBuildInfo: appUpdateStatus.detectedBuildInfo,
                lastCheckedAt: Date()
            )

            let testResult = try await commandRunner.run(CommandRequest(
                executable: "swift",
                arguments: ["test"],
                workingDirectory: sourceRoot
            ))
            guard testResult.succeeded else {
                throw FactoryError.commandFailed(testResult.output)
            }

            try appRelauncher()
            statusMessage = "Factory Desktop updated. Restarting into the new build..."
            appTerminator()
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Factory Desktop update failed."
            await refreshAppUpdateStatus()
        }

        isWorking = false
    }

    private func reloadCodexLinks() throws {
        guard let repository else { return }
        if let project = selectedProject {
            selectedCodexProjectLink = try repository.codexProjectLink(projectId: project.id)
            codexSessionLinks = try repository.codexSessionLinks(projectId: project.id)
            selectedRunnerProjectLink = try repository.runnerProjectLink(projectId: project.id)
            runnerSessionLinks = try repository.runnerSessionLinks(projectId: project.id)
        } else {
            selectedCodexProjectLink = nil
            codexSessionLinks = []
            selectedRunnerProjectLink = nil
            runnerSessionLinks = []
        }
        if let task = selectedTask {
            selectedTaskCodexSessionLink = try repository.latestCodexSessionLink(taskId: task.id)
            selectedTaskRunnerSessionLink = try repository.latestRunnerSessionLink(taskId: task.id)
        } else {
            selectedTaskCodexSessionLink = nil
            selectedTaskRunnerSessionLink = nil
        }
    }

    public func reloadWorkerState() throws {
        guard let repository else { return }
        if let task = selectedTask {
            runnerWorkspaces = try repository.runnerWorkspaces(taskId: task.id)
            selectedRunnerWorkspace = runnerWorkspaces.first
            selectedRunnerSession = try repository.latestRunnerSession(taskId: task.id)
            latestRunnerExecution = try repository.latestRunnerExecution(taskId: task.id)
            latestWorkerReport = try repository.latestWorkerReport(taskId: task.id)
            workerEvents = try repository.workerEvents(taskId: task.id)
            workerContextItems = try repository.workerContextItems(taskId: task.id)
            workerPromptSnapshots = try repository.workerPromptSnapshots(taskId: task.id)
            workerEvidence = try repository.workerEvidence(taskId: task.id)
            workerMessageQueue = try repository.workerMessageQueue(taskId: task.id)
            workerToolApprovals = try repository.workerToolApprovals(taskId: task.id)
            let draftText = try repository.workerComposerDraft(taskId: task.id, sessionId: selectedRunnerSession?.id)
            workerComposerState = WorkerComposerState(
                taskId: task.id,
                sessionId: selectedRunnerSession?.id,
                phase: workerComposerPhase(task: task, execution: latestRunnerExecution, queuedMessages: workerMessageQueue),
                draft: draftText,
                parsedMentions: WorkerComposerMentionParser.parse(draftText),
                queuedCount: workerMessageQueue.filter { $0.status == .queued }.count,
                supportsSteering: false
            )
            taskProposals = try repository.taskProposals(sourceTaskId: task.id)
            runnerNotifications = try repository.runnerNotifications(taskId: task.id)
            latestLifecycleSnapshot = try repository.latestLifecycleSnapshot(taskId: task.id)
            if isWorkerRunDetailPresented || workerRunDetail?.task.id == task.id {
                workerRunDetail = try makeWorkerRunDetail(task: task, executionId: workerRunDetail?.execution?.id)
            }
        } else {
            runnerWorkspaces = []
            selectedRunnerWorkspace = nil
            selectedRunnerSession = nil
            latestRunnerExecution = nil
            latestWorkerReport = nil
            workerEvents = []
            workerContextItems = []
            workerPromptSnapshots = []
            workerEvidence = []
            workerMessageQueue = []
            workerToolApprovals = []
            workerComposerState = WorkerComposerState()
            taskProposals = []
            runnerNotifications = []
            latestLifecycleSnapshot = nil
            workerRunDetail = nil
        }
    }

    private func workerComposerPhase(
        task: FactoryTask,
        execution: RunnerExecution?,
        queuedMessages: [WorkerMessageQueueItem]
    ) -> WorkerComposerPhase {
        if isWorking {
            return .sending
        }
        if workerProcessStatus(for: execution) == .running || execution?.status == .running {
            return queuedMessages.contains { $0.status == .queued } ? .queued : .running
        }
        if queuedMessages.contains(where: { $0.status == .queued }) {
            return .queued
        }
        if task.status == .blocked {
            return .feedback
        }
        return .idle
    }

    private func makeWorkerRunDetail(task: FactoryTask, executionId: String? = nil) throws -> WorkerRunDetail {
        guard let repository else { throw FactoryError.missingSelection }
        let execution = try executionId.flatMap { try repository.runnerExecution(id: $0) } ?? repository.latestRunnerExecution(taskId: task.id)
        let session = try execution.flatMap { try repository.runnerSession(id: $0.sessionId) } ?? repository.latestRunnerSession(taskId: task.id)
        let workspace = try session.flatMap { try repository.runnerWorkspace(id: $0.workspaceId) } ?? repository.latestRunnerWorkspace(taskId: task.id)
        let agentTurns = try session.map { try repository.agentTurns(sessionId: $0.id) } ?? []
        let prompt: String
        if !agentTurns.isEmpty {
            prompt = agentTurns
                .first { $0.role.lowercased() == "user" }?
                .content ?? ""
        } else {
            prompt = ""
        }
        let report = try execution.flatMap { try repository.workerReport(executionId: $0.id) } ?? repository.latestWorkerReport(taskId: task.id)
        let detailDiffSnapshot = workspace.flatMap { workerWorkspace in
            gitSnapshot.worktreePath == workerWorkspace.worktreePath ? gitSnapshot : nil
        }
        return WorkerRunDetail(
            task: task,
            workspace: workspace,
            session: session,
            execution: execution,
            prompt: prompt,
            agentTurns: agentTurns,
            report: report,
            proposals: try repository.taskProposals(sourceTaskId: task.id),
            lifecycleSnapshots: try repository.lifecycleSnapshots(taskId: task.id),
            notifications: try repository.runnerNotifications(taskId: task.id),
            events: try repository.taskEvents(taskId: task.id),
            diffSnapshot: detailDiffSnapshot
        )
    }

    public func refreshActiveWorkerProcesses() async {
        activeWorkerProcesses = await workerProcessRegistry.snapshots()
    }

    public func workerProcessSnapshot(executionId: String?) -> WorkerProcessSnapshot? {
        guard let executionId else { return nil }
        return activeWorkerProcesses.first { $0.executionId == executionId }
    }

    public func workerProcessStatus(for execution: RunnerExecution?) -> WorkerProcessStatus {
        guard let execution else { return .unknown }
        if let snapshot = workerProcessSnapshot(executionId: execution.id) {
            return snapshot.status
        }
        switch execution.status {
        case .queued: return .unknown
        case .running: return .detached
        case .completed: return .completed
        case .failed: return .failed
        case .cancelled: return .cancelled
        case .detached: return .detached
        case .unknown: return .unknown
        }
    }

    public func workerRunIsCancellable(_ execution: RunnerExecution?) -> Bool {
        guard let execution else { return false }
        return workerProcessSnapshot(executionId: execution.id)?.status == .running
    }

    public func updateWorkerComposerDraft(_ draft: String) {
        workerComposerState.draft = draft
        workerComposerState.parsedMentions = WorkerComposerMentionParser.parse(draft)
        guard let repository, let task = selectedTask else { return }
        do {
            try repository.upsertWorkerComposerDraft(
                taskId: task.id,
                sessionId: selectedRunnerSession?.id,
                draftText: draft
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func submitWorkerComposerDraft(steer: Bool = false) async {
        await sendWorkerMessage(workerComposerState.draft, steer: steer, forceSend: false)
    }

    public func sendQueuedWorkerMessageNow(_ item: WorkerMessageQueueItem) async {
        guard let repository else { return }
        do {
            try repository.updateWorkerQueuedMessageStatus(id: item.id, status: .sent)
            try reloadWorkerState()
            await sendWorkerMessage(item.body, steer: false, forceSend: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func deleteQueuedWorkerMessage(_ item: WorkerMessageQueueItem) {
        perform {
            guard let repository = self.repository else { return }
            try repository.deleteWorkerQueuedMessage(id: item.id)
            try self.reloadWorkerState()
            self.statusMessage = "Removed queued worker message."
        }
    }

    public func stopWorkerFromComposer() async {
        workerComposerState.phase = .stopping
        await cancelWorkerRun()
        workerComposerState.phase = workerComposerPhase(
            task: selectedTask ?? FactoryTask(projectId: "", title: ""),
            execution: latestRunnerExecution,
            queuedMessages: workerMessageQueue
        )
    }

    private func sendWorkerMessage(_ text: String, steer: Bool, forceSend: Bool) async {
        guard let repository, let task = selectedTask else {
            errorMessage = FactoryError.missingSelection.localizedDescription
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let activeRun = isWorking || workerProcessStatus(for: latestRunnerExecution) == .running || latestRunnerExecution?.status == .running
        if activeRun && !steer && !forceSend {
            queueWorkerMessage(trimmed, repository: repository, task: task)
            return
        }

        workerComposerState.phase = .sending
        do {
            try persistWorkerTurnContext(instruction: trimmed, task: task, repository: repository)
            try repository.upsertWorkerComposerDraft(taskId: task.id, sessionId: selectedRunnerSession?.id, draftText: "")
            workerComposerState.draft = ""
            workerComposerState.parsedMentions = []
            try reloadWorkerState()
        } catch {
            errorMessage = error.localizedDescription
            workerComposerState.phase = .idle
            return
        }

        if selectedRunnerSession == nil {
            await assignSelectedTaskToAIWorker(additionalInstruction: trimmed)
        } else {
            await resumeWorker(additionalInstruction: trimmed)
        }

        do {
            try reloadWorkerState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func queueWorkerMessage(_ text: String, repository: FactoryRepository, task: FactoryTask) {
        do {
            let mentions = WorkerComposerMentionParser.parse(text)
            let item = WorkerMessageQueueItem(
                taskId: task.id,
                sessionId: selectedRunnerSession?.id,
                body: text,
                mentions: mentions
            )
            try repository.upsert(workerMessageQueueItem: item)
            try repository.insert(workerEvent: WorkerEvent(
                taskId: task.id,
                sessionId: selectedRunnerSession?.id,
                executionId: latestRunnerExecution?.id,
                branchKey: selectedRunnerWorkspace?.branchName ?? selectedRunnerWorkspace?.worktreePath,
                kind: .message,
                source: .user,
                payloadJSON: WorkerEventPayload(
                    role: "User",
                    title: "Queued Message",
                    body: text,
                    status: "Queued",
                    mentions: mentions
                ).json
            ))
            try repository.upsertWorkerComposerDraft(taskId: task.id, sessionId: selectedRunnerSession?.id, draftText: "")
            try reloadWorkerState()
            statusMessage = "Queued worker message."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persistWorkerTurnContext(
        instruction: String,
        task: FactoryTask,
        repository: FactoryRepository
    ) throws {
        let mentions = WorkerComposerMentionParser.parse(instruction)
        let contextPack = ContextPackBuilder.build(
            project: selectedProject,
            task: task,
            diffSnapshot: gitSnapshot,
            artifacts: artifacts,
            runs: runsForSelectedTask,
            reviewFeedback: latestDiffReviewText,
            previousSummary: latestWorkerReport?.summary ?? ""
        )
        var itemIds: [String] = []
        var hashes: [String] = []
        for var item in contextPack.items {
            item.sessionId = selectedRunnerSession?.id
            try repository.insert(workerContextItem: item)
            if item.included {
                itemIds.append(item.id)
                hashes.append(item.contentHash)
            }
        }

        let promptText = workerTurnPromptText(instruction: instruction, contextItems: contextPack.items)
        try repository.insert(workerPromptSnapshot: WorkerPromptSnapshot(
            taskId: task.id,
            sessionId: selectedRunnerSession?.id,
            executionId: latestRunnerExecution?.id,
            selectedContextItemIds: itemIds,
            contextHashes: hashes,
            tokenCount: contextPack.tokenCount,
            budget: contextPack.budget,
            provider: selectedRunnerProjectLink?.preferredModelProfile?.provider ?? .codex,
            model: selectedRunnerProjectLink?.preferredModelProfile?.modelName ?? selectedModel,
            promptMetadataJSON: contextPack.promptMetadataJSON,
            promptText: promptText
        ))
        try repository.insert(workerEvent: WorkerEvent(
            taskId: task.id,
            sessionId: selectedRunnerSession?.id,
            executionId: latestRunnerExecution?.id,
            branchKey: selectedRunnerWorkspace?.branchName ?? selectedRunnerWorkspace?.worktreePath,
            kind: .message,
            source: .user,
            payloadJSON: WorkerEventPayload(
                role: "User",
                title: "Instruction",
                body: instruction,
                mentions: mentions
            ).json
        ))
    }

    private func workerTurnPromptText(instruction: String, contextItems: [WorkerContextItem]) -> String {
        let included = contextItems.filter(\.included)
        let contextList = included.map { item in
            "- [\(item.kind.displayName)] \(item.title) \(item.path.map { "(\($0))" } ?? "")"
        }.joined(separator: "\n")
        return """
        # Worker Turn

        ## Instruction
        \(instruction)

        ## Context Items
        \(contextList.isEmpty ? "- No explicit context items selected." : contextList)
        """
    }

    public func selectProject(_ projectID: String?) {
        selectedProjectID = projectID
        selectedTaskID = tasks.first { $0.projectId == projectID }?.id
        selectedWorkspaceScope = .project
        latestPreflightReport = nil
        latestLifecycleReport = nil
        latestTaskStateReview = nil
        latestLifecycleSyncResult = nil
        latestRunnerRecommendation = nil
        latestCodexSessionRecommendation = nil
        selectedRunnerWorkspace = nil
        selectedRunnerSession = nil
        latestRunnerExecution = nil
        latestWorkerReport = nil
        taskProposals = []
        runnerNotifications = []
        latestLifecycleSnapshot = nil
        Task { await refreshGitStatus() }
        do {
            try reloadRunsAndArtifacts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func selectTask(_ taskID: String?, openWorkspace: Bool = true) {
        selectedTaskID = taskID
        if openWorkspace {
            selectedWorkspaceScope = taskID == nil ? .project : .task
        }
        selectedRunOutput = ""
        latestPreflightReport = nil
        latestLifecycleReport = nil
        latestTaskStateReview = nil
        latestLifecycleSyncResult = nil
        latestRunnerRecommendation = nil
        latestCodexSessionRecommendation = nil
        selectedRunnerWorkspace = nil
        selectedRunnerSession = nil
        latestRunnerExecution = nil
        latestWorkerReport = nil
        taskProposals = []
        runnerNotifications = []
        latestLifecycleSnapshot = nil
        Task { await refreshGitStatus() }
        do {
            try reloadRunsAndArtifacts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func registerProject(
        name: String,
        type: ProjectType,
        path: String,
        defaultBranch: String,
        buildCommand: String = "",
        unitTestCommand: String = "",
        integrationTestCommand: String = "",
        e2eTestCommand: String = "",
        visualQCCommand: String = ""
    ) {
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
                commandConfiguration: ProjectCommandConfiguration(
                    build: buildCommand,
                    unitTests: unitTestCommand,
                    integrationTests: integrationTestCommand,
                    e2eTests: e2eTestCommand,
                    visualQC: visualQCCommand
                ),
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
            buildCommand: "swift build",
            unitTestCommand: "swift test"
        )
    }

    public func showProjectWorkspace() {
        selectedWorkspaceScope = .project
    }

    public func showKanbanWorkspace() {
        selectedWorkspaceScope = .kanban
    }

    public func showTaskWorkspace() {
        guard selectedTask != nil else {
            selectedWorkspaceScope = .project
            return
        }
        selectedWorkspaceScope = .task
    }

    public func createTask(title: String = "", type: TaskType = .planning, goal: String = "") async {
        guard let repository, let project = selectedProject else {
            errorMessage = FactoryError.missingSelection.localizedDescription
            return
        }
        if project.type == .codeRepo {
            guard await ensureLifecycleGateAllowsStart(project: project, selectedTask: nil) else { return }
        }

        perform {
            let task = FactoryTask(
                projectId: project.id,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled task" : title,
                type: type,
                status: .backlog,
                kind: .task,
                readiness: goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .needsScoping : .scoped,
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
            self.selectedWorkspaceScope = .task
            self.statusMessage = "Created task \(task.title)."
        }
    }

    public func saveTask(_ task: FactoryTask) {
        perform {
            guard let repository = self.repository else { return }
            let previousStatus = self.tasks.first { $0.id == task.id }?.status
            var updated = task
            updated.triageStatus = FactoryTaskTriageStatus.fromLegacyStatus(updated.status)
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

    public func updateTaskStatus(taskID: String, status: TaskStatus) {
        perform {
            guard let task = self.tasks.first(where: { $0.id == taskID }) else {
                throw FactoryError.missingSelection
            }
            try self.updateStatus(
                for: task,
                to: status,
                source: .manual,
                eventKind: .statusChangedManually,
                message: "Manual status changed to \(status.displayName)."
            )
            self.statusMessage = "Moved task to \(status.displayName)."
        }
    }

    public func deleteSelectedTask() {
        perform {
            guard let repository = self.repository, let task = self.selectedTask else {
                throw FactoryError.missingSelection
            }
            let projectID = task.projectId
            try repository.deleteTask(id: task.id)
            self.selectedTaskID = self.tasks
                .filter { $0.projectId == projectID && $0.id != task.id }
                .sorted { $0.updatedAt > $1.updatedAt }
                .first?
                .id
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

    public func refreshLifecycleScan() async {
        guard let project = selectedProject, let repository, let gitService else {
            errorMessage = FactoryError.missingSelection.localizedDescription
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let projectTasks = tasks.filter { $0.projectId == project.id }
            let projectRuns = try repository.runs(projectId: project.id)
            let projectArtifacts = try repository.artifacts(projectId: project.id)
            latestLifecycleReport = await gitService.lifecycleReport(
                project: project,
                selectedTask: selectedTask,
                tasks: projectTasks,
                runs: projectRuns,
                artifacts: projectArtifacts
            )
            statusMessage = "Lifecycle scan refreshed."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func createWorktree(flavor: WorktreeFlavor) async {
        guard let project = selectedProject, var task = selectedTask, let repository, let gitService else {
            errorMessage = FactoryError.missingSelection.localizedDescription
            return
        }
        guard await ensureLifecycleGateAllowsStart(project: project, selectedTask: task) else { return }
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
            task.setBaseBranchCommit(await gitService.defaultBranchHead(project: project), for: flavor)
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
                markdown += "\n## Selected Task Worktree\n\nNo task worktree exists yet. That is fine for naming, describing, prioritizing, planning, review, and clarification. Create a task worktree only when the next intended step is concrete checked-out repo work such as editing files, running isolated build/test commands, or reviewing a checked-out diff.\n"
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
        guard await ensureLifecycleGateAllowsStart(project: project, selectedTask: task) else { return }
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
            projectId: project.id,
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
            try repository.upsert(run: run)
            try updateStatus(
                for: &task,
                to: .planning,
                source: .automatic,
                eventKind: .statusChangedAutomatically,
                runId: run.id,
                message: "Planning run started.",
                repository: repository
            )
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

        if project.type == .codeRepo, let missingPath = firstMissingSelectedWorktreePath(task) {
            handleMissingWorktreePath(missingPath)
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
            projectId: project.id,
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
            try repository.upsert(run: run)
            try updateStatus(
                for: &task,
                to: .planReview,
                source: .automatic,
                eventKind: .statusChangedAutomatically,
                runId: run.id,
                message: "Codex plan review started.",
                repository: repository
            )
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
            if project.type == .codeRepo, let missingPath = self.firstMissingSelectedWorktreePath(task) {
                self.handleMissingWorktreePath(missingPath)
                return
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
            if project.type == .codeRepo, let missingPath = self.firstMissingSelectedWorktreePath(task) {
                self.handleMissingWorktreePath(missingPath)
                return
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
        guard GitService.pathIsExistingDirectory(path) else {
            handleMissingWorktreePath(path)
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
                errorMessage = worktreeRequirementMessage(
                    for: "opening an isolated implementation environment in VS Code"
                )
                return
            }
            guard GitService.pathIsExistingDirectory(path) else {
                handleMissingWorktreePath(path)
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

    public func linkRunnerProject(workspacePath: String, provider: RunnerProvider = .codex) {
        perform {
            guard let repository = self.repository, let project = self.selectedProject else {
                throw FactoryError.missingSelection
            }
            let trimmed = workspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
            let path = trimmed.isEmpty ? project.path : trimmed
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw FactoryError.invalidProjectPath(path)
            }
            let existing = try repository.runnerProjectLink(projectId: project.id)
            let link = RunnerProjectLink(
                id: existing?.id ?? UUID().uuidString,
                projectId: project.id,
                provider: provider,
                workspacePath: URL(fileURLWithPath: path).standardizedFileURL.path,
                preferredMode: nil,
                preferredModelProfile: existing?.preferredModelProfile,
                createdAt: existing?.createdAt ?? Date(),
                updatedAt: Date()
            )
            try repository.upsert(runnerProjectLink: link)
            try self.reloadCodexLinks()
            self.statusMessage = "Linked runner workspace."
        }
    }

    public func unlinkRunnerProject() {
        perform {
            guard let repository = self.repository, let project = self.selectedProject else {
                throw FactoryError.missingSelection
            }
            try repository.deleteRunnerProjectLink(projectId: project.id)
            try self.reloadCodexLinks()
            self.statusMessage = "Unlinked runner workspace."
        }
    }

    public func attachRunnerSessionToSelectedTask(sessionID: String, provider: RunnerProvider = .codex) {
        guard provider == .codex else {
            errorMessage = "Only the Codex runner adapter is implemented in v1."
            return
        }
        attachCodexSessionToSelectedTask(sessionId: sessionID)
    }

    public func detachRunnerSessionFromSelectedTask() {
        detachCodexSessionFromSelectedTask()
    }

    public func refreshSelectedTaskRunnerSessionState() async {
        await refreshSelectedTaskCodexSessionState()
    }

    public func checkSelectedTaskRunnerSession() async {
        await runSelectedTaskCodexSessionCheck()
    }

    public func continueRunnerSession() async {
        await continueRunnerSession(taskID: selectedTask?.id)
    }

    public func linkCodexProject(workspacePath: String) {
        linkRunnerProject(workspacePath: workspacePath, provider: .codex)
    }

    public func unlinkCodexProject() {
        unlinkRunnerProject()
    }

    public func attachCodexSessionToSelectedTask(sessionId: String) {
        perform {
            guard let repository = self.repository, let project = self.selectedProject, let task = self.selectedTask else {
                throw FactoryError.missingSelection
            }
            let trimmed = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw FactoryError.commandFailed("Enter a Codex session ID first.")
            }
            _ = try self.codexCLIService.commandRequest(for: .resume(sessionId: trimmed))
            let workspacePath = self.codexWorkspacePath(project: project, task: task)
            let link = CodexSessionLink(
                projectId: project.id,
                taskId: task.id,
                codexSessionId: trimmed,
                workspacePath: workspacePath,
                mode: self.codexMode(workspacePath: workspacePath, project: project),
                branchName: task.codexBranch ?? task.localBranch,
                worktreePath: task.codexWorktreePath ?? task.localWorktreePath,
                status: .active,
                lastSeenAt: Date(),
                lastSummary: "Session attached in Factory Desktop."
            )
            try repository.upsert(codexSessionLink: link)
            try self.reloadCodexLinks()
            self.statusMessage = "Attached Codex session \(trimmed.shortID)."
        }
    }

    public func detachCodexSessionFromSelectedTask() {
        perform {
            guard let repository = self.repository, let link = self.selectedTaskCodexSessionLink else {
                throw FactoryError.missingSelection
            }
            try repository.detachCodexSessionLinkFromTask(id: link.id)
            try self.reloadCodexLinks()
            self.statusMessage = "Detached Codex session \(link.codexSessionId.shortID)."
        }
    }

    public func openSelectedProjectInCodex() async {
        guard let project = selectedProject else {
            errorMessage = FactoryError.missingSelection.localizedDescription
            return
        }
        let workspacePath = selectedCodexProjectLink?.workspacePath ?? project.path
        await runCodexCommand(
            kind: .openProject,
            summary: "Open Codex project",
            commandText: "codex app \(workspacePath)",
            transcriptPrefix: "codex-open-project",
            sessionLink: selectedTaskCodexSessionLink,
            successfulStatus: .active
        ) {
            try await self.codexCLIService.openApp(workspacePath: workspacePath)
        }
    }

    public func resumeSelectedTaskCodexSession() async {
        guard let link = selectedTaskCodexSessionLink else {
            errorMessage = "Attach a Codex session before resuming."
            return
        }
        await runCodexCommand(
            kind: .resumeSession,
            summary: "Resume Codex session",
            commandText: "codex resume \(link.codexSessionId)",
            transcriptPrefix: "codex-resume-session",
            sessionLink: link,
            successfulStatus: .active
        ) {
            try await self.codexCLIService.resume(sessionId: link.codexSessionId)
        }
    }

    public func refreshSelectedTaskCodexSessionState() async {
        guard let repository, let link = selectedTaskCodexSessionLink else {
            errorMessage = "Attach a Codex session before refreshing."
            return
        }
        isWorking = true
        defer { isWorking = false }
        let availability = await codexCLIService.availability()
        do {
            let status: CodexSessionStatus = availability.isAvailable ? link.status : .failed
            try repository.updateCodexSessionLink(
                id: link.id,
                status: status,
                lastSeenAt: Date(),
                lastSummary: availability.message,
                transcriptPath: link.transcriptPath
            )
            try reloadCodexLinks()
            statusMessage = availability.message
            if !availability.isAvailable {
                errorMessage = availability.message
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func runSelectedTaskCodexSessionCheck() async {
        guard let link = selectedTaskCodexSessionLink else {
            errorMessage = "Attach a Codex session before running a session check."
            return
        }
        await runCodexCommand(
            kind: .sessionCheck,
            summary: "Codex session state check",
            commandText: "codex exec resume \(link.codexSessionId)",
            transcriptPrefix: "codex-session-check",
            sessionLink: link,
            successfulStatus: .completed
        ) {
            try await self.codexCLIService.execResume(
                sessionId: link.codexSessionId,
                workspacePath: link.workspacePath,
                instruction: "Resume this session in read-only mode and summarize current state, blockers, and next recommended Factory Desktop action. Do not edit files."
            )
        }
    }

    public func scopeWorkItem(taskID: String? = nil, provider: RunnerProvider = .codex) async {
        guard let repository, let project = selectedProject else {
            errorMessage = FactoryError.missingSelection.localizedDescription
            return
        }
        guard var task = (taskID.flatMap { id in tasks.first { $0.id == id } }) ?? selectedTask else {
            errorMessage = "Select a task first."
            return
        }
        guard let adapter = runnerAdapters[provider] else {
            errorMessage = "Runner provider \(provider.displayName) is not configured."
            return
        }

        isWorking = true
        defer { isWorking = false }

        let directory = paths.runDirectory(project: project, task: task)
        let promptURL = directory.appendingPathComponent("\(task.id.shortID)-scoping-prompt.md")
        let outputURL = directory.appendingPathComponent("\(task.id.shortID)-scoping-output.log")
        let prompt = workItemScopingPrompt(project: project, task: task)
        var run = RunRecord(
            projectId: project.id,
            taskId: task.id,
            executor: "\(provider.rawValue)_runner",
            model: selectedRunnerProjectLink?.preferredModelProfile?.modelName,
            status: .running,
            command: nil,
            promptPath: promptURL.path,
            outputPath: outputURL.path,
            summary: "Scoping task"
        )

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try prompt.write(to: promptURL, atomically: true, encoding: .utf8)
            try repository.upsert(run: run)
            task.status = .planning
            task.triageStatus = FactoryTaskTriageStatus.fromLegacyStatus(task.status)
            task.readiness = .needsScoping
            task.updatedAt = Date()
            try repository.upsert(task: task)
            try reload()
            selectedTaskID = task.id

            let request = RunnerRequest(
                provider: provider,
                mode: .scoping,
                workspacePath: selectedRunnerProjectLink?.workspacePath ?? project.path,
                taskID: task.id,
                instruction: prompt,
                modelProfile: selectedRunnerProjectLink?.preferredModelProfile,
                sandboxMode: .readOnly
            )
            let result = try await adapter.execute(request)
            try result.output.write(to: outputURL, atomically: true, encoding: .utf8)
            run.status = result.succeeded ? .succeeded : .failed
            run.command = result.command.displayString
            run.exitCode = Int(result.exitCode)
            run.summary = result.summary
            run.endedAt = result.endedAt
            try repository.upsert(run: run)

            task = mergeScopingResult(result, into: task)
            task.updatedAt = Date()
            try repository.upsert(task: task)
            try reload()
            selectedTaskID = task.id
            selectedRunOutput = result.output
            let action: RunnerRecommendedAction = task.readiness == .executable ? .dispatch : .scope
            latestRunnerRecommendation = RunnerRecommendation(
                action: action,
                reason: task.recommendedNextAction.isEmpty ? result.summary : task.recommendedNextAction
            )
            statusMessage = result.succeeded ? "Scoped task." : "Task scoping failed."
            if !result.succeeded {
                errorMessage = result.output
            }
        } catch {
            run.status = .failed
            run.summary = error.localizedDescription
            run.endedAt = Date()
            try? repository.upsert(run: run)
            errorMessage = error.localizedDescription
        }
    }

    public func runEditorAssist(
        action: EditorAssistAction,
        documentMarkdown: String,
        target: EditorAssistTarget,
        customInstruction: String = ""
    ) async {
        guard let repository, let project = selectedProject, let task = selectedTask else {
            errorMessage = FactoryError.missingSelection.localizedDescription
            return
        }
        let provider = selectedEditorAssistProvider

        isEditorAssistRunning = true
        isWorking = true
        defer {
            isEditorAssistRunning = false
            isWorking = false
        }

        let instruction = EditorAssistPrompt.instruction(
            action: action,
            taskTitle: task.title,
            documentMarkdown: documentMarkdown,
            target: target,
            customInstruction: customInstruction
        )
        let directory = paths.runDirectory(project: project, task: task)
        let promptURL = directory.appendingPathComponent("\(task.id.shortID)-editor-assist-prompt.md")
        let outputURL = directory.appendingPathComponent("\(task.id.shortID)-editor-assist-output.log")
        var run = RunRecord(
            projectId: project.id,
            taskId: task.id,
            executor: "\(provider.rawValue)_editor_assist",
            model: editorAssistModelName(for: provider),
            status: .running,
            promptPath: promptURL.path,
            outputPath: outputURL.path,
            summary: "Editor assist: \(action.displayName)"
        )

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try instruction.write(to: promptURL, atomically: true, encoding: .utf8)
            try repository.upsert(run: run)
            try reloadRunsAndArtifacts()

            let request = RunnerRequest(
                provider: provider,
                mode: .editorAssist,
                workspacePath: runnerWorkspacePath(project: project, task: task),
                taskID: task.id,
                instruction: instruction,
                modelProfile: selectedRunnerProjectLink?.preferredModelProfile,
                sandboxMode: .readOnly
            )
            latestEditorAssistSuggestion = nil
            latestAIAssistProposal = nil
            let result = try await executeEditorAssistRequest(request)
            try result.output.write(to: outputURL, atomically: true, encoding: .utf8)

            run.status = result.succeeded ? .succeeded : .failed
            run.command = result.command.displayString
            run.exitCode = Int(result.exitCode)
            run.summary = result.summary
            run.endedAt = result.endedAt
            try repository.upsert(run: run)
            try reloadRunsAndArtifacts()

            selectedRunOutput = result.output
            if result.succeeded {
                latestEditorAssistSuggestion = EditorAssistSuggestion.parse(provider: provider, action: action, output: result.output)
                latestAIAssistProposal = AIAssistProposal.parse(
                    provider: provider,
                    action: action,
                    output: result.output,
                    target: target,
                    customInstruction: customInstruction
                )
                statusMessage = "Editor assist suggestion ready."
            } else {
                errorMessage = result.output
                statusMessage = "Editor assist failed."
            }
        } catch {
            run.status = .failed
            run.summary = error.localizedDescription
            run.endedAt = Date()
            try? repository.upsert(run: run)
            errorMessage = error.localizedDescription
        }
    }

    private func editorAssistModelName(for provider: RunnerProvider) -> String? {
        switch provider {
        case .localOllama:
            return selectedModel
        default:
            return selectedRunnerProjectLink?.preferredModelProfile?.modelName
        }
    }

    private func executeEditorAssistRequest(_ request: RunnerRequest) async throws -> RunnerResult {
        switch request.provider {
        case .localOllama:
            let startedAt = Date()
            let output = try await ollamaClient.generate(
                model: selectedModel,
                prompt: request.instruction,
                contextTokens: ModelPolicy.effectiveContext(for: selectedModel)
            )
            let endedAt = Date()
            return RunnerResult(
                provider: .localOllama,
                mode: .editorAssist,
                command: RunnerCommand(executable: "ollama", arguments: ["generate", selectedModel]),
                standardOutput: output,
                standardError: "",
                exitCode: 0,
                startedAt: startedAt,
                endedAt: endedAt,
                summary: "Editor assist suggestion ready.",
                sessionMetadata: RunnerSessionMetadata()
            )
        default:
            guard let adapter = runnerAdapters[request.provider] else {
                throw NSError(
                    domain: "FactoryDesktop.EditorAssist",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "AI assist provider \(request.provider.displayName) is not configured."]
                )
            }
            guard adapter.supportedModes.contains(.editorAssist) else {
                throw NSError(
                    domain: "FactoryDesktop.EditorAssist",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "AI assist provider \(request.provider.displayName) does not support editor assist."]
                )
            }
            return try await adapter.execute(request)
        }
    }

    public func clearEditorAssistSuggestion() {
        latestEditorAssistSuggestion = nil
        latestAIAssistProposal = nil
    }

    public func dispatchTask(taskID: String? = nil, provider: RunnerProvider = .codex) async {
        guard let project = selectedProject else {
            errorMessage = FactoryError.missingSelection.localizedDescription
            return
        }
        guard let task = (taskID.flatMap { id in tasks.first { $0.id == id } }) ?? selectedTask else {
            errorMessage = "Select a task to dispatch."
            return
        }
        guard let adapter = runnerAdapters[provider] else {
            errorMessage = "Runner provider \(provider.displayName) is not configured."
            return
        }
        guard task.readiness == .executable else {
            errorMessage = "Scope this task until readiness is executable before dispatch."
            return
        }
        if project.type == .codeRepo {
            guard hasExistingTaskWorktree(task) else {
                errorMessage = worktreeRequirementMessage(for: "dispatching implementation work")
                statusMessage = "Create a task worktree before concrete repo-scoped work."
                return
            }
            guard await ensureLifecycleGateAllowsStart(project: project, selectedTask: task) else { return }
        }
        let workspacePath = runnerWorkspacePath(project: project, task: task)
        let request = RunnerRequest(
            provider: provider,
            mode: .coding,
            workspacePath: workspacePath,
            taskID: task.id,
            instruction: taskDispatchPrompt(project: project, task: task),
            modelProfile: selectedRunnerProjectLink?.preferredModelProfile,
            linkedSessionID: nil,
            sandboxMode: .readOnly
        )
        await runRunnerRequest(
            request,
            project: project,
            task: task,
            summary: "Dispatch task",
            transcriptPrefix: "runner-dispatch",
            sessionLink: nil,
            successfulStatus: .active,
            adapter: adapter
        )
    }

    public func assignSelectedTaskToAIWorker(additionalInstruction: String = "") async {
        await assignTaskToAIWorker(taskID: selectedTask?.id, additionalInstruction: additionalInstruction)
    }

    public func assignTaskToAIWorker(taskID: String? = nil, additionalInstruction: String = "") async {
        guard let repository, let project = selectedProject else {
            errorMessage = FactoryError.missingSelection.localizedDescription
            return
        }
        guard let task = (taskID.flatMap { id in tasks.first { $0.id == id } }) ?? selectedTask else {
            errorMessage = "Select a task to assign."
            return
        }
        guard let adapter = runnerAdapters[.codex] else {
            errorMessage = "Codex runner is not configured."
            return
        }
        if project.type == .codeRepo {
            guard await ensureLifecycleGateAllowsStart(project: project, selectedTask: task) else { return }
        }

        isWorking = true
        defer { isWorking = false }

        do {
            var task = task
            let workspace = try await ensureRunnerWorkspace(project: project, task: &task, repository: repository)
            try await runWorkerLoop(
                project: project,
                task: task,
                workspace: workspace,
                existingSession: nil,
                runReason: "assign_to_ai_worker",
                additionalInstruction: additionalInstruction,
                adapter: adapter,
                repository: repository
            )
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "AI Worker assignment failed."
        }
    }

    public func resumeWorker(additionalInstruction: String = "") async {
        await resumeWorker(
            taskID: selectedTask?.id,
            sessionID: selectedRunnerSession?.id,
            additionalInstruction: additionalInstruction
        )
    }

    private func resumeWorker(taskID: String?, sessionID: String?, additionalInstruction: String = "") async {
        guard let repository, let project = selectedProject else {
            errorMessage = FactoryError.missingSelection.localizedDescription
            return
        }
        guard let task = (taskID.flatMap { id in tasks.first { $0.id == id } }) ?? selectedTask else {
            errorMessage = FactoryError.missingSelection.localizedDescription
            return
        }
        guard let workspace = selectedRunnerWorkspace ?? (try? repository.latestRunnerWorkspace(taskId: task.id)),
              let session = sessionID.flatMap({ try? repository.runnerSession(id: $0) }) ?? selectedRunnerSession ?? (try? repository.latestRunnerSession(taskId: task.id)) else {
            await assignTaskToAIWorker(taskID: task.id, additionalInstruction: additionalInstruction)
            return
        }
        guard let adapter = runnerAdapters[session.provider] else {
            errorMessage = "Runner provider \(session.provider.displayName) is not configured."
            return
        }

        isWorking = true
        defer { isWorking = false }

        do {
            try await runWorkerLoop(
                project: project,
                task: task,
                workspace: workspace,
                existingSession: session,
                runReason: "resume_ai_worker",
                additionalInstruction: additionalInstruction,
                adapter: adapter,
                repository: repository
            )
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "AI Worker resume failed."
        }
    }

    public func reviewLatestWorkerReport() {
        guard let report = latestWorkerReport else {
            statusMessage = "No worker report is available."
            return
        }
        selectedRunOutput = report.rawText.isEmpty ? report.summary : report.rawText
        statusMessage = "Showing latest worker report."
    }

    public func viewLatestWorkerLogs() {
        guard latestRunnerExecution?.logPath ?? selectedRunnerSession?.transcriptPath != nil else {
            statusMessage = "No worker log is available."
            return
        }
        showWorkerRunDetail(executionId: latestRunnerExecution?.id, expandRawLogs: true)
        statusMessage = "Showing worker conversation logs."
    }

    public func prepareWorkerRunDetailForWorkspace(executionId: String? = nil, expandRawLogs: Bool = false) {
        perform {
            guard let task = self.selectedTask else { throw FactoryError.missingSelection }
            self.workerRawLogsInitiallyExpanded = expandRawLogs
            self.workerRunDetail = try self.makeWorkerRunDetail(task: task, executionId: executionId)
            self.isWorkerRunDetailPresented = false
            self.statusMessage = expandRawLogs ? "Showing worker logs in workspace." : "Showing worker workspace."
            Task { await self.refreshWorkerRunDetailDiffSnapshot() }
        }
    }

    public func showWorkerRunDetail(executionId: String? = nil, expandRawLogs: Bool = false) {
        perform {
            guard let task = self.selectedTask else { throw FactoryError.missingSelection }
            self.workerRawLogsInitiallyExpanded = expandRawLogs
            self.workerRunDetail = try self.makeWorkerRunDetail(task: task, executionId: executionId)
            self.isWorkerRunDetailPresented = true
            self.statusMessage = "Showing worker conversation."
            Task { await self.refreshWorkerRunDetailDiffSnapshot() }
        }
    }

    private func refreshWorkerRunDetailDiffSnapshot() async {
        guard let gitService, var detail = workerRunDetail, let path = detail.workspace?.worktreePath else { return }
        do {
            detail.diffSnapshot = try await gitService.snapshot(worktreePath: path)
            guard workerRunDetail?.task.id == detail.task.id,
                  workerRunDetail?.execution?.id == detail.execution?.id else {
                return
            }
            workerRunDetail = detail
        } catch {
            // The conversation can still render from the worker report when the worktree is unavailable.
        }
    }

    public func openWorkerLog() async {
        guard let path = workerRunDetail?.execution?.logPath ?? latestRunnerExecution?.logPath ?? selectedRunnerSession?.transcriptPath else {
            statusMessage = "No worker log is available."
            return
        }
        await openPath(path, successMessage: "Opened worker log.")
    }

    public func openWorkerWorktree() async {
        guard let path = workerRunDetail?.workspace?.worktreePath ?? selectedRunnerWorkspace?.worktreePath else {
            statusMessage = "No worker workspace is available."
            return
        }
        await openPath(path, successMessage: "Opened worker workspace.")
    }

    public func retryWorkerRun() async {
        guard let detail = workerRunDetail else {
            await resumeWorker()
            return
        }
        await resumeWorker(taskID: detail.task.id, sessionID: detail.session?.id)
    }

    public func cancelWorkerRun() async {
        guard let repository,
              let selectedTask = selectedTask ?? workerRunDetail?.task else {
            errorMessage = FactoryError.missingSelection.localizedDescription
            return
        }
        let detail: WorkerRunDetail
        do {
            detail = try workerRunDetail ?? makeWorkerRunDetail(task: selectedTask, executionId: latestRunnerExecution?.id)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        guard var execution = detail.execution else {
            errorMessage = FactoryError.missingSelection.localizedDescription
            return
        }
        await refreshActiveWorkerProcesses()
        guard workerRunIsCancellable(execution) else {
            statusMessage = "Stop is unavailable for completed or detached runs."
            return
        }

        activeWorkerProcesses = activeWorkerProcesses.map { snapshot in
            guard snapshot.executionId == execution.id else { return snapshot }
            var updated = snapshot
            updated.status = .cancelling
            return updated
        }
        appendWorkerLogLine("Cancellation requested by user.", path: execution.logPath)

        let didCancel = await workerProcessRegistry.cancel(executionId: execution.id)
        await refreshActiveWorkerProcesses()
        guard didCancel else {
            statusMessage = "Worker run is no longer attached to a live process."
            return
        }

        do {
            execution.status = .cancelled
            execution.endedAt = execution.endedAt ?? Date()
            try repository.upsert(runnerExecution: execution)
            try repository.insert(runnerNotification: RunnerNotification(
                taskId: detail.task.id,
                sessionId: detail.session?.id,
                executionId: execution.id,
                level: .warning,
                message: "Worker run was cancelled by user. Log and worktree were preserved."
            ))
            try repository.insert(taskEvent: TaskEvent(
                taskId: detail.task.id,
                kind: .statusChangedAutomatically,
                source: .automatic,
                message: "AI Worker cancellation requested. Previous task status: \(detail.task.status.displayName). New task status: \(detail.task.status.displayName). Reason: user stopped execution. Evidence: execution \(execution.id.shortID), log \(execution.logPath ?? "unavailable").",
                previousStatus: detail.task.status,
                newStatus: detail.task.status
            ))
            if let project = selectedProject {
                try await refreshWorkerLifecycleSnapshot(project: project, task: detail.task, repository: repository)
            }
            try reload()
            selectedTaskID = detail.task.id
            workerRunDetail = try makeWorkerRunDetail(task: detail.task, executionId: execution.id)
            statusMessage = "AI Worker cancelled. Log and worktree were preserved."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func markWorkerRunFailed() {
        perform {
            guard let repository = self.repository,
                  var detail = self.workerRunDetail,
                  var execution = detail.execution,
                  let task = self.tasks.first(where: { $0.id == detail.task.id }) else {
                throw FactoryError.missingSelection
            }
            execution.status = .failed
            execution.endedAt = execution.endedAt ?? Date()
            try repository.upsert(runnerExecution: execution)
            if var session = detail.session {
                session.status = .failed
                session.updatedAt = Date()
                try repository.upsert(runnerSession: session)
            }
            try repository.insert(runnerNotification: RunnerNotification(
                taskId: task.id,
                sessionId: detail.session?.id,
                executionId: execution.id,
                level: .warning,
                message: "Worker run marked failed by user. Evidence: \(execution.logPath ?? "no log path recorded")."
            ))
            try repository.insert(taskEvent: TaskEvent(
                taskId: task.id,
                kind: .statusChangedManually,
                source: .manual,
                message: "Worker run marked failed. Previous task status: \(task.status.displayName). New task status: \(task.status.displayName). Reason: user marked execution failed. Evidence: execution \(execution.id.shortID), log \(execution.logPath ?? "unavailable").",
                previousStatus: task.status,
                newStatus: task.status
            ))
            try self.reloadWorkerState()
            detail.execution = execution
            detail.notifications = try repository.runnerNotifications(taskId: task.id)
            detail.events = try repository.taskEvents(taskId: task.id)
            self.workerRunDetail = detail
            self.statusMessage = "Marked worker run failed."
        }
    }

    public func markWorkerNeedsReview() {
        perform {
            guard let repository = self.repository,
                  var task = self.selectedTask ?? self.workerRunDetail?.task else {
                throw FactoryError.missingSelection
            }
            let previousStatus = task.status
            task.status = .readyForReview
            task.triageStatus = FactoryTaskTriageStatus.fromLegacyStatus(.readyForReview)
            task.updatedAt = Date()
            try repository.upsert(task: task)
            try repository.insert(taskEvent: TaskEvent(
                taskId: task.id,
                kind: .statusChangedManually,
                source: .manual,
                message: "Marked needs review from worker detail. Previous task status: \(previousStatus.displayName). New task status: Ready for Review. Reason: user requested review. Evidence: execution \(self.workerRunDetail?.execution?.id.shortID ?? self.latestRunnerExecution?.id.shortID ?? "unavailable"), report \(self.workerRunDetail?.report?.parseStatus.displayName ?? self.latestWorkerReport?.parseStatus.displayName ?? "unavailable").",
                previousStatus: previousStatus,
                newStatus: .readyForReview
            ))
            try self.reload()
            self.selectedTaskID = task.id
            self.workerRunDetail = try self.makeWorkerRunDetail(task: task, executionId: self.workerRunDetail?.execution?.id)
            self.statusMessage = "Marked task needs review."
        }
    }

    public func dismissRunnerNotification(_ notification: RunnerNotification) {
        perform {
            guard let repository = self.repository else { throw FactoryError.missingSelection }
            try repository.markRunnerNotificationRead(id: notification.id)
            try self.reloadWorkerState()
            if let task = self.workerRunDetail?.task {
                self.workerRunDetail = try self.makeWorkerRunDetail(task: task, executionId: self.workerRunDetail?.execution?.id)
            }
            self.statusMessage = "Dismissed worker notification."
        }
    }

    public func retryParseWorkerReport() {
        perform {
            guard let repository = self.repository,
                  let detail = self.workerRunDetail,
                  let execution = detail.execution,
                  let session = detail.session,
                  let report = detail.report else {
                throw FactoryError.missingSelection
            }
            let parsed = WorkerReportParser.parse(
                output: report.rawText,
                sessionId: session.id,
                executionId: execution.id,
                sourceTaskId: detail.task.id
            )
            if var parsedReport = parsed.report {
                parsedReport.id = report.id
                try repository.upsert(workerReport: parsedReport)
                for proposal in parsed.proposals {
                    try repository.upsert(taskProposal: proposal)
                }
                if parsed.status == .partiallyParsed {
                    try repository.insert(runnerNotification: RunnerNotification(
                        taskId: detail.task.id,
                        sessionId: session.id,
                        executionId: execution.id,
                        level: .warning,
                        message: parsed.error ?? "Worker report partially parsed."
                    ))
                }
            } else {
                let failedReport = WorkerReport(
                    id: report.id,
                    sessionId: session.id,
                    executionId: execution.id,
                    status: .failed,
                    parseStatus: parsed.status,
                    parseError: parsed.error,
                    summary: parsed.error ?? "Worker report could not be parsed.",
                    rawText: parsed.rawReportText
                )
                try repository.upsert(workerReport: failedReport)
                try repository.insert(runnerNotification: RunnerNotification(
                    taskId: detail.task.id,
                    sessionId: session.id,
                    executionId: execution.id,
                    level: .warning,
                    message: parsed.error ?? "Worker report needs review."
                ))
            }
            try self.reloadWorkerState()
            self.workerRunDetail = try self.makeWorkerRunDetail(task: detail.task, executionId: execution.id)
            self.statusMessage = parsed.report == nil ? "Retry parse failed; raw report preserved." : "Worker report parsed."
        }
    }

    public func createTask(from proposal: TaskProposal) {
        perform {
            guard let repository = self.repository else { throw FactoryError.missingSelection }
            let task = try repository.acceptTaskProposal(id: proposal.id)
            try self.reload()
            self.selectedTaskID = task.id
            self.selectedWorkspaceScope = .task
            self.statusMessage = "Created task from worker proposal."
        }
    }

    public func createAllProposedTasks() {
        perform {
            guard let repository = self.repository, let sourceTask = self.selectedTask else {
                throw FactoryError.missingSelection
            }
            let proposals = try repository.taskProposals(sourceTaskId: sourceTask.id, status: .proposed)
            var created: [FactoryTask] = []
            for proposal in proposals {
                created.append(try repository.acceptTaskProposal(id: proposal.id))
            }
            try self.reload()
            self.selectedTaskID = created.first?.id ?? sourceTask.id
            self.statusMessage = "Created \(created.count) proposed task\(created.count == 1 ? "" : "s")."
        }
    }

    public func dismissTaskProposal(_ proposal: TaskProposal) {
        perform {
            guard let repository = self.repository else { throw FactoryError.missingSelection }
            try repository.dismissTaskProposal(id: proposal.id)
            try self.reloadWorkerState()
            self.statusMessage = "Dismissed worker proposal."
        }
    }

    public func dismissAllTaskProposals() {
        perform {
            guard let repository = self.repository, let task = self.selectedTask else {
                throw FactoryError.missingSelection
            }
            let proposals = try repository.taskProposals(sourceTaskId: task.id, status: .proposed)
            for proposal in proposals {
                try repository.dismissTaskProposal(id: proposal.id)
            }
            try self.reloadWorkerState()
            self.statusMessage = "Dismissed \(proposals.count) worker proposal\(proposals.count == 1 ? "" : "s")."
        }
    }

    public func continueRunnerSession(taskID: String? = nil) async {
        guard let repository else {
            errorMessage = FactoryError.missingSelection.localizedDescription
            return
        }
        let task = (taskID.flatMap { id in tasks.first { $0.id == id } }) ?? selectedTask
        guard let task else {
            errorMessage = "Select a task with a linked runner session."
            return
        }
        guard let link = try? repository.latestRunnerSessionLink(taskId: task.id) else {
            errorMessage = "Attach a runner session before continuing."
            return
        }
        guard let project = selectedProject, let adapter = runnerAdapters[link.provider] else {
            errorMessage = "Runner provider is unavailable."
            return
        }
        let request = RunnerRequest(
            provider: link.provider,
            mode: .coding,
            workspacePath: link.workspacePath,
            taskID: task.id,
            instruction: taskDispatchPrompt(project: project, task: task),
            modelProfile: selectedRunnerProjectLink?.preferredModelProfile,
            linkedSessionID: link.sessionID,
            sandboxMode: .readOnly
        )
        await runRunnerRequest(
            request,
            project: project,
            task: task,
            summary: "Continue runner session",
            transcriptPrefix: "runner-continue",
            sessionLink: link,
            successfulStatus: .active,
            adapter: adapter
        )
    }

    public func runFirstTestCommand() async {
        await runWorkflowCommand(.unitTests)
    }

    public func runWorkflowCommand(_ kind: WorkflowRunKind) async {
        guard let project = selectedProject, var task = selectedTask, let repository else {
            errorMessage = FactoryError.missingSelection.localizedDescription
            return
        }
        guard project.commandConfiguration.command(for: kind) != nil else {
            statusMessage = "\(kind.displayName) is not configured."
            selectedRunOutput = ""
            return
        }
        if project.type == .codeRepo, let missingPath = firstMissingSelectedWorktreePath(task) {
            handleMissingWorktreePath(missingPath)
            return
        }
        if project.type == .codeRepo, !hasExistingTaskWorktree(task) {
            statusMessage = worktreeRequirementMessage(for: "running \(kind.displayName)")
            return
        }

        isWorking = true
        defer { isWorking = false }

        let runID = UUID().uuidString
        let runner = LocalRunnerService(commandRunner: commandRunner, paths: paths, repository: repository)

        do {
            let result = try await runner.runConfiguredCommand(
                project: project,
                task: task,
                kind: kind,
                runID: runID,
                onRunStarted: { startedRun in
                    try self.applyWorkflowEvent(
                        Self.startedEvent(for: kind),
                        to: &task,
                        runId: startedRun.id,
                        message: "\(kind.displayName) started: \(startedRun.command ?? "missing command")."
                    )
                    try self.reload()
                    self.selectedTaskID = task.id
                    self.statusMessage = "\(kind.displayName) running..."
                }
            )
            guard let run = result.run else {
                statusMessage = "\(kind.displayName) is not configured."
                return
            }
            let artifact = try insertLocalRunnerArtifact(kind: kind, task: task, run: run)
            try applyWorkflowEvent(
                Self.finishedEvent(for: kind, passed: result.status == .passed),
                to: &task,
                runId: run.id,
                artifactId: artifact.id,
                message: "\(kind.displayName) \(result.status == .passed ? "passed" : "failed"): \(run.command ?? "missing command").",
                testsPassed: kind.isTestKind ? result.status == .passed : nil,
                diffExists: !gitSnapshot.changedFiles.isEmpty
            )
            try reload()
            selectedTaskID = task.id
            selectedRunOutput = result.output
            statusMessage = result.status == .passed ? "\(kind.displayName) passed." : "\(kind.displayName) failed."
            if result.status == .failed {
                errorMessage = "\(kind.displayName) failed. See \(result.logPath ?? "run log")."
            }
        } catch {
            try? reload()
            selectedTaskID = task.id
            selectedRunOutput = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    private func insertLocalRunnerArtifact(kind: WorkflowRunKind, task: FactoryTask, run: RunRecord) throws -> Artifact {
        guard let repository, let outputPath = run.outputPath else {
            throw FactoryError.missingSelection
        }
        let artifactType: ArtifactType = kind.isTestKind ? .testOutput : .implementationLog
        let artifact = Artifact(
            taskId: task.id,
            runId: run.id,
            type: artifactType,
            path: outputPath,
            description: "Local runner log: \(kind.displayName)"
        )
        try repository.insert(artifact: artifact)
        return artifact
    }

    private static func startedEvent(for kind: WorkflowRunKind) -> TaskWorkflowEventKind {
        switch kind {
        case .build:
            return .buildStarted
        case .unitTests, .integrationTests, .e2eTests:
            return .testsStarted
        case .visualQC:
            return .visualQCStarted
        }
    }

    private static func finishedEvent(for kind: WorkflowRunKind, passed: Bool) -> TaskWorkflowEventKind {
        switch kind {
        case .build:
            return passed ? .buildFinished : .buildFailed
        case .unitTests, .integrationTests, .e2eTests:
            return passed ? .testsFinished : .testsFailed
        case .visualQC:
            return passed ? .visualQCFinished : .visualQCFailed
        }
    }

    public func reviewDiffLocally() async {
        guard let project = selectedProject, var task = selectedTask, let repository, let gitService else {
            errorMessage = FactoryError.missingSelection.localizedDescription
            return
        }
        if project.type == .codeRepo, let missingPath = firstMissingSelectedWorktreePath(task) {
            handleMissingWorktreePath(missingPath)
            return
        }
        if project.type == .codeRepo, !hasExistingTaskWorktree(task) {
            statusMessage = worktreeRequirementMessage(for: "reviewing a diff")
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
            if project.type == .codeRepo, let missingPath = self.firstMissingSelectedWorktreePath(task) {
                self.handleMissingWorktreePath(missingPath)
                return
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
            errorMessage = worktreeRequirementMessage(for: "committing changes")
            return
        }
        guard GitService.pathIsExistingDirectory(path) else {
            handleMissingWorktreePath(path)
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

    public func performWorktreeRepairAction(_ action: WorktreeRepairAction, displayID: String) {
        switch action {
        case .refreshLifecycleScan:
            Task { await refreshLifecycleScan() }
        case .removeStaleWorktreeReference, .markWorktreeCleaned:
            clearStoredWorktreePath(displayID: displayID, action: action)
        case .archiveTask:
            updateSelectedTaskStatus(.archived)
        case .recreateWorktreeFromBranch:
            Task { await refreshSelectedTaskWorktree(displayID: displayID) }
        case .relinkExistingWorktree:
            statusMessage = "\(action.displayName) is a P0 placeholder. No worktree was relinked."
        }
    }

    public func canPerformWorktreeRepairAction(_ action: WorktreeRepairAction, displayID: String? = nil) -> Bool {
        switch action {
        case .recreateWorktreeFromBranch:
            guard let displayID else { return false }
            return selectedTaskWorktreeDisplays.contains { $0.id == displayID }
        case .relinkExistingWorktree:
            return false
        default:
            return !action.isFoundationOnly
        }
    }

    public func performLifecycleAction(_ action: LifecycleSafeAction, item: LifecycleItem) async {
        guard let project = selectedProject, let repository, let gitService else {
            errorMessage = FactoryError.missingSelection.localizedDescription
            return
        }
        var task = selectedTask

        isWorking = true
        defer { isWorking = false }

        do {
            var completionStatusMessage: String?
            switch action {
            case .refreshScan:
                await refreshLifecycleScan()
                return
            case .inspectDiff:
                guard let request = gitService.lifecycleActionCommand(action, project: project, item: item) else {
                    errorMessage = "No diff command is available for this item."
                    return
                }
                let result = try await commandRunner.run(request)
                selectedRunOutput = result.output
                completionStatusMessage = "Diff preview refreshed."
            case .createWIPBackupCommit:
                guard let selectedTask = task,
                      let flavor = worktreeFlavor(for: selectedTask, item: item),
                      let path = item.path else {
                    errorMessage = "This lifecycle item is not linked to the selected task worktree."
                    return
                }
                let result = try await gitService.commitAll(path: path, defaultBranch: project.defaultBranch, message: "WIP backup before refresh")
                selectedRunOutput = result.output
                task = selectedTask
                task?.setBaseBranchCommit(await gitService.defaultBranchHead(project: project), for: flavor)
                if let task {
                    try repository.upsert(task: task)
                }
                completionStatusMessage = "WIP commit created."
            case .stashWorktreeChanges:
                guard let selectedTask = task,
                      let flavor = worktreeFlavor(for: selectedTask, item: item) else {
                    errorMessage = "This lifecycle item is not linked to the selected task worktree."
                    return
                }
                let result = try await gitService.stashTaskWorktreeChanges(project: project, task: selectedTask, flavor: flavor)
                selectedRunOutput = result.output
                completionStatusMessage = "Stashed local worktree changes."
            case .refreshFromMain:
                guard let selectedTask = task,
                      let flavor = worktreeFlavor(for: selectedTask, item: item) else {
                    errorMessage = "This lifecycle item is not linked to the selected task worktree."
                    return
                }
                let assessment = try await gitService.refreshTaskWorktreeFromMain(project: project, task: selectedTask, flavor: flavor)
                task = selectedTask
                task?.setBaseBranchCommit(assessment.defaultHead, for: flavor)
                if let task {
                    try repository.upsert(task: task)
                }
                completionStatusMessage = "Refreshed task worktree from \(project.defaultBranch)."
            case .rebaseOntoMain:
                guard let selectedTask = task,
                      let flavor = worktreeFlavor(for: selectedTask, item: item) else {
                    errorMessage = "This lifecycle item is not linked to the selected task worktree."
                    return
                }
                let assessment = try await gitService.rebaseTaskWorktreeOntoDefault(project: project, task: selectedTask, flavor: flavor)
                task = selectedTask
                task?.setBaseBranchCommit(assessment.defaultHead, for: flavor)
                if let task {
                    try repository.upsert(task: task)
                }
                completionStatusMessage = "Rebased task worktree onto \(project.defaultBranch)."
            case .fastForwardMergeToMain:
                guard let request = gitService.lifecycleActionCommand(action, project: project, item: item) else {
                    errorMessage = "No merge command is available for this item."
                    return
                }
                let result = try await commandRunner.run(request)
                selectedRunOutput = result.output
                completionStatusMessage = "Fast-forward merge completed."
            case .pushMain:
                let result = try await gitService.pushDefaultBranch(project: project)
                selectedRunOutput = result.output
                completionStatusMessage = "Pushed \(project.defaultBranch) to origin."
            case .deleteMergedBranch, .deleteDuplicateBranch:
                guard let branch = item.branch else {
                    errorMessage = "No branch is linked to this lifecycle item."
                    return
                }
                let result = try await gitService.deleteLocalBranch(project: project, branch: branch)
                selectedRunOutput = result.output
                completionStatusMessage = "Deleted local branch \(branch)."
            case .removeCleanWorktree:
                guard let path = item.path else {
                    errorMessage = "No worktree path is linked to this lifecycle item."
                    return
                }
                func pathVariants(_ value: String) -> Set<String> {
                    let url = URL(fileURLWithPath: value)
                    let standardized = url.standardizedFileURL.path
                    let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
                    var variants: Set<String> = [value, standardized, resolved]
                    for variant in Array(variants) {
                        if variant.hasPrefix("/private/var/") {
                            variants.insert("/var/" + String(variant.dropFirst("/private/var/".count)))
                        } else if variant.hasPrefix("/var/") {
                            variants.insert("/private/var/" + String(variant.dropFirst("/var/".count)))
                        }
                    }
                    return variants
                }
                let removedPathVariants = pathVariants(path)
                let result = try await gitService.removeCleanWorktree(project: project, path: path)
                selectedRunOutput = result.output
                if var linkedTask = try repository.tasks(projectId: project.id).first(where: { task in
                    task.localWorktreePath.map { !pathVariants($0).isDisjoint(with: removedPathVariants) } == true ||
                        task.codexWorktreePath.map { !pathVariants($0).isDisjoint(with: removedPathVariants) } == true
                }) {
                    if linkedTask.localWorktreePath.map({ !pathVariants($0).isDisjoint(with: removedPathVariants) }) == true {
                        linkedTask.localWorktreePath = nil
                    }
                    if linkedTask.codexWorktreePath.map({ !pathVariants($0).isDisjoint(with: removedPathVariants) }) == true {
                        linkedTask.codexWorktreePath = nil
                    }
                    linkedTask.updatedAt = Date()
                    try repository.upsert(task: linkedTask)
                    if task?.id == linkedTask.id {
                        task = linkedTask
                    }
                }
                completionStatusMessage = "Removed clean worktree."
            case .pruneWorktreeMetadata:
                let result = try await gitService.pruneWorktreeMetadata(project: project)
                selectedRunOutput = result.output
                completionStatusMessage = "Pruned stale Git worktree metadata."
            case .archiveOldArtifacts, .deleteOldArtifacts:
                errorMessage = "\(action.displayName) is not wired yet."
                return
            case .keepProtectBackupBranch:
                completionStatusMessage = "Backup branch kept. No changes made."
            }

            try reload()
            if let task {
                selectedTaskID = task.id
            }
            await refreshGitStatus()
            await refreshLifecycleScan()
            if let completionStatusMessage {
                statusMessage = completionStatusMessage
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    public func syncSelectedTaskLifecycle() async -> TaskLifecycleSyncResult? {
        guard let repository, let project = selectedProject, let task = selectedTask else {
            errorMessage = FactoryError.missingSelection.localizedDescription
            return nil
        }

        isWorking = true
        defer { isWorking = false }

        do {
            try reloadRunsAndArtifacts()
            let facts = try await taskLifecycleFacts(project: project, task: task, repository: repository)
            let evaluation = TaskLifecycleService.evaluate(facts)
            let result = TaskLifecycleSyncResult(evaluation: evaluation, facts: facts, previousStatus: task.status)
            latestLifecycleSyncResult = result

            guard task.status != .archived else {
                statusMessage = "Lifecycle sync skipped: task is archived."
                return result
            }
            guard evaluation.isAutomaticSafe else {
                statusMessage = "Lifecycle sync skipped: \(evaluation.reason)"
                return result
            }
            guard evaluation.recommendedStatus != task.status else {
                statusMessage = "Lifecycle sync checked: status is already \(task.status.displayName)."
                return result
            }

            var updated = task
            let previousStatus = updated.status
            updated.status = evaluation.recommendedStatus
            updated.updatedAt = Date()
            let event = TaskEvent(
                taskId: updated.id,
                kind: .statusChangedAutomatically,
                source: .automatic,
                message: "Lifecycle sync: \(evaluation.reason)",
                previousStatus: previousStatus,
                newStatus: updated.status
            )
            try repository.upsert(task: updated)
            try repository.insert(taskEvent: event)
            try reload()
            selectedTaskID = updated.id
            latestTaskStateReview = nil
            statusMessage = "Lifecycle sync changed status to \(updated.status.displayName)."
            let appliedResult = TaskLifecycleSyncResult(
                evaluation: evaluation,
                facts: facts,
                previousStatus: previousStatus,
                appliedStatus: updated.status,
                event: event
            )
            latestLifecycleSyncResult = appliedResult
            return appliedResult
        } catch {
            errorMessage = error.localizedDescription
            return nil
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
            try auditMissingWorktreeReferences(task: task, summaries: taskWorktreeSummaries, repository: repository)

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
            let hasDiffReviewArtifact = artifactSummaries.contains { $0.type == .localDiffReview && $0.exists }
            let hasFinalReviewArtifact = artifactSummaries.contains { $0.type == .finalReview && $0.exists }
            let hasDiffReview = hasDiffReviewArtifact || hasFinalReviewArtifact
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

            let workflowSummaries = WorkflowCheckSummariesBuilder.build(
                project: project,
                runs: try repository.runs(taskId: task.id),
                artifacts: try repository.artifacts(taskId: task.id)
            )
            let cleanupSafetyState = Self.lifecycleCleanupSafetyState(
                hasRiskyPreflight: hasRiskyPreflight,
                hasExistingWorktree: hasExistingWorktree,
                hasMissingWorktree: !missingWorktrees.isEmpty,
                hasImplementationChanges: hasImplementationChanges,
                projectType: project.type
            )
            let lifecycleEvaluation = TaskLifecycleService.evaluate(TaskLifecycleFacts(
                currentStatus: task.status,
                taskType: task.type,
                hasBranch: task.localBranch != nil || task.codexBranch != nil,
                hasWorktree: hasExistingWorktree,
                worktreeIsDirty: hasExistingWorktree ? hasImplementationChanges : nil,
                hasCommits: appearsMerged ? true : nil,
                appearsMergedIntoDefault: appearsMerged,
                latestBuildStatus: Self.workflowStatus(.build, in: workflowSummaries),
                latestTestStatus: Self.latestTestStatus(in: workflowSummaries),
                latestVisualQCStatus: Self.workflowStatus(.visualQC, in: workflowSummaries),
                hasDiffReviewArtifact: hasDiffReviewArtifact,
                hasFinalReviewArtifact: hasFinalReviewArtifact,
                hasPlan: hasPlan,
                hasPlanReview: hasPlanReview,
                latestPlanDecision: latestDecision,
                hasApprovedPlan: hasApprovedPlan,
                hasPreflight: hasPreflight,
                hasRiskyPreflight: hasRiskyPreflight,
                hasStalePreflight: hasStalePreflight,
                cleanupSafetyState: cleanupSafetyState
            ))
            let recommendation = (
                lifecycleEvaluation.recommendedAction,
                lifecycleEvaluation.reason
            )

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

    private func openPath(_ path: String, successMessage: String) async {
        do {
            _ = try await commandRunner.run(CommandRequest(executable: "open", arguments: [path]))
            statusMessage = successMessage
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func appendWorkerLogLine(_ message: String, path: String?) {
        guard let path else { return }
        let line = "\n[\(DateCoding.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: path),
           let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
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

    private func runRunnerRequest(
        _ request: RunnerRequest,
        project: Project,
        task: FactoryTask,
        summary: String,
        transcriptPrefix: String,
        sessionLink: RunnerSessionLink?,
        successfulStatus: RunnerSessionStatus,
        adapter: RunnerProviderAdapter
    ) async {
        guard let repository else {
            errorMessage = FactoryError.missingSelection.localizedDescription
            return
        }

        isWorking = true
        defer { isWorking = false }

        let startedAt = Date()
        let directory = paths.runDirectory(project: project, task: task)
        let transcriptURL = directory.appendingPathComponent("\(transcriptPrefix)-\(UUID().uuidString.shortID).log")
        var run = RunRecord(
            projectId: project.id,
            taskId: task.id,
            executor: "\(request.provider.rawValue)_runner",
            model: request.modelProfile?.modelName,
            status: .running,
            command: nil,
            outputPath: transcriptURL.path,
            summary: summary,
            startedAt: startedAt
        )

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try repository.upsert(run: run)
            try reloadRunsAndArtifacts()

            let result = try await adapter.execute(request)
            let log = runnerLogText(
                provider: request.provider,
                mode: request.mode,
                command: result.command.displayString,
                startedAt: startedAt,
                endedAt: result.endedAt,
                exitCode: Int(result.exitCode),
                standardOutput: result.standardOutput,
                standardError: result.standardError
            )
            try log.write(to: transcriptURL, atomically: true, encoding: .utf8)

            run.status = result.succeeded ? .succeeded : .failed
            run.command = result.command.displayString
            run.exitCode = Int(result.exitCode)
            run.summary = result.summary
            run.endedAt = result.endedAt
            try repository.upsert(run: run)

            if let existing = sessionLink {
                try repository.updateRunnerSessionLink(
                    id: existing.id,
                    status: result.succeeded ? successfulStatus : .failed,
                    lastSeenAt: result.endedAt,
                    lastSummary: result.summary,
                    transcriptPath: transcriptURL.path
                )
            } else if let sessionID = result.sessionMetadata?.sessionID, !sessionID.isEmpty {
                let newLink = RunnerSessionLink(
                    projectId: project.id,
                    taskId: task.id,
                    provider: request.provider,
                    sessionID: sessionID,
                    workspacePath: request.workspacePath,
                    lastMode: request.mode,
                    branchName: task.codexBranch ?? task.localBranch,
                    worktreePath: task.codexWorktreePath ?? task.localWorktreePath,
                    status: result.succeeded ? successfulStatus : .failed,
                    lastSeenAt: result.endedAt,
                    lastSummary: result.summary,
                    transcriptPath: transcriptURL.path
                )
                try repository.upsert(runnerSessionLink: newLink)
            }

            try reloadRunsAndArtifacts()
            selectedTaskID = task.id
            selectedRunOutput = log
            if result.succeeded {
                await refreshRunnerLifecycleBridge(project: project, task: task, result: result)
            } else {
                latestRunnerRecommendation = RunnerRecommendation(
                    action: .needsManualReview,
                    reason: "\(summary) failed. Review the runner transcript before continuing."
                )
                errorMessage = result.output
            }
            statusMessage = result.succeeded ? "\(summary) completed." : "\(summary) failed."
        } catch {
            let endedAt = Date()
            let log = runnerLogText(
                provider: request.provider,
                mode: request.mode,
                command: summary,
                startedAt: startedAt,
                endedAt: endedAt,
                exitCode: nil,
                standardOutput: "",
                standardError: error.localizedDescription
            )
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? log.write(to: transcriptURL, atomically: true, encoding: .utf8)
            run.status = .failed
            run.summary = error.localizedDescription
            run.endedAt = endedAt
            try? repository.upsert(run: run)
            selectedRunOutput = log
            latestRunnerRecommendation = RunnerRecommendation(
                action: .needsManualReview,
                reason: "\(summary) failed before lifecycle facts could be refreshed."
            )
            errorMessage = error.localizedDescription
        }
    }

    private func ensureRunnerWorkspace(
        project: Project,
        task: inout FactoryTask,
        repository: FactoryRepository
    ) async throws -> RunnerWorkspace {
        if let existing = try repository.latestRunnerWorkspace(taskId: task.id),
           !existing.archived,
           !existing.cleaned,
           FileManager.default.fileExists(atPath: existing.worktreePath) || project.type != .codeRepo {
            return existing
        }

        var branchName = task.codexBranch ?? task.localBranch ?? "worker/\(task.id.shortID)"
        var worktreePath: String
        if project.type == .codeRepo {
            guard let gitService else { throw FactoryError.missingSelection }
            if let codexPath = task.codexWorktreePath, Self.existingDirectory(codexPath) {
                worktreePath = codexPath
                branchName = task.codexBranch ?? branchName
            } else if let localPath = task.localWorktreePath, Self.existingDirectory(localPath) {
                worktreePath = localPath
                branchName = task.localBranch ?? branchName
            } else {
                let result = try await gitService.createWorktree(project: project, task: task, flavor: .codex)
                task.codexBranch = result.branch
                task.codexWorktreePath = result.path
                task.setBaseBranchCommit(await gitService.defaultBranchHead(project: project), for: .codex)
                task.updatedAt = Date()
                try repository.upsert(task: task)
                branchName = result.branch
                worktreePath = result.path
            }
        } else {
            worktreePath = project.path
            branchName = "manual/\(task.id.shortID)"
        }

        let baseCommit = project.type == .codeRepo ? await gitService?.defaultBranchHead(project: project) : nil
        let headCommit = await repoHead(path: worktreePath)
        let workspace = RunnerWorkspace(
            projectId: project.id,
            taskId: task.id,
            branchName: branchName,
            worktreePath: worktreePath,
            baseCommit: task.codexBaseBranchCommit ?? task.localBaseBranchCommit ?? baseCommit,
            headCommit: headCommit
        )
        try repository.upsert(runnerWorkspace: workspace)
        try reload()
        selectedTaskID = task.id
        return workspace
    }

    private func runWorkerLoop(
        project: Project,
        task: FactoryTask,
        workspace: RunnerWorkspace,
        existingSession: RunnerSession?,
        runReason: String,
        additionalInstruction: String = "",
        adapter: RunnerProviderAdapter,
        repository: FactoryRepository
    ) async throws {
        let startedAt = Date()
        let directory = paths.runDirectory(project: project, task: task)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let promptURL = directory.appendingPathComponent("\(runReason)-\(UUID().uuidString.shortID)-prompt.md")
        let logURL = directory.appendingPathComponent("\(runReason)-\(UUID().uuidString.shortID).log")
        let prompt = workerPrompt(project: project, task: task, additionalInstruction: additionalInstruction)
        try prompt.write(to: promptURL, atomically: true, encoding: .utf8)

        var session = existingSession ?? RunnerSession(
            workspaceId: workspace.id,
            provider: .codex,
            mode: .coding,
            modelProfile: selectedRunnerProjectLink?.preferredModelProfile,
            status: .active
        )
        session.status = .active
        session.updatedAt = Date()
        try repository.upsert(runnerSession: session)
        try repository.insert(agentTurn: AgentTurn(sessionId: session.id, role: "user", content: prompt))

        let linkedSessionID = session.externalSessionId
        let commandRequest = try codexCLIService.commandRequest(for: linkedSessionID.map {
            .execResume(sessionId: $0, workspacePath: workspace.worktreePath, instruction: prompt, sandboxMode: .workspaceWrite)
        } ?? .exec(workspacePath: workspace.worktreePath, instruction: prompt, sandboxMode: .workspaceWrite))

        var execution = RunnerExecution(
            sessionId: session.id,
            runReason: runReason,
            command: commandRequest.displayString,
            status: .running,
            logPath: logURL.path,
            beforeRepoState: await repoState(path: workspace.worktreePath),
            startedAt: startedAt
        )
        try repository.upsert(runnerExecution: execution)
        try markWorkerAssigned(task: task, executionID: execution.id, repository: repository)
        try reloadWorkerState()
        statusMessage = runReason == "assign_to_ai_worker" ? "AI Worker running..." : "AI Worker resumed..."

        let request = RunnerRequest(
            provider: .codex,
            mode: .coding,
            workspacePath: workspace.worktreePath,
            taskID: task.id,
            instruction: prompt,
            modelProfile: selectedRunnerProjectLink?.preferredModelProfile,
            linkedSessionID: linkedSessionID,
            sandboxMode: .workspaceWrite
        )
        let processRegistration = WorkerProcessRegistration(
            executionId: execution.id,
            sessionId: session.id,
            taskId: task.id,
            startedAt: startedAt,
            command: commandRequest.displayString,
            workingDirectory: commandRequest.workingDirectory?.path
        )
        let rawResult = try await workerCommandExecutor.execute(commandRequest, registration: processRegistration)
        let result = RunnerResult(
            provider: request.provider,
            mode: request.mode,
            command: RunnerCommand(
                executable: commandRequest.executable,
                arguments: commandRequest.arguments,
                workingDirectory: commandRequest.workingDirectory?.path
            ),
            standardOutput: rawResult.standardOutput,
            standardError: rawResult.standardError,
            exitCode: rawResult.exitCode,
            startedAt: startedAt,
            endedAt: Date(),
            summary: CodexSessionResultImporter.shortSummary(
                from: rawResult,
                fallback: rawResult.wasCancelled ? "AI Worker cancelled." : (rawResult.succeeded ? "AI Worker completed." : "AI Worker failed.")
            ),
            sessionMetadata: RunnerSessionMetadata(sessionID: CodexSessionResultImporter.detectSessionID(in: rawResult.output))
        )
        let log = runnerLogText(
            provider: request.provider,
            mode: request.mode,
            command: result.command.displayString,
            startedAt: startedAt,
            endedAt: result.endedAt,
            exitCode: Int(result.exitCode),
            standardOutput: result.standardOutput,
            standardError: result.standardError
        ) + (rawResult.wasCancelled ? "\n[\(DateCoding.string(from: Date()))] Cancellation requested by user.\n" : "")
        try log.write(to: logURL, atomically: true, encoding: .utf8)
        try repository.insert(agentTurn: AgentTurn(sessionId: session.id, role: "assistant", content: result.output))

        session.externalSessionId = result.sessionMetadata?.sessionID ?? session.externalSessionId
        session.status = rawResult.wasCancelled ? .paused : (result.succeeded ? .completed : .failed)
        session.transcriptPath = logURL.path
        session.updatedAt = result.endedAt
        try repository.upsert(runnerSession: session)

        execution.command = result.command.displayString
        execution.status = rawResult.wasCancelled ? .cancelled : (result.succeeded ? .completed : .failed)
        execution.exitCode = Int(result.exitCode)
        execution.afterRepoState = await repoState(path: workspace.worktreePath)
        execution.endedAt = result.endedAt
        try repository.upsert(runnerExecution: execution)

        var updatedWorkspace = workspace
        updatedWorkspace.headCommit = await repoHead(path: workspace.worktreePath)
        updatedWorkspace.updatedAt = Date()
        try repository.upsert(runnerWorkspace: updatedWorkspace)

        if !rawResult.wasCancelled || result.output.range(of: "WORKER REPORT", options: [.caseInsensitive]) != nil {
            try ingestWorkerReport(
                result: result,
                task: task,
                session: session,
                execution: execution,
                repository: repository
            )
        }
        try await refreshWorkerLifecycleSnapshot(project: project, task: task, repository: repository)
        try reload()
        selectedTaskID = task.id
        selectedRunOutput = log
        statusMessage = rawResult.wasCancelled ? "AI Worker cancelled. Log and worktree were preserved." : (result.succeeded ? "AI Worker completed. Review the worker report." : "AI Worker failed. Review the worker log.")
    }

    private func ingestWorkerReport(
        result: RunnerResult,
        task: FactoryTask,
        session: RunnerSession,
        execution: RunnerExecution,
        repository: FactoryRepository
    ) throws {
        let parsed = WorkerReportParser.parse(
            output: result.output,
            sessionId: session.id,
            executionId: execution.id,
            sourceTaskId: task.id
        )
        guard let report = parsed.report else {
            let failedReport = WorkerReport(
                sessionId: session.id,
                executionId: execution.id,
                status: .failed,
                parseStatus: parsed.status,
                parseError: parsed.error,
                summary: parsed.error ?? "Worker report could not be parsed.",
                rawText: parsed.rawReportText
            )
            try repository.upsert(workerReport: failedReport)
            try repository.insert(runnerNotification: RunnerNotification(
                taskId: task.id,
                sessionId: session.id,
                executionId: execution.id,
                level: .warning,
                message: parsed.error ?? "Worker report needs review."
            ))
            return
        }

        try repository.upsert(workerReport: report)
        if report.parseStatus == .partiallyParsed {
            try repository.insert(runnerNotification: RunnerNotification(
                taskId: task.id,
                sessionId: session.id,
                executionId: execution.id,
                level: .warning,
                message: report.parseError ?? "Worker report partially parsed."
            ))
        }
        for proposal in parsed.proposals {
            try repository.upsert(taskProposal: proposal)
        }
        try applyWorkerReportStatus(report, to: task, executionID: execution.id, repository: repository)
    }

    private func markWorkerAssigned(
        task: FactoryTask,
        executionID: String,
        repository: FactoryRepository
    ) throws {
        guard task.status != .done, task.status != .archived, task.status != .building else { return }
        var updated = task
        try updateStatus(
            for: &updated,
            to: .building,
            source: .automatic,
            eventKind: .statusChangedAutomatically,
            message: "AI Worker automation changed task status. Previous status: \(task.status.displayName). New status: Building. Reason: worker execution started. Evidence: execution \(executionID.shortID).",
            repository: repository
        )
    }

    private func applyWorkerReportStatus(
        _ report: WorkerReport,
        to task: FactoryTask,
        executionID: String,
        repository: FactoryRepository
    ) throws {
        guard task.status != .done, task.status != .archived else { return }
        let nextStatus: TaskStatus?
        switch report.status {
        case .blocked:
            nextStatus = .blocked
        case .completed, .needsReview:
            nextStatus = .readyForReview
        case .failed:
            nextStatus = nil
        }
        guard let nextStatus, nextStatus != task.status else { return }
        var updated = task
        try updateStatus(
            for: &updated,
            to: nextStatus,
            source: .automatic,
            eventKind: .statusChangedAutomatically,
            message: "AI Worker automation changed task status. Previous status: \(task.status.displayName). New status: \(nextStatus.displayName). Reason: worker report status \(report.status.displayName). Evidence: execution \(executionID.shortID); parse \(report.parseStatus.displayName); summary \(report.summary.nonEmptyTrimmed ?? "unavailable").",
            repository: repository
        )
    }

    private func refreshWorkerLifecycleSnapshot(
        project: Project,
        task: FactoryTask,
        repository: FactoryRepository
    ) async throws {
        let workspace = try repository.latestRunnerWorkspace(taskId: task.id)
        let execution = try repository.latestRunnerExecution(taskId: task.id)
        let report = try repository.latestWorkerReport(taskId: task.id)
        let notifications = try repository.runnerNotifications(taskId: task.id, unreadOnly: true)
        let proposals = try repository.taskProposals(sourceTaskId: task.id, status: .proposed)
        let snapshot = await lifecycleMonitorService.snapshot(
            project: project,
            task: task,
            workspace: workspace,
            latestExecution: execution,
            latestReport: report,
            unseenNotifications: notifications.count,
            proposedTasksCount: proposals.count
        )
        try repository.upsert(lifecycleSnapshot: snapshot)
    }

    private func repoState(path: String) async -> String? {
        guard Self.existingDirectory(path) else { return nil }
        let result = try? await commandRunner.run(CommandRequest(
            executable: "git",
            arguments: ["status", "--short", "--branch"],
            workingDirectory: URL(fileURLWithPath: path)
        ))
        return result?.output
    }

    private func repoHead(path: String) async -> String? {
        guard Self.existingDirectory(path) else { return nil }
        let result = try? await commandRunner.run(CommandRequest(
            executable: "git",
            arguments: ["rev-parse", "--short", "HEAD"],
            workingDirectory: URL(fileURLWithPath: path)
        ))
        guard result?.succeeded == true else { return nil }
        return result?.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runCodexCommand(
        kind: CodexSessionCommandKind,
        summary: String,
        commandText: String,
        transcriptPrefix: String,
        sessionLink: CodexSessionLink?,
        successfulStatus: CodexSessionStatus,
        operation: @escaping () async throws -> CommandResult
    ) async {
        guard let repository, let project = selectedProject else {
            errorMessage = FactoryError.missingSelection.localizedDescription
            return
        }

        let task = selectedTask
        isWorking = true
        defer { isWorking = false }

        let startedAt = Date()
        let directory: URL
        if let task {
            directory = paths.runDirectory(project: project, task: task)
        } else {
            directory = paths.runs
                .appendingPathComponent(Slug.make(project.name), isDirectory: true)
                .appendingPathComponent("project", isDirectory: true)
        }
        let transcriptURL = directory.appendingPathComponent("\(transcriptPrefix)-\(UUID().uuidString.shortID).log")
        var run: RunRecord?

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let task {
                let created = RunRecord(
                    projectId: project.id,
                    taskId: task.id,
                    executor: "codex_cli",
                    status: .running,
                    command: commandText,
                    outputPath: transcriptURL.path,
                    summary: "\(kind.displayName): \(summary)",
                    startedAt: startedAt
                )
                try repository.upsert(run: created)
                run = created
                try reloadRunsAndArtifacts()
            }

            let result = try await operation()
            let endedAt = Date()
            let log = codexLogText(
                kind: kind,
                command: result.command,
                startedAt: startedAt,
                endedAt: endedAt,
                exitCode: Int(result.exitCode),
                standardOutput: result.standardOutput,
                standardError: result.standardError
            )
            try log.write(to: transcriptURL, atomically: true, encoding: .utf8)
            let importedStatus = CodexSessionResultImporter.status(for: result, successfulStatus: successfulStatus)
            let importedSummary = CodexSessionResultImporter.shortSummary(
                from: result,
                fallback: result.succeeded ? "\(summary) completed." : "\(summary) failed."
            )

            if var run {
                run.status = importedStatus == .failed ? .failed : .succeeded
                run.exitCode = Int(result.exitCode)
                run.summary = "\(kind.displayName): \(importedSummary)"
                run.endedAt = endedAt
                try repository.upsert(run: run)
            }

            if let sessionLink {
                try repository.updateCodexSessionLink(
                    id: sessionLink.id,
                    status: importedStatus,
                    lastSeenAt: endedAt,
                    lastSummary: importedSummary,
                    transcriptPath: transcriptURL.path
                )
            }

            try reloadRunsAndArtifacts()
            selectedRunOutput = log
            if result.succeeded, importedStatus != .failed {
                await refreshCodexLifecycleBridge(project: project, task: task, result: result)
            }
            statusMessage = importedStatus == .failed ? "\(summary) failed." : "\(summary) completed."
            if importedStatus == .failed {
                latestCodexSessionRecommendation = CodexSessionResultRecommendation(
                    action: .needsManualReview,
                    reason: "\(summary) failed. Review the Codex transcript before continuing."
                )
                errorMessage = result.output.isEmpty ? "\(summary) failed." : result.output
            }
        } catch {
            let endedAt = Date()
            let log = codexLogText(
                kind: kind,
                command: commandText,
                startedAt: startedAt,
                endedAt: endedAt,
                exitCode: nil,
                standardOutput: "",
                standardError: error.localizedDescription
            )
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? log.write(to: transcriptURL, atomically: true, encoding: .utf8)
            if var run {
                run.status = .failed
                run.summary = "\(summary) failed"
                run.endedAt = endedAt
                try? repository.upsert(run: run)
            }
            if let sessionLink {
                try? repository.updateCodexSessionLink(
                    id: sessionLink.id,
                    status: .failed,
                    lastSeenAt: endedAt,
                    lastSummary: error.localizedDescription,
                    transcriptPath: transcriptURL.path
                )
            }
            try? reloadRunsAndArtifacts()
            selectedRunOutput = log
            latestCodexSessionRecommendation = CodexSessionResultRecommendation(
                action: .needsManualReview,
                reason: "\(summary) failed before lifecycle facts could be refreshed."
            )
            errorMessage = error.localizedDescription
        }
    }

    private func codexWorkspacePath(project: Project, task: FactoryTask?) -> String {
        selectedCodexProjectLink?.workspacePath
            ?? task?.codexWorktreePath
            ?? task?.localWorktreePath
            ?? project.path
    }

    private func runnerWorkspacePath(project: Project, task: FactoryTask?) -> String {
        selectedRunnerProjectLink?.workspacePath
            ?? task?.localWorktreePath
            ?? task?.codexWorktreePath
            ?? project.path
    }

    private func codexMode(workspacePath: String, project: Project) -> CodexExecutionMode {
        if workspacePath == project.path {
            return .local
        }
        if workspacePath.contains("/.factory/worktrees/") {
            return .worktree
        }
        return .unknown
    }

    private func refreshCodexLifecycleBridge(project: Project, task: FactoryTask?, result: CommandResult) async {
        guard let task else {
            latestCodexSessionRecommendation = CodexSessionResultRecommendation(
                action: .noAction,
                reason: "Codex command completed at the project level."
            )
            return
        }
        guard let repository else {
            latestCodexSessionRecommendation = CodexSessionResultRecommendation(
                action: .needsManualReview,
                reason: "Repository state was unavailable after the Codex command."
            )
            return
        }

        do {
            if let gitService {
                gitSnapshot = try await gitService.snapshot(project: project, task: task)
            }
            let facts = try await taskLifecycleFacts(project: project, task: task, repository: repository)
            let evaluation = TaskLifecycleService.evaluate(facts)
            latestCodexSessionRecommendation = codexRecommendation(
                result: result,
                gitSnapshot: gitSnapshot,
                latestTestStatus: facts.latestTestStatus,
                lifecycleEvaluation: evaluation,
                currentStatus: task.status
            )
            latestLifecycleReport = nil
        } catch {
            latestCodexSessionRecommendation = CodexSessionResultRecommendation(
                action: .needsManualReview,
                reason: "Codex command completed, but lifecycle facts could not be refreshed: \(error.localizedDescription)"
            )
        }
    }

    private func refreshRunnerLifecycleBridge(project: Project, task: FactoryTask?, result: RunnerResult) async {
        guard let task else {
            latestRunnerRecommendation = RunnerRecommendation(
                action: .noAction,
                reason: "Runner command completed at the project level."
            )
            return
        }
        guard let repository else {
            latestRunnerRecommendation = RunnerRecommendation(
                action: .needsManualReview,
                reason: "Repository state was unavailable after the runner command."
            )
            return
        }

        do {
            if let gitService {
                gitSnapshot = try await gitService.snapshot(project: project, task: task)
            }
            let facts = try await taskLifecycleFacts(project: project, task: task, repository: repository)
            let evaluation = TaskLifecycleService.evaluate(facts)
            latestRunnerRecommendation = runnerRecommendation(
                result: result,
                gitSnapshot: gitSnapshot,
                latestTestStatus: facts.latestTestStatus,
                lifecycleEvaluation: evaluation,
                currentStatus: task.status
            )
            latestLifecycleReport = nil
        } catch {
            latestRunnerRecommendation = RunnerRecommendation(
                action: .needsManualReview,
                reason: "Runner command completed, but lifecycle facts could not be refreshed: \(error.localizedDescription)"
            )
        }
    }

    private func codexRecommendation(
        result: CommandResult,
        gitSnapshot: GitSnapshot,
        latestTestStatus: WorkflowCheckStatus?,
        lifecycleEvaluation: TaskLifecycleEvaluation,
        currentStatus: TaskStatus
    ) -> CodexSessionResultRecommendation {
        if CodexSessionResultImporter.containsClearFailure(result.output) {
            return CodexSessionResultRecommendation(
                action: .needsManualReview,
                reason: "Codex output contains a failure signal."
            )
        }
        if !gitSnapshot.changedFiles.isEmpty {
            if latestTestStatus == .passed {
                return CodexSessionResultRecommendation(
                    action: .reviewDiff,
                    reason: "Git changes are present and latest tests passed."
                )
            }
            return CodexSessionResultRecommendation(
                action: .runTests,
                reason: "Git changes are present after Codex activity."
            )
        }
        if lifecycleEvaluation.isAutomaticSafe,
           lifecycleEvaluation.recommendedStatus != currentStatus {
            return CodexSessionResultRecommendation(
                action: .syncLifecycle,
                reason: "Lifecycle evaluation has a safe status recommendation."
            )
        }
        if lifecycleEvaluation.requiredManualReview {
            return CodexSessionResultRecommendation(
                action: .needsManualReview,
                reason: lifecycleEvaluation.reason
            )
        }
        return CodexSessionResultRecommendation(
            action: .noAction,
            reason: "No Git changes or lifecycle updates were detected."
        )
    }

    private func runnerRecommendation(
        result: RunnerResult,
        gitSnapshot: GitSnapshot,
        latestTestStatus: WorkflowCheckStatus?,
        lifecycleEvaluation: TaskLifecycleEvaluation,
        currentStatus: TaskStatus
    ) -> RunnerRecommendation {
        if CodexSessionResultImporter.containsClearFailure(result.output) {
            return RunnerRecommendation(
                action: .needsManualReview,
                reason: "Runner output contains a failure signal."
            )
        }
        if !gitSnapshot.changedFiles.isEmpty {
            if latestTestStatus == .passed {
                return RunnerRecommendation(
                    action: .reviewDiff,
                    reason: "Git changes are present and latest tests passed."
                )
            }
            return RunnerRecommendation(
                action: .runTests,
                reason: "Git changes are present after runner activity."
            )
        }
        if lifecycleEvaluation.isAutomaticSafe,
           lifecycleEvaluation.recommendedStatus != currentStatus {
            return RunnerRecommendation(
                action: .syncLifecycle,
                reason: "Lifecycle evaluation has a safe status recommendation."
            )
        }
        if lifecycleEvaluation.requiredManualReview {
            return RunnerRecommendation(
                action: .needsManualReview,
                reason: lifecycleEvaluation.reason
            )
        }
        return RunnerRecommendation(
            action: .noAction,
            reason: "No Git changes or lifecycle updates were detected."
        )
    }

    private func codexLogText(
        kind: CodexSessionCommandKind,
        command: String,
        startedAt: Date,
        endedAt: Date,
        exitCode: Int?,
        standardOutput: String,
        standardError: String
    ) -> String {
        """
        Kind: \(kind.rawValue)
        Command: \(command)
        Started: \(DateCoding.string(from: startedAt))
        Ended: \(DateCoding.string(from: endedAt))
        Exit code: \(exitCode.map(String.init) ?? "unavailable")

        stdout:
        \(standardOutput.isEmpty ? "(empty)" : standardOutput)

        stderr:
        \(standardError.isEmpty ? "(empty)" : standardError)
        """
    }

    private func runnerLogText(
        provider: RunnerProvider,
        mode: RunnerMode,
        command: String,
        startedAt: Date,
        endedAt: Date,
        exitCode: Int?,
        standardOutput: String,
        standardError: String
    ) -> String {
        """
        Provider: \(provider.rawValue)
        Mode: \(mode.rawValue)
        Command: \(command)
        Started: \(DateCoding.string(from: startedAt))
        Ended: \(DateCoding.string(from: endedAt))
        Exit code: \(exitCode.map(String.init) ?? "unavailable")

        stdout:
        \(standardOutput.isEmpty ? "(empty)" : standardOutput)

        stderr:
        \(standardError.isEmpty ? "(empty)" : standardError)
        """
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
            task.triageStatus = FactoryTaskTriageStatus.fromLegacyStatus(status)
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

    public static func isMarkdownPath(_ path: String) -> Bool {
        URL(fileURLWithPath: path).pathExtension.lowercased() == "md"
    }

    public static func normalizedMarkdownPath(_ path: String) -> String {
        MarkdownDocumentStore.normalizedMarkdownPath(path)
    }

    private func clearStoredWorktreePath(displayID: String, action: WorktreeRepairAction) {
        perform {
            guard let repository = self.repository, var task = self.selectedTask else {
                throw FactoryError.missingSelection
            }
            let previousPath: String?
            switch displayID {
            case "local":
                previousPath = task.localWorktreePath
                task.localWorktreePath = nil
            case "codex":
                previousPath = task.codexWorktreePath
                task.codexWorktreePath = nil
            default:
                self.statusMessage = "Unknown worktree reference."
                return
            }
            task.updatedAt = Date()
            try repository.upsert(task: task)
            try repository.insert(taskEvent: TaskEvent(
                taskId: task.id,
                kind: .statusChangedAutomatically,
                source: .automatic,
                message: "\(action.displayName): cleared stale \(displayID) worktree path \(previousPath ?? "missing"). Branch metadata was preserved."
            ))
            try self.reload()
            self.selectedTaskID = task.id
            self.latestLifecycleReport = nil
            self.statusMessage = "\(action.displayName) completed. Branch metadata was preserved."
        }
    }

    private func worktreeFlavor(for displayID: String) -> WorktreeFlavor? {
        switch displayID {
        case "local":
            return .local
        case "codex":
            return .codex
        default:
            return nil
        }
    }

    private func worktreeFlavor(for task: FactoryTask, item: LifecycleItem) -> WorktreeFlavor? {
        if item.branch == task.localBranch || item.path == task.localWorktreePath {
            return .local
        }
        if item.branch == task.codexBranch || item.path == task.codexWorktreePath {
            return .codex
        }
        return nil
    }

    public func refreshSelectedTaskWorktree(displayID: String) async {
        guard let project = selectedProject, var task = selectedTask, let repository, let gitService,
              let flavor = worktreeFlavor(for: displayID) else {
            errorMessage = FactoryError.missingSelection.localizedDescription
            return
        }

        isWorking = true
        defer { isWorking = false }

        do {
            let assessment = await gitService.assessTaskWorktreeRefresh(project: project, task: task, flavor: flavor)
            guard assessment.canRefresh else {
                statusMessage = assessment.reason
                errorMessage = assessment.reason
                return
            }

            let result = try await gitService.refreshTaskWorktreeFromDefault(project: project, task: task, flavor: flavor)
            switch flavor {
            case .local:
                task.localBranch = result.branch
                task.localWorktreePath = result.path
            case .codex:
                task.codexBranch = result.branch
                task.codexWorktreePath = result.path
            }
            task.setBaseBranchCommit(await gitService.defaultBranchHead(project: project), for: flavor)
            try repository.upsert(task: task)
            try reload()
            selectedTaskID = task.id
            await refreshGitStatus()
            await refreshLifecycleScan()
            statusMessage = "Refreshed \(flavor == .local ? "task" : "alternate") worktree from \(project.defaultBranch)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleMissingWorktreePath(_ path: String) {
        statusMessage = "Missing Worktree: This task references a worktree path that no longer exists."
        selectedRunOutput = """
        Missing Worktree

        This task references a worktree path that no longer exists.

        \(path)

        Use the Task Worktree repair actions to remove the stale reference, mark it cleaned, recreate from branch, relink an existing worktree, or archive the task.
        """
        if let repository, let task = selectedTask {
            try? repository.insert(taskEvent: TaskEvent(
                taskId: task.id,
                kind: .statusChangedAutomatically,
                source: .automatic,
                message: "Lifecycle hygiene detected missing worktree reference: \(path)."
            ))
            try? reloadRunsAndArtifacts()
        }
    }

    private func firstMissingSelectedWorktreePath(_ task: FactoryTask) -> String? {
        TaskWorktreeDisplayMapper.displays(for: task)
            .first { $0.state == .missingPath }?
            .path
    }

    private func auditMissingWorktreeReferences(task: FactoryTask, summaries: [TaskWorktreeSummary], repository: FactoryRepository) throws {
        for summary in summaries where !summary.exists {
            try repository.insert(taskEvent: TaskEvent(
                taskId: task.id,
                kind: .statusChangedAutomatically,
                source: .automatic,
                message: "Lifecycle hygiene detected missing worktree reference: \(summary.path)."
            ))
        }
    }

    private func ensureLifecycleGateAllowsStart(project: Project, selectedTask: FactoryTask?) async -> Bool {
        guard project.type == .codeRepo else { return true }
        guard let repository, let gitService else { return true }
        do {
            let projectTasks = tasks.filter { $0.projectId == project.id }
            let projectRuns = try repository.runs(projectId: project.id)
            let projectArtifacts = try repository.artifacts(projectId: project.id)
            let report = await gitService.lifecycleReport(
                project: project,
                selectedTask: selectedTask,
                tasks: projectTasks,
                runs: projectRuns,
                artifacts: projectArtifacts
            )
            latestLifecycleReport = report
            switch report.preflightGate.level {
            case .green:
                return true
            case .yellow:
                statusMessage = "Lifecycle scan has warnings; proceeding with caution."
                return true
            case .red:
                errorMessage = "Lifecycle preflight blocked this action. Open Lifecycle & Cleanup and fix red checks first."
                statusMessage = "Blocked by Lifecycle & Cleanup preflight."
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func latestExistingArtifact(type: ArtifactType) -> Artifact? {
        artifacts.first { $0.type == type.rawValue && FileManager.default.fileExists(atPath: $0.path) }
    }

    private func taskLifecycleFacts(project: Project, task: FactoryTask, repository: FactoryRepository) async throws -> TaskLifecycleFacts {
        let artifactSummaries = taskStateArtifactSummaries()
        let taskWorktreeSummaries = await taskStateWorktreeSummaries(task: task)
        let canonicalSummary = await canonicalWorktreeSummary(project: project)
        let gitFacts = await gitService?.taskLifecycleGitFacts(project: project, task: task)
        let missingWorktrees = taskWorktreeSummaries.filter { !$0.exists }
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
        let hasDiffReviewArtifact = artifactSummaries.contains { $0.type == .localDiffReview && $0.exists }
        let hasFinalReviewArtifact = artifactSummaries.contains { $0.type == .finalReview && $0.exists }
        let hasExistingWorktree = taskWorktreeSummaries.contains { $0.exists }
        let workflowSummaries = WorkflowCheckSummariesBuilder.build(
            project: project,
            runs: try repository.runs(taskId: task.id),
            artifacts: try repository.artifacts(taskId: task.id)
        )
        var cleanupSafetyState = Self.lifecycleCleanupSafetyState(
            hasRiskyPreflight: hasRiskyPreflight,
            hasExistingWorktree: gitFacts?.worktreePathExists ?? hasExistingWorktree,
            hasMissingWorktree: !missingWorktrees.isEmpty,
            hasImplementationChanges: gitFacts?.worktreeIsDirty ?? hasImplementationChanges,
            projectType: project.type
        )
        if gitFacts?.isAmbiguous == true {
            cleanupSafetyState = .ambiguous
        }
        let branchExists = gitFacts?.branchExists ?? (task.localBranch != nil || task.codexBranch != nil)
        let worktreeExists = gitFacts?.worktreePathExists ?? hasExistingWorktree
        let worktreeIsDirty = gitFacts?.worktreeIsDirty ?? (hasExistingWorktree ? hasImplementationChanges : nil)

        return TaskLifecycleFacts(
            currentStatus: task.status,
            taskType: task.type,
            hasBranch: branchExists,
            hasWorktree: worktreeExists,
            worktreeIsDirty: worktreeIsDirty,
            hasCommits: gitFacts?.hasCommits,
            hasUnmergedCommitsComparedToDefault: gitFacts?.hasUnmergedCommitsComparedToDefault,
            appearsMergedIntoDefault: gitFacts?.appearsMergedIntoDefault,
            defaultBranchResolved: gitFacts?.defaultBranchResolved,
            gitFactSource: gitFacts?.source ?? .none,
            isGitStateAmbiguous: gitFacts?.isAmbiguous ?? false,
            gitAmbiguityReasons: gitFacts?.ambiguityReasons ?? [],
            latestBuildStatus: Self.workflowStatus(.build, in: workflowSummaries),
            latestTestStatus: Self.latestTestStatus(in: workflowSummaries),
            latestVisualQCStatus: Self.workflowStatus(.visualQC, in: workflowSummaries),
            hasDiffReviewArtifact: hasDiffReviewArtifact,
            hasFinalReviewArtifact: hasFinalReviewArtifact,
            hasPlan: hasPlan,
            hasPlanReview: hasPlanReview,
            latestPlanDecision: latestDecision,
            hasApprovedPlan: hasApprovedPlan,
            hasPreflight: hasPreflight,
            hasRiskyPreflight: hasRiskyPreflight,
            hasStalePreflight: hasStalePreflight,
            cleanupSafetyState: cleanupSafetyState
        )
    }

    private static func workflowStatus(_ kind: WorkflowRunKind, in summaries: [WorkflowCheckSummary]) -> WorkflowCheckStatus? {
        summaries.first { $0.kind == kind }?.status
    }

    private static func latestTestStatus(in summaries: [WorkflowCheckSummary]) -> WorkflowCheckStatus? {
        let testStatuses = [WorkflowRunKind.unitTests, .integrationTests, .e2eTests]
            .compactMap { workflowStatus($0, in: summaries) }
            .filter { $0 != .notConfigured && $0 != .notRun }
        if testStatuses.contains(.failed) { return .failed }
        if testStatuses.contains(.running) { return .running }
        if testStatuses.contains(.passed) { return .passed }
        if testStatuses.contains(.cancelled) { return .cancelled }
        if testStatuses.contains(.unknown) { return .unknown }
        return nil
    }

    private static func lifecycleCleanupSafetyState(
        hasRiskyPreflight: Bool,
        hasExistingWorktree: Bool,
        hasMissingWorktree: Bool,
        hasImplementationChanges: Bool,
        projectType: ProjectType
    ) -> TaskLifecycleCleanupSafetyState {
        if hasRiskyPreflight { return .blocked }
        if hasMissingWorktree { return .missingWorktree }
        if hasImplementationChanges { return .dirty }
        if hasExistingWorktree || projectType != .codeRepo { return .safe }
        return .unknown
    }

    private func hasExistingTaskWorktree(_ task: FactoryTask) -> Bool {
        [task.localWorktreePath, task.codexWorktreePath]
            .compactMap { $0 }
            .contains { path in
                Self.existingDirectory(path)
            }
    }

    private func worktreeRequirementMessage(for nextStep: String) -> String {
        "This task can stay worktree-optional for planning, review, and clarification, but \(nextStep) is a concrete repo-scoped step. Create, relink, or repair a task worktree before continuing so the repo work happens in an isolated checkout."
    }

    private static func existingDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
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

    private func workItemScopingPrompt(project: Project, task: FactoryTask) -> String {
        """
        You are Factory Desktop's runner-agnostic scoping assistant.
        Scope this task without editing code.

        Return JSON only with this shape:
        {
          "title": "...",
          "kind": "idea|bug|feature|task|chore|tech_debt",
          "goal": "...",
          "context": "...",
          "acceptanceCriteria": ["..."],
          "priorityLabel": "critical|high|normal|low|someday",
          "readiness": "raw|needs_scoping|scoped|executable",
          "category": "...",
          "effort": "unknown|small|medium|large",
          "risk": "unknown|low|medium|high",
          "dependencies": "...",
          "nonGoals": "...",
          "scopingNotes": "...",
          "suggestedSplit": "...",
          "recommendedNextAction": "..."
        }

        Project:
        - Name: \(project.name)
        - Type: \(project.type.rawValue)
        - Path: \(project.path)

        Task:
        - Title: \(task.title)
        - Kind: \(task.kind.rawValue)
        - Status: \(task.status.rawValue)
        - Readiness: \(task.readiness.rawValue)
        - Priority: \(task.priorityLabel.rawValue)
        - Category: \(task.category.isEmpty ? "unknown" : task.category)
        - Source: \(task.source.isEmpty ? "unknown" : task.source)
        - Goal: \(task.goal.isEmpty ? "missing" : task.goal)
        - Context: \(task.context.isEmpty ? "missing" : task.context)
        - Acceptance criteria: \(task.acceptanceCriteria.isEmpty ? "missing" : task.acceptanceCriteria.joined(separator: " | "))
        - Dependencies: \(task.dependencies.isEmpty ? "none" : task.dependencies)
        - Non-goals: \(task.nonGoals.isEmpty ? "none" : task.nonGoals)

        Prefer practical scoping. Keep the title concise, acceptance criteria testable, and the next action explicit.
        Mark readiness executable only when the task is small and clear enough for coding-mode dispatch.
        If it is too broad, keep readiness scoped or needs_scoping and use suggestedSplit to describe child tasks.
        """
    }

    private func taskDispatchPrompt(project: Project, task: FactoryTask) -> String {
        let acceptance = task.acceptanceCriteria.isEmpty
            ? "- No explicit acceptance criteria provided."
            : task.acceptanceCriteria.map { "- \($0)" }.joined(separator: "\n")
        let tests = project.commandConfiguration.unitTests.map { "- \($0)" } ?? "- No unit test command configured."
        return """
        You are Factory Desktop's coding runner.
        Execute this task in a safe, review-oriented way. Do not mark the task done yourself.

        Task:
        - Title: \(task.title)
        - ID: \(task.id)
        - Status: \(task.status.rawValue)
        - Kind: \(task.kind.rawValue)
        - Readiness: \(task.readiness.rawValue)
        - Priority: \(task.priorityLabel.rawValue)

        Goal:
        \(task.goal.isEmpty ? task.title : task.goal)

        Context:
        \(task.context.isEmpty ? "No extra context provided." : task.context)

        Acceptance criteria:
        \(acceptance)

        Constraints:
        - Keep lifecycle sync as the only authority for persisted task status changes.
        - Do not claim the task is done just because code was changed.
        - Prefer minimal safe changes with clear verification.

        Verification commands:
        \(tests)
        """
    }

    private func workerPrompt(project: Project, task: FactoryTask, additionalInstruction: String = "") -> String {
        let acceptance = task.acceptanceCriteria.isEmpty
            ? "- No explicit acceptance criteria provided."
            : task.acceptanceCriteria.map { "- \($0)" }.joined(separator: "\n")
        let verificationCommands = [
            project.commandConfiguration.build,
            project.commandConfiguration.unitTests,
            project.commandConfiguration.integrationTests,
            project.commandConfiguration.e2eTests,
            project.commandConfiguration.visualQC
        ]
        .compactMap { $0 }
        let tests = verificationCommands.isEmpty
            ? "- No verification commands configured. If you do not run tests, say so explicitly."
            : verificationCommands.map { "- \($0)" }.joined(separator: "\n")
        let followUp = additionalInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let followUpSection = followUp.isEmpty ? "" : """

        User follow-up instruction for this worker turn:
        \(followUp)

        Follow the user follow-up where it is consistent with the task and safety rules.
        """

        return """
        You are Factory Desktop's AI Worker for one FactoryTask.
        Work inside the assigned workspace only. Make focused implementation changes for this task when needed.

        Safety rules:
        - Do not mark the task Done.
        - Do not merge, push, delete worktrees, or clean worktrees.
        - Do not create real backlog tasks.
        - Keep changes scoped to this FactoryTask.
        - If tests are not run, explicitly say tests were not run and why.

        Project:
        - Name: \(project.name)
        - Type: \(project.type.rawValue)
        - Path: \(project.path)
        - Default branch: \(project.defaultBranch)

        FactoryTask:
        - ID: \(task.id)
        - Title: \(task.title)
        - Type: \(task.type.rawValue)
        - Status: \(task.status.rawValue)
        - Priority: \(task.priorityLabel.rawValue)
        - Readiness: \(task.readiness.rawValue)

        Goal:
        \(task.goal.isEmpty ? task.title : task.goal)

        Context:
        \(task.context.isEmpty ? "No extra context provided." : task.context)

        Acceptance criteria:
        \(acceptance)

        Suggested verification:
        \(tests)
        \(followUpSection)

        Finish your response with this exact structured block:

        WORKER REPORT
        Status: completed | needs_review | blocked | failed
        Summary:
        Files Changed:
        Tests Run:
        Risks:
        Blockers:
        Follow-up Tasks Proposed:
        Next Recommended Action:
        Recommended Task Status:

        Follow-up tasks must be proposals only. Use "None" when there are none.
        Recommended Task Status may be In Progress, Needs Review, Blocked, or blank. Never recommend Done.
        """
    }

    private func mergeScopingResult(_ result: RunnerResult, into task: FactoryTask) -> FactoryTask {
        var updated = task
        if let draft = parseBacklogScopingDraft(from: result.output) {
            if let title = draft.title?.nonEmptyTrimmed { updated.title = title }
            if let kind = draft.kind.flatMap(FactoryTaskKind.init(rawValue:)) { updated.kind = kind }
            if let goal = draft.goal?.nonEmptyTrimmed { updated.goal = goal }
            if let context = draft.context?.nonEmptyTrimmed { updated.context = context }
            if let acceptanceCriteria = draft.acceptanceCriteria?.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }), !acceptanceCriteria.isEmpty {
                updated.acceptanceCriteria = acceptanceCriteria
            }
            if let priorityLabel = draft.priorityLabel.flatMap(FactoryTaskPriorityLabel.init(rawValue:)) {
                updated.priorityLabel = priorityLabel
                updated.priority = priorityLabel.taskPriority
            }
            if let readiness = draft.readiness.flatMap(FactoryTaskReadiness.init(rawValue:)) { updated.readiness = readiness }
            if let category = draft.category?.nonEmptyTrimmed { updated.category = category }
            if let effort = draft.effort.flatMap(FactoryTaskEffort.init(rawValue:)) { updated.effort = effort }
            if let risk = draft.risk.flatMap(FactoryTaskRisk.init(rawValue:)) { updated.risk = risk }
            if let dependencies = draft.dependencies?.nonEmptyTrimmed { updated.dependencies = dependencies }
            if let nonGoals = draft.nonGoals?.nonEmptyTrimmed { updated.nonGoals = nonGoals }
            if let scopingNotes = draft.scopingNotes?.nonEmptyTrimmed { updated.scopingNotes = scopingNotes }
            if let suggestedSplit = draft.suggestedSplit?.nonEmptyTrimmed { updated.suggestedSplit = suggestedSplit }
            if let recommendedNextAction = draft.recommendedNextAction?.nonEmptyTrimmed {
                updated.recommendedNextAction = recommendedNextAction
            }
        } else {
            updated.recommendedNextAction = result.summary
        }
        switch updated.readiness {
        case .executable:
            updated.status = .ready
        case .scoped, .needsScoping, .raw:
            updated.status = .backlog
        }
        updated.triageStatus = FactoryTaskTriageStatus.fromLegacyStatus(updated.status)
        return updated
    }

    private func parseBacklogScopingDraft(from output: String) -> BacklogScopingDraft? {
        guard let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}") else { return nil }
        let json = String(output[start...end])
        return JSONCoding.decode(json, as: BacklogScopingDraft.self)
    }

    private static func lines(from text: String) -> [String] {
        text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct BacklogScopingDraft: Codable {
    var title: String?
    var kind: String?
    var goal: String?
    var context: String?
    var acceptanceCriteria: [String]?
    var priorityLabel: String?
    var readiness: String?
    var category: String?
    var effort: String?
    var risk: String?
    var dependencies: String?
    var nonGoals: String?
    var scopingNotes: String?
    var suggestedSplit: String?
    var recommendedNextAction: String?
}

private extension String {
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension DateFormatter {
    static let backup: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
