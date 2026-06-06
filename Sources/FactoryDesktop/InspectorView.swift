import FactoryDesktopCore
import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var store: AppStore
    @State private var commitMessage = ""
    @State private var showingCommitConfirmation = false
    @State private var showAllArtifacts = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                projectCard
                worktreeCard
                actionCard
                taskStateCard
                preflightCard
                gitCard
                artifactsCard
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

    private var worktreeCard: some View {
        InspectorCard(title: "Task Worktree") {
            if store.selectedTask != nil {
                if store.selectedTaskWorktreeDisplays.isEmpty {
                    Text("No task worktree created.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.selectedTaskWorktreeDisplays) { display in
                        InfoRow(label: display.label, value: display.path ?? "Not created")
                        InfoRow(label: "Task branch", value: display.branch ?? "Not created")
                        Text(display.executionMode)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
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

                if store.latestTaskStateReview != nil {
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
            .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.selectedTask?.status != .readyForReview || store.isWorking)
        }
        .buttonStyle(.bordered)
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
                } else {
                    primaryButton("Build Locally", systemImage: "hammer") {
                        store.buildLocallyPlaceholder()
                    }
                }
                secondaryButton("Generate Codex Build Handoff", systemImage: "paperplane") {
                    store.generateCodexHandoff()
                }
                secondaryButton("Run Tests", systemImage: "checkmark.seal") {
                    Task { await store.runFirstTestCommand() }
                }
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
                if !store.gitSnapshot.changedFiles.isEmpty {
                    secondaryButton("Review Diff Locally", systemImage: "doc.text.magnifyingglass") {
                        Task { await store.reviewDiffLocally() }
                    }
                }
            case .readyForReview:
                primaryButton("Review Diff Locally", systemImage: "doc.text.magnifyingglass") {
                    Task { await store.reviewDiffLocally() }
                }
                secondaryButton("Generate Codex Diff Review Handoff", systemImage: "paperplane") {
                    store.askCodexToReviewDiff()
                }
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
        .disabled(store.selectedTask == nil)

        Button {
            store.generateCodexHandoff()
        } label: {
            Label("Generate Codex Build Handoff", systemImage: "paperplane")
        }
        .disabled(!canSendToCodexBuild)
    }

    private var canSendToCodexBuild: Bool {
        guard let status = store.selectedTask?.status else { return false }
        return !store.isWorking && status == .approved
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
        case .runTests:
            primaryButton(action.displayName, systemImage: "checkmark.seal") {
                Task { await store.runFirstTestCommand() }
            }
        case .reviewDiff:
            primaryButton(action.displayName, systemImage: "doc.text.magnifyingglass") {
                Task { await store.reviewDiffLocally() }
            }
        case .commitAndMerge:
            Text("Primary next action: Commit and Merge")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        case .archive:
            Text("Primary next action: Archive")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
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
