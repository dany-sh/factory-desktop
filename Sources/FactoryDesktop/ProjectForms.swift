import AppKit
import FactoryDesktopCore
import SwiftUI

struct RegisterProjectView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type: ProjectType = .codeRepo
    @State private var path = SelfRepoLocator.sourceRoot.path
    @State private var defaultBranch = "main"
    @State private var testCommands = "swift test"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Register Project")
                .font(.title.weight(.semibold))
            Form {
                TextField("Name", text: $name)
                Picker("Type", selection: $type) {
                    ForEach(ProjectType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                HStack {
                    TextField("Path", text: $path)
                    Button("Choose...") {
                        chooseDirectory()
                    }
                }
                TextField("Default branch", text: $defaultBranch)
                VStack(alignment: .leading) {
                    Text("Test commands")
                    TextEditor(text: $testCommands)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 90)
                }
            }
            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                Spacer()
                Button("Register This App") {
                    store.registerSelfProject()
                    dismiss()
                }
                Button("Register") {
                    store.registerProject(
                        name: name,
                        type: type,
                        path: path,
                        defaultBranch: defaultBranch,
                        testCommandsText: testCommands
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 640)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
            if name.isEmpty {
                name = url.lastPathComponent
            }
        }
    }
}

struct NewTaskView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var type: TaskType = .coding
    @State private var goal = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New Task")
                .font(.title.weight(.semibold))
            if let project = store.selectedProject {
                Text("Project: \(project.name)")
                    .foregroundStyle(.secondary)
            }
            Form {
                TextField("Title", text: $title)
                Picker("Type", selection: $type) {
                    ForEach(TaskType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                VStack(alignment: .leading) {
                    Text("Goal")
                    TextEditor(text: $goal)
                        .frame(minHeight: 110)
                }
            }
            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                Spacer()
                Button("Create Task") {
                    store.createTask(title: title, type: type, goal: goal)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 540)
    }
}
