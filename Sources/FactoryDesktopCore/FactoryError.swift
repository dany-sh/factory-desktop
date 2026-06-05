import Foundation

public enum FactoryError: LocalizedError {
    case databaseOpenFailed(String)
    case databaseExecutionFailed(String)
    case databaseQueryFailed(String)
    case migrationFailed(String)
    case commandBlocked(String)
    case commandRequiresApproval(String)
    case commandFailed(String)
    case invalidProjectPath(String)
    case notCodeProject
    case missingSelection
    case unsafeMainBranch(String)
    case ollamaFailed(String)

    public var errorDescription: String? {
        switch self {
        case .databaseOpenFailed(let message): "Could not open database: \(message)"
        case .databaseExecutionFailed(let message): "Database execution failed: \(message)"
        case .databaseQueryFailed(let message): "Database query failed: \(message)"
        case .migrationFailed(let message): "Migration failed: \(message)"
        case .commandBlocked(let command): "Blocked unsafe command: \(command)"
        case .commandRequiresApproval(let command): "Command requires manual approval: \(command)"
        case .commandFailed(let message): "Command failed: \(message)"
        case .invalidProjectPath(let path): "Invalid project path: \(path)"
        case .notCodeProject: "Worktrees are only available for code projects."
        case .missingSelection: "Select a project and task first."
        case .unsafeMainBranch(let branch): "Refusing to operate directly on protected branch \(branch)."
        case .ollamaFailed(let message): "Ollama request failed: \(message)"
        }
    }
}
