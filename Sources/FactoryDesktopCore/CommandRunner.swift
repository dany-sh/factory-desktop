import Foundation

public struct CommandRequest: Equatable {
    public var executable: String
    public var arguments: [String]
    public var workingDirectory: URL?
    public var manuallyApproved: Bool
    public var standardInput: String?

    public init(
        executable: String,
        arguments: [String] = [],
        workingDirectory: URL? = nil,
        manuallyApproved: Bool = false,
        standardInput: String? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.manuallyApproved = manuallyApproved
        self.standardInput = standardInput
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
            let inputPipe: Pipe?
            if request.standardInput != nil {
                let pipe = Pipe()
                process.standardInput = pipe
                inputPipe = pipe
            } else {
                inputPipe = nil
            }

            try process.run()
            let outputTask = Task {
                outputPipe.fileHandleForReading.readDataToEndOfFile()
            }
            if let standardInput = request.standardInput, let inputPipe {
                inputPipe.fileHandleForWriting.write(Data(standardInput.utf8))
                try? inputPipe.fileHandleForWriting.close()
            }
            process.waitUntilExit()

            let data = await outputTask.value
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
            return ["build", "test"].contains(arguments.first ?? "")
        case "npm":
            return arguments.count >= 2 && arguments[0] == "run" && [
                "build",
                "lint",
                "test",
                "integration",
                "e2e",
                "visual",
                "visual-qc",
                "visualqc"
            ].contains(arguments[1])
        case "python", "python3":
            return arguments.count >= 2 && arguments[0] == "-m" && arguments[1] == "pytest"
        case "true", "false", "printf", "echo":
            return true
        case "open", "code":
            return true
        case "codex":
            return isAllowedCodex(arguments)
        default:
            return false
        }
    }

    private func isAllowedCodex(_ arguments: [String]) -> Bool {
        guard arguments.first == "exec" else { return false }
        guard optionValue(in: arguments, short: "-s", long: "--sandbox") == "read-only" else { return false }
        guard optionValue(in: arguments, short: "-C", long: "--cd") != nil else { return false }
        guard !arguments.contains("--dangerously-bypass-approvals-and-sandbox") else { return false }
        guard !arguments.contains("--dangerously-bypass-hook-trust") else { return false }
        guard !arguments.contains("--add-dir") else { return false }
        return true
    }

    private func optionValue(in arguments: [String], short: String, long: String) -> String? {
        for index in arguments.indices {
            let argument = arguments[index]
            if argument == short || argument == long {
                let valueIndex = arguments.index(after: index)
                return arguments.indices.contains(valueIndex) ? arguments[valueIndex] : nil
            }
            let longPrefix = "\(long)="
            if argument.hasPrefix(longPrefix) {
                return String(argument.dropFirst(longPrefix.count))
            }
        }
        return nil
    }

    private func isAllowedGit(_ arguments: [String], manuallyApproved: Bool) -> Bool {
        guard let first = arguments.first else { return false }
        switch first {
        case "status", "log", "add":
            return true
        case "rev-parse":
            return isAllowedGitRevParse(arguments)
        case "rev-list":
            return isAllowedGitRevList(arguments)
        case "merge-base":
            return isAllowedGitMergeBase(arguments)
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

    private func isAllowedGitRevParse(_ arguments: [String]) -> Bool {
        guard arguments.first == "rev-parse", arguments.count >= 2 else { return false }
        let allowedOptions = Set(["--short", "--verify", "--abbrev-ref", "--show-toplevel", "--git-dir", "--is-inside-work-tree"])
        return arguments.dropFirst().allSatisfy { argument in
            allowedOptions.contains(argument) || isSafeGitRevision(argument)
        }
    }

    private func isAllowedGitRevList(_ arguments: [String]) -> Bool {
        guard arguments.first == "rev-list", arguments.count >= 2 else { return false }
        let allowedOptions = Set(["--left-right", "--count"])
        return arguments.dropFirst().allSatisfy { argument in
            allowedOptions.contains(argument) || isSafeGitRevision(argument)
        }
    }

    private func isAllowedGitMergeBase(_ arguments: [String]) -> Bool {
        guard arguments.first == "merge-base", arguments.count == 4 else { return false }
        guard arguments[1] == "--is-ancestor" else { return false }
        return isSafeGitRevision(arguments[2]) && isSafeGitRevision(arguments[3])
    }

    private func isSafeGitRevision(_ argument: String) -> Bool {
        guard !argument.isEmpty else { return false }
        guard !argument.hasPrefix("-") else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/_-.~^:")
        return argument.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
