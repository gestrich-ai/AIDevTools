import PRRadarModelsService

public protocol GitHubPRServiceProtocol: Sendable {
    func pullRequest(number: Int, useCache: Bool) async throws -> GitHubPullRequest
    func comments(number: Int, useCache: Bool) async throws -> GitHubPullRequestComments
    func updatePR(number: Int) async throws
    func updatePRs(numbers: [Int]) async throws
    func updateAllPRs() async throws -> [GitHubPullRequest]
    func changes() -> AsyncStream<Int>
}
