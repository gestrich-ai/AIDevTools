import OctokitSDK
import PRRadarModelsService

public protocol GitHubAPIServiceProtocol: Sendable {
    func checkRuns(prNumber: Int, headSHA: String) async throws -> [GitHubCheckRun]
    func fileContent(path: String, ref: String) async throws -> String
    func getBranchHead(branch: String) async throws -> BranchHead
    func getFileContentWithSHA(path: String, ref: String) async throws -> (sha: String, content: String)
    func getGitTree(treeSHA: String) async throws -> [GitTreeEntry]
    func getPullRequest(number: Int) async throws -> GitHubPullRequest
    func getPullRequestComments(number: Int) async throws -> GitHubPullRequestComments
    func getRepository() async throws -> GitHubRepository
    func isMergeable(prNumber: Int) async throws -> Bool?
    func listDirectoryNames(path: String, ref: String) async throws -> [String]
    func listPullRequests(limit: Int, filter: PRFilter) async throws -> [GitHubPullRequest]
    func listReviews(prNumber: Int) async throws -> [GitHubReview]
    func requestedReviewers(prNumber: Int) async throws -> [String]
}
