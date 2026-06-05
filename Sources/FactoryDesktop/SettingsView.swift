import FactoryDesktopCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings")
                .font(.title.weight(.semibold))

            GroupBox("Local Model Policy") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Default planner model", selection: $store.selectedModel) {
                        ForEach(ModelPolicy.recommendedModels) { model in
                            Text("\(model.id) · \(model.role)").tag(model.id)
                        }
                    }
                    Text("64k is the default context. Factory caps qwen3.5:9b at 128k and granite4.1:3b at 64k; it never applies 256k globally.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(ModelPolicy.recommendedModels) { model in
                        HStack {
                            Text(model.id)
                                .font(.system(.caption, design: .monospaced))
                            Spacer()
                            Text("\(model.defaultContext / 1000)k default / \(model.maximumContext / 1000)k max")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            GroupBox("Local Storage") {
                VStack(alignment: .leading, spacing: 8) {
                    PathRow(label: "Root", path: store.paths.root.path)
                    PathRow(label: "SQLite DB", path: store.paths.database.path)
                    PathRow(label: "Runs", path: store.paths.runs.path)
                    PathRow(label: "Worktrees", path: store.paths.worktrees.path)
                    HStack {
                        Button("Backup Database Now") {
                            store.backupDatabaseNow()
                        }
                        Spacer()
                    }
                }
            }

            GroupBox("Safety") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Allowed shell entry points include git status/diff/log/branch/worktree/switch/checkout/add/commit, xcodebuild, swift test, npm run lint/test, python -m pytest, open, and code.")
                    Text("Blocked fragments include rm -rf, sudo, git reset --hard, git push --force, chmod -R 777, killall, pkill, and curl | sh.")
                    Text("Commits require explicit confirmation and are refused on main/master/default branch.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
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
