import CredentialService
import Foundation
import GitHubService
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModelsService
import UseCaseSDK

public struct PostSingleCommentUseCase: UseCase {

    private let config: PRRadarRepoConfig

    public init(config: PRRadarRepoConfig) {
        self.config = config
    }

    /// Posts a single comment to GitHub, then fetches fresh comments from GitHub (with retry)
    /// until the posted comment is confirmed visible. Returns the updated comment list.
    public func execute(
        comment: PRComment,
        suppressedCount: Int = 0,
        commitSHA: String,
        prNumber: Int,
        commitHash: String? = nil
    ) async throws -> [ReviewComment] {
        guard let githubAccount = config.githubCredentialProfileId else {
            throw CredentialError.notConfigured(profileId: nil)
        }
        let gitHub = try await GitHubServiceFactory.createGitHubAPI(repoPath: config.repoPath, githubAccount: githubAccount, explicitToken: config.explicitToken)
        let commentService = CommentService(githubService: gitHub)
        try await commentService.postReviewComment(
            prNumber: prNumber,
            comment: comment,
            suppressedCount: suppressedCount,
            commitSHA: commitSHA
        )
        return try await fetchConfirmed(pendingId: comment.id, prNumber: prNumber, commitHash: commitHash)
    }

    /// Fetches comments from GitHub with retry until the just-posted comment (identified by
    /// `pendingId`) is no longer pending, or until max attempts are exhausted.
    ///
    /// GitHub has a brief eventual-consistency window after a POST where the new comment may
    /// not yet appear in GET responses. Retrying ensures the disk cache is written with
    /// confirmed data, so the correct posted state persists across app restarts.
    private func fetchConfirmed(pendingId: String, prNumber: Int, commitHash: String?) async throws -> [ReviewComment] {
        let fetchUseCase = FetchReviewCommentsUseCase(config: config)

        for attempt in 0..<3 {
            if attempt > 0 {
                try await Task.sleep(for: .seconds(2))
            }
            let updated = try await fetchUseCase.execute(
                prNumber: prNumber,
                minScore: 1,
                commitHash: commitHash,
                cachedOnly: false
            )
            let stillPending = updated.contains { $0.id == pendingId && $0.state == .new }
            if !stillPending {
                return updated
            }
        }

        throw PostSingleCommentError.postNotConfirmed
    }
}

public enum PostSingleCommentError: LocalizedError {
    case postNotConfirmed

    public var errorDescription: String? {
        "Comment was posted but did not appear in GitHub after several retries."
    }
}
