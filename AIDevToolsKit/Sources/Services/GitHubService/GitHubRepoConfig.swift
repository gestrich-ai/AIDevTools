import Foundation

public struct GitHubRepoConfig: Sendable {
    public let account: String
    public let cacheURL: URL
    public let name: String
    public let repoPath: String
    public let repoSlug: String
    public let token: String?

    public init(account: String, cacheURL: URL, name: String, repoPath: String, repoSlug: String, token: String?) {
        self.account = account
        self.cacheURL = cacheURL
        self.name = name
        self.repoPath = repoPath
        self.repoSlug = repoSlug
        self.token = token
    }
}
