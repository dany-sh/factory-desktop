import Foundation

public enum WorkspaceSelectionScope: String, Codable, Equatable, Identifiable {
    case project
    case task

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .project: "Project View"
        case .task: "Task View"
        }
    }
}

public struct ProjectStatusSummary: Equatable {
    public var hygieneSeverity: HygieneSeverity
    public var totalTaskCount: Int
    public var activeTaskCount: Int
    public var archivedTaskCount: Int
    public var cleanupItemCount: Int
    public var selectedTaskBlockerCount: Int
    public var historicalItemCount: Int
    public var artifactWasteItemCount: Int
    public var recentHygieneEventCount: Int
    public var currentBranch: String
    public var defaultBranch: String
    public var head: String
    public var workingTreeState: String
    public var preflightStatus: String

    public init(
        hygieneSeverity: HygieneSeverity,
        totalTaskCount: Int,
        activeTaskCount: Int,
        archivedTaskCount: Int,
        cleanupItemCount: Int,
        selectedTaskBlockerCount: Int,
        historicalItemCount: Int,
        artifactWasteItemCount: Int,
        recentHygieneEventCount: Int,
        currentBranch: String,
        defaultBranch: String,
        head: String,
        workingTreeState: String,
        preflightStatus: String
    ) {
        self.hygieneSeverity = hygieneSeverity
        self.totalTaskCount = totalTaskCount
        self.activeTaskCount = activeTaskCount
        self.archivedTaskCount = archivedTaskCount
        self.cleanupItemCount = cleanupItemCount
        self.selectedTaskBlockerCount = selectedTaskBlockerCount
        self.historicalItemCount = historicalItemCount
        self.artifactWasteItemCount = artifactWasteItemCount
        self.recentHygieneEventCount = recentHygieneEventCount
        self.currentBranch = currentBranch
        self.defaultBranch = defaultBranch
        self.head = head
        self.workingTreeState = workingTreeState
        self.preflightStatus = preflightStatus
    }
}

public struct TaskProjectStatusSummary: Equatable {
    public var hygieneSeverity: HygieneSeverity
    public var hasProjectIssue: Bool
    public var blockerCount: Int
    public var projectCleanupCount: Int
    public var message: String

    public init(
        hygieneSeverity: HygieneSeverity,
        hasProjectIssue: Bool,
        blockerCount: Int,
        projectCleanupCount: Int,
        message: String
    ) {
        self.hygieneSeverity = hygieneSeverity
        self.hasProjectIssue = hasProjectIssue
        self.blockerCount = blockerCount
        self.projectCleanupCount = projectCleanupCount
        self.message = message
    }
}

public enum ProjectWorkspacePresentation {
    public static func projectStatusSummary(
        project: Project?,
        tasks: [FactoryTask],
        hygiene: ProjectHygieneSummary,
        report: RepoHygieneReport?
    ) -> ProjectStatusSummary {
        let activeTaskCount = tasks.filter { $0.status != .done && $0.status != .archived }.count
        let archivedTaskCount = tasks.count - activeTaskCount
        return ProjectStatusSummary(
            hygieneSeverity: hygiene.severity,
            totalTaskCount: tasks.count,
            activeTaskCount: activeTaskCount,
            archivedTaskCount: archivedTaskCount,
            cleanupItemCount: hygiene.totalCleanupItemCount,
            selectedTaskBlockerCount: hygiene.selectedTaskBlockerCount,
            historicalItemCount: hygiene.historicalItemCount,
            artifactWasteItemCount: hygiene.artifactWasteItemCount,
            recentHygieneEventCount: report?.hygieneEvents.count ?? 0,
            currentBranch: report?.currentBranch ?? "unknown",
            defaultBranch: project?.defaultBranch ?? report?.defaultBranch ?? "unknown",
            head: report?.currentHEAD ?? "unknown",
            workingTreeState: report?.workingTreeClean.map { $0 ? "clean" : "dirty" } ?? "unknown",
            preflightStatus: report?.preflightGate.level.displayName ?? "Not scanned"
        )
    }

    public static func taskProjectStatusSummary(hygiene: ProjectHygieneSummary) -> TaskProjectStatusSummary {
        let projectCleanupCount = max(hygiene.totalCleanupItemCount - hygiene.selectedTaskRelevantItemCount, 0)
        if hygiene.selectedTaskBlockerCount > 0 {
            return TaskProjectStatusSummary(
                hygieneSeverity: hygiene.severity,
                hasProjectIssue: true,
                blockerCount: hygiene.selectedTaskBlockerCount,
                projectCleanupCount: projectCleanupCount,
                message: "\(hygiene.selectedTaskBlockerCount) project-level blocker item(s) affect this task."
            )
        }
        if projectCleanupCount > 0 {
            return TaskProjectStatusSummary(
                hygieneSeverity: hygiene.severity,
                hasProjectIssue: true,
                blockerCount: 0,
                projectCleanupCount: projectCleanupCount,
                message: "\(projectCleanupCount) project cleanup item(s) exist outside this task workspace."
            )
        }
        return TaskProjectStatusSummary(
            hygieneSeverity: hygiene.severity,
            hasProjectIssue: false,
            blockerCount: 0,
            projectCleanupCount: 0,
            message: "No project-wide hygiene issues are currently affecting this task."
        )
    }
}
