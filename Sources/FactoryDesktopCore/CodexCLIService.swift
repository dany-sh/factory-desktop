import Foundation

public struct CodexCLIAvailability: Equatable {
    public var isAvailable: Bool
    public var version: String?
    public var message: String

    public init(isAvailable: Bool, version: String? = nil, message: String) {
        self.isAvailable = isAvailable
        self.version = version
        self.message = message
    }
}

public enum CodexCLIAction: Equatable {
    case locate
    case version
    case openApp(workspacePath: String)
    case resume(sessionId: String)
    case exec(workspacePath: String, instruction: String, sandboxMode: RunnerSandboxMode = .readOnly)
    case execResume(sessionId: String, workspacePath: String, instruction: String, sandboxMode: RunnerSandboxMode = .readOnly)
}

public final class CodexCLIService {
    private let runCommand: (CommandRequest) async throws -> CommandResult

    public init(commandRunner: CommandRunner) {
        self.runCommand = { request in
            try await commandRunner.run(request)
        }
    }

    public init(runCommand: @escaping (CommandRequest) async throws -> CommandResult) {
        self.runCommand = runCommand
    }

    public func availability() async -> CodexCLIAvailability {
        do {
            let which = try await runCommand(commandRequest(for: .locate))
            guard which.succeeded else {
                return CodexCLIAvailability(isAvailable: false, message: "codex CLI was not found.")
            }
            let version = try await runCommand(commandRequest(for: .version))
            let text = version.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return CodexCLIAvailability(
                isAvailable: version.succeeded,
                version: text.isEmpty ? nil : text,
                message: version.succeeded ? "codex CLI is available." : "codex CLI exists, but --version failed."
            )
        } catch {
            return CodexCLIAvailability(isAvailable: false, message: error.localizedDescription)
        }
    }

    public func openApp(workspacePath: String) async throws -> CommandResult {
        try await runCommand(commandRequest(for: .openApp(workspacePath: workspacePath)))
    }

    public func resume(sessionId: String) async throws -> CommandResult {
        try await runCommand(commandRequest(for: .resume(sessionId: sessionId)))
    }

    public func exec(
        workspacePath: String,
        instruction: String,
        sandboxMode: RunnerSandboxMode = .readOnly
    ) async throws -> CommandResult {
        try await runCommand(commandRequest(for: .exec(
            workspacePath: workspacePath,
            instruction: instruction,
            sandboxMode: sandboxMode
        )))
    }

    public func execResume(
        sessionId: String,
        workspacePath: String,
        instruction: String,
        sandboxMode: RunnerSandboxMode = .readOnly
    ) async throws -> CommandResult {
        try await runCommand(commandRequest(for: .execResume(
            sessionId: sessionId,
            workspacePath: workspacePath,
            instruction: instruction,
            sandboxMode: sandboxMode
        )))
    }

    public func run(_ request: CommandRequest) async throws -> CommandResult {
        try await runCommand(request)
    }

    public func commandRequest(for action: CodexCLIAction) throws -> CommandRequest {
        switch action {
        case .locate:
            return CommandRequest(executable: "which", arguments: ["codex"])
        case .version:
            return CommandRequest(executable: "codex", arguments: ["--version"])
        case .openApp(let workspacePath):
            try validateWorkspacePath(workspacePath)
            return CommandRequest(executable: "codex", arguments: ["app", workspacePath])
        case .resume(let sessionId):
            try validateSessionID(sessionId)
            return CommandRequest(executable: "codex", arguments: ["resume", sessionId])
        case .exec(let workspacePath, let instruction, let sandboxMode):
            try validateWorkspacePath(workspacePath)
            let prompt = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalInstruction = prompt.isEmpty ? "Summarize current state." : prompt
            return CommandRequest(
                executable: "codex",
                arguments: ["exec", "-C", workspacePath, "-s", sandboxMode.codexCLIValue, finalInstruction]
            )
        case .execResume(let sessionId, let workspacePath, let instruction, let sandboxMode):
            try validateSessionID(sessionId)
            try validateWorkspacePath(workspacePath)
            let prompt = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalInstruction = prompt.isEmpty ? "Resume this Codex session and summarize current state." : prompt
            return CommandRequest(
                executable: "codex",
                arguments: ["exec", "-C", workspacePath, "-s", sandboxMode.codexCLIValue, "resume", sessionId, finalInstruction]
            )
        }
    }

    private func validateWorkspacePath(_ path: String) throws {
        guard path.hasPrefix("/") else {
            throw FactoryError.invalidProjectPath(path)
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw FactoryError.invalidProjectPath(path)
        }
    }

    private func validateSessionID(_ sessionId: String) throws {
        let trimmed = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == sessionId, !sessionId.isEmpty, !sessionId.hasPrefix("-") else {
            throw FactoryError.commandRequiresApproval("codex resume \(sessionId)")
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")
        guard sessionId.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw FactoryError.commandRequiresApproval("codex resume \(sessionId)")
        }
    }
}

private extension RunnerSandboxMode {
    var codexCLIValue: String {
        switch self {
        case .readOnly:
            return "read-only"
        case .workspaceWrite:
            return "workspace-write"
        case .unrestricted:
            return "read-only"
        }
    }
}
