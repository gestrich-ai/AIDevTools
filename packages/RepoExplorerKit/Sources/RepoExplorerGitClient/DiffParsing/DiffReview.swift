import Foundation

/// Represents a comment on a specific line in a diff
public struct DiffComment: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let filePath: String
    public let lineNumber: Int
    public let lineContent: String
    public var comment: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        filePath: String,
        lineNumber: Int,
        lineContent: String,
        comment: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.lineContent = lineContent
        self.comment = comment
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Represents a review of a git diff with comments
public struct DiffReview: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let diff: GitDiff
    public var comments: [DiffComment]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        diff: GitDiff,
        comments: [DiffComment] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.diff = diff
        self.comments = comments
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Add a comment to the review
    public mutating func addComment(_ comment: DiffComment) {
        comments.append(comment)
        updatedAt = Date()
    }

    /// Update an existing comment
    public mutating func updateComment(id: UUID, newComment: String) {
        if let index = comments.firstIndex(where: { $0.id == id }) {
            comments[index].comment = newComment
            comments[index].updatedAt = Date()
            updatedAt = Date()
        }
    }

    /// Remove a comment from the review
    public mutating func removeComment(id: UUID) {
        comments.removeAll { $0.id == id }
        updatedAt = Date()
    }

    /// Get comments for a specific file
    public func comments(forFile filePath: String) -> [DiffComment] {
        comments.filter { $0.filePath == filePath }
    }

    /// Get comment for a specific line in a file
    public func comment(forFile filePath: String, line lineNumber: Int) -> DiffComment? {
        comments.first { $0.filePath == filePath && $0.lineNumber == lineNumber }
    }

    /// Export comments as formatted text for pasting into AI editor
    public func exportCommentsAsText() -> String {
        guard !comments.isEmpty else {
            return "No comments"
        }

        var output = "# Diff Review Comments\n\n"

        let groupedByFile = Dictionary(grouping: comments) { $0.filePath }
        let sortedFiles = groupedByFile.keys.sorted()

        for filePath in sortedFiles {
            output += "## \(filePath)\n\n"

            let fileComments = groupedByFile[filePath]?.sorted { $0.lineNumber < $1.lineNumber } ?? []
            for comment in fileComments {
                output += "**Line \(comment.lineNumber):**\n"
                output += "```\n\(comment.lineContent)\n```\n"
                output += "\(comment.comment)\n\n"
            }
        }

        return output
    }
}
