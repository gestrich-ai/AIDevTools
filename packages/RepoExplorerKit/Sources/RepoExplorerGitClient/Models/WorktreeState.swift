import Foundation

/// State of a worktree
public struct WorktreeState: Codable, Sendable {
    public var path: String
    public var hasUnstagedChanges: Bool
    public var lastCommitSHA: String?
    public var lastCommitMessage: String?
    public var lastCommitDate: Date?
    public var branchName: String

    // Remote tracking state
    public var isPushedToRemote: Bool = false  // Is branch pushed to GitHub?
    public var commitsAheadOfRemote: Int = 0   // Number of local commits not on remote
    public var commitsBehindRemote: Int = 0    // Number of remote commits not in local
    public var remoteTrackingBranch: String?   // e.g., "origin/branch-name"

    public init(
        path: String,
        hasUnstagedChanges: Bool = false,
        lastCommitSHA: String? = nil,
        lastCommitMessage: String? = nil,
        lastCommitDate: Date? = nil,
        branchName: String,
        isPushedToRemote: Bool = false,
        commitsAheadOfRemote: Int = 0,
        commitsBehindRemote: Int = 0,
        remoteTrackingBranch: String? = nil
    ) {
        self.path = path
        self.hasUnstagedChanges = hasUnstagedChanges
        self.lastCommitSHA = lastCommitSHA
        self.lastCommitMessage = lastCommitMessage
        self.lastCommitDate = lastCommitDate
        self.branchName = branchName
        self.isPushedToRemote = isPushedToRemote
        self.commitsAheadOfRemote = commitsAheadOfRemote
        self.commitsBehindRemote = commitsBehindRemote
        self.remoteTrackingBranch = remoteTrackingBranch
    }
}
