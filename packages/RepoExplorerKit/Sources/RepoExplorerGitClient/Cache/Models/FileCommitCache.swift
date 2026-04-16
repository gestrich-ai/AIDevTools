import Foundation
import SwiftData

/// SwiftData model for caching file existence and commit information
@Model
final class FileCommitCache {
    /// Unique identifier combining path:repoCommitHash
    @Attribute(.unique) var id: String
    
    /// File path (relative to repo root)
    var filePath: String
    
    /// The commit hash of the repository when this was cached
    var repoCommitHash: String
    
    /// The last commit hash that modified this file
    var lastFileCommitHash: String?
    
    /// Whether the file exists in the repository
    var fileExists: Bool
    
    /// Cache metadata
    var createdAt: Date
    var lastAccessed: Date
    
    init(
        filePath: String,
        repoCommitHash: String,
        lastFileCommitHash: String? = nil,
        fileExists: Bool
    ) {
        self.id = Self.makeId(filePath: filePath, repoCommitHash: repoCommitHash)
        self.filePath = filePath
        self.repoCommitHash = repoCommitHash
        self.lastFileCommitHash = lastFileCommitHash
        self.fileExists = fileExists
        self.createdAt = Date()
        self.lastAccessed = Date()
    }
    
    /// Create a unique ID for cache lookup
    static func makeId(filePath: String, repoCommitHash: String) -> String {
        "\(filePath)@\(repoCommitHash)"
    }
    
    /// Update last accessed time
    func touch() {
        self.lastAccessed = Date()
    }
}
