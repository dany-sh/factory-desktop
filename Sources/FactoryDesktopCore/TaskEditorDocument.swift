import Foundation

public struct TaskEditorDocument: Equatable, Sendable {
    public var brief: String
    public var acceptanceText: String

    public init(brief: String, acceptanceText: String) {
        self.brief = brief
        self.acceptanceText = acceptanceText
    }

    public var markdown: String {
        Self.markdown(brief: brief, acceptanceText: acceptanceText)
    }

    public static func markdown(brief: String, acceptanceText: String) -> String {
        var sections: [String] = []
        let trimmedBrief = brief.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBrief.isEmpty {
            sections.append(trimmedBrief)
        }

        let criteria = acceptanceItems(from: acceptanceText)
        if !criteria.isEmpty {
            sections.append("## Acceptance Criteria\n" + criteria.map { "- \($0)" }.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }

    public static func parse(_ markdown: String) -> TaskEditorDocument {
        let lines = markdown.components(separatedBy: .newlines)
        var briefLines: [String] = []
        var acceptanceLines: [String] = []
        var isAcceptanceSection = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.isAcceptanceHeading(trimmed) {
                isAcceptanceSection = true
                continue
            }

            if isAcceptanceSection {
                acceptanceLines.append(line)
            } else {
                briefLines.append(line)
            }
        }

        return TaskEditorDocument(
            brief: briefLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            acceptanceText: acceptanceItems(from: acceptanceLines.joined(separator: "\n")).joined(separator: "\n")
        )
    }

    public static func acceptanceItems(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { normalizedAcceptanceLine($0) }
            .filter { !$0.isEmpty }
    }

    private static func isAcceptanceHeading(_ line: String) -> Bool {
        let heading = line
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return heading == "acceptance criteria" || heading == "acceptance"
    }

    private static func normalizedAcceptanceLine(_ line: String) -> String {
        var value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("- ") || value.hasPrefix("* ") {
            value = String(value.dropFirst(2))
        } else if let range = value.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
            value.removeSubrange(range)
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum EditorAssistAction: String, CaseIterable, Identifiable, Sendable {
    case rewriteSelection = "rewrite_selection"
    case tightenGoal = "tighten_goal"
    case findAmbiguity = "find_ambiguity"
    case generateAcceptanceCriteria = "generate_acceptance_criteria"
    case splitTask = "split_task"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .rewriteSelection: "Rewrite Selection"
        case .tightenGoal: "Tighten Goal"
        case .findAmbiguity: "Find Ambiguity"
        case .generateAcceptanceCriteria: "Generate Acceptance"
        case .splitTask: "Split Task"
        }
    }
}

public struct EditorAssistProviderOption: Identifiable, Equatable, Sendable {
    public var provider: RunnerProvider
    public var isAvailable: Bool
    public var detail: String

    public init(provider: RunnerProvider, isAvailable: Bool, detail: String) {
        self.provider = provider
        self.isAvailable = isAvailable
        self.detail = detail
    }

    public var id: RunnerProvider { provider }
}

public struct EditorAssistSuggestion: Identifiable, Equatable, Sendable {
    public var id: String
    public var provider: RunnerProvider
    public var action: EditorAssistAction
    public var summary: String
    public var replacementMarkdown: String
    public var rawOutput: String
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        provider: RunnerProvider,
        action: EditorAssistAction,
        summary: String,
        replacementMarkdown: String,
        rawOutput: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.provider = provider
        self.action = action
        self.summary = summary
        self.replacementMarkdown = replacementMarkdown
        self.rawOutput = rawOutput
        self.createdAt = createdAt
    }

    public static func parse(provider: RunnerProvider, action: EditorAssistAction, output: String) -> EditorAssistSuggestion {
        let replacement = fencedMarkdown(in: output) ?? output.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = firstSummaryLine(in: output, fallback: action.displayName)
        return EditorAssistSuggestion(
            provider: provider,
            action: action,
            summary: summary,
            replacementMarkdown: replacement,
            rawOutput: output
        )
    }

    private static func fencedMarkdown(in output: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"```(?:markdown|md)?\s*\n([\s\S]*?)\n```"#, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regex.firstMatch(in: output, range: range),
              let bodyRange = Range(match.range(at: 1), in: output) else {
            return nil
        }
        let body = String(output[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
    }

    private static func firstSummaryLine(in output: String, fallback: String) -> String {
        output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("```") } ?? fallback
    }
}

public enum EditorAssistPrompt {
    public static func instruction(
        action: EditorAssistAction,
        taskTitle: String,
        documentMarkdown: String,
        selectedText: String
    ) -> String {
        let trimmedSelection = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectionBlock = trimmedSelection.isEmpty ? "(no selection)" : trimmedSelection
        return """
        You are Factory Desktop's task-writing assistant.
        Suggest improvements only. Do not edit files, run commands, or change task state.

        Task: \(taskTitle)
        Action: \(action.displayName)

        Selected text:
        \(selectionBlock)

        Current task document:
        \(documentMarkdown)

        Return a concise explanation followed by one fenced markdown block containing the exact replacement or insertion text.
        The user will review and accept or reject the suggestion manually.
        """
    }
}
