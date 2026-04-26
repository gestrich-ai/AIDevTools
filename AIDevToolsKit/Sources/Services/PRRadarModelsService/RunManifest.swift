import Foundation

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

public struct PRManifestEntry: Codable, Sendable {
    public let costUsd: Double?
    public let failureReason: String?
    public let prNumber: Int
    public let status: PRRunStatus
    public let title: String
    public let violationsFound: Int?

    public init(
        costUsd: Double? = nil,
        failureReason: String? = nil,
        prNumber: Int,
        status: PRRunStatus,
        title: String,
        violationsFound: Int? = nil
    ) {
        self.costUsd = costUsd
        self.failureReason = failureReason
        self.prNumber = prNumber
        self.status = status
        self.title = title
        self.violationsFound = violationsFound
    }
}

public enum PRRunStatus: String, Codable, Sendable {
    case failed
    case succeeded
}
