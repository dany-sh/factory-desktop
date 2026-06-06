import Foundation

public struct ArtifactDisplayGroups: Equatable {
    public var current: [Artifact]
    public var history: [Artifact]
    public var rawLogs: [Artifact]

    public init(current: [Artifact], history: [Artifact], rawLogs: [Artifact]) {
        self.current = current
        self.history = history
        self.rawLogs = rawLogs
    }
}

public enum ArtifactGrouping {
    public static func group(_ artifacts: [Artifact]) -> ArtifactDisplayGroups {
        let sorted = artifacts.sorted { $0.createdAt > $1.createdAt }
        let approvedPlan = firstExistingOrLatest(.approvedPlan, in: sorted)
        let currentTypes: Set<ArtifactType> = [
            .preflight,
            .taskStateReview,
            .testOutput,
            .localDiffReview,
            .finalReview,
            .implementationLog
        ]
        let rawTypes: Set<ArtifactType> = [
            .plannerPrompt,
            .codexPlanReviewHandoff,
            .codexDiffReviewHandoff
        ]

        var currentIDs: Set<String> = []
        var rawLogs: [Artifact] = []

        if let approvedPlan {
            currentIDs.insert(approvedPlan.id)
        } else if let plan = firstExistingOrLatest(.plan, in: sorted) {
            currentIDs.insert(plan.id)
        }

        for type in currentTypes {
            if let artifact = firstExistingOrLatest(type, in: sorted) {
                currentIDs.insert(artifact.id)
            }
        }

        for artifact in sorted where artifact.artifactType.map(rawTypes.contains) == true || isRawLogLike(artifact) {
            rawLogs.append(artifact)
        }

        let rawIDs = Set(rawLogs.map(\.id))
        let current = sorted.filter { currentIDs.contains($0.id) && !rawIDs.contains($0.id) }
        let history = sorted.filter { !currentIDs.contains($0.id) && !rawIDs.contains($0.id) }

        return ArtifactDisplayGroups(current: current, history: history, rawLogs: rawLogs)
    }

    private static func firstExistingOrLatest(_ type: ArtifactType, in artifacts: [Artifact]) -> Artifact? {
        let matches = artifacts.filter { $0.artifactType == type }
        return matches.first { FileManager.default.fileExists(atPath: $0.path) } ?? matches.first
    }

    private static func isRawLogLike(_ artifact: Artifact) -> Bool {
        let value = "\(artifact.path) \(artifact.description)".lowercased()
        return value.contains("prompt") || value.contains(".log") || value.contains("raw log")
    }
}

public extension Artifact {
    var artifactType: ArtifactType? {
        ArtifactType(rawValue: type)
    }
}
