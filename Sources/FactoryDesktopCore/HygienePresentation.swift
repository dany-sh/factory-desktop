import Foundation

public enum HygieneItemScope: String, CaseIterable, Codable, Identifiable {
    case selectedTask
    case archivedTask
    case project
    case branch
    case artifactWaste
    case backupProtected

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .selectedTask: "Selected Task"
        case .archivedTask: "Archived Task References"
        case .project: "Project Hygiene"
        case .branch: "Branch Lifecycle"
        case .artifactWaste: "Artifact / Run Log Waste"
        case .backupProtected: "Protected Backup Branches"
        }
    }
}

public enum HygieneSeverity: String, CaseIterable, Codable, Identifiable {
    case safe
    case warning
    case blocked
    case informational

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .safe: "Safe"
        case .warning: "Warning"
        case .blocked: "Blocked"
        case .informational: "Informational"
        }
    }
}

public struct ArtifactWasteGroup: Equatable, Identifiable {
    public var id: String
    public var title: String
    public var artifactType: String
    public var count: Int
    public var items: [ArtifactWasteItem]

    public init(id: String, title: String, artifactType: String, count: Int, items: [ArtifactWasteItem]) {
        self.id = id
        self.title = title
        self.artifactType = artifactType
        self.count = count
        self.items = items
    }
}

public struct CleanupPresentationGroup: Equatable, Identifiable {
    public var id: String
    public var title: String
    public var scope: HygieneItemScope
    public var severity: HygieneSeverity
    public var count: Int
    public var collapsedByDefault: Bool
    public var lifecycleItems: [LifecycleItem]
    public var artifactGroups: [ArtifactWasteGroup]

    public init(
        id: String,
        title: String,
        scope: HygieneItemScope,
        severity: HygieneSeverity,
        count: Int,
        collapsedByDefault: Bool,
        lifecycleItems: [LifecycleItem] = [],
        artifactGroups: [ArtifactWasteGroup] = []
    ) {
        self.id = id
        self.title = title
        self.scope = scope
        self.severity = severity
        self.count = count
        self.collapsedByDefault = collapsedByDefault
        self.lifecycleItems = lifecycleItems
        self.artifactGroups = artifactGroups
    }
}

public struct ProjectHygieneSummary: Equatable {
    public var severity: HygieneSeverity
    public var totalCleanupItemCount: Int
    public var selectedTaskRelevantItemCount: Int
    public var selectedTaskBlockerCount: Int
    public var historicalItemCount: Int
    public var artifactWasteItemCount: Int
    public var presentationGroups: [CleanupPresentationGroup]

    public init(
        severity: HygieneSeverity,
        totalCleanupItemCount: Int,
        selectedTaskRelevantItemCount: Int,
        selectedTaskBlockerCount: Int,
        historicalItemCount: Int,
        artifactWasteItemCount: Int,
        presentationGroups: [CleanupPresentationGroup]
    ) {
        self.severity = severity
        self.totalCleanupItemCount = totalCleanupItemCount
        self.selectedTaskRelevantItemCount = selectedTaskRelevantItemCount
        self.selectedTaskBlockerCount = selectedTaskBlockerCount
        self.historicalItemCount = historicalItemCount
        self.artifactWasteItemCount = artifactWasteItemCount
        self.presentationGroups = presentationGroups
    }
}

public enum ProjectHygienePresentation {
    public static func summarize(
        report: RepoHygieneReport?,
        selectedTask: FactoryTask?,
        tasks: [FactoryTask]
    ) -> ProjectHygieneSummary {
        guard let report else {
            return ProjectHygieneSummary(
                severity: .informational,
                totalCleanupItemCount: 0,
                selectedTaskRelevantItemCount: 0,
                selectedTaskBlockerCount: 0,
                historicalItemCount: 0,
                artifactWasteItemCount: 0,
                presentationGroups: []
            )
        }

        let selectedItems = report.lifecycleItems.filter { isSelectedTaskItem($0, task: selectedTask) }
        let archivedTaskIDs = Set(tasks.filter { $0.status == .done || $0.status == .archived }.map(\.id))
        let historicalItems = report.lifecycleItems.filter { item in
            !selectedItems.contains(item) && archivedTaskIDs.contains(where: { archivedTaskID in
                item.id.contains(archivedTaskID)
            })
        }
        let backupItems = report.lifecycleItems.filter { !selectedItems.contains($0) && !historicalItems.contains($0) && $0.classification == .backupProtected }
        let branchItems = report.lifecycleItems.filter { !selectedItems.contains($0) && !historicalItems.contains($0) && !backupItems.contains($0) && $0.kind == .branch }
        let projectItems = report.lifecycleItems.filter { item in
            !selectedItems.contains(item) &&
                !historicalItems.contains(item) &&
                !backupItems.contains(item) &&
                !branchItems.contains(item)
        }
        let artifactGroups = groupArtifactWaste(report.artifactWasteItems)

        var groups: [CleanupPresentationGroup] = []
        appendGroup(
            &groups,
            id: "selected-task",
            title: "Selected Task Cleanup",
            scope: .selectedTask,
            items: selectedItems,
            collapsedByDefault: false
        )
        appendGroup(
            &groups,
            id: "project-worktrees",
            title: "Project Worktrees and Metadata",
            scope: .project,
            items: projectItems,
            collapsedByDefault: false
        )
        appendGroup(
            &groups,
            id: "branch-lifecycle",
            title: "Branch Lifecycle",
            scope: .branch,
            items: branchItems,
            collapsedByDefault: branchItems.count > 6
        )
        appendGroup(
            &groups,
            id: "backup-protected",
            title: "Protected Backup Branches",
            scope: .backupProtected,
            items: backupItems,
            collapsedByDefault: true
        )
        appendGroup(
            &groups,
            id: "historical-task-references",
            title: "Archived Task References",
            scope: .archivedTask,
            items: historicalItems,
            collapsedByDefault: true
        )
        if !artifactGroups.isEmpty {
            groups.append(CleanupPresentationGroup(
                id: "artifact-waste",
                title: "Artifact / Run Log Waste",
                scope: .artifactWaste,
                severity: severity(forArtifacts: report.artifactWasteItems),
                count: report.artifactWasteItems.count,
                collapsedByDefault: true,
                artifactGroups: artifactGroups
            ))
        }

        let selectedBlockers = selectedItems.filter { severity(for: $0) == .blocked }.count
        return ProjectHygieneSummary(
            severity: overallSeverity(gate: report.preflightGate.level, groups: groups),
            totalCleanupItemCount: report.lifecycleItems.count + report.artifactWasteItems.count,
            selectedTaskRelevantItemCount: selectedItems.count,
            selectedTaskBlockerCount: selectedBlockers,
            historicalItemCount: historicalItems.count,
            artifactWasteItemCount: report.artifactWasteItems.count,
            presentationGroups: groups
        )
    }

    private static func appendGroup(
        _ groups: inout [CleanupPresentationGroup],
        id: String,
        title: String,
        scope: HygieneItemScope,
        items: [LifecycleItem],
        collapsedByDefault: Bool
    ) {
        guard !items.isEmpty else { return }
        groups.append(CleanupPresentationGroup(
            id: id,
            title: title,
            scope: scope,
            severity: groupSeverity(for: items, scope: scope),
            count: items.count,
            collapsedByDefault: collapsedByDefault,
            lifecycleItems: items
        ))
    }

    private static func isSelectedTaskItem(_ item: LifecycleItem, task: FactoryTask?) -> Bool {
        guard let task else { return false }
        if item.id.contains(task.id) { return true }
        if let branch = item.branch, branch == task.localBranch || branch == task.codexBranch { return true }
        if let path = item.path, path == task.localWorktreePath || path == task.codexWorktreePath { return true }
        return false
    }

    private static func severity(for gateLevel: LifecycleGateLevel) -> HygieneSeverity {
        switch gateLevel {
        case .green: .safe
        case .yellow: .warning
        case .red: .blocked
        }
    }

    private static func severity(for items: [LifecycleItem]) -> HygieneSeverity {
        if items.contains(where: { severity(for: $0) == .blocked }) { return .blocked }
        if items.contains(where: { severity(for: $0) == .warning }) { return .warning }
        return items.isEmpty ? .informational : .safe
    }

    private static func groupSeverity(for items: [LifecycleItem], scope: HygieneItemScope) -> HygieneSeverity {
        let itemSeverity = severity(for: items)
        if scope == .archivedTask && itemSeverity == .blocked {
            return .warning
        }
        return itemSeverity
    }

    private static func overallSeverity(gate: LifecycleGateLevel, groups: [CleanupPresentationGroup]) -> HygieneSeverity {
        let severities = [severity(for: gate)] + groups.map(\.severity)
        if severities.contains(.blocked) { return .blocked }
        if severities.contains(.warning) { return .warning }
        if severities.contains(.informational) { return .informational }
        return .safe
    }

    private static func severity(for item: LifecycleItem) -> HygieneSeverity {
        switch item.classification {
        case .dirtyRisk, .unpushedRisk, .missingPath, .orphanedMetadata, .unknownRisk:
            .blocked
        case .outdated, .readyToMerge, .duplicateEquivalent, .backupProtected, .removedCleaned, .staleCandidate:
            .warning
        case .healthy, .active, .alreadyMerged:
            .safe
        }
    }

    private static func severity(forArtifacts items: [ArtifactWasteItem]) -> HygieneSeverity {
        if items.contains(where: { $0.classification == .orphaned || $0.classification == .safeToDelete }) {
            return .warning
        }
        if items.contains(where: { $0.classification == .old || $0.classification == .safeToArchive }) {
            return .informational
        }
        return .safe
    }

    public static func groupArtifactWaste(_ items: [ArtifactWasteItem]) -> [ArtifactWasteGroup] {
        let grouped = Dictionary(grouping: items) { item in
            "\(runKey(for: item))|\(artifactTypeName(for: item.path))"
        }
        return grouped.map { key, values in
            let sorted = values.sorted { $0.path < $1.path }
            let first = sorted[0]
            let typeName = artifactTypeName(for: first.path)
            let runTitle = runTitle(for: first)
            return ArtifactWasteGroup(
                id: key,
                title: runTitle,
                artifactType: typeName,
                count: sorted.count,
                items: sorted
            )
        }
        .sorted {
            if $0.title == $1.title {
                return $0.artifactType < $1.artifactType
            }
            return $0.title < $1.title
        }
    }

    private static func runKey(for item: ArtifactWasteItem) -> String {
        if let runId = item.runId, !runId.isEmpty {
            return "run-\(runId)"
        }
        let url = URL(fileURLWithPath: item.path)
        let parent = url.deletingLastPathComponent().lastPathComponent
        if !parent.isEmpty {
            return "folder-\(parent)"
        }
        return "task-\(item.taskId ?? "project")"
    }

    private static func runTitle(for item: ArtifactWasteItem) -> String {
        if let runId = item.runId, !runId.isEmpty {
            return "Run \(runId.shortID)"
        }
        let parent = URL(fileURLWithPath: item.path).deletingLastPathComponent().lastPathComponent
        if !parent.isEmpty {
            return "Folder \(parent)"
        }
        return item.taskId.map { "Task \($0.shortID)" } ?? "Project artifacts"
    }

    private static func artifactTypeName(for path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? "artifact" : name
    }
}
