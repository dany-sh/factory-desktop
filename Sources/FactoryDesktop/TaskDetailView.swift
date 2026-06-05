import FactoryDesktopCore
import SwiftUI

struct TaskDetailView: View {
    @EnvironmentObject private var store: AppStore
    @State private var draft = TaskDraft()
    @State private var acceptanceText = ""

    var body: some View {
        Group {
            if let task = store.selectedTask {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(task: task)
                        taskForm(task: task)
                        workflowBar
                        runLog
                    }
                    .padding(24)
                }
                .onAppear {
                    load(task)
                }
                .onChange(of: task.id) { _, _ in
                    load(task)
                }
            } else {
                ContentUnavailableView(
                    "No Task Selected",
                    systemImage: "tray",
                    description: Text("Create a task to start intake, planning, handoff, and review.")
                )
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

            LabeledTextEditor(title: "Goal", text: $draft.goal, minHeight: 90)
            LabeledTextEditor(title: "Context", text: $draft.context, minHeight: 110)
            LabeledTextEditor(title: "Acceptance criteria (one per line)", text: $acceptanceText, minHeight: 90)

            HStack {
                Button("Save Task") {
                    store.saveTask(draft.task(updating: task, acceptanceText: acceptanceText))
                }
                .keyboardShortcut("s", modifiers: [.command])

                Button("Delete", role: .destructive) {
                    store.deleteSelectedTask()
                }
                Spacer()
            }
        }
        .padding()
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
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
                    store.generateCodexHandoff()
                } label: {
                    Label("Generate Handoff", systemImage: "doc.text")
                }
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

    private func load(_ task: FactoryTask) {
        draft = TaskDraft(task: task)
        acceptanceText = task.acceptanceCriteria.joined(separator: "\n")
    }
}

private struct LabeledTextEditor: View {
    var title: String
    @Binding var text: String
    var minHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: minHeight)
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
        updated.acceptanceCriteria = acceptanceText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return updated
    }
}
