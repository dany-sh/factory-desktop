import Foundation

public struct CommandRequest: Equatable {
    public var executable: String
    public var arguments: [String]
    public var workingDirectory: URL?
    public var manuallyApproved: Bool

    public init(
        executable: String,
        arguments: [String] = [],
        workingDirectory: URL? = nil,
        manuallyApproved: Bool = false
    ) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.manuallyApproved = manuallyApproved
    }

    public var displayString: String {
        ([executable] + arguments).joined(separator: " ")
    }
}

public struct CommandResult: Equatable {
    public var command: String
    public var exitCode: Int32
    public var output: String

    public var succeeded: Bool { exitCode == 0 }

    public init(command: String, exitCode: Int32, output: String) {
        self.command = command
        self.exitCode = exitCode
        self.output = output
    }
}

public final class CommandRunner {
    public init() {}

    public func run(_ request: CommandRequest) async throws -> CommandResult {
        try validate(request)

        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [request.executable] + request.arguments
            if let workingDirectory = request.workingDirectory {
                process.currentDirectoryURL = workingDirectory
            }

            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            try process.run()
            process.waitUntilExit()

            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return CommandResult(command: request.displayString, exitCode: process.terminationStatus, output: output)
        }.value
    }

    public func validate(_ request: CommandRequest) throws {
        let command = request.displayString
        let normalized = command.lowercased()

        let blockedFragments = [
            "rm -rf",
            "sudo",
            "git reset --hard",
            "git push --force",
            "chmod -r 777",
            "killall",
            "pkill",
            "curl | sh"
        ]
        if blockedFragments.contains(where: { normalized.contains($0) }) {
            throw FactoryError.commandBlocked(command)
        }

        guard isAllowlisted(request) else {
            if request.manuallyApproved {
                return
            }
            throw FactoryError.commandRequiresApproval(command)
        }
    }

    private func isAllowlisted(_ request: CommandRequest) -> Bool {
        let executable = request.executable
        let arguments = request.arguments

        switch executable {
        case "git":
            return isAllowedGit(arguments, manuallyApproved: request.manuallyApproved)
        case "xcodebuild":
            return true
        case "swift":
            return arguments.first == "test"
        case "npm":
            return arguments.count >= 2 && arguments[0] == "run" && ["lint", "test"].contains(arguments[1])
        case "python", "python3":
            return arguments.count >= 2 && arguments[0] == "-m" && arguments[1] == "pytest"
        case "open", "code":
            return true
        default:
            return false
        }
    }

    private func isAllowedGit(_ arguments: [String], manuallyApproved: Bool) -> Bool {
        guard let first = arguments.first else { return false }
        switch first {
        case "status", "log", "add":
            return true
        case "commit":
            return manuallyApproved
        case "branch":
            return arguments.count == 1 || arguments.dropFirst().allSatisfy { ["--show-current", "--list", "-a"].contains($0) || !$0.hasPrefix("-") }
        case "worktree":
            guard arguments.count >= 1 else { return false }
            if arguments.count == 1 { return true }
            return ["add", "list"].contains(arguments[1])
        case "switch":
            let blocked = ["--discard-changes", "--force", "-f"]
            return !arguments.dropFirst().contains(where: { blocked.contains($0) })
        case "checkout":
            return !arguments.dropFirst().contains(where: { $0 == "--" || $0 == "." || $0 == "-f" || $0 == "--force" })
        case "diff":
            return arguments.allSatisfy { $0 == "diff" || $0 == "--stat" || !$0.hasPrefix("-") }
        default:
            return false
        }
    }
}
