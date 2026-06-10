import Darwin
import Foundation

public enum WorkerProcessStatus: String, Codable, Equatable, Sendable {
    case running
    case cancelling
    case cancelled
    case completed
    case failed
    case detached
    case unknown

    public var displayName: String {
        switch self {
        case .running: "Running"
        case .cancelling: "Cancelling"
        case .cancelled: "Cancelled"
        case .completed: "Completed"
        case .failed: "Failed"
        case .detached: "Detached"
        case .unknown: "Unknown"
        }
    }
}

public struct WorkerProcessRegistration: Equatable, Sendable {
    public var executionId: String
    public var sessionId: String
    public var taskId: String
    public var startedAt: Date
    public var command: String
    public var workingDirectory: String?

    public init(
        executionId: String,
        sessionId: String,
        taskId: String,
        startedAt: Date,
        command: String,
        workingDirectory: String?
    ) {
        self.executionId = executionId
        self.sessionId = sessionId
        self.taskId = taskId
        self.startedAt = startedAt
        self.command = command
        self.workingDirectory = workingDirectory
    }
}

public struct WorkerProcessSnapshot: Identifiable, Equatable, Sendable {
    public var id: String { executionId }
    public var executionId: String
    public var sessionId: String
    public var taskId: String
    public var startedAt: Date
    public var command: String
    public var workingDirectory: String?
    public var status: WorkerProcessStatus

    public init(registration: WorkerProcessRegistration, status: WorkerProcessStatus) {
        self.executionId = registration.executionId
        self.sessionId = registration.sessionId
        self.taskId = registration.taskId
        self.startedAt = registration.startedAt
        self.command = registration.command
        self.workingDirectory = registration.workingDirectory
        self.status = status
    }
}

public protocol WorkerProcessHandle: AnyObject, Sendable {
    var isRunning: Bool { get }
    var cancellationRequested: Bool { get }
    func terminate()
    func kill()
    func waitUntilExit() async
}

public actor WorkerProcessRegistry {
    private struct Entry {
        var registration: WorkerProcessRegistration
        var handle: WorkerProcessHandle
        var status: WorkerProcessStatus
    }

    private var entries: [String: Entry] = [:]

    public init() {}

    public func register(_ registration: WorkerProcessRegistration, handle: WorkerProcessHandle) {
        entries[registration.executionId] = Entry(
            registration: registration,
            handle: handle,
            status: .running
        )
    }

    public func unregister(executionId: String, finalStatus: WorkerProcessStatus) {
        entries.removeValue(forKey: executionId)
    }

    public func snapshot(executionId: String) -> WorkerProcessSnapshot? {
        entries[executionId].map { WorkerProcessSnapshot(registration: $0.registration, status: $0.status) }
    }

    public func snapshots() -> [WorkerProcessSnapshot] {
        entries.values
            .map { WorkerProcessSnapshot(registration: $0.registration, status: $0.status) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    public func isLive(executionId: String) -> Bool {
        guard let entry = entries[executionId] else { return false }
        return entry.status == .running && entry.handle.isRunning
    }

    @discardableResult
    public func cancel(executionId: String, graceNanoseconds: UInt64 = 3_000_000_000) async -> Bool {
        guard var entry = entries[executionId] else { return false }
        entry.status = .cancelling
        entries[executionId] = entry
        entry.handle.terminate()

        let waitTask = Task {
            await entry.handle.waitUntilExit()
        }
        let pollNanoseconds: UInt64 = 50_000_000
        var waited: UInt64 = 0
        while entry.handle.isRunning && waited < graceNanoseconds {
            try? await Task.sleep(nanoseconds: pollNanoseconds)
            waited += pollNanoseconds
        }
        if entry.handle.isRunning {
            entry.handle.kill()
        }
        await waitTask.value

        if var latest = entries[executionId] {
            latest.status = .cancelled
            entries[executionId] = latest
        }
        return true
    }
}

public final class ProcessWorkerHandle: WorkerProcessHandle, @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private var didRequestCancellation = false

    public init(process: Process) {
        self.process = process
    }

    public var isRunning: Bool {
        process.isRunning
    }

    public var cancellationRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didRequestCancellation
    }

    public func terminate() {
        lock.lock()
        didRequestCancellation = true
        lock.unlock()
        if process.isRunning {
            process.terminate()
        }
    }

    public func kill() {
        lock.lock()
        didRequestCancellation = true
        lock.unlock()
        if process.isRunning {
            process.interrupt()
            if process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    public func waitUntilExit() async {
        await Task.detached {
            self.process.waitUntilExit()
        }.value
    }
}

public protocol WorkerCommandExecuting: AnyObject {
    func execute(_ request: CommandRequest, registration: WorkerProcessRegistration?) async throws -> CommandResult
}

public final class CancellableWorkerCommandExecutor: WorkerCommandExecuting {
    private let commandRunner: CommandRunner
    private let registry: WorkerProcessRegistry

    public init(commandRunner: CommandRunner, registry: WorkerProcessRegistry) {
        self.commandRunner = commandRunner
        self.registry = registry
    }

    public func execute(_ request: CommandRequest, registration: WorkerProcessRegistration?) async throws -> CommandResult {
        if let registration {
            return try await commandRunner.runCancellable(request, registration: registration, registry: registry)
        }
        return try await commandRunner.run(request)
    }
}

public final class CodexServiceWorkerCommandExecutor: WorkerCommandExecuting {
    private let service: CodexCLIService

    public init(service: CodexCLIService) {
        self.service = service
    }

    public func execute(_ request: CommandRequest, registration: WorkerProcessRegistration?) async throws -> CommandResult {
        try await service.run(request)
    }
}
