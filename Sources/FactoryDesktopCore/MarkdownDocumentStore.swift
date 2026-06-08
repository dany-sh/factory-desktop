import Foundation

public struct MarkdownFileVersion: Equatable, Sendable {
    public var modificationDate: Date?
    public var fileSize: UInt64?

    public init(modificationDate: Date?, fileSize: UInt64?) {
        self.modificationDate = modificationDate
        self.fileSize = fileSize
    }
}

public struct MarkdownDocument: Identifiable, Equatable, Sendable {
    public var path: String
    public var title: String
    public var text: String
    public var savedText: String
    public var lastModifiedAt: Date?
    public var version: MarkdownFileVersion?
    public var fileExists: Bool
    public var isWritable: Bool
    public var externalChangeDetected: Bool

    public init(
        path: String,
        title: String,
        text: String,
        savedText: String,
        lastModifiedAt: Date?,
        version: MarkdownFileVersion?,
        fileExists: Bool,
        isWritable: Bool,
        externalChangeDetected: Bool = false
    ) {
        self.path = path
        self.title = title
        self.text = text
        self.savedText = savedText
        self.lastModifiedAt = lastModifiedAt
        self.version = version
        self.fileExists = fileExists
        self.isWritable = isWritable
        self.externalChangeDetected = externalChangeDetected
    }

    public var id: String { path }

    public var isDirty: Bool {
        text != savedText
    }

    public var canEdit: Bool {
        fileExists && isWritable
    }
}

public enum MarkdownDocumentSaveConflict: Error, LocalizedError, Equatable {
    case fileNotFound(String)
    case readOnlyFile(String)
    case fileChangedOnDisk(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Markdown file not found: \(path)"
        case .readOnlyFile(let path):
            return "Markdown file is read-only: \(path)"
        case .fileChangedOnDisk(let path):
            return "Markdown file changed on disk since it was opened: \(path)"
        }
    }
}

public struct MarkdownOpenTarget: Equatable, Sendable {
    public var path: String
    public var title: String

    public init(path: String, title: String) {
        self.path = path
        self.title = title
    }
}

public enum PendingMarkdownDecision: Equatable, Sendable {
    case open(MarkdownOpenTarget)
    case close
}

public struct MarkdownDocumentStore {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func loadDocument(atPath path: String, title: String? = nil) throws -> MarkdownDocument {
        let normalizedPath = normalized(path)
        let displayTitle = normalizedTitle(for: normalizedPath, fallback: title)
        let exists = fileManager.fileExists(atPath: normalizedPath)
        let version = fileVersion(atPath: normalizedPath)
        let lastModifiedAt = version?.modificationDate
        let isWritable = exists && fileManager.isWritableFile(atPath: normalizedPath)

        guard exists else {
            return MarkdownDocument(
                path: normalizedPath,
                title: displayTitle,
                text: "",
                savedText: "",
                lastModifiedAt: nil,
                version: nil,
                fileExists: false,
                isWritable: false
            )
        }

        let text = try String(contentsOfFile: normalizedPath, encoding: .utf8)
        return MarkdownDocument(
            path: normalizedPath,
            title: displayTitle,
            text: text,
            savedText: text,
            lastModifiedAt: lastModifiedAt,
            version: version,
            fileExists: true,
            isWritable: isWritable
        )
    }

    public func refreshMetadata(for document: MarkdownDocument) -> MarkdownDocument {
        let normalizedPath = normalized(document.path)
        let exists = fileManager.fileExists(atPath: normalizedPath)
        let version = fileVersion(atPath: normalizedPath)
        let lastModifiedAt = version?.modificationDate
        let isWritable = exists && fileManager.isWritableFile(atPath: normalizedPath)

        var refreshed = document
        refreshed.path = normalizedPath
        refreshed.fileExists = exists
        refreshed.version = document.version
        refreshed.lastModifiedAt = lastModifiedAt
        refreshed.isWritable = isWritable
        refreshed.externalChangeDetected = exists ? version != document.version : document.version != nil
        return refreshed
    }

    public func updatingDraft(_ document: MarkdownDocument, text: String) -> MarkdownDocument {
        var updated = document
        updated.text = text
        return updated
    }

    public func discardChanges(for document: MarkdownDocument) throws -> MarkdownDocument {
        try loadDocument(atPath: document.path, title: document.title)
    }

    public func save(_ document: MarkdownDocument) throws -> MarkdownDocument {
        let normalizedPath = normalized(document.path)
        guard fileManager.fileExists(atPath: normalizedPath) else {
            throw MarkdownDocumentSaveConflict.fileNotFound(normalizedPath)
        }
        guard fileManager.isWritableFile(atPath: normalizedPath) else {
            throw MarkdownDocumentSaveConflict.readOnlyFile(normalizedPath)
        }
        guard fileVersion(atPath: normalizedPath) == document.version else {
            throw MarkdownDocumentSaveConflict.fileChangedOnDisk(normalizedPath)
        }

        try document.text.write(toFile: normalizedPath, atomically: true, encoding: .utf8)
        return try loadDocument(atPath: normalizedPath, title: document.title)
    }

    private func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func normalizedTitle(for path: String, fallback: String?) -> String {
        let trimmed = fallback?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? URL(fileURLWithPath: path).lastPathComponent : trimmed
    }

    private func fileVersion(atPath path: String) -> MarkdownFileVersion? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: path) else {
            return nil
        }

        let modificationDate = attributes[.modificationDate] as? Date
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value
        return MarkdownFileVersion(modificationDate: modificationDate, fileSize: fileSize)
    }
}
