import Foundation

public enum AppUpdateAvailability: Equatable {
    case checking
    case upToDate
    case available
    case applying
}

public struct AppUpdateStatus: Equatable {
    public var availability: AppUpdateAvailability
    public var message: String
    public var detectedBuildInfo: BuildInfo?
    public var lastCheckedAt: Date?

    public init(
        availability: AppUpdateAvailability = .checking,
        message: String = "Checking Factory Desktop updates...",
        detectedBuildInfo: BuildInfo? = nil,
        lastCheckedAt: Date? = nil
    ) {
        self.availability = availability
        self.message = message
        self.detectedBuildInfo = detectedBuildInfo
        self.lastCheckedAt = lastCheckedAt
    }

    public var isUpdateAvailable: Bool {
        availability == .available
    }

    public var isApplying: Bool {
        availability == .applying
    }
}

public enum AppUpdateService {
    public static func evaluate(launched: BuildInfo, current: BuildInfo, checkedAt: Date = Date()) -> AppUpdateStatus {
        guard launched.sourceSignature != BuildInfoService.unknownValue,
              current.sourceSignature != BuildInfoService.unknownValue else {
            return AppUpdateStatus(
                availability: .checking,
                message: "Update status unavailable for this launch.",
                detectedBuildInfo: current,
                lastCheckedAt: checkedAt
            )
        }

        guard launched.sourceSignature != current.sourceSignature else {
            return AppUpdateStatus(
                availability: .upToDate,
                message: "Factory Desktop is up to date.",
                detectedBuildInfo: current,
                lastCheckedAt: checkedAt
            )
        }

        let message: String
        if launched.shortSHA != current.shortSHA {
            message = "A newer checkout is available: \(launched.shortSHA) -> \(current.shortSHA)."
        } else {
            message = "Local Factory Desktop source changes are ready to rebuild."
        }

        return AppUpdateStatus(
            availability: .available,
            message: message,
            detectedBuildInfo: current,
            lastCheckedAt: checkedAt
        )
    }

    public static func relaunchCurrentApplication() throws {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-n", bundleURL.path]
            try process.run()
            return
        }

        guard let executableURL = Bundle.main.executableURL ?? ProcessInfo.processInfo.arguments.first.map({ URL(fileURLWithPath: $0) }) else {
            throw FactoryError.commandFailed("relaunch-current-application")
        }

        let process = Process()
        process.executableURL = executableURL
        process.currentDirectoryURL = SelfRepoLocator.sourceRoot
        try process.run()
    }
}
