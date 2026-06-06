import FactoryDesktopCore
import SwiftUI

struct TaskDetailView: View {
    @EnvironmentObject private var store: AppStore
    @State private var draft = TaskDraft()
    @State private var acceptanceText = ""
    @State private var loadedTaskID: String?
    @FocusState private var focusedField: TaskEditorField?

    var body: some View {
        Group {
            if let task = store.selectedTask {
                VStack(alignment: .leading, spacing: 18) {
                    header(task: task)
                    taskForm(task: task)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            workflowBar
                            planPanel
                            runLog
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollDismissesKeyboard(.never)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Button("Save Task") {
                            save(task)
                        }
                        .keyboardShortcut("s", modifiers: [.command])

                        if draft.hasChanges(comparedTo: task, acceptanceText: acceptanceText) {
                            Text("Unsaved changes")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }

                        Spacer()

                        Button("Delete", role: .destructive) {
                            store.deleteSelectedTask()
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.bar)
                }
                .onAppear {
                    loadIfNeeded(task)
                }
                .onChange(of: task.id) { _, _ in
                    loadIfNeeded(task)
                }
            } else {
                ContentUnavailableView(
                    "No Task Selected",
                    systemImage: "tray",
                    description: Text("Create a task to start intake, planning, handoff, and review.")
                )
                .onAppear {
                    loadedTaskID = nil
                    draft = TaskDraft()
                    acceptanceText = ""
                    focusedField = nil
                }
            }
        }
    }

    private func header(task: FactoryTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.title)
                .font(.largeTitle.weight(.semibold))
                .lineLimit(2)
            HStack {
                StatusPill(text: task.status.displayName)
                Text(task.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                if store.isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    private func taskForm(task: FactoryTask) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Title", text: $draft.title)
                .font(.title3)
                .focused($focusedField, equals: .title)

            HStack {
                Picker("Status", selection: $draft.status) {
                    ForEach(TaskStatus.allCases) { status in
                        Text(status.displayName).tag(status)
                    }
                }
                Picker("Type", selection: $draft.type) {
                    ForEach(TaskType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                Picker("Priority", selection: $draft.priority) {
                    ForEach(TaskPriority.allCases) { priority in
                        Text(priority.displayName).tag(priority)
                    }
                }
            }

            LabeledTextEditor(
                title: "Goal",
                text: $draft.goal,
                minHeight: 90,
                focusedField: $focusedField,
                field: .goal
            )
            LabeledTextEditor(
                title: "Context",
                text: $draft.context,
                minHeight: 110,
                focusedField: $focusedField,
                field: .context
            )
            LabeledTextEditor(
                title: "Acceptance criteria (one per line)",
                text: $acceptanceText,
                minHeight: 90,
                focusedField: $focusedField,
                field: .acceptanceCriteria
            )
        }
        .padding()
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
    }

    private func save(_ task: FactoryTask) {
        store.saveTask(draft.task(updating: task, acceptanceText: acceptanceText))
    }

    private var workflowBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Controlled Workflow")
                .font(.headline)
            HStack {
                Picker("Planner model", selection: $store.selectedModel) {
                    ForEach(ModelPolicy.recommendedModels) { model in
                        Text("\(model.id) · \(model.role)").tag(model.id)
                    }
                }
                .frame(maxWidth: 340)

                Button {
                    Task { await store.planLocally() }
                } label: {
                    Label("Plan Locally", systemImage: "brain")
                }
                .disabled(store.isWorking)

                Button {
                    Task { await store.askCodexToReviewPlan() }
                } label: {
                    Label("Ask Codex to Review Plan", systemImage: "doc.text.magnifyingglass")
                }
                .disabled(store.isWorking || store.latestPlanArtifact == nil)
            }
            Text("Factory v0.1 plans and records. It does not autonomously edit files.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.separator.opacity(0.6))
        )
    }

    private var planPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Plan")
                    .font(.headline)
                Spacer()
                if let artifact = store.latestPlanArtifact {
                    Text(artifact.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if store.latestPlanText.isEmpty {
                Text("No saved plan yet. Run Plan Locally to create plan.md.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    Text(store.latestPlanText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(minHeight: 260)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            }

            if !store.latestPlanReviewText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Latest Plan Review")
                        .font(.subheadline.weight(.semibold))
                    ScrollView {
                        Text(store.latestPlanReviewText)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .frame(minHeight: 180)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.separator.opacity(0.6))
        )
    }

    private var runLog: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Run Log")
                .font(.headline)

            if store.runsForSelectedTask.isEmpty {
                Text("No runs yet. Local planner output, test output, and future executor runs will appear here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.runsForSelectedTask) { run in
                    Button {
                        store.loadRunOutput(run)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(run.summary.isEmpty ? run.executor : run.summary)
                                    .font(.body)
                                Text("\(run.executor) \(run.model ?? "") · \(run.status.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(run.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }

            if !store.selectedRunOutput.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected Output")
                        .font(.subheadline.weight(.semibold))
                    ScrollView {
                        Text(store.selectedRunOutput)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .frame(minHeight: 220)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func loadIfNeeded(_ task: FactoryTask) {
        guard loadedTaskID != task.id else { return }
        load(task)
    }

    private func load(_ task: FactoryTask) {
        draft = TaskDraft(task: task)
        acceptanceText = task.acceptanceCriteria.joined(separator: "\n")
        loadedTaskID = task.id
        focusedField = nil
    }
}

private enum TaskEditorField: Hashable {
    case title
    case goal
    case context
    case acceptanceCriteria
}

private struct LabeledTextEditor: View {
    var title: String
    @Binding var text: String
    var minHeight: CGFloat
    var focusedField: FocusState<TaskEditorField?>.Binding
    var field: TaskEditorField

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.body)
                .focused(focusedField, equals: field)
                .frame(height: minHeight)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct StatusPill: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.14), in: Capsule())
            .foregroundStyle(Color.accentColor)
    }
}

private struct TaskDraft {
    var title = ""
    var type: TaskType = .coding
    var status: TaskStatus = .inbox
    var priority: TaskPriority = .normal
    var goal = ""
    var context = ""

    init() {}

    init(task: FactoryTask) {
        title = task.title
        type = task.type
        status = task.status
        priority = task.priority
        goal = task.goal
        context = task.context
    }

    func task(updating task: FactoryTask, acceptanceText: String) -> FactoryTask {
        var updated = task
        updated.title = title
        updated.type = type
        updated.status = status
        updated.priority = priority
        updated.goal = goal
        updated.context = context
        updated.acceptanceCriteria = Self.acceptanceCriteria(from: acceptanceText)
        return updated
    }

    func hasChanges(comparedTo task: FactoryTask, acceptanceText: String) -> Bool {
        title != task.title ||
            type != task.type ||
            status != task.status ||
            priority != task.priority ||
            goal != task.goal ||
            context != task.context ||
            Self.acceptanceCriteria(from: acceptanceText) != task.acceptanceCriteria
    }

    private static func acceptanceCriteria(from acceptanceText: String) -> [String] {
        acceptanceText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
