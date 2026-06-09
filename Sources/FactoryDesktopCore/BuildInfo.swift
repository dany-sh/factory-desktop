import Foundation

public enum RepoState: String, Equatable, Codable {
    case clean
    case dirty
    case unknown

    public var displayName: String { rawValue }
}

public struct BuildInfo: Equatable, Codable {
    public var appVersion: String
    public var branch: String
    public var shortSHA: String
    public var repoState: RepoState
    public var sourceSignature: String
    public var repoPath: String
    public var launchTimestamp: Date

    public init(
        appVersion: String,
        branch: String,
        shortSHA: String,
        repoState: RepoState,
        sourceSignature: String,
        repoPath: String,
        launchTimestamp: Date
    ) {
        self.appVersion = appVersion
        self.branch = branch
        self.shortSHA = shortSHA
        self.repoState = repoState
        self.sourceSignature = sourceSignature
        self.repoPath = repoPath
        self.launchTimestamp = launchTimestamp
    }

    public var compactIdentity: String {
        "v\(appVersion) · \(compactBranch) · \(shortSHA) · \(repoState.displayName)"
    }

    public var compactBranch: String {
        Self.compactBranchName(branch)
    }

    public static func compactBranchName(_ branch: String) -> String {
        let parts = branch.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return branch }
        let idPart = parts[1].split(separator: "-", maxSplits: 1).first.map(String.init) ?? parts[1]
        return "\(parts[0])/\(idPart)"
    }

    public static func unknown(repoPath: String, launchTimestamp: Date = Date()) -> BuildInfo {
        BuildInfo(
            appVersion: BuildInfoService.defaultAppVersion,
            branch: BuildInfoService.unknownValue,
            shortSHA: BuildInfoService.unknownValue,
            repoState: .unknown,
            sourceSignature: BuildInfoService.unknownValue,
            repoPath: repoPath,
            launchTimestamp: launchTimestamp
        )
    }
}

public enum BuildInfoService {
    public static let defaultAppVersion = "0.1.0-dev"
    public static let unknownValue = "unknown"

    public static func current(
        sourceRoot: URL = SelfRepoLocator.sourceRoot,
        launchTimestamp: Date = Date()
    ) -> BuildInfo {
        let repoPath = sourceRoot.path
        let appVersion = Self.appVersion()

        guard let branch = gitOutput(["branch", "--show-current"], in: sourceRoot),
              let shortSHA = gitOutput(["rev-parse", "--short", "HEAD"], in: sourceRoot),
              let porcelain = gitOutput(["status", "--porcelain"], in: sourceRoot) else {
            return BuildInfo(
                appVersion: appVersion,
                branch: unknownValue,
                shortSHA: unknownValue,
                repoState: .unknown,
                sourceSignature: unknownValue,
                repoPath: repoPath,
                launchTimestamp: launchTimestamp
            )
        }

        let normalizedShortSHA = normalizedGitValue(shortSHA)
        return BuildInfo(
            appVersion: appVersion,
            branch: normalizedGitValue(branch),
            shortSHA: normalizedShortSHA,
            repoState: repoState(fromPorcelainOutput: porcelain),
            sourceSignature: sourceSignature(shortSHA: normalizedShortSHA, porcelainOutput: porcelain),
            repoPath: repoPath,
            launchTimestamp: launchTimestamp
        )
    }

    public static func repoState(fromPorcelainOutput output: String?) -> RepoState {
        guard let output else { return .unknown }
        return output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .clean : .dirty
    }

    public static func normalizedGitValue(_ output: String?) -> String {
        let value = output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? unknownValue : value
    }

    public static func sourceSignature(shortSHA: String, porcelainOutput: String?) -> String {
        let normalizedSHA = normalizedGitValue(shortSHA)
        let rawPorcelain = porcelainOutput ?? ""
        return "\(normalizedSHA):\(stableDigest(rawPorcelain))"
    }

    private static func appVersion(bundle: Bundle = .main) -> String {
        let keys = ["CFBundleShortVersionString", "CFBundleVersion"]
        for key in keys {
            if let version = bundle.object(forInfoDictionaryKey: key) as? String,
               !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return version
            }
        }
        return defaultAppVersion
    }

    private static func gitOutput(_ arguments: [String], in directory: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = directory

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private static func stableDigest(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}
