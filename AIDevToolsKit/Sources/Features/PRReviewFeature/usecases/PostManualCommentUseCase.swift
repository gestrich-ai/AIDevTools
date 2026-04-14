import CredentialService
import GitHubService
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModelsService
import UseCaseSDK

public struct PostManualCommentUseCase: UseCase {

    private let config: PRRadarRepoConfig

    public init(config: PRRadarRepoConfig) {
        self.config = config
    }

    /// Posts a manual review comment to GitHub, then fetches fresh comments and returns
    /// the updated list. Swallows fetch errors — a failure to refresh does not undo the post.
    public func execute(
        prNumber: Int,
        filePath: String,
        lineNumber: Int,
        body: String,
        commitSHA: String,
        commitHash: String? = nil
    ) async throws -> [ReviewComment] {
        guard let githubAccount = config.githubCredentialProfileId else {
            throw CredentialError.notConfigured(profileId: nil)
        }
        let gitHub = try await GitHubServiceFactory.createGitHubAPI(repoPath: config.repoPath, githubAccount: githubAccount, explicitToken: config.explicitToken)
        try await gitHub.postReviewComment(
            number: prNumber,
            commitId: commitSHA,
            path: filePath,
            line: lineNumber,
            body: body
        )
        let fetchUseCase = FetchReviewCommentsUseCase(config: config)
        return (try? await fetchUseCase.execute(
            prNumber: prNumber,
            minScore: 1,
            commitHash: commitHash,
            cachedOnly: false
        )) ?? []
    }
}
