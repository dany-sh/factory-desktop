import FactoryDesktopCore
import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var store: AppStore
    @State private var commitMessage = ""
    @State private var codexWorkspacePath = ""
    @State private var codexSessionID = ""
    @State private var showingCommitConfirmation = false
    @State private var showAllArtifacts = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                projectCard
                if store.selectedWorkspaceScope == .project {
                    projectWorkspaceCard
                    lifecycleCard
                } else {
                    codexCard
                    worktreeCard
                    actionCard
                    taskStateCard
                    lifecycleSyncCard
                    preflightCard
                    compactProjectStatusCard
                    gitCard
                    artifactsCard
                }
            }
            .padding(18)
        }
        .alert("Commit selected worktree?", isPresented: $showingCommitConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Commit") {
                Task { await store.commitSelectedWorktree(message: commitMessage) }
            }
        } message: {
            Text("Factory will run git add -A and git commit only in the selected task worktree, never on main/master/default.")
        }
        .onAppear {
            syncCodexWorkspaceDraft()
        }
        .onChange(of: store.selectedProjectID) { _, _ in
            syncCodexWorkspaceDraft()
            codexSessionID = ""
        }
        .onChange(of: store.selectedCodexProjectLink?.workspacePath) { _, _ in
            syncCodexWorkspaceDraft()
        }
    }

    private var projectCard: some View {
        InspectorCard(title: "Project Context") {
            if let project = store.selectedProject {
                InfoRow(label: "Name", value: project.name)
                InfoRow(label: "Type", value: project.type.displayName)
                InfoRow(label: "Path", value: project.path)
                InfoRow(label: "Default", value: project.defaultBranch)
                Divider()
                Text("Test Commands")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if project.testCommands.isEmpty {
                    Text("None configured.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(project.testCommands, id: \.self) { command in
                        Text(command)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            } else {
                Text("No project selected.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var codexCard: some View {
        InspectorCard(title: "Codex Session") {
            if let project = store.selectedProject {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Project Workspace")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField(project.path, text: $codexWorkspacePath)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button {
                            store.linkCodexProject(workspacePath: codexWorkspacePath.isEmpty ? project.path : codexWorkspacePath)
                        } label: {
                            Label(store.selectedCodexProjectLink == nil ? "Link Project" : "Update Link", systemImage: "link")
                        }
                        Button {
                            Task { await store.openSelectedProjectInCodex() }
                        } label: {
                            Label("Open Codex Project", systemImage: "arrow.up.forward.app")
                        }
                        .disabled(store.isWorking)
                        if store.selectedCodexProjectLink != nil {
                            Button {
                                store.unlinkCodexProject()
                            } label: {
                                Label("Unlink", systemImage: "link.badge.minus")
                            }
                            .disabled(store.isWorking)
                        }
                    }
                    .buttonStyle(.bordered)

                    if let link = store.selectedCodexProjectLink {
                        InfoRow(label: "Linked path", value: link.workspacePath)
                        InfoRow(label: "Preferred mode", value: link.preferredMode.displayName)
                    }

                    Divider()

                    if let session = store.selectedTaskCodexSessionLink {
                        InfoRow(label: "Session ID", value: session.codexSessionId)
                        InfoRow(label: "Mode", value: session.mode.displayName)
                        InfoRow(label: "Workspace", value: session.workspacePath)
                        if let branch = session.branchName {
                            InfoRow(label: "Branch", value: branch)
                        }
                        if let worktree = session.worktreePath {
                            InfoRow(label: "Worktree", value: worktree)
                        }
                        InfoRow(label: "Status", value: session.status.displayName)
                        InfoRow(label: "Last seen", value: session.lastSeenAt?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown")
                        if let summary = session.lastSummary, !summary.isEmpty {
                            InfoRow(label: "Summary", value: summary)
                        }
                        if let recommendation = store.latestCodexSessionRecommendation {
                            InfoRow(label: "Next", value: recommendation.action.displayName)
                            InfoRow(label: "Reason", value: recommendation.reason)
                        }
                        HStack {
                            Button {
                                Task { await store.resumeSelectedTaskCodexSession() }
                            } label: {
                                Label("Resume Session", systemImage: "play.circle")
                            }
                            Button {
                                Task { await store.refreshSelectedTaskCodexSessionState() }
                            } label: {
                                Label("Refresh Session", systemImage: "arrow.clockwise")
                            }
                            Button {
                                Task { await store.runSelectedTaskCodexSessionCheck() }
                            } label: {
                                Label("Check Session", systemImage: "checkmark.seal")
                            }
                            Button {
                                store.detachCodexSessionFromSelectedTask()
                            } label: {
                                Label("Detach", systemImage: "xmark.circle")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.isWorking)
                    } else if store.selectedTask != nil {
                        Text("No Codex session linked")
                            .foregroundStyle(.secondary)
                        TextField("Session ID", text: $codexSessionID)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            store.attachCodexSessionToSelectedTask(sessionId: codexSessionID)
                            codexSessionID = ""
                        } label: {
                            Label("Attach Session", systemImage: "link.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(codexSessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isWorking)
                    } else {
                        Text("Select a task to attach a Codex session.")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("No project selected.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func syncCodexWorkspaceDraft() {
        codexWorkspacePath = store.selectedCodexProjectLink?.workspacePath ?? store.selectedProject?.path ?? ""
    }

    private var worktreeCard: some View {
        InspectorCard(title: "Task Worktree") {
            if store.selectedTask != nil {
                if store.selectedTaskWorktreeDisplays.isEmpty {
                    Text("No task worktree created.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.selectedTaskWorktreeDisplays) { display in
                        TaskWorktreeReferenceView(display: display)
                    }
                }
            } else {
                Text("Select a task to create worktrees.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionCard: some View {
        InspectorCard(title: "Next Actions") {
            VStack(alignment: .leading, spacing: 8) {
                if let review = store.latestTaskStateReview {
                    recommendedActionButton(review.recommendedAction)
                } else if let task = store.selectedTask, task.status == .archived || task.status == .done {
                    completedTaskActionSummary(task)
                } else {
                    Button {
                        Task { await store.reviewTaskState() }
                    } label: {
                        Label("Review Task State", systemImage: "list.bullet.clipboard")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.selectedTask == nil || store.isWorking)
                }

                if store.latestTaskStateReview != nil, store.selectedTask?.status != .archived, store.selectedTask?.status != .done {
                    Button {
                        Task { await store.reviewTaskState() }
                    } label: {
                        Label("Review Task State", systemImage: "list.bullet.clipboard")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .disabled(store.selectedTask == nil || store.isWorking)
                }

                Button {
                    Task { await store.runPreflightCheck() }
                } label: {
                    Label("Preflight Check", systemImage: "checklist.checked")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(store.selectedTask == nil || store.isWorking)

                Divider()
                nextActionButtons
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
            Text("Setup")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            setupButtons

            Divider()
            TextField("Commit message", text: $commitMessage)
            Button {
                showingCommitConfirmation = true
            } label: {
                Label("Commit Selected Worktree", systemImage: "checkmark.circle")
            }
            .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.selectedTask?.status != .readyForReview || store.isWorking || selectedCodeWorktreeUnavailable)
        }
        .buttonStyle(.bordered)
    }

    private func completedTaskActionSummary(_ task: FactoryTask) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.status == .archived ? "Archived" : "No action required")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Button("Reopen Task") {}
                .disabled(true)
                .help("Foundation-only placeholder.")
        }
    }

    @ViewBuilder
    private var nextActionButtons: some View {
        if let task = store.selectedTask {
            switch task.status {
            case .backlog, .ready, .planning:
                if store.canPlanSelectedTaskLocally {
                    primaryButton("Plan Locally", systemImage: "brain") {
                        Task { await store.planLocally() }
                    }
                } else {
                    primaryButton("Create Task Worktree", systemImage: "point.3.connected.trianglepath.dotted") {
                        Task { await store.createWorktree(flavor: .local) }
                    }
                    if let warning = store.selectedTaskWorktreeWarning {
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            case .planReview:
                primaryButton("Review Plan Locally", systemImage: "checklist") {
                    Task { await store.reviewPlanLocally() }
                }
                secondaryButton("Generate Codex Plan Review Handoff", systemImage: "doc.text.magnifyingglass") {
                    store.generateCodexPlanReviewHandoff()
                }
                secondaryButton("Approve Plan", systemImage: "hand.thumbsup") {
                    store.approvePlan()
                }
                secondaryButton("Revise Plan Locally", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await store.planLocally() }
                }
            case .approved:
                if store.latestTaskStateReview?.hasImplementationChanges == true {
                    primaryButton("Run Tests", systemImage: "checkmark.seal") {
                        Task { await store.runFirstTestCommand() }
                    }
                    .disabled(selectedCodeWorktreeUnavailable)
                } else {
                    primaryButton("Build Locally", systemImage: "hammer") {
                        store.buildLocallyPlaceholder()
                    }
                    .disabled(selectedCodeWorktreeUnavailable)
                }
                secondaryButton("Generate Codex Build Handoff", systemImage: "paperplane") {
                    store.generateCodexHandoff()
                }
                .disabled(selectedCodeWorktreeUnavailable)
                secondaryButton("Run Tests", systemImage: "checkmark.seal") {
                    Task { await store.runFirstTestCommand() }
                }
                .disabled(selectedCodeWorktreeUnavailable)
            case .needsFixes:
                primaryButton("Revise Plan Locally", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await store.planLocally() }
                }
                secondaryButton("Generate Codex Plan Review Handoff", systemImage: "doc.text.magnifyingglass") {
                    store.generateCodexPlanReviewHandoff()
                }
            case .building, .testing:
                primaryButton("Run Tests", systemImage: "checkmark.seal") {
                    Task { await store.runFirstTestCommand() }
                }
                .disabled(selectedCodeWorktreeUnavailable)
                if !store.gitSnapshot.changedFiles.isEmpty {
                    secondaryButton("Review Diff Locally", systemImage: "doc.text.magnifyingglass") {
                        Task { await store.reviewDiffLocally() }
                    }
                    .disabled(selectedCodeWorktreeUnavailable)
                }
            case .readyForReview:
                primaryButton("Review Diff Locally", systemImage: "doc.text.magnifyingglass") {
                    Task { await store.reviewDiffLocally() }
                }
                .disabled(selectedCodeWorktreeUnavailable)
                secondaryButton("Generate Codex Diff Review Handoff", systemImage: "paperplane") {
                    store.askCodexToReviewDiff()
                }
                .disabled(selectedCodeWorktreeUnavailable)
                secondaryButton("Generate Review Note", systemImage: "doc.badge.clock") {
                    store.generateReviewNote()
                }
            case .done, .archived:
                Text("Task is done.")
                    .foregroundStyle(.secondary)
            case .blocked:
                primaryButton("Run Tests", systemImage: "checkmark.seal") {
                    Task { await store.runFirstTestCommand() }
                }
                .disabled(selectedCodeWorktreeUnavailable)
                secondaryButton("Generate Review Note", systemImage: "doc.badge.clock") {
                    store.generateReviewNote()
                }
            }
        } else {
            Text("Select a task to see next actions.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var setupButtons: some View {
        Button {
            Task { await store.refreshGitStatus() }
        } label: {
            Label("Refresh Git Status", systemImage: "arrow.clockwise")
        }

        if store.selectedProject?.type == .codeRepo, let task = store.selectedTask {
            if task.localWorktreePath == nil {
                Button {
                    Task { await store.createWorktree(flavor: .local) }
                } label: {
                    Label("Create Task Worktree", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .disabled(store.isWorking)
            }

            if task.codexWorktreePath == nil {
                Button {
                    Task { await store.createWorktree(flavor: .codex) }
                } label: {
                    Label("Create Alternate Worktree", systemImage: "terminal")
                }
                .disabled(store.isWorking)
            }
        }

        Button {
            Task { await store.openVSCodeForSelectedTask() }
        } label: {
            Label("Open VS Code", systemImage: "curlybraces.square")
        }
        .disabled(store.selectedTask == nil || selectedCodeWorktreeUnavailable)

        Button {
            store.generateCodexHandoff()
        } label: {
            Label("Generate Codex Build Handoff", systemImage: "paperplane")
        }
        .disabled(!canSendToCodexBuild)
    }

    private var canSendToCodexBuild: Bool {
        guard let status = store.selectedTask?.status else { return false }
        return !store.isWorking && status == .approved && !selectedCodeWorktreeUnavailable
    }

    private var selectedCodeWorktreeUnavailable: Bool {
        store.selectedProject?.type == .codeRepo && !store.selectedTaskCanUseWorktree
    }

    private var taskStateCard: some View {
        InspectorCard(title: "Task State Review") {
            if let review = store.latestTaskStateReview {
                InfoRow(label: "Recommended", value: review.recommendedAction.displayName)
                InfoRow(label: "Summary", value: review.summary)
                if review.hasPlan && !review.hasPlanReview {
                    Text("Plan exists but has not been reviewed.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                HStack(spacing: 12) {
                    TaskStateMetric(label: "Plan", value: review.hasPlan ? "yes" : "no")
                    TaskStateMetric(label: "Review", value: review.hasPlanReview ? "yes" : "no")
                    TaskStateMetric(label: "Preflight", value: review.hasPreflight ? (review.hasRiskyPreflight ? "risk" : "yes") : "no")
                }
                HStack(spacing: 12) {
                    TaskStateMetric(label: "Changes", value: review.hasImplementationChanges ? "yes" : "no")
                    TaskStateMetric(label: "Tests", value: review.hasTestOutput ? "yes" : "no")
                    TaskStateMetric(label: "Diff", value: review.hasDiffReview ? "yes" : "no")
                }
            } else if let artifact = store.latestTaskStateReviewArtifact {
                InfoRow(label: "Latest artifact", value: artifact.path)
                Button {
                    Task { await store.openArtifact(artifact) }
                } label: {
                    Label("Open Artifact", systemImage: "arrow.up.forward.app")
                }
            } else {
                Text("Run Review Task State to inspect artifacts and get one recommended next action.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var preflightCard: some View {
        InspectorCard(title: "Preflight") {
            if let report = store.latestPreflightReport {
                InfoRow(label: "Recommendation", value: report.overallRecommendation.displayName)
                HStack(spacing: 12) {
                    PreflightMetric(label: "Dirty", value: report.dirtyTargetCount)
                    PreflightMetric(label: "Missing", value: report.missingPathCount)
                    PreflightMetric(label: "Unpushed", value: report.unpushedCount)
                }

                Divider()
                ForEach(report.targets) { target in
                    PreflightTargetRow(target: target)
                    if target.id != report.targets.last?.id {
                        Divider()
                    }
                }
            } else {
                Text("Run Preflight Check to inspect the canonical repo and Factory-managed worktrees.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var lifecycleSyncCard: some View {
        InspectorCard(title: "Lifecycle Sync") {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    Task { await store.syncSelectedTaskLifecycle() }
                } label: {
                    Label("Sync lifecycle", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(store.selectedTask == nil || store.isWorking)

                LifecycleSyncSummaryView(
                    result: store.latestLifecycleSyncResult,
                    emptyMessage: "Run lifecycle sync to inspect Git-backed task facts."
                )
            }
        }
        .buttonStyle(.bordered)
    }

    private var lifecycleCard: some View {
        LifecycleCleanupView()
    }

    private var projectWorkspaceCard: some View {
        let summary = store.projectStatusSummary
        return InspectorCard(title: "Project Workspace") {
            Text("You are viewing project-wide state. Open a task from the dashboard or sidebar to return to task-specific execution details.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                TaskStateMetric(label: "Active", value: "\(summary.activeTaskCount)")
                TaskStateMetric(label: "Archived", value: "\(summary.archivedTaskCount)")
                TaskStateMetric(label: "Cleanup", value: "\(summary.cleanupItemCount)")
            }
            Button {
                Task { await store.refreshGitStatus() }
            } label: {
                Label("Refresh Git Status", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    private var compactProjectStatusCard: some View {
        let summary = store.taskProjectStatusSummary
        return InspectorCard(title: "Project Status") {
            Text(summary.message)
                .font(.caption)
                .foregroundStyle(summary.blockerCount > 0 ? .red : .secondary)
            HStack(spacing: 12) {
                TaskStateMetric(label: "Cleanup", value: "\(summary.projectCleanupCount)")
                TaskStateMetric(label: "Blockers", value: "\(summary.blockerCount)")
                TaskStateMetric(label: "Preflight", value: store.projectStatusSummary.preflightStatus)
            }
            Button {
                store.showProjectWorkspace()
            } label: {
                Label("Open Project Workspace", systemImage: "folder")
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func recommendedActionButton(_ action: TaskStateRecommendedAction) -> some View {
        switch action {
        case .createWorktree:
            primaryButton("Create Task Worktree", systemImage: "point.3.connected.trianglepath.dotted") {
                Task { await store.createWorktree(flavor: .local) }
            }
        case .runPreflight, .inspectPreflightFixGitState:
            primaryButton(action.displayName, systemImage: "checklist.checked") {
                Task { await store.runPreflightCheck() }
            }
        case .planLocally, .revisePlan:
            primaryButton(action.displayName, systemImage: "brain") {
                Task { await store.planLocally() }
            }
            .disabled(store.isWorking || !store.canPlanSelectedTaskLocally)
        case .reviewPlanLocally:
            primaryButton(action.displayName, systemImage: "checklist") {
                Task { await store.reviewPlanLocally() }
            }
        case .askCodexToReviewPlan:
            primaryButton("Generate Codex Plan Review Handoff", systemImage: "doc.text.magnifyingglass") {
                store.generateCodexPlanReviewHandoff()
            }
        case .approvePlan:
            primaryButton(action.displayName, systemImage: "hand.thumbsup") {
                store.approvePlan()
            }
        case .buildLocally:
            primaryButton(action.displayName, systemImage: "hammer") {
                store.buildLocallyPlaceholder()
            }
            .disabled(selectedCodeWorktreeUnavailable)
        case .runTests:
            primaryButton(action.displayName, systemImage: "checkmark.seal") {
                Task { await store.runFirstTestCommand() }
            }
            .disabled(selectedCodeWorktreeUnavailable)
        case .reviewDiff:
            primaryButton(action.displayName, systemImage: "doc.text.magnifyingglass") {
                Task { await store.reviewDiffLocally() }
            }
            .disabled(selectedCodeWorktreeUnavailable)
        case .commitAndMerge:
            Text("Primary next action: Commit and Merge")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        case .archive:
            Text("Primary next action: Archive")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        case .noActionRequired:
            VStack(alignment: .leading, spacing: 6) {
                Text(store.selectedTask?.status == .archived ? "Archived" : "No action required")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Button("Reopen Task") {}
                    .disabled(true)
                    .help("Foundation-only placeholder.")
            }
        case .investigate:
            primaryButton(action.displayName, systemImage: "list.bullet.clipboard") {
                Task { await store.reviewTaskState() }
            }
        }
    }

    private func primaryButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
        .disabled(store.selectedTask == nil || store.isWorking)
    }

    private func secondaryButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(store.selectedTask == nil || store.isWorking)
    }

    private var gitCard: some View {
        InspectorCard(title: "Git Status") {
            InfoRow(label: "Worktree", value: store.gitSnapshot.worktreePath.isEmpty ? "Not refreshed" : store.gitSnapshot.worktreePath)
            InfoRow(label: "Branch", value: store.gitSnapshot.currentBranch ?? "Unknown")
            Divider()
            Text("Changed Files")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if store.gitSnapshot.changedFiles.isEmpty {
                Text("No changed files detected.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.gitSnapshot.changedFiles, id: \.self) { file in
                    Text(file)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            Divider()
            Text("Diff Stat")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(store.gitSnapshot.diffStat.isEmpty ? "(empty)" : store.gitSnapshot.diffStat)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            Divider()
            Text("Raw Status")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(store.gitSnapshot.statusText.isEmpty ? "(not refreshed)" : store.gitSnapshot.statusText)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private var artifactsCard: some View {
        InspectorCard(title: "Artifacts") {
            let groups = store.artifactDisplayGroups
            if store.artifacts.isEmpty {
                Text("Handoffs and review notes will appear here.")
                    .foregroundStyle(.secondary)
            } else {
                Toggle("Show All Artifacts", isOn: $showAllArtifacts)
                    .toggleStyle(.switch)
                artifactList(title: "Current", artifacts: groups.current)
                if showAllArtifacts {
                    artifactList(title: "History", artifacts: groups.history)
                    artifactList(title: "Raw Logs / Prompts", artifacts: groups.rawLogs)
                }
            }
        }
    }

    private func artifactList(title: String, artifacts: [Artifact]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if artifacts.isEmpty {
                Text("None.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(artifacts) { artifact in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(artifact.artifactType?.displayName ?? artifact.type)
                            .font(.subheadline.weight(.semibold))
                        Text(artifact.path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Button {
                            Task { await store.openArtifact(artifact) }
                        } label: {
                            Label("Open Artifact", systemImage: "arrow.up.forward.app")
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

private struct InspectorCard<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.separator.opacity(0.55))
        )
    }
}

private struct InfoRow: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(label.lowercased().contains("path") ? .system(.caption, design: .monospaced) : .caption)
                .textSelection(.enabled)
        }
    }
}

private struct PreflightMetric: View {
    var label: String
    var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TaskStateMetric: View {
    var label: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct PreflightTargetRow: View {
    var target: PreflightTargetReport

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(target.type.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(target.recommendation.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(target.risks.isEmpty ? .green : .orange)
            }
            Text(target.path)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Text("Branch \(target.branch ?? "unknown") · HEAD \(target.headSHA ?? "unknown")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Exists \(target.pathExists ? "yes" : "no") · Clean \(target.isClean ? "yes" : "no") · staged/unstaged/untracked \(target.stagedCount)/\(target.unstagedCount)/\(target.untrackedCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Merged \(target.isMergedToDefault.map { $0 ? "yes" : "no" } ?? "unknown") · ahead/behind \(target.aheadOfRemote.map(String.init) ?? "unknown")/\(target.behindRemote.map(String.init) ?? "unknown")")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !target.risks.isEmpty {
                Text(target.risks.map(\.displayName).joined(separator: ", "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}
