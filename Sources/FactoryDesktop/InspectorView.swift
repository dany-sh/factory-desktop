import FactoryDesktopCore
import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var store: AppStore
    @State private var commitMessage = ""
    @State private var showingCommitConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                projectCard
                worktreeCard
                actionCard
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
        InspectorCard(title: "Task Branches") {
            if let task = store.selectedTask {
                InfoRow(label: "Local branch", value: task.localBranch ?? "Not created")
                InfoRow(label: "Local path", value: task.localWorktreePath ?? "Not created")
                InfoRow(label: "Codex branch", value: task.codexBranch ?? "Not created")
                InfoRow(label: "Codex path", value: task.codexWorktreePath ?? "Not created")
            } else {
                Text("Select a task to create worktrees.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionCard: some View {
        InspectorCard(title: "Next Actions") {
            VStack(alignment: .leading, spacing: 8) {
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
            .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.selectedTask?.status != .readyToCommit || store.isWorking)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private var nextActionButtons: some View {
        if let task = store.selectedTask {
            switch task.status {
            case .inbox, .planning:
                primaryButton("Plan Locally", systemImage: "brain") {
                    Task { await store.planLocally() }
                }
            case .planReady:
                primaryButton("Review Plan Locally", systemImage: "checklist") {
                    store.reviewPlanLocally()
                }
                secondaryButton("Ask Codex to Review Plan", systemImage: "doc.text.magnifyingglass") {
                    store.askCodexToReviewPlan()
                }
                secondaryButton("Approve Plan", systemImage: "hand.thumbsup") {
                    store.approvePlan()
                }
            case .planReview:
                primaryButton("Approve Plan", systemImage: "hand.thumbsup") {
                    store.approvePlan()
                }
                secondaryButton("Ask Codex to Review Plan", systemImage: "doc.text.magnifyingglass") {
                    store.askCodexToReviewPlan()
                }
            case .planApproved:
                primaryButton("Build Locally", systemImage: "hammer") {
                    store.buildLocallyPlaceholder()
                }
                secondaryButton("Run Tests", systemImage: "checkmark.seal") {
                    Task { await store.runFirstTestCommand() }
                }
            case .building, .built, .testing:
                primaryButton("Run Tests", systemImage: "checkmark.seal") {
                    Task { await store.runFirstTestCommand() }
                }
                if !store.gitSnapshot.changedFiles.isEmpty {
                    secondaryButton("Review Diff Locally", systemImage: "doc.text.magnifyingglass") {
                        Task { await store.reviewDiffLocally() }
                    }
                }
            case .needsReview:
                primaryButton("Review Diff Locally", systemImage: "doc.text.magnifyingglass") {
                    Task { await store.reviewDiffLocally() }
                }
                secondaryButton("Ask Codex to Review Diff", systemImage: "paperplane") {
                    store.askCodexToReviewDiff()
                }
                secondaryButton("Generate Review Note", systemImage: "doc.badge.clock") {
                    store.generateReviewNote()
                }
            case .readyToCommit:
                primaryButton("Generate Review Note", systemImage: "doc.badge.clock") {
                    store.generateReviewNote()
                }
                secondaryButton("Ask Codex to Review Diff", systemImage: "paperplane") {
                    store.askCodexToReviewDiff()
                }
            case .done:
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
                    Label("Create Local Worktree", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .disabled(store.isWorking)
            }

            if task.codexWorktreePath == nil {
                Button {
                    Task { await store.createWorktree(flavor: .codex) }
                } label: {
                    Label("Create Codex Worktree", systemImage: "terminal")
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
            Task { await store.sendToCodex() }
        } label: {
            Label("Send to Codex", systemImage: "terminal")
        }
        .disabled(store.selectedTask == nil || store.isWorking)
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
            if store.artifacts.isEmpty {
                Text("Handoffs and review notes will appear here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.artifacts) { artifact in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ArtifactType(rawValue: artifact.type)?.displayName ?? artifact.type)
                            .font(.subheadline.weight(.semibold))
                        Text(artifact.path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
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
