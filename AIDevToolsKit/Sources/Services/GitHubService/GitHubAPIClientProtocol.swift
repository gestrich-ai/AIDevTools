import PRRadarModelsService

public protocol GitHubAPIClientProtocol: Sendable {
    func getPullRequest(number: Int) async throws -> GitHubPullRequest
    func getPullRequestComments(number: Int) async throws -> GitHubPullRequestComments
    func getRepository() async throws -> GitHubRepository
    func listPullRequests(limit: Int, filter: PRFilter) async throws -> [GitHubPullRequest]
}
