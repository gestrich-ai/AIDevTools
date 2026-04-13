import Foundation
import GitHubService

public struct EnrichedPR: Sendable {
    public let pr: PRMetadata
    public var isDraft: Bool { pr.isDraft }
    public let reviewStatus: PRReviewStatus
    public let buildStatus: PRBuildStatus

    public init(
        pr: PRMetadata,
        reviewStatus: PRReviewStatus,
        buildStatus: PRBuildStatus
    ) {
        self.pr = pr
        self.reviewStatus = reviewStatus
        self.buildStatus = buildStatus
    }

    public var isMerged: Bool { pr.mergedAt != nil }

    public var ageDays: Int {
        let dateString = pr.mergedAt ?? pr.createdAt
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            return Int(Date().timeIntervalSince(date) / 86400)
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: dateString) {
            return Int(Date().timeIntervalSince(date) / 86400)
        }
        return 0
    }
}

public struct PRReviewStatus: Sendable {
    public let approvedBy: [String]
    public let changesRequestedBy: [String]
    public let pendingReviewers: [String]

    public init(approvedBy: [String], changesRequestedBy: [String] = [], pendingReviewers: [String]) {
        self.approvedBy = approvedBy
        self.changesRequestedBy = changesRequestedBy
        self.pendingReviewers = pendingReviewers
    }

    public init(reviews: [GitHubReview]) {
        approvedBy = Array(Set(reviews.filter { $0.state == .approved }.compactMap { $0.author?.displayName }))
        changesRequestedBy = Array(Set(reviews.filter { $0.state == .changesRequested }.compactMap { $0.author?.displayName }))
        pendingReviewers = Array(Set(reviews.filter { $0.state == .pending }.compactMap { $0.author?.displayName }))
    }
}

public enum PRBuildStatus: Sendable {
    case conflicting
    case failing(checks: [String])
    case passing
    case pending(checks: [String])
    case unknown

    public static func from(checkRuns: [GitHubCheckRun], isMergeable: Bool?) -> PRBuildStatus {
        if isMergeable == false { return .conflicting }
        let failing = checkRuns.filter { $0.isFailing }.map { $0.name }
        if !failing.isEmpty { return .failing(checks: failing) }
        let pending = checkRuns.filter { $0.status != .completed }.map { $0.name }
        if !pending.isEmpty { return .pending(checks: pending) }
        return checkRuns.isEmpty ? .unknown : .passing
    }
}

private extension GitHubAuthor {
    /// Prefers non-empty name over login for human-readable display.
    var displayName: String { (name.flatMap { $0.isEmpty ? nil : $0 }) ?? login }
}

extension ChainProject {
    public func taskHash(for pr: PRMetadata) -> String? {
        if let branchInfo = BranchInfo.fromBranchName(pr.headRefName) {
            return branchInfo.taskHash
        }
        guard let body = pr.body,
              let cursorPath = BranchInfo.sweepCursorPath(fromText: body) else { return nil }
        return tasks.first { $0.description == cursorPath }.map { generateTaskHash($0.description) }
    }
}
