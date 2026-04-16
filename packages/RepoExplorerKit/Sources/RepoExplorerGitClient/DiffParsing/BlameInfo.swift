import Foundation

/// Consolidated blame information structure replacing Ownership and LineBlame
public struct BlameInfo: Codable, Sendable, Equatable {
    public let author: GitAuthor
    public let commitHash: String
    public let commitDate: String?
    public let summary: String
    public let confidence: String?

    public init(
        author: GitAuthor,
        commitHash: String,
        commitDate: String? = nil,
        summary: String,
        confidence: String? = nil
    ) {
        self.author = author
        self.commitHash = commitHash
        self.commitDate = commitDate
        self.summary = summary
        self.confidence = confidence
    }

    /// Create from legacy Ownership structure
    public init(from ownership: Ownership) {
        self.author = ownership.author
        self.commitHash = ownership.commitHash
        self.commitDate = ownership.commitDate
        self.summary = ownership.summary
        self.confidence = ownership.confidence
    }
}
