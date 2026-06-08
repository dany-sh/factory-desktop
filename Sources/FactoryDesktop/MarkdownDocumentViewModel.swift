import FactoryDesktopCore
import Foundation

@MainActor
final class MarkdownDocumentViewModel: ObservableObject {
    @Published private(set) var document: MarkdownDocument?
    @Published var pendingDecision: PendingMarkdownDecision?
    @Published var errorMessage: String?

    let path: String

    private let store = MarkdownDocumentStore()

    init(path: String) {
        self.path = MarkdownDocumentStore.normalizedMarkdownPath(path)
    }

    func loadIfNeeded() {
        guard document == nil else { return }
        load()
    }

    func refresh() {
        guard let document else { return }
        self.document = store.refreshMetadata(for: document)
    }

    func updateText(_ text: String) {
        guard let document else { return }
        self.document = store.updatingDraft(document, text: text)
    }

    @discardableResult
    func save() -> Bool {
        guard let document else { return false }
        do {
            self.document = try store.save(document)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            refresh()
            return false
        }
    }

    func discardChanges() {
        guard let document else { return }
        do {
            self.document = try store.discardChanges(for: document)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestClose() {
        guard let document, document.isDirty else {
            pendingDecision = .close
            return
        }
        pendingDecision = .close
    }

    func cancelPendingDecision() {
        pendingDecision = nil
    }

    func resolvePendingDecision(saveChanges: Bool?, discardChanges: Bool = false) -> Bool {
        let pending = pendingDecision
        pendingDecision = nil

        if saveChanges == true, save() == false {
            pendingDecision = pending
            return false
        }

        if discardChanges {
            self.discardChanges()
        }

        return pending != nil
    }

    private func load() {
        do {
            document = try store.loadDocument(atPath: path)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
