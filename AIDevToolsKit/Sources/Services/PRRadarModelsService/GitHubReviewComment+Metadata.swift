import GitHubService

extension GitHubReviewComment {
    public var metadata: CommentMetadata? {
        CommentMetadata.parse(from: body)
    }

    public var bodyWithoutMetadata: String {
        CommentMetadata.stripMetadata(from: body)
    }

    public var metadataLine: Int? {
        metadata?.fileInfo?.line
    }

    public var metadataBlobSHA: String? {
        guard let sha = metadata?.fileInfo?.blobSHA, !sha.isEmpty else { return nil }
        return sha
    }
}
