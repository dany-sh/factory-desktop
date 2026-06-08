import Foundation

public enum CodexSessionResultImporter {
    public static func shortSummary(from result: CommandResult, fallback: String) -> String {
        let lines = result.output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let firstUsefulLine = lines.first(where: { !isNoiseLine($0) }) else {
            return fallback
        }

        if firstUsefulLine.count <= 180 {
            return firstUsefulLine
        }
        return String(firstUsefulLine.prefix(177)) + "..."
    }

    public static func status(for result: CommandResult, successfulStatus: CodexSessionStatus) -> CodexSessionStatus {
        guard result.succeeded else { return .failed }
        if containsClearFailure(result.output) {
            return .failed
        }
        return successfulStatus
    }

    public static func containsClearFailure(_ output: String) -> Bool {
        let normalized = output.lowercased()
        let failurePhrases = [
            "error:",
            "fatal:",
            "failed",
            "failure",
            "exception",
            "traceback",
            "could not resume",
            "session not found",
            "no such session",
            "permission denied"
        ]
        return failurePhrases.contains { normalized.contains($0) }
    }

    private static func isNoiseLine(_ line: String) -> Bool {
        let normalized = line.lowercased()
        return normalized.hasPrefix("warning:") ||
            normalized.hasPrefix("command:") ||
            normalized.hasPrefix("started:") ||
            normalized.hasPrefix("ended:") ||
            normalized.hasPrefix("exit code:")
    }
}
