import FactoryDesktopCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: AppRouter
    @State private var searchText = ""

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
                .frame(minWidth: 240, idealWidth: 260, maxWidth: 300)
                .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(router.selectedSettingsSection.title)
                        .font(.largeTitle.weight(.semibold))

                    sectionContent
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(32)
            }
            .frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onExitCommand {
            router.showMain()
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                router.showMain()
            } label: {
                Label("Back to app", systemImage: "chevron.left")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)

            TextField("Search settings", text: $searchText)
                .textFieldStyle(.roundedBorder)

            List(selection: settingsSelection) {
                ForEach(filteredSections) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
            }
            .listStyle(.sidebar)
        }
        .padding(16)
    }

    private var settingsSelection: Binding<SettingsSection?> {
        Binding {
            router.selectedSettingsSection
        } set: { section in
            if let section {
                router.selectedSettingsSection = section
            }
        }
    }

    private var filteredSections: [SettingsSection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return SettingsSection.allCases
        }
        return SettingsSection.allCases.filter {
            $0.title.localizedCaseInsensitiveContains(query)
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch router.selectedSettingsSection {
        case .general:
            settingsGroup("Factory Desktop") {
                SettingsRow(title: "Mode", value: "Local-first orchestration")
                SettingsRow(title: "Selected project", value: store.selectedProject?.name ?? "None")
                SettingsRow(title: "Selected task", value: store.selectedTask?.title ?? "None")
            }
        case .models:
            settingsGroup("Local Model Policy") {
                Picker("Default planner model", selection: $store.selectedModel) {
                    ForEach(ModelPolicy.recommendedModels) { model in
                        Text("\(model.id) · \(model.role)").tag(model.id)
                    }
                }
                Text("64k is the default context. Factory caps qwen3.5:9b at 128k and granite4.1:3b at 64k; it never applies 256k globally.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(ModelPolicy.recommendedModels) { model in
                    SettingsRow(
                        title: model.id,
                        value: "\(model.defaultContext / 1000)k default / \(model.maximumContext / 1000)k max",
                        monospacedTitle: true
                    )
                }
            }
        case .storage:
            settingsGroup("Local Storage") {
                PathRow(label: "Root", path: store.paths.root.path)
                PathRow(label: "SQLite DB", path: store.paths.database.path)
                PathRow(label: "Runs", path: store.paths.runs.path)
                PathRow(label: "Worktrees", path: store.paths.worktrees.path)
                Button("Backup Database Now") {
                    store.backupDatabaseNow()
                }
            }
        case .safety:
            settingsGroup("Command Safety") {
                Text("Allowed shell entry points include git status/diff/log/branch/worktree/switch/checkout/add/commit, xcodebuild, swift test, npm run lint/test, python -m pytest, open, and code.")
                Text("Blocked fragments include rm -rf, sudo, git reset --hard, git push --force, chmod -R 777, killall, pkill, and curl | sh.")
                Text("Commits require explicit confirmation and are refused on main/master/default branch.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        case .git:
            settingsGroup("Git") {
                SettingsRow(title: "Current branch", value: store.gitSnapshot.currentBranch ?? "Unknown")
                SettingsRow(title: "Worktree", value: store.gitSnapshot.worktreePath.isEmpty ? "Not refreshed" : store.gitSnapshot.worktreePath)
                SettingsRow(title: "Changed files", value: "\(store.gitSnapshot.changedFiles.count)")
            }
        case .codex:
            settingsGroup("Codex") {
                SettingsRow(title: "Handoff", value: "Generate task context for Codex from the selected task.")
                SettingsRow(title: "Artifacts", value: "\(store.artifacts.count)")
            }
        case .worktrees:
            settingsGroup("Worktrees") {
                SettingsRow(title: "Task worktree", value: store.selectedTask?.localWorktreePath ?? "Not created")
                SettingsRow(title: "Alternate worktree", value: store.selectedTask?.codexWorktreePath ?? "Not created")
            }
        case .about:
            settingsGroup("About") {
                SettingsRow(title: "App", value: "Factory Desktop")
                SettingsRow(title: "App version", value: store.buildInfo.appVersion)
                SettingsRow(title: "Branch", value: store.buildInfo.branch, monospacedValue: true)
                SettingsRow(title: "Short SHA", value: store.buildInfo.shortSHA, monospacedValue: true)
                SettingsRow(title: "Repo state", value: store.buildInfo.repoState.displayName)
                SettingsRow(title: "Repo path", value: store.buildInfo.repoPath, monospacedValue: true)
                SettingsRow(title: "Launch timestamp", value: store.buildInfo.launchTimestamp.formatted(date: .abbreviated, time: .standard))
                SettingsRow(title: "Database", value: store.paths.database.path, monospacedValue: true)
            }
        }
    }

    private func settingsGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.weight(.semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.55))
        }
    }
}

private struct SettingsRow: View {
    var title: String
    var value: String
    var monospacedTitle = false
    var monospacedValue = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .font(monospacedTitle ? .system(.callout, design: .monospaced) : .callout)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(monospacedValue ? .system(.callout, design: .monospaced) : .callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

private struct PathRow: View {
    var label: String
    var path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(path)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}
