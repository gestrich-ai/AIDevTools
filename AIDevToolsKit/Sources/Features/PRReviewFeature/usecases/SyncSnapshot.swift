import GitDiffModelsService
import PRRadarModelsService

public struct SyncSnapshot: Sendable {
    public let commitHash: String?
    public let commentCount: Int
    public let files: [String]
    public let prDiff: PRDiff?
    public let reviewCommentCount: Int
    public let reviewComments: [ReviewComment]
    public let reviewCount: Int
    public let storedEffectiveDiff: GitDiff?

    public init(
        prDiff: PRDiff? = nil,
        files: [String],
        commentCount: Int = 0,
        reviewCount: Int = 0,
        reviewCommentCount: Int = 0,
        reviewComments: [ReviewComment] = [],
        commitHash: String? = nil,
        storedEffectiveDiff: GitDiff? = nil
    ) {
        self.commitHash = commitHash
        self.commentCount = commentCount
        self.files = files
        self.prDiff = prDiff
        self.reviewCommentCount = reviewCommentCount
        self.reviewComments = reviewComments
        self.reviewCount = reviewCount
        self.storedEffectiveDiff = storedEffectiveDiff
    }
}
