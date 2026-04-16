import Foundation

// MARK: - Branch List Item

/// Raw branch information from git branch list
public struct BranchListItem: Sendable, Equatable {
    public let refName: String
    public let upstream: String?
    public let isHead: Bool
    public let commitHash: String
    public let commitDate: Date?
    public let isRemote: Bool

    public init(
        refName: String,
        upstream: String?,
        isHead: Bool,
        commitHash: String,
        commitDate: Date?,
        isRemote: Bool
    ) {
        self.refName = refName
        self.upstream = upstream
        self.isHead = isHead
        self.commitHash = commitHash
        self.commitDate = commitDate
        self.isRemote = isRemote
    }

    /// Clean branch name (strips "remotes/" prefix if present)
    public var cleanName: String {
        if isRemote && refName.hasPrefix("remotes/") {
            return String(refName.dropFirst("remotes/".count))
        }
        return refName
    }
}

// MARK: - Tracking Info

/// Ahead/behind tracking information for a branch
public struct TrackingInfo: Sendable, Equatable {
    public let ahead: Int
    public let behind: Int

    public init(ahead: Int, behind: Int) {
        self.ahead = ahead
        self.behind = behind
    }

    /// Whether branch has diverged (both ahead and behind)
    public var hasDiverged: Bool {
        ahead > 0 && behind > 0
    }

    /// Whether branch is in sync
    public var isInSync: Bool {
        ahead == 0 && behind == 0
    }
}

// MARK: - Commit Info

/// Commit information from git log
public struct CommitInfo: Sendable, Equatable {
    public let hash: String
    public let shortHash: String
    public let message: String
    public let authorName: String
    public let authorEmail: String
    public let authorTimestamp: Int
    public let committerName: String
    public let committerEmail: String
    public let committerTimestamp: Int

    public init(
        hash: String,
        shortHash: String,
        message: String,
        authorName: String,
        authorEmail: String,
        authorTimestamp: Int,
        committerName: String,
        committerEmail: String,
        committerTimestamp: Int
    ) {
        self.hash = hash
        self.shortHash = shortHash
        self.message = message
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.authorTimestamp = authorTimestamp
        self.committerName = committerName
        self.committerEmail = committerEmail
        self.committerTimestamp = committerTimestamp
    }

    /// Author date as Date
    public var authorDate: Date {
        Date(timeIntervalSince1970: TimeInterval(authorTimestamp))
    }

    /// Committer date as Date
    public var committerDate: Date {
        Date(timeIntervalSince1970: TimeInterval(committerTimestamp))
    }
}

// MARK: - Diff Stats

/// Statistics from git diff
public struct DiffStats: Sendable, Equatable {
    public let filesChanged: Int
    public let insertions: Int
    public let deletions: Int

    public init(filesChanged: Int, insertions: Int = 0, deletions: Int = 0) {
        self.filesChanged = filesChanged
        self.insertions = insertions
        self.deletions = deletions
    }
}

// MARK: - Merge Result

/// Result of a merge operation
public struct GitMergeResult: Sendable, Equatable {
    public let success: Bool
    public let hasConflicts: Bool
    public let conflictFiles: [String]
    public let errorMessage: String?

    public init(
        success: Bool,
        hasConflicts: Bool = false,
        conflictFiles: [String] = [],
        errorMessage: String? = nil
    ) {
        self.success = success
        self.hasConflicts = hasConflicts
        self.conflictFiles = conflictFiles
        self.errorMessage = errorMessage
    }
}
