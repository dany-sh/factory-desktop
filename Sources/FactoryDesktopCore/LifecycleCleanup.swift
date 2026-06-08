import Foundation

public enum LifecycleClassification: String, CaseIterable, Codable, Identifiable {
    case healthy
    case active
    case outdated
    case readyToMerge = "ready_to_merge"
    case alreadyMerged = "already_merged"
    case duplicateEquivalent = "duplicate_equivalent"
    case dirtyRisk = "dirty_risk"
    case unpushedRisk = "unpushed_risk"
    case backupProtected = "backup_protected"
    case missingPath = "missing_path"
    case removedCleaned = "removed_cleaned"
    case staleCandidate = "stale_candidate"
    case orphanedMetadata = "orphaned_metadata"
    case unknownRisk = "unknown_risk"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .healthy: "Healthy"
        case .active: "Active"
        case .outdated: "Outdated"
        case .readyToMerge: "Ready To Merge"
        case .alreadyMerged: "Already Merged"
        case .duplicateEquivalent: "Duplicate Equivalent"
        case .dirtyRisk: "Dirty Risk"
        case .unpushedRisk: "Unpushed Risk"
        case .backupProtected: "Backup Protected"
        case .missingPath: "Missing Path"
        case .removedCleaned: "Removed / Cleaned"
        case .staleCandidate: "Stale Candidate"
        case .orphanedMetadata: "Orphaned Metadata"
        case .unknownRisk: "Unknown Risk"
        }
    }
}

public enum LifecycleState: String, CaseIterable, Codable, Identifiable {
    case created
    case planning
    case approved
    case worktreeCreated = "worktree_created"
    case running
    case codeComplete = "code_complete"
    case testsRunning = "tests_running"
    case testsPassed = "tests_passed"
    case testsFailed = "tests_failed"
    case readyForReview = "ready_for_review"
    case mergeReady = "merge_ready"
    case merged
    case pushed
    case verifiedOnMain = "verified_on_main"
    case archived
    case cleaned
    case blocked
    case outdated
    case dirtyRisk = "dirty_risk"
    case conflictRisk = "conflict_risk"
    case duplicateEquivalent = "duplicate_equivalent"
    case backupProtected = "backup_protected"
    case abandoned
    case unknown

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .created: "Created"
        case .planning: "Planning"
        case .approved: "Approved"
        case .worktreeCreated: "Worktree Created"
        case .running: "Running"
        case .codeComplete: "Code Complete"
        case .testsRunning: "Tests Running"
        case .testsPassed: "Tests Passed"
        case .testsFailed: "Tests Failed"
        case .readyForReview: "Ready For Review"
        case .mergeReady: "Merge Ready"
        case .merged: "Merged"
        case .pushed: "Pushed"
        case .verifiedOnMain: "Verified On Main"
        case .archived: "Archived"
        case .cleaned: "Cleaned"
        case .blocked: "Blocked"
        case .outdated: "Outdated"
        case .dirtyRisk: "Dirty Risk"
        case .conflictRisk: "Conflict Risk"
        case .duplicateEquivalent: "Duplicate Equivalent"
        case .backupProtected: "Backup Protected"
        case .abandoned: "Abandoned"
        case .unknown: "Unknown"
        }
    }
}

public enum LifecycleRecommendedAction: String, CaseIterable, Codable, Identifiable {
    case continueWork = "continue_work"
    case runTests = "run_tests"
    case reviewDiff = "review_diff"
    case createBackup = "create_backup"
    case refreshFromMain = "refresh_from_main"
    case rebaseOntoMain = "rebase_onto_main"
    case mergeFastForward = "merge_fast_forward"
    case pushMain = "push_main"
    case deleteDuplicateBranch = "delete_duplicate_branch"
    case removeCleanWorktree = "remove_clean_worktree"
    case archiveArtifacts = "archive_artifacts"
    case manualReviewRequired = "manual_review_required"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .continueWork: "Continue Work"
        case .runTests: "Run Tests"
        case .reviewDiff: "Review Diff"
        case .createBackup: "Create Backup"
        case .refreshFromMain: "Refresh from Main"
        case .rebaseOntoMain: "Rebase onto Main"
        case .mergeFastForward: "Merge Fast Forward"
        case .pushMain: "Push Main"
        case .deleteDuplicateBranch: "Delete Duplicate Branch"
        case .removeCleanWorktree: "Remove Clean Worktree"
        case .archiveArtifacts: "Archive Artifacts"
        case .manualReviewRequired: "Blocked: Manual Review Required"
        }
    }
}

public enum LifecycleSafeAction: String, CaseIterable, Codable, Identifiable {
    case refreshScan = "refresh_scan"
    case inspectDiff = "inspect_diff"
    case refreshFromMain = "refresh_from_main"
    case rebaseOntoMain = "rebase_onto_main"
    case stashWorktreeChanges = "stash_worktree_changes"
    case createWIPBackupCommit = "create_wip_backup_commit"
    case fastForwardMergeToMain = "fast_forward_merge_to_main"
    case pushMain = "push_main"
    case deleteMergedBranch = "delete_merged_branch"
    case deleteDuplicateBranch = "delete_duplicate_branch"
    case removeCleanWorktree = "remove_clean_worktree"
    case pruneWorktreeMetadata = "prune_worktree_metadata"
    case archiveOldArtifacts = "archive_old_artifacts"
    case deleteOldArtifacts = "delete_old_artifacts"
    case keepProtectBackupBranch = "keep_protect_backup_branch"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .refreshScan: "Refresh Scan"
        case .inspectDiff: "Inspect Diff"
        case .refreshFromMain: "Refresh from Main"
        case .rebaseOntoMain: "Rebase onto Main"
        case .stashWorktreeChanges: "Stash Changes"
        case .createWIPBackupCommit: "Create WIP Backup Commit"
        case .fastForwardMergeToMain: "Fast-forward Merge to Main"
        case .pushMain: "Push Main"
        case .deleteMergedBranch: "Delete Merged Branch"
        case .deleteDuplicateBranch: "Delete Duplicate Branch"
        case .removeCleanWorktree: "Remove Clean Worktree"
        case .pruneWorktreeMetadata: "Prune Worktree Metadata"
        case .archiveOldArtifacts: "Archive Old Artifacts"
        case .deleteOldArtifacts: "Delete Old Artifacts"
        case .keepProtectBackupBranch: "Keep / Protect Backup Branch"
        }
    }

    public var isFoundationOnly: Bool {
        switch self {
        case .refreshScan, .inspectDiff, .refreshFromMain:
            return false
        default:
            return true
        }
    }

    public var requiresConfirmation: Bool {
        switch self {
        case .refreshScan, .inspectDiff, .refreshFromMain:
            return false
        default:
            return true
        }
    }
}

public struct LifecycleBlockedAction: Equatable, Codable, Identifiable {
    public var id: String { "\(action.rawValue)-\(reason)" }
    public var action: LifecycleSafeAction
    public var reason: String

    public init(action: LifecycleSafeAction, reason: String) {
        self.action = action
        self.reason = reason
    }
}

public enum LifecycleItemKind: String, CaseIterable, Codable, Identifiable {
    case branch
    case worktree
    case metadata

    public var id: String { rawValue }
}

public struct LifecycleItem: Equatable, Codable, Identifiable {
    public var id: String
    public var kind: LifecycleItemKind
    public var label: String
    public var path: String?
    public var branch: String?
    public var head: String?
    public var isClean: Bool?
    public var ahead: Int?
    public var behind: Int?
    public var classification: LifecycleClassification
    public var state: LifecycleState
    public var reason: String
    public var recommendation: LifecycleRecommendedAction
    public var allowedActions: [LifecycleSafeAction]
    public var blockedActions: [LifecycleBlockedAction]

    public init(
        id: String,
        kind: LifecycleItemKind,
        label: String,
        path: String? = nil,
        branch: String? = nil,
        head: String? = nil,
        isClean: Bool? = nil,
        ahead: Int? = nil,
        behind: Int? = nil,
        classification: LifecycleClassification,
        state: LifecycleState,
        reason: String,
        recommendation: LifecycleRecommendedAction,
        allowedActions: [LifecycleSafeAction],
        blockedActions: [LifecycleBlockedAction] = []
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.path = path
        self.branch = branch
        self.head = head
        self.isClean = isClean
        self.ahead = ahead
        self.behind = behind
        self.classification = classification
        self.state = state
        self.reason = reason
        self.recommendation = recommendation
        self.allowedActions = allowedActions
        self.blockedActions = blockedActions
    }
}

public enum LifecycleGateLevel: String, CaseIterable, Codable, Identifiable {
    case green
    case yellow
    case red

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .green: "Safe to start"
        case .yellow: "Warnings require confirmation"
        case .red: "Blocked until fixed"
        }
    }
}

public struct LifecycleGateCheck: Equatable, Codable, Identifiable {
    public var id: String
    public var label: String
    public var level: LifecycleGateLevel
    public var message: String

    public init(id: String, label: String, level: LifecycleGateLevel, message: String) {
        self.id = id
        self.label = label
        self.level = level
        self.message = message
    }
}

public struct LifecyclePreflightGate: Equatable, Codable {
    public var level: LifecycleGateLevel
    public var checks: [LifecycleGateCheck]

    public init(level: LifecycleGateLevel, checks: [LifecycleGateCheck]) {
        self.level = level
        self.checks = checks
    }
}

public enum ArtifactWasteClassification: String, CaseIterable, Codable, Identifiable {
    case active
    case recent
    case old
    case orphaned
    case safeToArchive = "safe_to_archive"
    case safeToDelete = "safe_to_delete"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .active: "Active"
        case .recent: "Recent"
        case .old: "Old"
        case .orphaned: "Orphaned"
        case .safeToArchive: "Safe To Archive"
        case .safeToDelete: "Safe To Delete"
        }
    }
}

public struct ArtifactWasteItem: Equatable, Codable, Identifiable {
    public var id: String
    public var projectId: String
    public var taskId: String?
    public var runId: String?
    public var path: String
    public var ageDays: Int?
    public var sizeBytes: Int64?
    public var isLinkedToActiveTaskOrRun: Bool
    public var classification: ArtifactWasteClassification
    public var recommendation: LifecycleRecommendedAction

    public init(
        id: String,
        projectId: String,
        taskId: String?,
        runId: String?,
        path: String,
        ageDays: Int?,
        sizeBytes: Int64?,
        isLinkedToActiveTaskOrRun: Bool,
        classification: ArtifactWasteClassification,
        recommendation: LifecycleRecommendedAction
    ) {
        self.id = id
        self.projectId = projectId
        self.taskId = taskId
        self.runId = runId
        self.path = path
        self.ageDays = ageDays
        self.sizeBytes = sizeBytes
        self.isLinkedToActiveTaskOrRun = isLinkedToActiveTaskOrRun
        self.classification = classification
        self.recommendation = recommendation
    }
}

public struct RunnerGitEnvironment: Equatable, Codable {
    public var gitDir: String?
    public var gitWorkTree: String?
    public var gitCommonDir: String?
    public var gitPrefix: String?

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.gitDir = Self.normalized(environment["GIT_DIR"])
        self.gitWorkTree = Self.normalized(environment["GIT_WORK_TREE"])
        self.gitCommonDir = Self.normalized(environment["GIT_COMMON_DIR"])
        self.gitPrefix = Self.normalized(environment["GIT_PREFIX"])
    }

    public var hasGitOverrides: Bool {
        gitDir != nil || gitWorkTree != nil || gitCommonDir != nil || gitPrefix != nil
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct GitWorktreeRecord: Equatable, Codable, Identifiable {
    public var id: String { path }
    public var path: String
    public var head: String?
    public var branch: String?
    public var isClean: Bool?
    public var isPrunable: Bool

    public init(path: String, head: String? = nil, branch: String? = nil, isClean: Bool? = nil, isPrunable: Bool = false) {
        self.path = path
        self.head = head
        self.branch = branch
        self.isClean = isClean
        self.isPrunable = isPrunable
    }
}

public struct GitBranchRecord: Equatable, Codable, Identifiable {
    public var id: String { name }
    public var name: String
    public var head: String?
    public var aheadOfOrigin: Int?
    public var behindOrigin: Int?
    public var aheadOfDefault: Int?
    public var behindDefault: Int?
    public var isMergedToDefault: Bool
    public var isDuplicateEquivalent: Bool
    public var hasUniqueCommits: Bool
    public var isBackupProtected: Bool
    public var isActiveFactoryBranch: Bool
    public var fastForwardPossible: Bool?

    public init(
        name: String,
        head: String? = nil,
        aheadOfOrigin: Int? = nil,
        behindOrigin: Int? = nil,
        aheadOfDefault: Int? = nil,
        behindDefault: Int? = nil,
        isMergedToDefault: Bool = false,
        isDuplicateEquivalent: Bool = false,
        hasUniqueCommits: Bool = false,
        isBackupProtected: Bool = false,
        isActiveFactoryBranch: Bool = false,
        fastForwardPossible: Bool? = nil
    ) {
        self.name = name
        self.head = head
        self.aheadOfOrigin = aheadOfOrigin
        self.behindOrigin = behindOrigin
        self.aheadOfDefault = aheadOfDefault
        self.behindDefault = behindDefault
        self.isMergedToDefault = isMergedToDefault
        self.isDuplicateEquivalent = isDuplicateEquivalent
        self.hasUniqueCommits = hasUniqueCommits
        self.isBackupProtected = isBackupProtected
        self.isActiveFactoryBranch = isActiveFactoryBranch
        self.fastForwardPossible = fastForwardPossible
    }
}

public enum MergeSafetyResult: String, CaseIterable, Codable, Identifiable {
    case duplicateEquivalent = "duplicate_equivalent"
    case fastForwardPossible = "fast_forward_possible"
    case manualReviewRequired = "manual_review_required"

    public var id: String { rawValue }
}

public enum MergeSafetyHelper {
    public static func assess(cherryPickLog: String, diffStat: String, defaultIsAncestorOfBranch: Bool?) -> MergeSafetyResult {
        let hasUniquePatch = !cherryPickLog.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !diffStat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasUniquePatch {
            return .duplicateEquivalent
        }
        if defaultIsAncestorOfBranch == true {
            return .fastForwardPossible
        }
        return .manualReviewRequired
    }
}

public struct RepoHygieneReport: Equatable, Codable {
    public var projectId: String
    public var projectName: String
    public var canonicalRepoPath: String
    public var currentBranch: String?
    public var currentHEAD: String?
    public var defaultBranch: String
    public var originDefaultBranch: String?
    public var workingTreeClean: Bool?
    public var defaultAheadOfOrigin: Int?
    public var defaultBehindOrigin: Int?
    public var localBranches: [GitBranchRecord]
    public var gitWorktrees: [GitWorktreeRecord]
    public var staleWorktreeMetadata: [String]
    public var runnerEnvironment: RunnerGitEnvironment
    public var lifecycleItems: [LifecycleItem]
    public var preflightGate: LifecyclePreflightGate
    public var artifactWasteItems: [ArtifactWasteItem]
    public var hygieneEvents: [String]
    public var generatedAt: Date

    public init(
        projectId: String,
        projectName: String,
        canonicalRepoPath: String,
        currentBranch: String?,
        currentHEAD: String?,
        defaultBranch: String,
        originDefaultBranch: String?,
        workingTreeClean: Bool?,
        defaultAheadOfOrigin: Int?,
        defaultBehindOrigin: Int?,
        localBranches: [GitBranchRecord],
        gitWorktrees: [GitWorktreeRecord],
        staleWorktreeMetadata: [String],
        runnerEnvironment: RunnerGitEnvironment,
        lifecycleItems: [LifecycleItem],
        preflightGate: LifecyclePreflightGate,
        artifactWasteItems: [ArtifactWasteItem],
        hygieneEvents: [String],
        generatedAt: Date = Date()
    ) {
        self.projectId = projectId
        self.projectName = projectName
        self.canonicalRepoPath = canonicalRepoPath
        self.currentBranch = currentBranch
        self.currentHEAD = currentHEAD
        self.defaultBranch = defaultBranch
        self.originDefaultBranch = originDefaultBranch
        self.workingTreeClean = workingTreeClean
        self.defaultAheadOfOrigin = defaultAheadOfOrigin
        self.defaultBehindOrigin = defaultBehindOrigin
        self.localBranches = localBranches
        self.gitWorktrees = gitWorktrees
        self.staleWorktreeMetadata = staleWorktreeMetadata
        self.runnerEnvironment = runnerEnvironment
        self.lifecycleItems = lifecycleItems
        self.preflightGate = preflightGate
        self.artifactWasteItems = artifactWasteItems
        self.hygieneEvents = hygieneEvents
        self.generatedAt = generatedAt
    }

    public var dirtyWorktrees: [GitWorktreeRecord] {
        gitWorktrees.filter { $0.isClean == false }
    }

    public var mergedBranches: [GitBranchRecord] {
        localBranches.filter(\.isMergedToDefault)
    }

    public var branchesWithNoDiffVsDefault: [GitBranchRecord] {
        localBranches.filter(\.isDuplicateEquivalent)
    }

    public var branchesWithUniqueCommits: [GitBranchRecord] {
        localBranches.filter(\.hasUniqueCommits)
    }

    public var backupProtectedBranches: [GitBranchRecord] {
        localBranches.filter(\.isBackupProtected)
    }

    public var unpushedCommits: [GitBranchRecord] {
        localBranches.filter { ($0.aheadOfOrigin ?? 0) > 0 }
    }

    public var activeFactoryCodexBranches: [GitBranchRecord] {
        localBranches.filter(\.isActiveFactoryBranch)
    }
}

public enum LifecycleParser {
    public static func parseWorktreePorcelain(_ output: String, prunablePaths: Set<String> = []) -> [GitWorktreeRecord] {
        var records: [GitWorktreeRecord] = []
        var currentPath: String?
        var currentHead: String?
        var currentBranch: String?

        func flush() {
            guard let currentPath else { return }
            records.append(GitWorktreeRecord(
                path: currentPath,
                head: currentHead,
                branch: currentBranch,
                isPrunable: prunablePaths.contains(currentPath)
            ))
        }

        for line in output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("worktree ") {
                flush()
                currentPath = String(line.dropFirst("worktree ".count))
                currentHead = nil
                currentBranch = nil
            } else if line.hasPrefix("HEAD ") {
                currentHead = String(line.dropFirst("HEAD ".count))
            } else if line.hasPrefix("branch ") {
                let ref = String(line.dropFirst("branch ".count))
                currentBranch = ref.replacingOccurrences(of: "refs/heads/", with: "")
            }
        }
        flush()
        return records
    }

    public static func parseBranchFormat(_ output: String) -> [GitBranchRecord] {
        output
            .split(separator: "\n")
            .compactMap { line -> GitBranchRecord? in
                let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
                guard let name = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                    return nil
                }
                let head = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : nil
                return GitBranchRecord(name: name, head: head?.isEmpty == true ? nil : head)
            }
    }

    public static func parseMergedBranches(_ output: String) -> Set<String> {
        Set(output.split(separator: "\n").map { line in
            line.replacingOccurrences(of: "*", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })
    }

    public static func parsePrunableWorktreePaths(_ output: String) -> Set<String> {
        Set(output.split(separator: "\n").compactMap { line in
            let value = String(line)
            guard value.hasPrefix("Removing worktrees/") || value.hasPrefix("Removing ") else { return nil }
            guard let quoteStart = value.firstIndex(of: "'"), let quoteEnd = value.lastIndex(of: "'"), quoteStart != quoteEnd else {
                return nil
            }
            return String(value[value.index(after: quoteStart)..<quoteEnd])
        })
    }
}

public enum LifecycleClassifier {
    public static func classifyBranch(
        _ branch: GitBranchRecord,
        defaultBranch: String,
        checkedOutBranches: Set<String>
    ) -> LifecycleItem {
        if branch.name == defaultBranch {
            if (branch.aheadOfOrigin ?? 0) > 0 {
                return LifecycleItem(
                    id: "branch-\(branch.name)",
                    kind: .branch,
                    label: branch.name,
                    branch: branch.name,
                    head: branch.head,
                    ahead: branch.aheadOfOrigin,
                    behind: branch.behindOrigin,
                    classification: .unpushedRisk,
                    state: .blocked,
                    reason: "Default branch has local commits not known to be on origin.",
                    recommendation: .pushMain,
                    allowedActions: [.refreshScan],
                    blockedActions: destructiveBranchBlocks(uniqueCommits: true)
                )
            }
            return LifecycleItem(
                id: "branch-\(branch.name)",
                kind: .branch,
                label: branch.name,
                branch: branch.name,
                head: branch.head,
                ahead: branch.aheadOfOrigin,
                behind: branch.behindOrigin,
                classification: .healthy,
                state: .verifiedOnMain,
                reason: "Default branch is the canonical integration branch.",
                recommendation: .continueWork,
                allowedActions: [.refreshScan]
            )
        }

        if branch.isBackupProtected {
            return LifecycleItem(
                id: "branch-\(branch.name)",
                kind: .branch,
                label: branch.name,
                branch: branch.name,
                head: branch.head,
                ahead: branch.aheadOfOrigin,
                behind: branch.behindOrigin,
                classification: .backupProtected,
                state: .backupProtected,
                reason: "Branch name looks like a backup, rescue, or snapshot branch.",
                recommendation: .manualReviewRequired,
                allowedActions: [.keepProtectBackupBranch, .inspectDiff],
                blockedActions: [LifecycleBlockedAction(action: .deleteMergedBranch, reason: "Backup branches are protected by default.")]
            )
        }

        if (branch.aheadOfOrigin ?? 0) > 0 {
            return LifecycleItem(
                id: "branch-\(branch.name)",
                kind: .branch,
                label: branch.name,
                branch: branch.name,
                head: branch.head,
                ahead: branch.aheadOfOrigin,
                behind: branch.behindOrigin,
                classification: .unpushedRisk,
                state: .blocked,
                reason: "Branch has commits not known to be on its origin tracking branch.",
                recommendation: .createBackup,
                allowedActions: [.inspectDiff],
                blockedActions: destructiveBranchBlocks(uniqueCommits: true)
            )
        }

        if branch.isDuplicateEquivalent {
            return LifecycleItem(
                id: "branch-\(branch.name)",
                kind: .branch,
                label: branch.name,
                branch: branch.name,
                head: branch.head,
                ahead: branch.aheadOfOrigin,
                behind: branch.behindOrigin,
                classification: .duplicateEquivalent,
                state: .duplicateEquivalent,
                reason: "Branch has no unique patch compared with \(defaultBranch).",
                recommendation: .deleteDuplicateBranch,
                allowedActions: [.inspectDiff, .deleteDuplicateBranch],
                blockedActions: [LifecycleBlockedAction(action: .fastForwardMergeToMain, reason: "No unique patch exists to merge.")]
            )
        }

        if branch.isMergedToDefault {
            return LifecycleItem(
                id: "branch-\(branch.name)",
                kind: .branch,
                label: branch.name,
                branch: branch.name,
                head: branch.head,
                ahead: branch.aheadOfOrigin,
                behind: branch.behindOrigin,
                classification: .alreadyMerged,
                state: .merged,
                reason: "Branch tip is already reachable from \(defaultBranch).",
                recommendation: .removeCleanWorktree,
                allowedActions: [.inspectDiff, .deleteMergedBranch]
            )
        }

        if let behindDefault = branch.behindDefault, behindDefault > 0 {
            let aheadDefault = branch.aheadOfDefault ?? 0
            if aheadDefault == 0 {
                return LifecycleItem(
                    id: "branch-\(branch.name)",
                    kind: .branch,
                    label: branch.name,
                    branch: branch.name,
                    head: branch.head,
                    ahead: aheadDefault,
                    behind: behindDefault,
                    classification: .outdated,
                    state: .outdated,
                    reason: "Branch is \(behindDefault) commit(s) behind \(defaultBranch) with no unique task commits. Refresh from Main is safe.",
                    recommendation: .refreshFromMain,
                    allowedActions: [.inspectDiff, .refreshFromMain]
                )
            }

            return LifecycleItem(
                id: "branch-\(branch.name)",
                kind: .branch,
                label: branch.name,
                branch: branch.name,
                head: branch.head,
                ahead: aheadDefault,
                behind: behindDefault,
                classification: .outdated,
                state: .outdated,
                reason: "Branch is \(aheadDefault) commit(s) ahead and \(behindDefault) behind \(defaultBranch). Rebase onto Main is required before continuing.",
                recommendation: .rebaseOntoMain,
                allowedActions: [.inspectDiff, .rebaseOntoMain],
                blockedActions: [LifecycleBlockedAction(action: .deleteDuplicateBranch, reason: "Branch has unique commits.")]
            )
        }

        if branch.hasUniqueCommits {
            let checkedOut = checkedOutBranches.contains(branch.name)
            let fastForwardBlocked = branch.fastForwardPossible == false
            return LifecycleItem(
                id: "branch-\(branch.name)",
                kind: .branch,
                label: branch.name,
                branch: branch.name,
                head: branch.head,
                ahead: branch.aheadOfOrigin,
                behind: branch.behindOrigin,
                classification: fastForwardBlocked ? .unknownRisk : (checkedOut ? .active : .readyToMerge),
                state: fastForwardBlocked ? .conflictRisk : (checkedOut ? .running : .mergeReady),
                reason: fastForwardBlocked ? "Branch has unique changes but cannot fast-forward \(defaultBranch)." : (checkedOut ? "Branch is checked out in a worktree and has unique work." : "Branch has unique commits that need review before merge."),
                recommendation: fastForwardBlocked ? .manualReviewRequired : (checkedOut ? .continueWork : .reviewDiff),
                allowedActions: [.inspectDiff],
                blockedActions: [LifecycleBlockedAction(action: .deleteDuplicateBranch, reason: "Branch has unique commits.")]
            )
        }

        return LifecycleItem(
            id: "branch-\(branch.name)",
            kind: .branch,
            label: branch.name,
            branch: branch.name,
            head: branch.head,
            classification: branch.isActiveFactoryBranch ? .active : .unknownRisk,
            state: branch.isActiveFactoryBranch ? .created : .unknown,
            reason: branch.isActiveFactoryBranch ? "Factory/Codex branch exists but lifecycle state is not fully known." : "Branch does not match a known safe cleanup state.",
            recommendation: .manualReviewRequired,
            allowedActions: [.inspectDiff],
            blockedActions: destructiveBranchBlocks(uniqueCommits: true)
        )
    }

    public static func classifyWorktree(_ worktree: GitWorktreeRecord, defaultBranch: String) -> LifecycleItem {
        if worktree.isPrunable {
            return LifecycleItem(
                id: "worktree-\(worktree.path)",
                kind: .worktree,
                label: worktree.branch ?? worktree.path,
                path: worktree.path,
                branch: worktree.branch,
                head: worktree.head,
                isClean: worktree.isClean,
                classification: .orphanedMetadata,
                state: .unknown,
                reason: "Git reports stale worktree metadata for this path.",
                recommendation: .manualReviewRequired,
                allowedActions: [.refreshScan],
                blockedActions: [LifecycleBlockedAction(action: .pruneWorktreeMetadata, reason: "Prune is foundation-only until confirmation wiring is complete.")]
            )
        }
        if worktree.isClean == false {
            return LifecycleItem(
                id: "worktree-\(worktree.path)",
                kind: .worktree,
                label: worktree.branch ?? worktree.path,
                path: worktree.path,
                branch: worktree.branch,
                head: worktree.head,
                isClean: worktree.isClean,
                classification: .dirtyRisk,
                state: .dirtyRisk,
                reason: "Worktree has staged, unstaged, or untracked changes.",
                recommendation: .reviewDiff,
                allowedActions: [.inspectDiff, .stashWorktreeChanges, .createWIPBackupCommit],
                blockedActions: [LifecycleBlockedAction(action: .removeCleanWorktree, reason: "Factory never deletes dirty worktrees.")]
            )
        }
        if worktree.branch == defaultBranch {
            return LifecycleItem(
                id: "worktree-\(worktree.path)",
                kind: .worktree,
                label: worktree.branch ?? worktree.path,
                path: worktree.path,
                branch: worktree.branch,
                head: worktree.head,
                isClean: worktree.isClean,
                classification: .unknownRisk,
                state: .blocked,
                reason: "Default branch is checked out in a worktree; verify this is the canonical repo.",
                recommendation: .manualReviewRequired,
                allowedActions: [.refreshScan, .inspectDiff]
            )
        }
        return LifecycleItem(
            id: "worktree-\(worktree.path)",
            kind: .worktree,
            label: worktree.branch ?? worktree.path,
            path: worktree.path,
            branch: worktree.branch,
            head: worktree.head,
            isClean: worktree.isClean,
            classification: .healthy,
            state: .worktreeCreated,
            reason: "Worktree is present and clean.",
            recommendation: .continueWork,
            allowedActions: [.refreshScan, .inspectDiff, .removeCleanWorktree]
        )
    }

    public static func classifyStoredTaskWorktreeReference(task: FactoryTask, display: TaskWorktreeDisplay) -> LifecycleItem {
        let classification: LifecycleClassification
        let state: LifecycleState
        let reason: String
        let recommendation: LifecycleRecommendedAction
        let allowedActions: [LifecycleSafeAction]
        let blockedActions: [LifecycleBlockedAction]

        switch display.state {
        case .healthy:
            classification = .healthy
            state = .worktreeCreated
            reason = "Stored task worktree reference points to an existing directory."
            recommendation = .continueWork
            allowedActions = [.refreshScan, .inspectDiff]
            blockedActions = []
        case .missingPath:
            classification = .missingPath
            state = .blocked
            reason = "This task references a worktree path that no longer exists."
            recommendation = .manualReviewRequired
            allowedActions = [.refreshScan]
            blockedActions = [
                LifecycleBlockedAction(action: .inspectDiff, reason: "Missing worktree paths cannot be opened or diffed."),
                LifecycleBlockedAction(action: .removeCleanWorktree, reason: "The worktree directory is already missing; repair task metadata instead.")
            ]
        case .removedCleaned:
            classification = .removedCleaned
            state = .cleaned
            reason = "The stored path has been cleared while the task branch reference remains."
            recommendation = .manualReviewRequired
            allowedActions = [.refreshScan]
            blockedActions = [LifecycleBlockedAction(action: .inspectDiff, reason: "No worktree path is linked.")]
        case .dirtyRisk:
            classification = .dirtyRisk
            state = .dirtyRisk
            reason = "Stored task worktree reference is marked dirty or risky."
            recommendation = .reviewDiff
            allowedActions = [.refreshScan, .inspectDiff]
            blockedActions = [LifecycleBlockedAction(action: .removeCleanWorktree, reason: "Factory never removes dirty worktrees.")]
        case .unknown:
            classification = .unknownRisk
            state = .unknown
            reason = "Stored task worktree reference cannot be classified."
            recommendation = .manualReviewRequired
            allowedActions = [.refreshScan]
            blockedActions = [LifecycleBlockedAction(action: .inspectDiff, reason: "Unknown worktree state requires review first.")]
        }

        return LifecycleItem(
            id: "task-worktree-\(task.id)-\(display.id)",
            kind: .worktree,
            label: "\(task.title): \(display.label)",
            path: display.path,
            branch: display.branch,
            isClean: display.state == .healthy ? true : nil,
            classification: classification,
            state: state,
            reason: reason,
            recommendation: recommendation,
            allowedActions: allowedActions,
            blockedActions: blockedActions
        )
    }

    public static func gate(
        project: Project,
        selectedTask: FactoryTask?,
        currentBranch: String?,
        workingTreeClean: Bool?,
        defaultAheadOfOrigin: Int?,
        worktrees: [GitWorktreeRecord],
        branches: [GitBranchRecord],
        staleMetadata: [String],
        runnerEnvironment: RunnerGitEnvironment
    ) -> LifecyclePreflightGate {
        var checks: [LifecycleGateCheck] = []

        if workingTreeClean == false {
            checks.append(LifecycleGateCheck(id: "canonical-dirty", label: "Canonical repo", level: .red, message: "Canonical repo has uncommitted changes."))
        }
        if (defaultAheadOfOrigin ?? 0) > 0 {
            checks.append(LifecycleGateCheck(id: "default-unpushed", label: "Default branch", level: .red, message: "\(project.defaultBranch) has local commits not known to be on origin."))
        }
        if let currentBranch, currentBranch != project.defaultBranch {
            checks.append(LifecycleGateCheck(id: "canonical-branch", label: "Canonical branch", level: .red, message: "Canonical repo is on \(currentBranch), expected \(project.defaultBranch)."))
        }
        let unexpectedDefaultWorktrees = worktrees.filter {
            $0.branch == project.defaultBranch && URL(fileURLWithPath: $0.path).standardizedFileURL.path != URL(fileURLWithPath: project.path).standardizedFileURL.path
        }
        if !unexpectedDefaultWorktrees.isEmpty {
            checks.append(LifecycleGateCheck(id: "default-worktree", label: "Default checkout", level: .red, message: "\(project.defaultBranch) is checked out outside the canonical repo."))
        }
        if worktrees.contains(where: { $0.isClean == false }) {
            checks.append(LifecycleGateCheck(id: "dirty-worktrees", label: "Dirty worktrees", level: .yellow, message: "One or more worktrees have uncommitted changes."))
        }
        let duplicateKeys = duplicateActiveBranchKeys(branches)
        if !duplicateKeys.isEmpty {
            checks.append(LifecycleGateCheck(id: "duplicate-active-branches", label: "Duplicate branches", level: .yellow, message: "Multiple active Factory/Codex branches look equivalent: \(duplicateKeys.sorted().joined(separator: ", "))."))
        }
        if let selectedTask {
            let hasExistingTaskWorkspace = [
                selectedTask.localBranch,
                selectedTask.codexBranch,
                selectedTask.localWorktreePath,
                selectedTask.codexWorktreePath
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains { !$0.isEmpty }

            let expectedBranches = [
                WorktreeFlavor.local.branchPrefix + "/" + selectedTask.id.shortID + "-" + Slug.make(selectedTask.title, maxLength: 36),
                WorktreeFlavor.codex.branchPrefix + "/" + selectedTask.id.shortID + "-" + Slug.make(selectedTask.title, maxLength: 36)
            ]
            if !hasExistingTaskWorkspace {
                let branchNames = Set(branches.map(\.name))
                if let existing = expectedBranches.first(where: { branchNames.contains($0) }) {
                    checks.append(LifecycleGateCheck(id: "target-branch-exists", label: "Target branch", level: .red, message: "\(existing) already exists."))
                }
                let checkedOutBranches = Set(worktrees.compactMap(\.branch))
                if let checkedOut = expectedBranches.first(where: { checkedOutBranches.contains($0) }) {
                    checks.append(LifecycleGateCheck(id: "target-branch-checked-out", label: "Target branch", level: .red, message: "\(checkedOut) is checked out elsewhere."))
                }
            }
        }
        if !staleMetadata.isEmpty {
            checks.append(LifecycleGateCheck(id: "stale-metadata", label: "Worktree metadata", level: .red, message: "Git reports stale worktree metadata."))
        }
        if runnerEnvironment.hasGitOverrides {
            checks.append(LifecycleGateCheck(id: "runner-git-env", label: "Runner environment", level: .red, message: "GIT_DIR, GIT_WORK_TREE, GIT_COMMON_DIR, or GIT_PREFIX is set."))
        }
        if checks.isEmpty {
            checks.append(LifecycleGateCheck(id: "safe", label: "Preflight", level: .green, message: "No blocking hygiene issues detected."))
        }

        let level: LifecycleGateLevel = checks.contains(where: { $0.level == .red }) ? .red : (checks.contains(where: { $0.level == .yellow }) ? .yellow : .green)
        return LifecyclePreflightGate(level: level, checks: checks)
    }

    public static func artifactWasteItems(project: Project, tasks: [FactoryTask], runs: [RunRecord], artifacts: [Artifact], now: Date = Date()) -> [ArtifactWasteItem] {
        let activeTaskIds = Set(tasks.filter { ![TaskStatus.done, .archived].contains($0.status) }.map(\.id))
        let activeRunIds = Set(runs.filter { $0.status == .running || $0.status == .queued }.map(\.id))

        return artifacts.sorted(by: { $0.createdAt > $1.createdAt }).map { artifact in
            let ageDays = Calendar.current.dateComponents([.day], from: artifact.createdAt, to: now).day
            let size = fileSize(path: artifact.path)
            let linked = activeTaskIds.contains(artifact.taskId) || artifact.runId.map { activeRunIds.contains($0) } == true
            let classification: ArtifactWasteClassification
            if linked {
                classification = .active
            } else if FileManager.default.fileExists(atPath: artifact.path) == false {
                classification = .orphaned
            } else if (ageDays ?? 0) >= 30 {
                classification = .safeToArchive
            } else if (ageDays ?? 0) >= 7 {
                classification = .old
            } else {
                classification = .recent
            }
            return ArtifactWasteItem(
                id: artifact.id,
                projectId: project.id,
                taskId: artifact.taskId,
                runId: artifact.runId,
                path: artifact.path,
                ageDays: ageDays,
                sizeBytes: size,
                isLinkedToActiveTaskOrRun: linked,
                classification: classification,
                recommendation: classification == .safeToArchive ? .archiveArtifacts : .continueWork
            )
        }
    }

    public static func hygieneEvents(from report: RepoHygieneReport) -> [String] {
        var events = [
            "Scan generated \(DateCoding.string(from: report.generatedAt)).",
            "Preflight gate: \(report.preflightGate.level.displayName)."
        ]
        if !report.dirtyWorktrees.isEmpty {
            events.append("\(report.dirtyWorktrees.count) dirty worktree(s) found.")
        }
        if !report.branchesWithNoDiffVsDefault.isEmpty {
            events.append("\(report.branchesWithNoDiffVsDefault.count) duplicate equivalent branch(es) found.")
        }
        if !report.staleWorktreeMetadata.isEmpty {
            events.append("\(report.staleWorktreeMetadata.count) stale worktree metadata item(s) found.")
        }
        return events
    }

    private static func destructiveBranchBlocks(uniqueCommits: Bool) -> [LifecycleBlockedAction] {
        uniqueCommits ? [
            LifecycleBlockedAction(action: .deleteMergedBranch, reason: "Branch has unique or unknown commits."),
            LifecycleBlockedAction(action: .deleteDuplicateBranch, reason: "Branch has unique or unknown commits.")
        ] : []
    }

    private static func duplicateActiveBranchKeys(_ branches: [GitBranchRecord]) -> Set<String> {
        let keys = branches.filter(\.isActiveFactoryBranch).map { semanticBranchKey($0.name) }
        let grouped = Dictionary(grouping: keys, by: { $0 })
        return Set(grouped.filter { !$0.key.isEmpty && $0.value.count > 1 }.map(\.key))
    }

    private static func semanticBranchKey(_ branch: String) -> String {
        let stripped = branch
            .replacingOccurrences(of: "local/", with: "")
            .replacingOccurrences(of: "codex/", with: "")
            .replacingOccurrences(of: "factory/", with: "")
        let parts = stripped.split(separator: "-", maxSplits: 1).map(String.init)
        return parts.count == 2 ? parts[1] : stripped
    }

    private static func fileSize(path: String) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }
        return size.int64Value
    }
}
