import Foundation

public final class CodexRunnerAdapter: RunnerProviderAdapter {
    public let provider: RunnerProvider = .codex
    public let supportedModes: Set<RunnerMode> = [.scoping, .planning, .coding, .review, .summary, .testDebug]

    private let service: CodexCLIService

    public init(service: CodexCLIService) {
        self.service = service
    }

    public func availability() async -> RunnerAvailability {
        let availability = await service.availability()
        return RunnerAvailability(isAvailable: availability.isAvailable, message: availability.message)
    }

    public func execute(_ request: RunnerRequest) async throws -> RunnerResult {
        let startedAt = Date()
        let commandRequest: CommandRequest
        if let linkedSessionID = request.linkedSessionID, !linkedSessionID.isEmpty {
            commandRequest = try service.commandRequest(for: .execResume(
                sessionId: linkedSessionID,
                workspacePath: request.workspacePath,
                instruction: request.instruction
            ))
        } else {
            commandRequest = try service.commandRequest(for: .exec(
                workspacePath: request.workspacePath,
                instruction: request.instruction
            ))
        }

        let command = RunnerCommand(
            executable: commandRequest.executable,
            arguments: commandRequest.arguments,
            workingDirectory: commandRequest.workingDirectory?.path
        )
        let rawResult: CommandResult
        if request.linkedSessionID != nil {
            rawResult = try await service.execResume(
                sessionId: request.linkedSessionID ?? "",
                workspacePath: request.workspacePath,
                instruction: request.instruction
            )
        } else {
            rawResult = try await service.exec(
                workspacePath: request.workspacePath,
                instruction: request.instruction
            )
        }
        let endedAt = Date()
        let summary = CodexSessionResultImporter.shortSummary(
            from: rawResult,
            fallback: rawResult.succeeded ? "\(request.mode.displayName) run completed." : "\(request.mode.displayName) run failed."
        )

        return RunnerResult(
            provider: provider,
            mode: request.mode,
            command: command,
            standardOutput: rawResult.standardOutput,
            standardError: rawResult.standardError,
            exitCode: rawResult.exitCode,
            startedAt: startedAt,
            endedAt: endedAt,
            summary: summary,
            sessionMetadata: RunnerSessionMetadata(sessionID: Self.detectSessionID(in: rawResult.output))
        )
    }

    private static func detectSessionID(in output: String) -> String? {
        let patterns = [
            #"session[_ ]id[:=]\s*([A-Za-z0-9._-]+)"#,
            #"resume\s+([A-Za-z0-9._-]+)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            guard let match = regex.firstMatch(in: output, options: [], range: range), match.numberOfRanges > 1,
                  let sessionRange = Range(match.range(at: 1), in: output) else { continue }
            return String(output[sessionRange])
        }
        return nil
    }
}
