import Foundation
import SwiftData

/// SwiftData model for caching Git blame information
@Model
final class GitBlameCache {
    /// Unique identifier combining path:line:commitHash
    @Attribute(.unique) var id: String
    
    /// File path (relative to repo root)
    var filePath: String
    
    /// Line number (0 for file-level commits)
    var line: Int
    
    /// The commit hash of the file at the time of caching
    var fileCommitHash: String
    
    /// Blame information
    var authorName: String
    var authorEmail: String
    var blameCommitHash: String
    var blameCommitMessage: String
    var blameCommitDate: Date?
    var confidence: String
    
    /// Cache metadata
    var createdAt: Date
    var lastAccessed: Date
    
    /// Whether this is a file-level commit (no specific line)
    var isFileCommit: Bool
    
    init(
        filePath: String,
        line: Int,
        fileCommitHash: String,
        authorName: String,
        authorEmail: String,
        blameCommitHash: String,
        blameCommitMessage: String,
        blameCommitDate: Date?,
        confidence: String,
        isFileCommit: Bool = false
    ) {
        self.id = Self.makeId(filePath: filePath, line: line, commitHash: fileCommitHash)
        self.filePath = filePath
        self.line = line
        self.fileCommitHash = fileCommitHash
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.blameCommitHash = blameCommitHash
        self.blameCommitMessage = blameCommitMessage
        self.blameCommitDate = blameCommitDate
        self.confidence = confidence
        self.createdAt = Date()
        self.lastAccessed = Date()
        self.isFileCommit = isFileCommit
    }
    
    /// Create a unique ID for cache lookup
    static func makeId(filePath: String, line: Int, commitHash: String) -> String {
        "\(filePath):\(line):\(commitHash)"
    }
    
    /// Update last accessed time
    func touch() {
        self.lastAccessed = Date()
    }
    
    /// Convert to Ownership model
    func toOwnership() -> Ownership {
        let author = GitAuthor(name: authorName, email: authorEmail)
        
        // Convert date to ISO8601 string if available
        var dateString: String?
        if let date = blameCommitDate {
            let formatter = ISO8601DateFormatter()
            dateString = formatter.string(from: date)
        }
        
        return Ownership(
            author: author,
            commitHash: blameCommitHash,
            summary: blameCommitMessage,
            commitDate: dateString,
            confidence: confidence
        )
    }
}
