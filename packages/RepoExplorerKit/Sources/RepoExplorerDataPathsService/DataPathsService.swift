import Foundation

public enum DataPathsError: Error, LocalizedError {
    case directoryCreationFailed(String, Error)
    case invalidPath(String)
    case invalidServiceName(String)

    public var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let path, let error):
            return "Failed to create directory at \(path): \(error.localizedDescription)"
        case .invalidPath(let path):
            return "Invalid data path: \(path)"
        case .invalidServiceName(let name):
            return "Invalid service name: \(name)"
        }
    }
}

/// Well-known service paths managed by DataPathsService.
public enum ServicePath {
    case appDatabase
    case bitriseArtifacts
    case bitriseBuilds
    case claudeUsageBilling
    case codeRefactorCache
    case codeRefactorCredentials
    case crashlyticsApps
    case crashlyticsCrashGroups
    case crashlyticsCrashes
    case crashlyticsEnrichment
    case crashlyticsStackTraces
    case crashlyticsVersions
    case gitBranchCache
    case mainThreadReports
    case mainThreadSymbolicated
    case refactorMagicJobs
    case teamCityArtifacts
    case worktrees

    var serviceName: String {
        switch self {
        case .appDatabase:
            return "app"
        case .bitriseArtifacts, .bitriseBuilds:
            return "bitrise"
        case .claudeUsageBilling:
            return "claude-usage"
        case .codeRefactorCache, .codeRefactorCredentials:
            return "code-refactor"
        case .crashlyticsApps, .crashlyticsCrashGroups, .crashlyticsCrashes, .crashlyticsEnrichment, .crashlyticsStackTraces, .crashlyticsVersions:
            return "crashlytics"
        case .gitBranchCache:
            return "git"
        case .mainThreadReports, .mainThreadSymbolicated:
            return "mainthread"
        case .refactorMagicJobs:
            return "refactor-magic"
        case .teamCityArtifacts:
            return "teamcity"
        case .worktrees:
            return "worktrees"
        }
    }

    var subdirectory: String {
        switch self {
        case .appDatabase:
            return "database"
        case .bitriseArtifacts, .teamCityArtifacts:
            return "artifacts"
        case .bitriseBuilds:
            return "builds"
        case .claudeUsageBilling:
            return "billing"
        case .codeRefactorCache:
            return "package-graphs"
        case .codeRefactorCredentials:
            return "credentials"
        case .crashlyticsApps:
            return "apps"
        case .crashlyticsCrashGroups:
            return "crash-groups"
        case .crashlyticsCrashes:
            return "crashes"
        case .crashlyticsEnrichment:
            return "enrichment"
        case .crashlyticsStackTraces:
            return "stacktraces"
        case .crashlyticsVersions:
            return "versions"
        case .gitBranchCache:
            return "branch-cache"
        case .mainThreadReports:
            return "reports"
        case .mainThreadSymbolicated:
            return "symbolicated"
        case .refactorMagicJobs:
            return "jobs"
        case .worktrees:
            return "git-worktrees"
        }
    }
}

public final class DataPathsService: @unchecked Sendable {
    private let fileManager: FileManager
    private let rootPath: URL

    public init() throws {
        let desktopPath = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let dataPath = desktopPath
            .appendingPathComponent("refactor-app")
            .appendingPathComponent("data")

        self.fileManager = .default
        self.rootPath = dataPath

        try Self.createDirectoryIfNeeded(at: rootPath, fileManager: fileManager)
    }

    internal init(rootPath: URL) throws {
        self.fileManager = .default
        self.rootPath = rootPath

        try Self.createDirectoryIfNeeded(at: rootPath, fileManager: fileManager)
    }

    public func path(for service: String) throws -> URL {
        guard !service.isEmpty else {
            throw DataPathsError.invalidServiceName("Service name cannot be empty")
        }

        let servicePath = rootPath.appendingPathComponent(service)
        try Self.createDirectoryIfNeeded(at: servicePath, fileManager: fileManager)
        return servicePath
    }

    public func path(for service: String, subdirectory: String) throws -> URL {
        guard !subdirectory.isEmpty else {
            throw DataPathsError.invalidServiceName("Subdirectory name cannot be empty")
        }

        let servicePath = try path(for: service)
        let subdirectoryPath = servicePath.appendingPathComponent(subdirectory)
        try Self.createDirectoryIfNeeded(at: subdirectoryPath, fileManager: fileManager)
        return subdirectoryPath
    }

    /// Get a well-known service path using the ServicePath enum.
    public func path(for servicePath: ServicePath) throws -> URL {
        try path(for: servicePath.serviceName, subdirectory: servicePath.subdirectory)
    }

    public func paths(for service: String, subdirectories: [String]) throws -> [String: URL] {
        var result: [String: URL] = [:]

        for subdirectory in subdirectories {
            let subdirectoryPath = try path(for: service, subdirectory: subdirectory)
            result[subdirectory] = subdirectoryPath
        }

        return result
    }

    private static func createDirectoryIfNeeded(at path: URL, fileManager: FileManager) throws {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: path.path, isDirectory: &isDirectory)

        if exists && !isDirectory.boolValue {
            throw DataPathsError.invalidPath("Path exists but is not a directory: \(path.path)")
        }

        if !exists {
            do {
                try fileManager.createDirectory(at: path, withIntermediateDirectories: true)
            } catch {
                throw DataPathsError.directoryCreationFailed(path.path, error)
            }
        }
    }
}
