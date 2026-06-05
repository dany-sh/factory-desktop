import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case models
    case storage
    case safety
    case git
    case codex
    case worktrees
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .models: "Models"
        case .storage: "Storage"
        case .safety: "Safety"
        case .git: "Git"
        case .codex: "Codex"
        case .worktrees: "Worktrees"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .models: "cpu"
        case .storage: "internaldrive"
        case .safety: "lock.shield"
        case .git: "arrow.triangle.branch"
        case .codex: "terminal"
        case .worktrees: "rectangle.connected.to.line.below"
        case .about: "info.circle"
        }
    }
}

enum AppScreen: Equatable {
    case main
    case settings(SettingsSection)
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var screen: AppScreen = .main

    var selectedSettingsSection: SettingsSection {
        get {
            if case .settings(let section) = screen {
                return section
            }
            return .general
        }
        set {
            screen = .settings(newValue)
        }
    }

    func openSettings(_ section: SettingsSection = .general) {
        screen = .settings(section)
    }

    func showMain() {
        screen = .main
    }
}
