import Foundation

public enum PRRunStatus: String, Codable, Sendable {
    case failed
    case succeeded
}

// MARK: - Persisted manifest (slim — metrics live in report/summary.json)

public struct PRManifestEntry: Codable, Sendable {
    public let failureReason: String?
    public let prNumber: Int
    public let status: PRRunStatus
    public let title: String

    public init(
        failureReason: String? = nil,
        prNumber: Int,
        status: PRRunStatus,
        title: String
    ) {
        self.failureReason = failureReason
        self.prNumber = prNumber
        self.status = status
        self.title = title
    }
}

public struct RunManifest: Codable, Sendable {
    public let completedAt: String
    public let config: String
    public let id: String
    public let prs: [PRManifestEntry]
    public let rulesPathName: String?
    public let startedAt: String

    public init(
        completedAt: String,
        config: String,
        id: String = UUID().uuidString,
        prs: [PRManifestEntry],
        rulesPathName: String?,
        startedAt: String
    ) {
        self.completedAt = completedAt
        self.config = config
        self.id = id
        self.prs = prs
        self.rulesPathName = rulesPathName
        self.startedAt = startedAt
    }
}

// MARK: - In-memory stats for current-run display (not persisted)

public struct RunAllPRStats: Sendable {
    public let aiTasksRun: Int
    public let entry: PRManifestEntry
    public let totalCostUsd: Double
    public let totalDurationMs: Int
    public let violationsFound: Int

    public init(
        aiTasksRun: Int,
        entry: PRManifestEntry,
        totalCostUsd: Double,
        totalDurationMs: Int,
        violationsFound: Int
    ) {
        self.aiTasksRun = aiTasksRun
        self.entry = entry
        self.totalCostUsd = totalCostUsd
        self.totalDurationMs = totalDurationMs
        self.violationsFound = violationsFound
    }

    public var formattedDuration: String { DurationFormatter.format(milliseconds: totalDurationMs) }
}
