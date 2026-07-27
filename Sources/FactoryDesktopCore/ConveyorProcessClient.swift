import Foundation

public struct ConveyorCommandResult: Equatable, Sendable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

public protocol ConveyorCommandExecuting: Sendable {
    func execute(arguments: [String]) async throws -> ConveyorCommandResult
}

public enum ConveyorProcessError: LocalizedError, Equatable {
    case busy
    case launch(String)
    case controller(String)
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .busy: "Another Conveyor change is still in progress."
        case let .launch(message), let .controller(message), let .invalidResponse(message): message
        }
    }
}

public struct ConveyorProcessExecutor: ConveyorCommandExecuting {
    public let controllerRoot: URL
    private let outputLimit = 256 * 1024

    public init(controllerRoot: URL = ConveyorProcessExecutor.defaultControllerRoot) {
        self.controllerRoot = controllerRoot
    }

    public static var defaultControllerRoot: URL {
        if let configured = ProcessInfo.processInfo.environment["FACTORY_CONVEYOR_ROOT"], !configured.isEmpty {
            return URL(fileURLWithPath: configured, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Developer/development-conveyor", isDirectory: true)
    }

    public func execute(arguments: [String]) async throws -> ConveyorCommandResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = controllerRoot.appendingPathComponent("scripts/conveyor")
            process.arguments = arguments
            process.currentDirectoryURL = controllerRoot
            let output = Pipe()
            let error = Pipe()
            process.standardOutput = output
            process.standardError = error
            do {
                try process.run()
            } catch {
                throw ConveyorProcessError.launch(error.localizedDescription)
            }
            let outputTask = Task.detached {
                Self.readBounded(output.fileHandleForReading, limit: outputLimit)
            }
            let errorTask = Task.detached {
                Self.readBounded(error.fileHandleForReading, limit: outputLimit)
            }
            process.waitUntilExit()
            let standardOutput = await outputTask.value
            let standardError = await errorTask.value
            return ConveyorCommandResult(
                exitCode: process.terminationStatus,
                standardOutput: standardOutput,
                standardError: standardError
            )
        }.value
    }

    private static func readBounded(_ handle: FileHandle, limit: Int) -> String {
        var captured = Data()
        while true {
            let chunk = handle.availableData
            guard !chunk.isEmpty else { break }
            if captured.count < limit {
                captured.append(chunk.prefix(limit - captured.count))
            }
        }
        return String(data: captured, encoding: .utf8) ?? ""
    }
}

public actor ConveyorMutationSerializer {
    private var isMutating = false

    public init() {}

    public func perform<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        guard !isMutating else { throw ConveyorProcessError.busy }
        isMutating = true
        defer { isMutating = false }
        return try await work()
    }
}

public final class ConveyorProcessClient: @unchecked Sendable {
    private let executor: any ConveyorCommandExecuting
    private let serializer: ConveyorMutationSerializer
    private let decoder = JSONDecoder()

    public init(
        executor: any ConveyorCommandExecuting = ConveyorProcessExecutor(),
        serializer: ConveyorMutationSerializer = ConveyorMutationSerializer()
    ) {
        self.executor = executor
        self.serializer = serializer
    }

    public func queue(
        projectID: String,
        scope: ConveyorScope = .active,
        milestone: String? = nil
    ) async throws -> ConveyorQueue {
        var arguments = ["queue", "--project", projectID, "--scope", scope.rawValue]
        if let milestone { arguments += ["--milestone", milestone] }
        arguments.append("--json")
        return try await decode(ConveyorQueue.self, arguments: arguments)
    }

    public func status(projectID: String) async throws -> ConveyorStatusProjection {
        try await decode(ConveyorStatusProjection.self, arguments: ["status", "--project", projectID])
    }

    public func markReady(projectID: String, featureID: String) async throws -> ConveyorMutationResult {
        try await mutation(["ready", "--project", projectID, "--feature", featureID])
    }

    public func moveToBacklog(projectID: String, featureID: String) async throws -> ConveyorMutationResult {
        try await mutation(["backlog", "--project", projectID, "--feature", featureID])
    }

    public func prioritize(
        projectID: String,
        featureID: String,
        priority: ConveyorPriority,
        beforeFeatureID: String? = nil
    ) async throws -> ConveyorMutationResult {
        var arguments = ["prioritize", "--project", projectID, "--feature", featureID, "--priority", priority.rawValue]
        if let beforeFeatureID { arguments += ["--before", beforeFeatureID] }
        return try await mutation(arguments)
    }

    public func reorder(projectID: String, featureID: String, beforeFeatureID: String) async throws -> ConveyorMutationResult {
        try await mutation(["prioritize", "--project", projectID, "--feature", featureID, "--before", beforeFeatureID])
    }

    public func pause(projectID: String) async throws -> ConveyorMutationResult {
        try await mutation(["pause", "--project", projectID])
    }

    public func unpause(projectID: String) async throws -> ConveyorMutationResult {
        try await mutation(["unpause", "--project", projectID])
    }

    public func runThisFeature(projectID: String, featureID: String) async throws -> ConveyorMutationResult {
        try await mutation(["run", "--project", projectID, "--feature", featureID])
    }

    public func runNext(projectID: String) async throws -> ConveyorMutationResult {
        try await mutation(["resume", "--project", projectID])
    }

    private func mutation(_ arguments: [String]) async throws -> ConveyorMutationResult {
        try await serializer.perform { [executor, decoder] in
            try await Self.decode(ConveyorMutationResult.self, executor: executor, decoder: decoder, arguments: arguments)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, arguments: [String]) async throws -> T {
        try await Self.decode(type, executor: executor, decoder: decoder, arguments: arguments)
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        executor: any ConveyorCommandExecuting,
        decoder: JSONDecoder,
        arguments: [String]
    ) async throws -> T {
        let result = try await executor.execute(arguments: arguments)
        guard result.exitCode == 0 else {
            throw ConveyorProcessError.controller(exactControllerError(result))
        }
        guard let data = result.standardOutput.data(using: .utf8) else {
            throw ConveyorProcessError.invalidResponse("Conveyor returned unreadable JSON.")
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ConveyorProcessError.invalidResponse("Conveyor returned invalid JSON: \(error.localizedDescription)")
        }
    }

    private static func exactControllerError(_ result: ConveyorCommandResult) -> String {
        let text = result.standardError.isEmpty ? result.standardOutput : result.standardError
        return text.isEmpty ? "Conveyor command failed (exit \(result.exitCode))." : text
    }
}
