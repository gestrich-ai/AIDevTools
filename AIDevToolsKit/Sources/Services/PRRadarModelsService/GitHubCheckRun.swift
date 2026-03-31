import Foundation

public struct GitHubCheckRun: Codable, Sendable {
    public let name: String
    public let status: GitHubCheckRunStatus
    public let conclusion: GitHubCheckRunConclusion?

    public init(name: String, status: GitHubCheckRunStatus, conclusion: GitHubCheckRunConclusion? = nil) {
        self.name = name
        self.status = status
        self.conclusion = conclusion
    }

    public var isPassing: Bool { conclusion == .success }
    public var isFailing: Bool { conclusion == .failure }
}

public enum GitHubCheckRunStatus: String, Codable, Sendable {
    case completed
    case inProgress = "in_progress"
    case queued
}

public enum GitHubCheckRunConclusion: String, Codable, Sendable {
    case cancelled
    case failure
    case neutral
    case skipped
    case success
    case timedOut = "timed_out"
}
