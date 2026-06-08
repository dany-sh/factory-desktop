import FactoryDesktopCore
import AppKit
import MarkdownUI
import SwiftUI

private enum MarkdownDocumentMode: String, CaseIterable, Identifiable {
    case preview
    case edit

    var id: Self { self }
}

struct MarkdownViewerEditorView: View {
    let documentPath: String
    @State private var mode: MarkdownDocumentMode = .preview
    @StateObject private var viewModel: MarkdownDocumentViewModel
    @State private var window: NSWindow?

    init(documentPath: String) {
        self.documentPath = documentPath
        _viewModel = StateObject(wrappedValue: MarkdownDocumentViewModel(path: documentPath))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            bodyContent
        }
        .frame(minWidth: 820, minHeight: 620)
        .onAppear {
            mode = .preview
            viewModel.loadIfNeeded()
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            viewModel.refresh()
        }
        .confirmationDialog(
            "You have unsaved markdown changes.",
            isPresented: Binding(
                get: { viewModel.pendingDecision != nil },
                set: { presented in
                    if !presented {
                        viewModel.cancelPendingDecision()
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Save") {
                if viewModel.resolvePendingDecision(saveChanges: true) {
                    closeWindow()
                }
            }
            Button("Discard Changes", role: .destructive) {
                if viewModel.resolvePendingDecision(saveChanges: false, discardChanges: true) {
                    closeWindow()
                }
            }
            Button("Cancel", role: .cancel) {
                _ = viewModel.resolvePendingDecision(saveChanges: nil)
            }
        } message: {
            Text("Save, discard, or cancel before closing this markdown window.")
        }
        .alert(
            "Markdown Document",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .background(WindowAccessor { resolvedWindow in
            window = resolvedWindow
            resolvedWindow.title = document?.title ?? URL(fileURLWithPath: documentPath).lastPathComponent
        })
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(document?.title ?? "Markdown Document")
                        .font(.title3.weight(.semibold))
                    Text(document?.path ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer()
                Picker("Mode", selection: $mode) {
                    Text("Preview").tag(MarkdownDocumentMode.preview)
                    Text("Edit").tag(MarkdownDocumentMode.edit)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
                .disabled((document?.canEdit == false) && mode == .edit)
                Button {
                    viewModel.requestClose()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 8) {
                metadataPill(document?.fileExists == true ? "Available" : "File not found")
                if let document, document.isDirty {
                    metadataPill("Unsaved changes", tint: .orange)
                }
                if let document, document.fileExists, document.isWritable == false {
                    metadataPill("Read-only", tint: .secondary)
                }
                if let lastModifiedAt = document?.lastModifiedAt {
                    metadataPill("Modified \(lastModifiedAt.formatted(date: .abbreviated, time: .shortened))")
                }
                Spacer()
                Button("Discard") {
                    viewModel.discardChanges()
                }
                .disabled(document?.isDirty != true)
                Button("Save") {
                    _ = viewModel.save()
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(document?.isDirty != true)
            }

            if let document, document.externalChangeDetected {
                Label("This file changed on disk while it was open. Save will be blocked until you reload or discard.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if let document, document.fileExists, document.isWritable == false {
                Label("This file is view-only because Factory Desktop does not have write access.", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(.background)
    }

    @ViewBuilder
    private var bodyContent: some View {
        if let document {
            switch mode {
            case .preview:
                preview(document)
            case .edit:
                editor(document)
            }
        } else {
            ContentUnavailableView(
                "No Markdown Document",
                systemImage: "doc.text",
                description: Text("Choose a markdown artifact or project note to open it here.")
            )
        }
    }

    private func preview(_ document: MarkdownDocument) -> some View {
        ScrollView {
            Group {
                if document.fileExists == false {
                    ContentUnavailableView(
                        "File Not Found",
                        systemImage: "doc.slash",
                        description: Text("The markdown file is missing or moved. You can keep the path visible here, but it cannot be read until the file returns.")
                    )
                } else {
                    Markdown(document.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func editor(_ document: MarkdownDocument) -> some View {
        Group {
            if document.fileExists == false {
                preview(document)
            } else {
                TextEditor(text: Binding(
                    get: { viewModel.document?.text ?? "" },
                    set: { viewModel.updateText($0) }
                ))
                .font(.system(.body, design: .monospaced))
                .disabled(document.canEdit == false)
                .padding(16)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }

    private var document: MarkdownDocument? {
        viewModel.document
    }

    private func metadataPill(_ text: String, tint: Color = .secondary) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private func closeWindow() {
        window?.performClose(nil)
    }
}
