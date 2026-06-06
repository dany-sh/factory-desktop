import Foundation

public struct PreflightReport: Equatable, Codable {
    public var projectName: String
    public var projectPath: String
    public var defaultBranch: String
    public var generatedAt: Date
    public var targets: [PreflightTargetReport]

    public init(
        projectName: String,
        projectPath: String,
        defaultBranch: String,
        generatedAt: Date = Date(),
        targets: [PreflightTargetReport]
    ) {
        self.projectName = projectName
        self.projectPath = projectPath
        self.defaultBranch = defaultBranch
        self.generatedAt = generatedAt
        self.targets = targets
    }

    public var dirtyTargetCount: Int {
        targets.filter { !$0.isClean }.count
    }

    public var missingPathCount: Int {
        targets.filter { !$0.pathExists }.count
    }

    public var unpushedCount: Int {
        targets.filter { ($0.aheadOfRemote ?? 0) > 0 }.count
    }

    public var overallRecommendation: PreflightRecommendedAction {
        if targets.contains(where: { $0.recommendation == .investigate }) { return .investigate }
        if targets.contains(where: { $0.recommendation == .fixMissingPath }) { return .fixMissingPath }
        if targets.contains(where: { $0.recommendation == .inspectDiff }) { return .inspectDiff }
        if targets.contains(where: { $0.recommendation == .commit }) { return .commit }
        if targets.contains(where: { $0.recommendation == .push }) { return .push }
        if targets.contains(where: { $0.recommendation == .merge }) { return .merge }
        if targets.contains(where: { $0.recommendation == .archive }) { return .archive }
        return .none
    }

    public var markdown: String {
        let summary = """
        # Preflight Check: \(projectName)

        Generated at: \(DateCoding.string(from: generatedAt))
        Project path: \(projectPath)
        Default branch: \(defaultBranch)
        Overall recommendation: \(overallRecommendation.displayName)

        ## Summary
        - Targets checked: \(targets.count)
        - Dirty targets: \(dirtyTargetCount)
        - Missing paths: \(missingPathCount)
        - Unpushed default branch targets: \(unpushedCount)

        ## Targets
        """
        let targetMarkdown = targets.map(\.markdown).joined(separator: "\n\n")
        return "\(summary)\n\(targetMarkdown)\n"
    }
}

public struct PreflightTargetReport: Identifiable, Equatable, Codable {
    public var id: String { path }
    public var type: PreflightTargetType
    public var path: String
    public var pathExists: Bool
    public var branch: String?
    public var headSHA: String?
    public var isClean: Bool
    public var stagedCount: Int
    public var unstagedCount: Int
    public var untrackedCount: Int
    public var aheadOfRemote: Int?
    public var behindRemote: Int?
    public var remoteTrackingExists: Bool
    public var isMergedToDefault: Bool?
    public var risks: [PreflightRisk]
    public var recommendation: PreflightRecommendedAction
    public var statusOutput: String
    public var error: String?

    public init(
        type: PreflightTargetType,
        path: String,
        pathExists: Bool,
        branch: String? = nil,
        headSHA: String? = nil,
        isClean: Bool = false,
        stagedCount: Int = 0,
        unstagedCount: Int = 0,
        untrackedCount: Int = 0,
        aheadOfRemote: Int? = nil,
        behindRemote: Int? = nil,
        remoteTrackingExists: Bool = false,
        isMergedToDefault: Bool? = nil,
        risks: [PreflightRisk] = [],
        recommendation: PreflightRecommendedAction = .investigate,
        statusOutput: String = "",
        error: String? = nil
    ) {
        self.type = type
        self.path = path
        self.pathExists = pathExists
        self.branch = branch
        self.headSHA = headSHA
        self.isClean = isClean
        self.stagedCount = stagedCount
        self.unstagedCount = unstagedCount
        self.untrackedCount = untrackedCount
        self.aheadOfRemote = aheadOfRemote
        self.behindRemote = behindRemote
        self.remoteTrackingExists = remoteTrackingExists
        self.isMergedToDefault = isMergedToDefault
        self.risks = risks
        self.recommendation = recommendation
        self.statusOutput = statusOutput
        self.error = error
    }

    public var markdown: String {
        """
        ### \(type.displayName)
        - Path: \(path)
        - Exists: \(pathExists ? "yes" : "no")
        - Branch: \(branch ?? "unknown")
        - HEAD: \(headSHA ?? "unknown")
        - Clean: \(isClean ? "yes" : "no")
        - Staged / unstaged / untracked: \(stagedCount) / \(unstagedCount) / \(untrackedCount)
        - Remote tracking ref: \(remoteTrackingExists ? "yes" : "no")
        - Ahead / behind remote: \(aheadOfRemote.map(String.init) ?? "unknown") / \(behindRemote.map(String.init) ?? "unknown")
        - Merged to default: \(isMergedToDefault.map { $0 ? "yes" : "no" } ?? "unknown")
        - Risks: \(risks.isEmpty ? "none" : risks.map(\.displayName).joined(separator: ", "))
        - Recommendation: \(recommendation.displayName)
        \(error.map { "- Error: \($0)" } ?? "")
        """
    }
}

public enum PreflightTargetType: String, CaseIterable, Codable, Identifiable {
    case canonicalRepo
    case localWorktree
    case codexWorktree
    case factoryWorktree

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .canonicalRepo: "Canonical repo"
        case .localWorktree: "Task worktree"
        case .codexWorktree: "Alternate worktree"
        case .factoryWorktree: "Factory worktree"
        }
    }
}

public enum PreflightRisk: String, CaseIterable, Codable, Identifiable {
    case dirtyWorktree
    case missingPath
    case unexpectedBranchLocation
    case uncommittedChanges
    case unpushedDefaultBranchCommits
    case branchNotMerged
    case unknownGitState

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .dirtyWorktree: "dirty worktree"
        case .missingPath: "missing path"
        case .unexpectedBranchLocation: "unexpected branch location"
        case .uncommittedChanges: "uncommitted changes"
        case .unpushedDefaultBranchCommits: "unpushed default branch commits"
        case .branchNotMerged: "branch not merged"
        case .unknownGitState: "unknown git state"
        }
    }
}

public enum PreflightRecommendedAction: String, CaseIterable, Codable, Identifiable {
    case none
    case inspectDiff
    case commit
    case merge
    case push
    case archive
    case fixMissingPath
    case investigate

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: "no action needed"
        case .inspectDiff: "inspect diff"
        case .commit: "commit"
        case .merge: "merge"
        case .push: "push"
        case .archive: "archive"
        case .fixMissingPath: "fix missing path"
        case .investigate: "investigate"
        }
    }
}

public struct PreflightStatusSummary: Equatable {
    public var branch: String?
    public var ahead: Int?
    public var behind: Int?
    public var stagedCount: Int
    public var unstagedCount: Int
    public var untrackedCount: Int
    public var isClean: Bool

    public init(
        branch: String?,
        ahead: Int?,
        behind: Int?,
        stagedCount: Int,
        unstagedCount: Int,
        untrackedCount: Int,
        isClean: Bool
    ) {
        self.branch = branch
        self.ahead = ahead
        self.behind = behind
        self.stagedCount = stagedCount
        self.unstagedCount = unstagedCount
        self.untrackedCount = untrackedCount
        self.isClean = isClean
    }

    public static func parsePorcelainV1BranchStatus(_ output: String) -> PreflightStatusSummary {
        var branch: String?
        var ahead: Int?
        var behind: Int?
        var staged = 0
        var unstaged = 0
        var untracked = 0
        var hasTrackedChange = false

        for line in output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("## ") {
                let parsed = parseBranchLine(line)
                branch = parsed.branch
                ahead = parsed.ahead
                behind = parsed.behind
                continue
            }

            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if line.hasPrefix("??") {
                untracked += 1
                continue
            }

            let padded = line.padding(toLength: 2, withPad: " ", startingAt: 0)
            let first = padded[padded.startIndex]
            let second = padded[padded.index(after: padded.startIndex)]
            if first != " " {
                staged += 1
                hasTrackedChange = true
            }
            if second != " " {
                unstaged += 1
                hasTrackedChange = true
            }
        }

        return PreflightStatusSummary(
            branch: branch,
            ahead: ahead,
            behind: behind,
            stagedCount: staged,
            unstagedCount: unstaged,
            untrackedCount: untracked,
            isClean: !hasTrackedChange && untracked == 0
        )
    }

    public static func parseAheadBehindCounts(_ output: String) -> (ahead: Int, behind: Int)? {
        let parts = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count == 2, let left = Int(parts[0]), let right = Int(parts[1]) else {
            return nil
        }
        return (ahead: left, behind: right)
    }

    private static func parseBranchLine(_ line: String) -> (branch: String?, ahead: Int?, behind: Int?) {
        let value = String(line.dropFirst(3))
        let branchPart = value.split(separator: " ", maxSplits: 1).first.map(String.init) ?? value
        let branch = branchPart.split(separator: ".").first.map(String.init)
        let ahead = parseBracketValue("ahead", from: value)
        let behind = parseBracketValue("behind", from: value)
        return (branch: branch, ahead: ahead, behind: behind)
    }

    private static func parseBracketValue(_ label: String, from value: String) -> Int? {
        guard let range = value.range(of: "\(label) ") else { return nil }
        let suffix = value[range.upperBound...]
        let digits = suffix.prefix { $0.isNumber }
        return Int(digits)
    }
}

public enum PreflightRecommendationMapper {
    public static func recommendation(for risks: [PreflightRisk], targetType: PreflightTargetType, isMerged: Bool?) -> PreflightRecommendedAction {
        if risks.contains(.unknownGitState) { return .investigate }
        if risks.contains(.missingPath) { return .fixMissingPath }
        if risks.contains(.dirtyWorktree) { return .inspectDiff }
        if risks.contains(.uncommittedChanges) { return .commit }
        if risks.contains(.unpushedDefaultBranchCommits) { return .push }
        if risks.contains(.unexpectedBranchLocation) { return .investigate }
        if risks.contains(.branchNotMerged) { return .merge }
        if targetType != .canonicalRepo, isMerged == true { return .archive }
        return .none
    }
}
