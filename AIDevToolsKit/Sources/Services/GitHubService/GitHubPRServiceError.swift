import Foundation

public enum GitHubPRServiceError: Error, LocalizedError {
    case listFetchFailed(String)
    case missingHeadRefOid(prNumber: Int)

    public var errorDescription: String? {
        switch self {
        case .listFetchFailed(let message):
            return "PR list fetch failed: \(message)"
        case .missingHeadRefOid(let prNumber):
            return "PR #\(prNumber) has no head commit SHA (headRefOid); cannot fetch check runs"
        }
    }
}
