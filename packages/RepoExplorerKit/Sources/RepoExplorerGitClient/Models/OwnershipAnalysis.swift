import Foundation

/// Enriched ownership analysis result with additional metadata
public struct OwnershipAnalysis: Codable, Sendable {
    public let author: GitAuthor
    public let commitHash: String
    public let commitDate: Date?
    public let commitMessage: String
    public let confidence: OwnershipConfidence
    public let attributionMethod: AttributionMethod

    public init(
        author: GitAuthor,
        commitHash: String,
        commitDate: Date? = nil,
        commitMessage: String,
        confidence: OwnershipConfidence,
        attributionMethod: AttributionMethod
    ) {
        self.author = author
        self.commitHash = commitHash
        self.commitDate = commitDate
        self.commitMessage = commitMessage
        self.confidence = confidence
        self.attributionMethod = attributionMethod
    }

    /// Create from basic GitRepo Ownership
    public init(fromOwnership ownership: Ownership, attributionMethod: AttributionMethod) {
        self.init(
            author: ownership.author,
            commitHash: ownership.commitHash,
            commitDate: ownership.commitDate.flatMap { ISO8601DateFormatter().date(from: $0) },
            commitMessage: ownership.summary,
            confidence: OwnershipConfidence(rawValue: ownership.confidence.lowercased()) ?? .medium,
            attributionMethod: attributionMethod
        )
    }
    
    /// Legacy compatibility - Create from basic GitRepo Ownership (for BuildAnalyzer compatibility)
    public init(from ownership: Ownership, attributionMethod: AttributionMethod) {
        self.init(fromOwnership: ownership, attributionMethod: attributionMethod)
    }
}
