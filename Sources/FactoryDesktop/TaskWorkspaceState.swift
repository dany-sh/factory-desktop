import FactoryDesktopCore
import SwiftUI

final class TaskWorkspaceState: ObservableObject {
    @Published private(set) var activeTaskID: String?
    @Published private(set) var activeDraftState: TaskDraftState?
    @Published var selectedStage: TaskWorkspaceStage = .write
    @Published var showAllArtifacts = false
    @Published var selectionState = TaskEditorSelectionState()
    @Published var inspectorPresented = true
    @Published var customInlinePrompt = ""

    let editorBridge = RichTaskEditorBridge()

    private let draftStore = TaskDraftStore()

    var draft: TaskDraft {
        get { activeDraftState?.draft ?? TaskDraft() }
        set {
            guard let taskID = activeTaskID else { return }
            activeDraftState = draftStore.update(taskID: taskID) { state in
                state.updateDraft(newValue)
            }
        }
    }

    var acceptanceText: String {
        get { activeDraftState?.acceptanceText ?? "" }
        set {
            guard let taskID = activeTaskID else { return }
            activeDraftState = draftStore.update(taskID: taskID) { state in
                state.updateAcceptanceText(newValue)
            }
        }
    }

    var isDirty: Bool {
        activeDraftState?.isDirty == true
    }

    var editorDocumentMarkdown: String {
        TaskEditorDocument.markdown(brief: draft.brief, acceptanceText: acceptanceText)
    }

    var currentAssistTarget: EditorAssistTarget {
        if selectionState.hasSelection {
            return EditorAssistTarget(
                kind: .selectedText,
                selectedText: selectionState.selectedText,
                activeSection: selectionState.activeSection
            )
        }

        if let activeSection = selectionState.activeSection {
            if selectionState.cursorAtInsertionPoint {
                return EditorAssistTarget(kind: .cursorInsertionPoint, activeSection: activeSection)
            }
            return EditorAssistTarget(kind: .section(activeSection), activeSection: activeSection)
        }

        if selectionState.isFocused {
            return EditorAssistTarget(kind: .cursorInsertionPoint)
        }

        return EditorAssistTarget(kind: .fullBrief)
    }

    func reset() {
        activeTaskID = nil
        activeDraftState = nil
        selectedStage = .write
        showAllArtifacts = false
        selectionState = TaskEditorSelectionState()
        customInlinePrompt = ""
        editorBridge.resetForNoTask()
    }

    func loadIfNeeded(_ task: FactoryTask) {
        load(task)
    }

    func load(_ task: FactoryTask) {
        let previousTaskID = activeTaskID
        editorBridge.prepareForTask(task.id)
        activeTaskID = task.id
        activeDraftState = draftStore.activate(task: task)
        if previousTaskID != task.id {
            selectionState = TaskEditorSelectionState()
            customInlinePrompt = ""
        }
    }

    func markTaskPersisted(_ task: FactoryTask) {
        activeTaskID = task.id
        activeDraftState = draftStore.markPersisted(task: task)
    }

    func updateEditorDocumentMarkdown(_ markdown: String) {
        guard let taskID = activeTaskID else { return }
        activeDraftState = draftStore.update(taskID: taskID) { state in
            state.updateDocumentMarkdown(markdown)
        }
    }

    func updateSelectionState(_ next: TaskEditorSelectionState) {
        let selectionChanged = next.selectedText != selectionState.selectedText
            || next.activeSection != selectionState.activeSection
            || next.isFocused != selectionState.isFocused
            || next.cursorAtInsertionPoint != selectionState.cursorAtInsertionPoint
        guard selectionChanged else { return }
        selectionState = next
    }

    func applyProposal(_ proposal: AIAssistProposal, insertOnly: Bool) {
        let current = editorDocumentMarkdown
        let replacement = proposal.replacementMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !replacement.isEmpty else { return }

        if insertOnly {
            updateEditorDocumentMarkdown(insertMarkdown(replacement, into: current, target: proposal.target))
            return
        }

        switch proposal.target.kind {
        case .selectedText:
            let selection = proposal.target.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !selection.isEmpty, let range = current.range(of: selection) {
                var updated = current
                updated.replaceSubrange(range, with: replacement)
                updateEditorDocumentMarkdown(updated)
            } else {
                updateEditorDocumentMarkdown(replacement)
            }
        case .section(let section):
            updateEditorDocumentMarkdown(replaceSection(section, in: current, with: replacement))
        case .cursorInsertionPoint:
            if let section = proposal.target.activeSection {
                updateEditorDocumentMarkdown(insertMarkdown(replacement, into: current, target: .init(kind: .section(section), activeSection: section)))
            } else {
                updateEditorDocumentMarkdown(insertMarkdown(replacement, into: current, target: proposal.target))
            }
        case .fullBrief:
            updateEditorDocumentMarkdown(replacement)
        }
    }

    private func insertMarkdown(_ replacement: String, into markdown: String, target: EditorAssistTarget) -> String {
        switch target.kind {
        case .section(let section):
            let original = sectionBody(in: markdown, section: section) ?? ""
            let combined = [original, replacement]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n")
            return replaceSection(section, in: markdown, with: combined)
        case .cursorInsertionPoint, .fullBrief, .selectedText:
            let separator = markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
            return markdown + separator + replacement
        }
    }

    private func replaceSection(_ section: EditorAssistSection, in markdown: String, with replacement: String) -> String {
        let normalizedReplacement = stripMatchingHeading(from: replacement, section: section)
        let heading = heading(for: section)
        let lines = markdown.components(separatedBy: .newlines)
        guard let headingIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(heading) == .orderedSame }) else {
            let separator = markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
            return markdown + separator + heading + "\n" + normalizedReplacement
        }

        var endIndex = lines.count
        if let nextIndex = lines[(headingIndex + 1)...].firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("## ") }) {
            endIndex = nextIndex
        }

        var updatedLines = Array(lines[..<headingIndex])
        updatedLines.append(lines[headingIndex])
        if !normalizedReplacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updatedLines.append(contentsOf: normalizedReplacement.components(separatedBy: .newlines))
        }
        if endIndex < lines.count {
            updatedLines.append(contentsOf: lines[endIndex...])
        }
        return updatedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sectionBody(in markdown: String, section: EditorAssistSection) -> String? {
        let lines = markdown.components(separatedBy: .newlines)
        let heading = heading(for: section)
        guard let headingIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(heading) == .orderedSame }) else {
            return nil
        }
        let bodyStart = headingIndex + 1
        let endIndex = lines[bodyStart...].firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("## ") }) ?? lines.count
        return lines[bodyStart..<endIndex].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripMatchingHeading(from markdown: String, section: EditorAssistSection) -> String {
        let lines = markdown.components(separatedBy: .newlines)
        guard let firstContentIndex = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let expectedHeading = heading(for: section).lowercased()
        if lines[firstContentIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == expectedHeading {
            return Array(lines.dropFirst(firstContentIndex + 1))
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func heading(for section: EditorAssistSection) -> String {
        switch section {
        case .goal: "## Goal"
        case .context: "## Context"
        case .scoping: "## Scoping"
        case .acceptanceCriteria: "## Acceptance Criteria"
        }
    }
}
