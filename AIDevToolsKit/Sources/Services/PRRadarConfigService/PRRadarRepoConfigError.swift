import Foundation

public enum PRRadarRepoConfigError: LocalizedError {
    case noDataRoot
    case noGitHubAccount(repoName: String)

    public var errorDescription: String? {
        switch self {
        case .noDataRoot:
            return "GitHub cache URL not configured; ensure dataRootURL is set on PRRadarRepoConfig"
        case .noGitHubAccount(let repoName):
            return "No GitHub credential profile configured for repo '\(repoName)'; ensure githubCredentialProfileId is set"
        }
    }
}
